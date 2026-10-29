#!/usr/bin/env pwsh
# retire_check - a retired name must not survive in the spec, the tests or the docs.
#
# A unit that renames or retires a name (type, method, event token, state) leaves references to the
# old one behind in spec tables, test titles and docs. Validation finds them as LOW findings, one fix
# round each. This gate finds them with git grep instead.
#
# Retired names are the union of:
#   * gates/.retired (retireCheck.file): one `old -> new` per line (`old` alone is fine; blank lines and
#     # comments are skipped). Explicit names need no other evidence.
#   * auto-derived: a token matching retireCheck.identRegex that is in a REMOVED line of
#     `git diff {base} -- paths.code`, occurs in paths.code at {base}, and has 0 whole-word
#     occurrences in paths.code now (the working tree: HEAD plus uncommitted work).
# retireCheck.allow names are never retired.
#
# A hit is a whole-word occurrence of a retired name, now, in paths.spec, testGlobs or
# retireCheck.extraGlobs, minus retireCheck.excludeGlobs, minus lines matching
# retireCheck.tombstoneRegex (a lifecycle marker: [REMOVED 2026-06-24 ...]). Each prints as
# `file:line: name` (`name -> new` when declared).
#
# mode: warn (default: hits print as WARN, exit 0) | strict (hits FAIL) | off. The retireCheck section
# absent = "not configured" PASS.
# {base}: -Base, else gates/.frozen, else config baseRef. Cost: one git diff and a few git grep calls.
#
# Exit 0 PASS, 1 FAIL, 2 config/usage error.
# Usage:  pwsh gates/retire_check.ps1 [-Base <sha>] [-Config gates/gates.config.json]

[CmdletBinding()]
param(
    [string]$Base = '',
    [string]$Config = 'gates/gates.config.json'
)
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_common.ps1"

$GateName = 'retire_check'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Output "FAIL ${GateName}: need git"; exit 2 }
if (-not (Test-Path -LiteralPath $Config)) { Write-Output "FAIL ${GateName}: cannot read config ${Config}: no such file"; exit 2 }
$Config = (Resolve-Path -LiteralPath $Config).Path
$cfg = Read-Config $Config $GateName
$rc = Get-CfgValue $cfg 'retireCheck' $null
if ($null -eq $rc) {
    Write-Output "PASS ${GateName}: not configured (retireCheck section absent) - retired names are unchecked."
    exit 0
}
$mode = Get-CfgValue $rc 'mode' 'warn'
if ($mode -eq 'off') { Write-Output "PASS ${GateName}: mode off."; exit 0 }
if ($mode -ne 'warn' -and $mode -ne 'strict') { Write-Output "FAIL ${GateName}: retireCheck.mode must be warn, strict or off (got '$mode')"; exit 2 }

$top = (& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $top) { Write-Output "FAIL ${GateName}: not inside a git work tree"; exit 2 }
$gd = ((& git -C $PSScriptRoot rev-parse --show-prefix) -replace '/$', '')
if (-not $gd) { $gd = '.' }
Set-Location -LiteralPath $top

if (-not $Base) { $Base = Get-FrozenSha (Join-Path $top $gd) }
if (-not $Base) { $Base = Get-CfgValue $cfg 'baseRef' 'main' }
& git rev-parse --verify --quiet "$Base^{commit}" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Output "FAIL ${GateName}: base '$Base' does not resolve - pass the QA-frozen SHA."; exit 2 }

