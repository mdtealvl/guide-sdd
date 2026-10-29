#!/usr/bin/env pwsh
# red_check - prove QA's new tests are RED on the frozen tree (tests in, no implementation).
#
# Stage 5 requires the tests "red and compiling at handoff", but nothing verified red: a test that
# passes without the implementation (a poll that times out to a pass, an assertion on a value the
# fixture already sets) is frozen and reaches Validation. Run by the Orchestrator right after `freeze`.
#
# Test files = those ADDED or MODIFIED between the branch point (merge-base of baseRef and the frozen
# SHA) and the frozen SHA, under redCheck.globs (default testGlobs). {tests} in redCheck.cmd becomes
# their file stems (name without the last extension) joined by redCheck.joiner (default |), e.g.
#   cmd "dotnet test --filter \"FullyQualifiedName~{tests}\"", joiner "|FullyQualifiedName~"
# Each output line matching redCheck.passRegex names a test that PASSED: capture group 1 is its name.
# Any passing test no redCheck.allowGreen entry matches FAILs the gate and is listed: route it to QA
# (Stage 5). An allowGreen entry is a glob over the whole test name (* ?; none = exact), for regression
# pins that are legitimately green before the change.
#
# The frozen SHA is -Base, else gates/.frozen (baseRef alone is not a freeze: exit 2). The tree must
# hold no paths.code change vs it. An unset redCheck.cmd = "not configured" PASS. The command runs from
# the project root (cmd /c on Windows, sh -c elsewhere); its exit code is ignored (a red run exits
# non-zero).
#
# Exit 0 PASS, 1 FAIL, 2 config/usage error.
# Usage:  pwsh gates/red_check.ps1 [-Base <frozen-sha>] [-Config gates/gates.config.json]

[CmdletBinding()]
param(
    [string]$Base = '',
    [string]$Config = 'gates/gates.config.json'
)
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_common.ps1"

$GateName = 'red_check'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Output "FAIL ${GateName}: need git"; exit 2 }
if (-not (Test-Path -LiteralPath $Config)) { Write-Output "FAIL ${GateName}: cannot read config ${Config}: no such file"; exit 2 }
$Config = (Resolve-Path -LiteralPath $Config).Path
$cfg = Read-Config $Config $GateName
$red = Get-CfgValue $cfg 'redCheck' $null

$cmd = Get-CfgValue $red 'cmd' ''
if ([string]::IsNullOrEmpty($cmd)) {
    Write-Output "PASS ${GateName}: not configured (redCheck.cmd unset) - red-first is unverified."
    exit 0
}
if (-not $cmd.Contains('{tests}')) { Write-Output "FAIL ${GateName}: redCheck.cmd must hold {tests}"; exit 2 }
$re = Get-CfgValue $red 'passRegex' ''
if (-not $re) { Write-Output "FAIL ${GateName}: redCheck.passRegex is unset - it names the passed tests (capture group 1 = test name)"; exit 2 }
if (-not $re.Contains('(')) { Write-Output "FAIL ${GateName}: redCheck.passRegex needs a capture group around the test name"; exit 2 }
if (-not (Test-PortableRegex $GateName 'redCheck.passRegex' $re)) { exit 2 }
$join = Get-RawText $red 'joiner' '|'

$top = (& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $top) { Write-Output "FAIL ${GateName}: not inside a git work tree"; exit 2 }
$gd = ((& git -C $PSScriptRoot rev-parse --show-prefix) -replace '/$', '')
if (-not $gd) { $gd = '.' }
Set-Location -LiteralPath $top

if (-not $Base) { $Base = Get-FrozenSha (Join-Path $top $gd) }
if (-not $Base) { Write-Output "FAIL ${GateName}: no frozen SHA - run gates/freeze.ps1 at Stage 5 exit or pass -Base <sha>."; exit 2 }
& git rev-parse --verify --quiet "$Base^{commit}" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Output "FAIL ${GateName}: frozen SHA '$Base' does not resolve."; exit 2 }
$from = (& git merge-base (Get-CfgValue $cfg 'baseRef' 'main') $Base 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $from) { Write-Output "FAIL ${GateName}: no merge-base of baseRef and $Base - set baseRef to the branch the unit started from."; exit 2 }

$paths = Get-CfgValue $cfg 'paths' $null
$code = @(Get-GlobSpecs (Get-CfgList $paths 'code'))
if ($code.Count -eq 0) { $code = @(':(glob)src/**') }
& git diff --quiet $Base -- @code 2>&1 | Out-Null
$dirty = ($LASTEXITCODE -ne 0)
if (-not $dirty) { $dirty = (@(& git ls-files --others --exclude-standard -- @code).Count -gt 0) }
if ($dirty) {
    Write-Output "FAIL ${GateName}: paths.code differs from the frozen SHA - red_check runs on the frozen tree, before the Engineer starts."
    exit 2
}

$globs = @(Get-CfgList $red 'globs')
if ($globs.Count -eq 0) { $globs = @(Get-CfgList $cfg 'testGlobs') }
if ($globs.Count -eq 0) { $globs = @(Get-CfgList $paths 'tests') }
if ($globs.Count -eq 0) { $globs = @('tests/**') }
$files = @(& git diff --name-only --no-renames --diff-filter=AM $from $Base -- @(Get-GlobSpecs $globs) | ForEach-Object { "$_".Trim() } | Where-Object { $_ } | Sort-Object -Unique)
if ($files.Count -eq 0) {
    Write-Output "PASS ${GateName}: no test file added or changed between the branch point and the frozen SHA."
    exit 0
}

$stems = New-Object 'System.Collections.Generic.SortedSet[string]' ([StringComparer]::Ordinal)
foreach ($f in $files) {
    $s = Get-FileStem $f
    if (-not $s -or $s -notmatch '^[A-Za-z0-9_.+-]+$') {
        Write-Output "FAIL ${GateName}: '$f' has a file stem outside [A-Za-z0-9_.+-]; {tests} cannot carry it safely."
        exit 2
    }
    [void]$stems.Add($s)
}
$cmd = $cmd.Replace('{tests}', ($stems -join $join))
if (-not (Test-OneLine $GateName 'redCheck.cmd' $cmd)) { exit 2 }
$r = Invoke-ShellCapture $cmd

$rx = [regex]$re
$passed = New-Object 'System.Collections.Generic.SortedSet[string]' ([StringComparer]::Ordinal)
foreach ($l in $r.out.Split([char]10)) {
    $m = $rx.Match($l)
    if ($m.Success -and $m.Groups.Count -gt 1 -and $m.Groups[1].Success -and $m.Groups[1].Value) { [void]$passed.Add($m.Groups[1].Value) }
}
$allow = @(Get-CfgList $red 'allowGreen')
$green = @($passed | Where-Object { $n = $_; -not ($allow | Where-Object { $n -clike $_ }) })
if ($green.Count -gt 0) {
    Write-Output "FAIL ${GateName}: $($green.Count) test(s) pass on the frozen tree, before any implementation (route to QA, Stage 5; a legitimate regression pin goes in redCheck.allowGreen):"
    foreach ($g in $green) { Write-Output "  $g" }
    exit 1
}
Write-Output "PASS ${GateName}: $($files.Count) new/changed test file(s) run; none passes without the implementation."
exit 0
