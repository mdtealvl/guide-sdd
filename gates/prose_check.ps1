#!/usr/bin/env pwsh
# prose_check - spec shards are terse and structured, not blocks of prose (SDD-PROP-09).
#
# Generic gate. Measures, per shard, (a) the PARAGRAPH SHARE - words inside paragraph
# text divided by all words - and (b) the LONGEST PARAGRAPH in words. Structured text
# (list items, table cells, code, headings, definition lists) is the spec form the method
# wants; paragraph text is what the form allows only where a rule cannot be a line.
#
#   HTML shards (.html/.htm): <li> <td> <th> <dt> <dd> <pre> <code> <h1>-<h6> <caption> are
#     structured; <p> outside them, and loose text, are paragraph. A <p> nested in a
#     structured element counts as structured for the share but still counts toward the
#     longest-paragraph figure. <script>/<style>/comments are ignored.
#   Markdown shards (anything else): list / numbered / lettered / roman items, headings,
#     table rows, fenced code, and indented continuation lines are structured; other
#     non-blank lines are paragraph (consecutive lines = one paragraph).
#
# Scope = spec shards changed vs baseRef (git diff base...HEAD + working tree + untracked),
# like fold_check - a shard touched this ship must meet the bar (migrate-on-contact).
# -All checks the whole corpus. Run from the repo root (paths.spec is repo-relative).
#
# proseCheck.mode: warn (default - violations print, exit 0) | strict (violations FAIL) |
# off (gate skipped). -Strict upgrades warn to strict; off always wins.
# FAIL CLOSED if git is present but the base does not resolve (exit 2) - unless -All.
#
# Exit 0 PASS/WARN, 1 FAIL (strict), 2 config/usage error.
# Usage:  pwsh gates/prose_check.ps1 [-Config gates/gates.config.json] [-Base <ref>] [-All] [-Strict] [-Report]

[CmdletBinding()]
param(
    [string]$Config = 'gates/gates.config.json',
    [string]$Base,
    [switch]$All,
    [switch]$Strict,
    [switch]$Report
)
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_common.ps1"

$GateName = 'prose_check'
$cfg = Read-Config $Config $GateName

$specGlobs = @('spec/**/*.body.md')
if ($cfg.PSObject.Properties.Name -contains 'paths' -and $cfg.paths -and ($cfg.paths.PSObject.Properties.Name -contains 'spec') -and $cfg.paths.spec) {
    $specGlobs = @($cfg.paths.spec)
}
$pc = Get-CfgValue $cfg 'proseCheck' $null
$mode      = [string](Get-CfgValue $pc 'mode' 'warn')
$maxShare  = [double](Get-CfgValue $pc 'maxParaShare' 0.35)
$maxParaW  = [int](Get-CfgValue $pc 'maxParaWords' 100)
$minWords  = [int](Get-CfgValue $pc 'minWords' 120)
$exclude   = @(Get-CfgValue $pc 'excludeGlobs' @())
$maxSharePct = [int][math]::Floor($maxShare * 100 + 0.5)

if ($mode -eq 'off') {
    Write-Output "SKIP ${GateName}: proseCheck.mode=off in config."
    exit 0
}
if ($mode -ne 'strict' -and $mode -ne 'warn') {
    Write-Output "FAIL ${GateName}: proseCheck.mode must be warn | strict | off (got '$mode')."
    exit 2
}
if ($Strict) { $mode = 'strict' }

# ---------------------------------------------------------------- word counting
$wordRe = [regex]'[^ \t\r\n\f\v]+'
function Get-WordCount([string]$s) {
    if ([string]::IsNullOrEmpty($s)) { return 0 }
    return $wordRe.Matches($s).Count
}