$ident = Get-CfgValue $rc 'identRegex' '_*[A-Za-z0-9]+_[A-Za-z0-9_]+|[A-Za-z0-9]*[a-z][A-Za-z0-9]*[A-Z][A-Za-z0-9_]*'
$tomb = Get-CfgValue $rc 'tombstoneRegex' '\[(DEPRECATED|SUPERSEDED|MOVED|REMOVED) [0-9]{4}-[0-9]{2}-[0-9]{2}'
$rfile = Get-CfgValue $rc 'file' "$gd/.retired"
foreach ($re in @($ident, $tomb)) {
    & git grep --no-index -q -E -e $re -- "$gd/_common.ps1" 2>&1 | Out-Null
    if ($LASTEXITCODE -gt 1) { Write-Output "FAIL ${GateName}: '$re' is not a regex git grep -E accepts (retireCheck.identRegex / tombstoneRegex)"; exit 2 }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('retire_check-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $tmp | Out-Null
try {
    $paths = Get-CfgValue $cfg 'paths' $null
    $code = @(Get-GlobSpecs (Get-CfgList $paths 'code'))
    if ($code.Count -eq 0) { $code = @(':(glob)src/**') }

    # 1. explicit names: name -> new ('' when none)
    $names = [ordered]@{}
    if (Test-Path -LiteralPath $rfile) {
        foreach ($l in (Read-FileLines $rfile)) {
            if ($l -match '^\s*(#|$)') { continue }
            $new = ''; $old = $l
            $m = [regex]::Match($l, '\s*->\s*')
            if ($m.Success) { $old = $l.Substring(0, $m.Index); $new = $l.Substring($m.Index + $m.Length).Trim() }
            $old = $old.Trim()
            if ($old -and $old -notmatch '\s' -and -not $names.Contains($old)) { $names[$old] = $new }
        }
    }

    # 2. auto-derived: removed-line tokens present at the base and gone now
    $diff = @(& git diff --no-renames --no-color -U0 $Base -- @code 2>$null)
    $cand = New-Object 'System.Collections.Generic.SortedSet[string]' ([StringComparer]::Ordinal)
    $hdr = $false
    $identRx = [regex]::new($ident)
    foreach ($l0 in $diff) {
        $l = "$l0" -replace "`r$", ''
        if ($l.StartsWith('diff --git')) { $hdr = $true; continue }
        if ($l.StartsWith('@@')) { $hdr = $false; continue }
        if (-not $hdr -and $l.StartsWith('-')) {
            foreach ($mm in $identRx.Matches($l.Substring(1))) { if ($mm.Value.Length -ge 4) { [void]$cand.Add($mm.Value) } }
        }
    }
    if ($cand.Count -gt 0) {
        Write-LfFile "$tmp/cand" @($cand)
        $atBase = New-Object 'System.Collections.Generic.SortedSet[string]' ([StringComparer]::Ordinal)
        foreach ($x in @(& git grep -h -o -w -F -f "$tmp/cand" $Base -- @code 2>$null)) { if ("$x") { [void]$atBase.Add(("$x" -replace "`r$", '')) } }
        $atNow = New-Object 'System.Collections.Generic.HashSet[string]'
        if ($atBase.Count -gt 0) {
            Write-LfFile "$tmp/atbase" @($atBase)
            foreach ($x in @(& git grep -h -o -w -F -f "$tmp/atbase" --untracked -- @code 2>$null)) { [void]$atNow.Add(("$x" -replace "`r$", '')) }
        }
        foreach ($n in $atBase) { if (-not $atNow.Contains($n) -and -not $names.Contains($n)) { $names[$n] = '' } }
    }

    # 3. drop allowed names
    foreach ($a in (Get-CfgList $rc 'allow')) { if ($names.Contains($a)) { $names.Remove($a) } }
    if ($names.Count -eq 0) { Write-Output "PASS ${GateName}: no retired names vs $Base."; exit 0 }
    Write-LfFile "$tmp/names" @($names.Keys)

    # 4. whole-word hits in spec, tests and extra globs, minus tombstone lines
    $scope = @(Get-GlobSpecs (@(Get-CfgList $paths 'spec') + @(Get-CfgList $cfg 'testGlobs') + @(Get-CfgList $rc 'extraGlobs')))
    if ($scope.Count -eq 0) { Write-Output "PASS ${GateName}: no paths.spec, testGlobs or extraGlobs to check."; exit 0 }
    $scope += @(Get-GlobSpecs (Get-CfgList $rc 'excludeGlobs') -Exclude)
    $scope += @(Get-GlobSpecs @($rfile) -Exclude)
    $hits = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($x in @(& git grep -I --untracked -n -o -w -F -f "$tmp/names" -- @scope 2>$null)) { if ("$x") { [void]$hits.Add(("$x" -replace "`r$", '')) } }
    $tombLines = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($x in @(& git grep -I --untracked -n -E -e $tomb -- @scope 2>$null)) {
        $p = "$x".Split(':', 3)
        if ($p.Count -ge 2) { [void]$tombLines.Add($p[0] + ':' + $p[1]) }
    }
    $live = @()
    foreach ($h in $hits) {
        $p = $h.Split(':', 3)
        if ($p.Count -lt 3) { continue }
        if ($tombLines.Contains($p[0] + ':' + $p[1])) { continue }
        $live += [pscustomobject]@{ File = $p[0]; Line = [int]$p[1]; Name = $p[2] }
    }
    if ($live.Count -eq 0) { Write-Output "PASS ${GateName}: no retired name survives ($($names.Count) checked vs $Base)."; exit 0 }
    $verdict = if ($mode -eq 'strict') { 'FAIL' } else { 'WARN' }
    Write-Output "$verdict ${GateName}: $($live.Count) reference(s) to a retired name (a name that lives on goes in retireCheck.allow):"
    foreach ($h in ($live | Sort-Object -Property @{ Expression = { $_.File }; Ascending = $true }, @{ Expression = { $_.Line }; Ascending = $true })) {
        $nw = $names[$h.Name]
        Write-Output ("  {0}:{1}: {2}{3}" -f $h.File, $h.Line, $h.Name, $(if ($nw) { " -> $nw" } else { '' }))
    }
    if ($mode -eq 'strict') { exit 1 }
    Write-Output "PASS ${GateName}: warn mode - not enforced (retireCheck.mode = strict fails the gate)."
    exit 0
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
