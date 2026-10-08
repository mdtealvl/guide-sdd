#!/usr/bin/env pwsh
# static_check - the project's linter / type checker / formatter check, run as a gate (checkCmd).
#
# The suite proves only what QA thought to test; static analysis is the cheapest net under the rest
# (wrong or unused imports, type errors, dead code, bug patterns, format drift). REQUIRED, like
# suiteCmd: an unset checkCmd is exit 2, never a silent skip. "none" opts out on the record - the bank
# prints it every run.
#
# Verdict:
#   * staticCheck.findingRegex unset - checkCmd's exit code decides (0 = PASS).
#   * findingRegex set (the brownfield ratchet) - the lines of output matching it are counted
#     (line by line, as the rule engine) and compared with staticCheck.baseline: more = FAIL (new
#     findings), fewer = PASS with a note to lower the baseline. An exit code outside
#     staticCheck.findingExitCodes (default 0, 1) FAILs: the run did not finish. A non-zero exit with no
#     matching line FAILs: the tool broke, or the regex no longer fits its output.
#   * Commands are one line, and must mean the same under sh -c and cmd /c (else call a script).
# The command runs from the project root (run_all's cwd; cmd /c on Windows, sh -c elsewhere); its
# output is printed above the verdict.
#
# Suppressions are the bypass: an inline `eslint-disable` / `noqa` / `#pragma warning disable` in
# paths.code passes this gate. Ban them with a constitutionRules must_not_match row, and list the
# linter's own config under testGlobs so it freezes with the tests (gates/README.md).
#
# Usage:  pwsh gates/static_check.ps1 [-Config gates/gates.config.json]

[CmdletBinding()]
param(
    [string]$Config = 'gates/gates.config.json'
)
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_common.ps1"

$GateName = 'static_check'
$cfg = Read-Config $Config $GateName

$cmd = Get-CfgValue $cfg 'checkCmd' ''
if ([string]::IsNullOrEmpty($cmd) -or $cmd -like '<from project-details*') {
    Write-Output "FAIL ${GateName}: checkCmd is not set in $Config - set the project's lint / type-check command, or `"none`" to opt out on the record (INIT section 5)."
    exit 2
}
if ($cmd -eq 'none') {
    Write-Output "PASS ${GateName}: opted out (checkCmd is `"none`") - no static analysis runs."
    exit 0
}

if (-not (Test-OneLine $GateName 'checkCmd' $cmd)) { exit 2 }
$sc = Get-CfgValue $cfg 'staticCheck' $null
$re = Get-CfgValue $sc 'findingRegex' ''
$bl = Get-RawText $sc 'baseline' '0'
if ($bl -notmatch '^[0-9]{1,15}$') { Write-Output "FAIL ${GateName}: staticCheck.baseline must be a whole number (got '$bl')"; exit 2 }
$bl = [long]$bl
$codes = @(0, 1)
$rawCodes = Get-CfgValue $sc 'findingExitCodes' $null
if ($null -ne $rawCodes) {
    $codes = @()
    foreach ($c in @($rawCodes)) {
        $t = [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0}', $c)
        if ($c -is [bool] -or $t -notmatch '^[0-9]+$') { Write-Output "FAIL ${GateName}: staticCheck.findingExitCodes must be whole numbers (got '$t')"; exit 2 }
        $codes += [long]$t
    }
}
if ($re -and -not (Test-PortableRegex $GateName 'staticCheck.findingRegex' $re)) { exit 2 }

$r = Invoke-ShellCapture $cmd
if ($r.out) { Write-Output $r.out }
$rc = $r.rc

if ([string]::IsNullOrEmpty($re)) {
    if ($rc -eq 0) { Write-Output "PASS ${GateName}: checkCmd exited 0."; exit 0 }
    Write-Output "FAIL ${GateName}: checkCmd exited $rc."
    exit 1
}

# The ratchet trusts a count only from a run that finished: an exit code outside findingExitCodes
# (default 0 and 1; most linters exit 1 for findings, 2+ for a crash or a config error) FAILs.
if ($codes -notcontains [long]$rc) {
    Write-Output "FAIL ${GateName}: checkCmd exited $rc, not a findings exit code ($($codes -join ' '); staticCheck.findingExitCodes) - the tool errored."
    exit 1
}
$rx = [regex]$re
$n = @($r.out.Split([char]10) | Where-Object { $rx.IsMatch($_) }).Count
if ($rc -ne 0 -and $n -eq 0) {
    Write-Output "FAIL ${GateName}: checkCmd exited $rc but no line matched staticCheck.findingRegex - the tool errored, or the regex no longer fits its output."
    exit 1
}
if ($n -gt $bl) {
    Write-Output "FAIL ${GateName}: $n finding(s) > baseline $bl - new findings; fix them (the baseline only ratchets down)."
    exit 1
}
if ($n -lt $bl) {
    Write-Output "PASS ${GateName}: $n finding(s) < baseline $bl - lower staticCheck.baseline to $n (ratchet)."
    exit 0
}
Write-Output "PASS ${GateName}: $n finding(s) = baseline $bl."
exit 0