# ---------------------------------------------------------------- HTML measure
$structTags = @('li','td','th','dt','dd','pre','code','h1','h2','h3','h4','h5','h6','caption')
$blockTags  = @('p','div','section','article','ul','ol','dl','table','blockquote','hr','li','dt','dd','pre','h1','h2','h3','h4','h5','h6','tr','td','th','thead','tbody','figure','aside','nav','header','footer','details','summary')
$skipTags   = @('script','style')

function Measure-Html([string]$t) {
    $total = 0; $para = 0; $maxPara = 0; $cur = 0
    $structDepth = 0; $skipDepth = 0; $inP = $false
    $pos = 0; $n = $t.Length
    while ($pos -lt $n) {
        $i = $t.IndexOf('<', $pos)
        if ($i -lt 0) { $seg = $t.Substring($pos) } else { $seg = $t.Substring($pos, $i - $pos) }
        $w = Get-WordCount $seg
        if ($w -gt 0 -and $skipDepth -eq 0) {
            $total += $w
            if ($structDepth -eq 0) { $para += $w }
            if ($inP) { $cur += $w }
        }
        if ($i -lt 0) { break }
        if ($i + 4 -le $n -and $t.Substring($i, 4) -eq '<!--') {
            $e = $t.IndexOf('-->', $i + 4)
            if ($e -lt 0) { break }
            $pos = $e + 3
            continue
        }
        $j = $t.IndexOf('>', $i)
        if ($j -lt 0) { break }
        $tag = $t.Substring($i, $j - $i + 1)
        $pos = $j + 1
        $k = 1; $isClose = $false
        if ($k -lt $tag.Length -and $tag[$k] -eq '/') { $isClose = $true; $k++ }
        $start = $k
        while ($k -lt $tag.Length -and (($tag[$k] -ge 'a' -and $tag[$k] -le 'z') -or ($tag[$k] -ge 'A' -and $tag[$k] -le 'Z') -or ($tag[$k] -ge '0' -and $tag[$k] -le '9'))) { $k++ }
        $name = $tag.Substring($start, $k - $start).ToLowerInvariant()
        if ($name -eq '') { continue }
        $selfClose = $tag.EndsWith('/>')
        if ($skipTags -contains $name) {
            if ($isClose) { if ($skipDepth -gt 0) { $skipDepth-- } } elseif (-not $selfClose) { $skipDepth++ }
            continue
        }
        if ($name -eq 'p') {
            if ($isClose) {
                if ($inP) { if ($cur -gt $maxPara) { $maxPara = $cur }; $cur = 0; $inP = $false }
            } elseif (-not $selfClose) {
                if ($inP) { if ($cur -gt $maxPara) { $maxPara = $cur }; $cur = 0 }
                $inP = $true
            }
            continue
        }
        if ($inP -and ($blockTags -contains $name)) {
            if ($cur -gt $maxPara) { $maxPara = $cur }; $cur = 0; $inP = $false
        }
        if ($structTags -contains $name) {
            if ($isClose) { if ($structDepth -gt 0) { $structDepth-- } } elseif (-not $selfClose) { $structDepth++ }
        }
    }
    if ($inP -and $cur -gt $maxPara) { $maxPara = $cur }
    return @{ total = $total; para = $para; maxPara = $maxPara }
}

# ---------------------------------------------------------------- Markdown measure
$mdStructRe = [regex]'^[ \t]*(?:[-*+][ \t]+|[0-9]+[.)][ \t]+|[A-Za-z][.)][ \t]+|[ivxlcIVXLC]+[.)][ \t]+|#+[ \t]+|\|)'
$bt = [string][char]96
$mdFenceRe  = [regex]('^[ \t]*(?:' + $bt + $bt + $bt + '|~~~)')
$mdBlankRe  = [regex]'^[ \t]*$'
$tabChar = [char]9

function Get-Indent([string]$line) {
    $c = 0
    foreach ($ch in $line.ToCharArray()) {
        if ($ch -eq ' ') { $c++ } elseif ($ch -eq $tabChar) { $c += 4 } else { break }
    }
    return $c
}

