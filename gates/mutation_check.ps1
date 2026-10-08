#!/usr/bin/env pwsh
# mutation_check - measure test strength by mutation testing (mutation.cmd), for Validation.
#
# Red-first proves QA's tests fail without an implementation, not that they catch a WRONG one. A
# mutation tool (Stryker, mutmut, cargo-mutants, PIT, go-mutesting...) plants small faults in the code
# and counts the ones the suite kills. A surviving mutant in changed code is a missing test: Validation
# routes it to QA (Stage 5), never to the Engineer.
#
# OPTIONAL: an unset mutation.cmd PASSes with "not configured" (test strength is then unmeasured, and
# the bank says so every run). Mutation runs are slow - scope them to the diff:
#   {base} in mutation.cmd becomes the QA-frozen SHA (-Base > gates/.frozen > config baseRef), e.g.
#   "dotnet stryker --since:{base}", "npx stryker run --incremental".
#
# Verdict:
#   * mutation.scoreRegex unset - mutation.cmd's exit code decides (0 = PASS; most tools take their own
#     threshold, e.g. Stryker thresholds.break, PIT mutationThreshold).
#   * scoreRegex set - the first line matching it carries the score: the first number in the match
#     (e.g. "Mutation score: 85.71" -> 85.71) is compared with mutation.minScore (default 0). The exit code
#     is then ignored (tools exit non-zero when mutants survive); no match at all FAILs.
# The command runs from the project root (cmd /c on Windows, sh -c elsewhere); its output is printed
# above the verdict.
#
# Usage:  pwsh gates/mutation_check.ps1 [-Base <sha>] [-Config gates/gates.config.json]

[CmdletBinding()]
param(
    [string]$Base = '',
    [string]$Config = 'gates/gates.config.json'
)
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_common.ps1"

$GateName = 'mutation_check'
$cfg = Read-Config $Config $GateName
$mut = Get-CfgValue $cfg 'mutation' $null

$cmd = Get-CfgValue $mut 'cmd' ''
if ([string]::IsNullOrEmpty($cmd)) {
    Write-Output "PASS ${GateName}: not configured (mutation.cmd unset) - test strength is unmeasured."
    exit 0
}

if ($cmd.Contains('{base}')) {
    $frozenPath = Join-Path $PSScriptRoot '.frozen'
    if (-not $Base -and (Test-Path -LiteralPath $frozenPath)) {
        $line = (Get-Content -LiteralPath $frozenPath | Where-Object { $_ -match '^sha=([0-9a-fA-F]+)' } | Select-Object -First 1)
        if ($line) { $Base = [regex]::Match($line, '^sha=([0-9a-fA-F]+)').Groups[1].Value }
    }
    if (-not $Base) { $Base = Get-CfgValue $cfg 'baseRef' '' }
    if (-not $Base) { Write-Output "FAIL ${GateName}: mutation.cmd uses {base} but no base is known - pass the frozen SHA or run the freeze gate."; exit 2 }
    $cmd = $cmd.Replace('{base}', $Base)
}

if (-not (Test-OneLine $GateName 'mutation.cmd' $cmd)) { exit 2 }
$min = Get-RawText $mut 'minScore' '0'
if ($min -notmatch '^[0-9]+([.][0-9]+)?$') { Write-Output "FAIL ${GateName}: mutation.minScore must be a number (got '$min')"; exit 2 }
$re = Get-CfgValue $mut 'scoreRegex' ''
if ($re -and -not (Test-PortableRegex $GateName 'mutation.scoreRegex' $re)) { exit 2 }

$r = Invoke-ShellCapture $cmd
if ($r.out) { Write-Output $r.out }
$rc = $r.rc

if ([string]::IsNullOrEmpty($re)) {
    if ($rc -eq 0) { Write-Output "PASS ${GateName}: mutation.cmd exited 0."; exit 0 }
    Write-Output "FAIL ${GateName}: mutation.cmd exited $rc - surviving mutants are missing tests (route to QA, Stage 5)."
    exit 1
}

$rx = [regex]$re
$score = ''
foreach ($l in $r.out.Split([char]10)) {
    $m = $rx.Match($l)
    if ($m.Success) { $score = [regex]::Match($m.Value, '[0-9]+([.][0-9]+)?').Value; break }
}
if (-not $score) {
    Write-Output "FAIL ${GateName}: no score in the output (mutation.scoreRegex matched nothing; exit $rc) - the tool errored, or the regex no longer fits."
    exit 1
}
$inv = [Globalization.CultureInfo]::InvariantCulture
if ([double]::Parse($score, $inv) -ge [double]::Parse($min, $inv)) {
    Write-Output "PASS ${GateName}: mutation score $score >= minScore $min."
    exit 0
}
Write-Output "FAIL ${GateName}: mutation score $score < minScore $min - surviving mutants are missing tests (route to QA, Stage 5)."
exit 1
