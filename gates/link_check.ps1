#!/usr/bin/env pwsh
# link_check — every spec cross-ref/href resolves to a real anchor/shard.
#
# Generic gate. Content-only spec shards keep the parse trivial, so link_check is a
# pure set operation: collect the anchor set (declared anchors UNION clause-IDs) across
# all shards, then assert every internal cross-ref points into it. Skips http/mailto.
#
# A clause-ID is DECLARED only when it appears on an anchored line (id=, name=, {#..},
# <!-- §..) or a heading / bold-or-list definition line; bare prose occurrences are
# citations that must resolve. SAFETY FALLBACK: if nothing is anchored, treat all
# clause-IDs as declared and print a NOTE.
#
# Exit 0 PASS, 1 FAIL, 2 config error.
# Usage:  pwsh gates/link_check.ps1 [-Config gates/gates.config.json]

[CmdletBinding()]
param(
    [string]$Config = 'gates/gates.config.json'
)
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_common.ps1"

$cfg = Read-Config $Config 'link_check'
$clausePattern = Get-CfgValue $cfg 'clauseIdRegex' '\b[A-Z]{2,}\.\d+\b'
$specGlob = 'spec/**/*.body.md'
if ($cfg.PSObject.Properties.Name -contains 'paths' -and $cfg.paths -and ($cfg.paths.PSObject.Properties.Name -contains 'spec') -and $cfg.paths.spec) {
    $specGlob = $cfg.paths.spec
}
$clauseRe = [regex]$clausePattern

$shards = Expand-Globs $specGlob
if ($shards.Count -eq 0) {
    Write-Output "FAIL link_check: no spec shards matched $specGlob"
    exit 1
}

# Anchor declarations, stack-agnostic across Markdown + content-only HTML fragments.
$anchorPatterns = @(
    [regex]'id\s*=\s*["'']([^"'']+)["'']',
    [regex]'name\s*=\s*["'']([^"'']+)["'']',
    [regex]'\{#([^}\s]+)\}',
    [regex]'<!--\s*§\s*([^\s]+)'
)
# Cross-references: capture the href target (with optional file part + #fragment).
$hrefPatterns = @(
    [regex]'\]\(\s*([^)\s]+)\s*\)',
    [regex]'href\s*=\s*["'']([^"'']+)["'']'
)
$headingRe = [regex]'^\s*#{1,6}\s'
$defnRe = [regex]('^\s*[-*]?\s*\**' + $clausePattern)

$globalAnchors  = New-Object 'System.Collections.Generic.HashSet[string]'
$globalClauses  = New-Object 'System.Collections.Generic.HashSet[string]'
$declaredClauses = New-Object 'System.Collections.Generic.HashSet[string]'
$shardNames = New-Object 'System.Collections.Generic.HashSet[string]'
$perShard = @{}   # basename -> HashSet(anchors+clauses)
$texts = @{}

foreach ($s in $shards) {
    $t = Read-FileText $s
    $texts[$s] = $t
    $name = Split-Path -Leaf $s
    [void]$shardNames.Add($name)

    $anchors = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($pat in $anchorPatterns) {
        foreach ($m in $pat.Matches($t)) { [void]$anchors.Add($m.Groups[1].Value) }
    }
    $clauses = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($m in $clauseRe.Matches($t)) { [void]$clauses.Add($m.Value) }

    $ps = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($a in $anchors) { [void]$ps.Add($a) }
    foreach ($c in $clauses) { [void]$ps.Add($c) }
    $perShard[$name] = $ps
    foreach ($a in $anchors) { [void]$globalAnchors.Add($a) }
    foreach ($c in $clauses) { [void]$globalAnchors.Add($c); [void]$globalClauses.Add($c) }

    # Per-line: a clause-ID on an anchored / heading / definition line is declared.
    foreach ($line in ($t -split "`n")) {
        $isDecl = $false
        foreach ($p in $anchorPatterns) { if ($p.IsMatch($line)) { $isDecl = $true; break } }
        if (-not $isDecl) { if ($headingRe.IsMatch($line)) { $isDecl = $true } }
        if (-not $isDecl) { if ($defnRe.IsMatch($line)) { $isDecl = $true } }
        if ($isDecl) {
            foreach ($m in $clauseRe.Matches($line)) { [void]$declaredClauses.Add($m.Value) }
        }
    }
}

# SAFETY FALLBACK: a project that never anchors its clauses must not false-FAIL.
if ($declaredClauses.Count -eq 0) {
    foreach ($c in $globalClauses) { [void]$declaredClauses.Add($c) }
    Write-Output "NOTE link_check: no anchored clause declarations found; treating all clause-IDs as declared."
}

# Check every href and every cited clause-ID resolves.
$broken = New-Object System.Collections.Generic.List[object]
foreach ($s in $shards) {
    $t = $texts[$s]
    $src = Split-Path -Leaf $s
    foreach ($pat in $hrefPatterns) {
        foreach ($m in $pat.Matches($t)) {
            $href = $m.Groups[1].Value
            if ($href -match '^(https?://|mailto:|tel:)') { continue }
            $hashIdx = $href.IndexOf('#')
            if ($hashIdx -ge 0) {
                $filePart = $href.Substring(0, $hashIdx)
                $frag = $href.Substring($hashIdx + 1)
            } else {
                $filePart = $href
                $frag = ''
            }
            if ($filePart) {
                $target = Split-Path -Leaf $filePart
                if (-not $shardNames.Contains($target)) {
                    $broken.Add([pscustomobject]@{ src = $src; ref = $href; why = 'no such shard' })
                    continue
                }
                if ($frag -and (-not $perShard[$target].Contains($frag))) {
                    $broken.Add([pscustomobject]@{ src = $src; ref = $href; why = "shard has no anchor #$frag" })
                }
            } elseif ($frag) {
                if (-not $globalAnchors.Contains($frag)) {
                    $broken.Add([pscustomobject]@{ src = $src; ref = $href; why = "no anchor #$frag anywhere" })
                }
            }
        }
    }
    foreach ($m in $clauseRe.Matches($t)) {
        $cid = $m.Value
        if (-not $declaredClauses.Contains($cid)) {
            $broken.Add([pscustomobject]@{ src = $src; ref = $cid; why = 'cited clause-ID not declared (no anchored declaration found)' })
        }
    }
}

if ($broken.Count -eq 0) {
    Write-Output "PASS link_check: $($shards.Count) shard(s), all cross-refs resolve."
    exit 0
}

Write-Output "FAIL link_check: $($broken.Count) unresolved reference(s):"
foreach ($b in $broken) {
    Write-Output "  $($b.src): '$($b.ref)' — $($b.why)"
}
exit 1