function Measure-Md([string[]]$lines) {
    $total = 0; $para = 0; $maxPara = 0; $cur = 0
    $inFence = $false; $contIndent = -1; $prevBlank = $true
    foreach ($line in $lines) {
        if ($null -eq $line) { continue }
        if ($mdFenceRe.IsMatch($line)) {
            $inFence = -not $inFence
            if ($cur -gt $maxPara) { $maxPara = $cur }; $cur = 0
            $contIndent = -1; $prevBlank = $false
            continue
        }
        if ($inFence) { $total += Get-WordCount $line; continue }
        if ($mdBlankRe.IsMatch($line)) {
            if ($cur -gt $maxPara) { $maxPara = $cur }; $cur = 0
            $contIndent = -1; $prevBlank = $true
            continue
        }
        $w = Get-WordCount $line
        $m = $mdStructRe.Match($line)
        if ($m.Success) {
            $total += $w
            if ($cur -gt $maxPara) { $maxPara = $cur }; $cur = 0
            $trim = $line.TrimStart(' ', $tabChar)
            if ($trim.StartsWith('#') -or $trim.StartsWith('|')) { $contIndent = -1 } else { $contIndent = $m.Length }
            $prevBlank = $false
            continue
        }
        $indent = Get-Indent $line
        if (-not $prevBlank -and $contIndent -ge 0 -and $indent -ge $contIndent) { $total += $w; continue }
        $total += $w; $para += $w; $cur += $w
        $prevBlank = $false; $contIndent = -1
    }
    if ($cur -gt $maxPara) { $maxPara = $cur }
    return @{ total = $total; para = $para; maxPara = $maxPara }
}

# ---------------------------------------------------------------- shard set
function Expand-GlobsUnder([string[]]$globs) {
    # Like Expand-Globs, but enumerates only under each glob's static prefix directory
    # (spec corpora sit beside very large trees; walking the whole root is wasteful).
    $root = ((Get-Location).Path -replace '\\', '/').TrimEnd('/')
    $result = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($g in $globs) {
        if ([string]::IsNullOrEmpty($g)) { continue }
        $gn = $g -replace '\\', '/'
        $idx = $gn.IndexOfAny([char[]]@('*', '?', '['))
        $static = if ($idx -ge 0) { $gn.Substring(0, $idx) } else { $gn }
        $slash = $static.LastIndexOf('/')
        $dir = if ($slash -ge 0) { $static.Substring(0, $slash) } else { '.' }
        if ($dir -eq '') { $dir = '.' }
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        $re = ConvertTo-Regex $gn
        Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $full = $_.FullName -replace '\\', '/'
            if ($full.StartsWith($root + '/')) {
                $rel = $full.Substring($root.Length + 1)
                if ($re.IsMatch($rel)) { [void]$result.Add($rel) }
            }
        }
    }
    $arr = @($result)
    if ($arr.Count -gt 1) { [array]::Sort($arr, [System.StringComparer]::Ordinal) }
    return $arr
}

$shards = @(Expand-GlobsUnder $specGlobs)
if ($exclude.Count -gt 0) {
    $exRes = @()
    foreach ($g in $exclude) { if ($g) { $exRes += ,(ConvertTo-Regex ($g -replace '\\', '/')) } }
    $keep = New-Object System.Collections.Generic.List[string]
    foreach ($f in $shards) {
        $hit = $false
        foreach ($re in $exRes) { if ($re.IsMatch($f)) { $hit = $true; break } }
        if (-not $hit) { $keep.Add($f) }
    }
    $shards = @($keep)
}
if ($shards.Count -eq 0) {
    Write-Output "FAIL ${GateName}: no spec shards matched $($specGlobs -join ', ')"
    exit 1
}

