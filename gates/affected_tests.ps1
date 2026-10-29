#!/usr/bin/env pwsh
# affected_tests - pick the unit's own tests mechanically; never a judgment call.
#
# The two-tier ship gate runs "smoke + the unit's own tests". Left to each orchestrator, "own tests"
# under-selects: a lane changed services whose existing tests it did not run and turned main red.
#
# Keys = the file stems (name without the last extension) of the paths.code files changed vs {base}
# (tracked changes, deletes and untracked files included) plus affectedTests.extraStems.
# Affected tests = the test files under affectedTests.globs (default testGlobs) that are themselves
# changed (since the branch point: merge-base of baseRef and {base}), PLUS every one holding a whole-word
# occurrence of a key (git grep -l -w).
#   -List    print them (key: <stem> / test: <path>) and exit 0.
#   default  run affectedTests.cmd with {tests} = the affected files' stems joined by
#            affectedTests.joiner (else redCheck.joiner, else |); put {tests} inside the quotes the
#            runner's filter needs. Its output is printed; exit 0 when it exits 0, else 1.
# Add a project's always-run category in the cmd itself. An unset cmd = "not configured" PASS (use
# -List). {base}: -Base, else gates/.frozen, else config baseRef.
#
# Exit 0 PASS, 1 FAIL (cmd failed), 2 config/usage error.
# Usage:  pwsh gates/affected_tests.ps1 [-List] [-Base <sha>] [-Config gates/gates.config.json]

[CmdletBinding()]
param(
    [switch]$List,
    [string]$Base = '',
    [string]$Config = 'gates/gates.config.json'
)
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_common.ps1"

$GateName = 'affected_tests'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Output "FAIL ${GateName}: need git"; exit 2 }
if (-not (Test-Path -LiteralPath $Config)) { Write-Output "FAIL ${GateName}: cannot read config ${Config}: no such file"; exit 2 }
$Config = (Resolve-Path -LiteralPath $Config).Path
$cfg = Read-Config $Config $GateName
$aff = Get-CfgValue $cfg 'affectedTests' $null

$cmd = Get-CfgValue $aff 'cmd' ''
if (-not $List) {
    if ([string]::IsNullOrEmpty($cmd)) {
        Write-Output "PASS ${GateName}: not configured (affectedTests.cmd unset) - use -List to see the affected tests."
        exit 0
    }
    if (-not $cmd.Contains('{tests}')) { Write-Output "FAIL ${GateName}: affectedTests.cmd must hold {tests}"; exit 2 }
}
$join = Get-RawText $aff 'joiner' (Get-RawText (Get-CfgValue $cfg 'redCheck' $null) 'joiner' '|')

$top = (& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $top) { Write-Output "FAIL ${GateName}: not inside a git work tree"; exit 2 }
$gd = ((& git -C $PSScriptRoot rev-parse --show-prefix) -replace '/$', '')
if (-not $gd) { $gd = '.' }
Set-Location -LiteralPath $top

$baseRef = Get-CfgValue $cfg 'baseRef' 'main'
if (-not $Base) { $Base = Get-FrozenSha (Join-Path $top $gd) }
if (-not $Base) { $Base = $baseRef }
& git rev-parse --verify --quiet "$Base^{commit}" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Output "FAIL ${GateName}: base '$Base' does not resolve - pass the QA-frozen SHA."; exit 2 }
$tbase = (& git merge-base $baseRef $Base 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $tbase) { $tbase = $Base }

$paths = Get-CfgValue $cfg 'paths' $null
$code = @(Get-GlobSpecs (Get-CfgList $paths 'code'))
if ($code.Count -eq 0) { $code = @(':(glob)src/**') }
$globs = @(Get-CfgList $aff 'globs')
if ($globs.Count -eq 0) { $globs = @(Get-CfgList $cfg 'testGlobs') }
if ($globs.Count -eq 0) { $globs = @(Get-CfgList $paths 'tests') }
if ($globs.Count -eq 0) { $globs = @('tests/**') }
$tspec = @(Get-GlobSpecs $globs)

function Get-Lines($raw) { return @($raw | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) }

$codeFiles = Get-Lines (@(& git diff --name-only --no-renames $Base -- @code 2>$null) + @(& git ls-files --others --exclude-standard -- @code 2>$null))
$keys = New-Object 'System.Collections.Generic.SortedSet[string]' ([StringComparer]::Ordinal)
foreach ($f in $codeFiles) { $s = Get-FileStem $f; if ($s) { [void]$keys.Add($s) } }
foreach ($e in (Get-CfgList $aff 'extraStems')) { [void]$keys.Add($e) }

$tests = New-Object 'System.Collections.Generic.SortedSet[string]' ([StringComparer]::Ordinal)
foreach ($t in (Get-Lines (@(& git diff --name-only --no-renames --diff-filter=ACMR $tbase -- @tspec 2>$null) + @(& git ls-files --others --exclude-standard -- @tspec 2>$null)))) { [void]$tests.Add($t) }
if ($keys.Count -gt 0) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('affected_tests-' + [guid]::NewGuid().ToString('N') + '.keys')
    try {
        Write-LfFile $tmp @($keys)
        foreach ($t in (Get-Lines (@(& git grep -I -l -w -F -f $tmp --untracked -- @tspec 2>$null)))) { [void]$tests.Add($t) }
    } finally { Remove-Item -Force $tmp -ErrorAction SilentlyContinue }
}
$short = $Base.Substring(0, [Math]::Min(7, $Base.Length))

if ($List) {
    foreach ($k in $keys) { Write-Output "key: $k" }
    foreach ($t in $tests) { Write-Output "test: $t" }
    Write-Output "PASS ${GateName}: $($keys.Count) key(s), $($tests.Count) affected test file(s) vs $short."
    exit 0
}
if ($tests.Count -eq 0) {
    Write-Output "PASS ${GateName}: no affected test file ($($keys.Count) key(s) vs $short)."
    exit 0
}

$stems = New-Object 'System.Collections.Generic.SortedSet[string]' ([StringComparer]::Ordinal)
foreach ($f in $tests) {
    $s = Get-FileStem $f
    if (-not $s -or $s -notmatch '^[A-Za-z0-9_.+-]+$') {
        Write-Output "FAIL ${GateName}: '$f' has a file stem outside [A-Za-z0-9_.+-]; {tests} cannot carry it safely."
        exit 2
    }
    [void]$stems.Add($s)
}
$cmd = $cmd.Replace('{tests}', ($stems -join $join))
if (-not (Test-OneLine $GateName 'affectedTests.cmd' $cmd)) { exit 2 }
$r = Invoke-ShellCapture $cmd
if ($r.out) { Write-Output $r.out }
if ($r.rc -eq 0) {
    Write-Output "PASS ${GateName}: affectedTests.cmd exited 0 ($($tests.Count) test file(s))."
    exit 0
}
Write-Output "FAIL ${GateName}: affectedTests.cmd exited $($r.rc) ($($tests.Count) test file(s))."
exit 1