# ---------------------------------------------------------------- scope
$gitAvailable = [bool](Get-Command git -ErrorAction SilentlyContinue)
$files = @(); $scope = ''
if ($All) {
    $files = $shards; $scope = 'all shards'
} elseif (-not $gitAvailable) {
    Write-Output "NOTE ${GateName}: git unavailable - checking ALL spec shards."
    $files = $shards; $scope = 'all shards (no git)'
} else {
    $base = $Base
    if (-not $base) { $base = Get-CfgValue $cfg 'baseRef' 'main' }
    git rev-parse --verify --quiet "$base^{commit}" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Output "FAIL ${GateName}: baseRef '$base' does not resolve - set baseRef to the ship base, or run with -All."
        exit 2
    }
    $out = & git diff --name-only "$base...HEAD" 2>$null
    if ($LASTEXITCODE -ne 0) { $out = & git diff --name-only "$base" 2>$null }
    if ($LASTEXITCODE -ne 0) {
        Write-Output "NOTE ${GateName}: git diff failed - checking ALL spec shards."
        $files = $shards; $scope = 'all shards (git diff failed)'
    } else {
        $changed = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($line in @($out)) { if ($line) { [void]$changed.Add((([string]$line).Trim() -replace '\\', '/')) } }
        $wt = & git diff --name-only HEAD 2>$null
        if ($LASTEXITCODE -eq 0) { foreach ($line in @($wt)) { if ($line) { [void]$changed.Add((([string]$line).Trim() -replace '\\', '/')) } } }
        $un = & git ls-files --others --exclude-standard 2>$null
        if ($LASTEXITCODE -eq 0) { foreach ($line in @($un)) { if ($line) { [void]$changed.Add((([string]$line).Trim() -replace '\\', '/')) } } }
        $files = @($shards | Where-Object { $changed.Contains($_) })
        $scope = "changed vs $base"
    }
}

# ---------------------------------------------------------------- measure + report
Write-Output ("{0}: scope={1} ({2} shard(s)); thresholds share<={3}% para<={4}w (share applies at >={5}w); mode={6}" -f $GateName, $scope, $files.Count, $maxSharePct, $maxParaW, $minWords, $mode)
if ($files.Count -eq 0) {
    Write-Output "PASS ${GateName}: no spec shards in scope."
    exit 0
}

$over = 0
foreach ($f in $files) {
    if ($f -match '\.html?$') { $r = Measure-Html (Read-FileText $f) } else { $r = Measure-Md (Read-FileLines $f) }
    $total = [int]$r.total; $para = [int]$r.para; $mp = [int]$r.maxPara
    $pct = 0
    if ($total -gt 0) { $pct = [int][math]::Floor(($para * 200 + $total) / (2 * $total)) }
    $reasons = @()
    if ($total -ge $minWords -and $pct -gt $maxSharePct) { $reasons += "share>$maxSharePct%" }
    if ($mp -gt $maxParaW) { $reasons += "para>${maxParaW}w" }
    if ($reasons.Count -gt 0) {
        $over++
        Write-Output ("  OVER  {0,3}%  {1,5}w  {2}  [{3}]" -f $pct, $mp, $f, ($reasons -join ', '))
    } elseif ($Report) {
        $note = ''
        if ($total -lt $minWords) { $note = "  (share n/a: ${total}w < ${minWords}w)" }
        Write-Output ("  ok    {0,3}%  {1,5}w  {2}{3}" -f $pct, $mp, $f, $note)
    }
}

if ($over -eq 0) {
    Write-Output "PASS ${GateName}: $($files.Count) shard(s) checked, 0 over threshold."
    exit 0
}
if ($mode -eq 'strict') {
    Write-Output "FAIL ${GateName}: $($files.Count) shard(s) checked, $over over threshold - restructure per stages/3_spec.md 'Spec form' (decisions only; lists/tables/code; one fact per line)."
    exit 1
}
Write-Output "WARN ${GateName}: $($files.Count) shard(s) checked, $over over threshold (mode=warn - set proseCheck.mode=strict or pass -Strict to enforce)."
exit 0
