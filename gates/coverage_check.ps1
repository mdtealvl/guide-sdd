#!/usr/bin/env pwsh
# coverage_check — every behavioural clause-ID resolves to >=1 test-ID, both directions.
#
# Generic gate. Stack-agnostic: pure text scan parameterised by gates.config.json.
#
# Default mode  : clauses from spec shards (paths.spec); tags from test files (testGlobs).
# -Plan mode    : tags from the Stage-4 test plan (a *plan*.body.md shard tagged with
#                 @clause: lines), so the plan is coverage-checked before any test exists.
#
# Clause-set scope:
#   default       = WHOLE-CORPUS — every clause in paths.spec needs a test. This is the
#                   SHIP-TIME invariant; run it with no flag at Stage 5/7.
#   -Manifest <f> = PER-UNIT — restrict the clause set to the clause-IDs listed in the
#                   shard manifest <f> (one clause-ID per line, OR any text whose clause-IDs
#                   are matched by clauseIdRegex). For fast in-loop feedback on a single
#                   shard/unit; NOT a substitute for the whole-corpus ship check.
#
# A clause CB.12 is "covered" when some test/plan file contains the literal tag
# "<testClauseTag>CB.12" (default tag prefix "@clause:").
#
# PASS when clauses == tagged (no orphan clauses, no tags for unknown clauses).
# Exit 0 PASS, 1 FAIL, 2 config/usage error.
#
# Usage:
#   pwsh gates/coverage_check.ps1 [-Config gates/gates.config.json] [-Plan]
#        [-PlanGlob 'spec/**/*plan*.body.md'] [-Manifest <file>]

[CmdletBinding()]
param(
    [string]$Config = 'gates/gates.config.json',
    [switch]$Plan,
    [string]$PlanGlob = 'spec/**/*plan*.body.md',
    [string]$Manifest
)
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_common.ps1"

$cfg = Read-Config $Config 'coverage_check'

$clausePattern = Get-CfgValue $cfg 'clauseIdRegex' '\b[A-Z]{2,}\.\d+\b'
$tagPrefix     = Get-CfgValue $cfg 'testClauseTag' '@clause:'
$specGlob      = 'spec/**/*.body.md'
if ($cfg.PSObject.Properties.Name -contains 'paths' -and $cfg.paths -and ($cfg.paths.PSObject.Properties.Name -contains 'spec') -and $cfg.paths.spec) {
    $specGlob = $cfg.paths.spec
}
$testGlobs = $null
if ($cfg.PSObject.Properties.Name -contains 'testGlobs' -and $cfg.testGlobs) { $testGlobs = @($cfg.testGlobs) }
if (-not $testGlobs) {
    $defTests = 'tests/**'
    if ($cfg.PSObject.Properties.Name -contains 'paths' -and $cfg.paths -and ($cfg.paths.PSObject.Properties.Name -contains 'tests') -and $cfg.paths.tests) { $defTests = $cfg.paths.tests }
    $testGlobs = @($defTests)
}

$clauseRe = [regex]$clausePattern

$specFiles = Expand-Globs $specGlob
if ($specFiles.Count -eq 0) {
    Write-Output "FAIL coverage_check: no spec shards matched $specGlob"
    exit 1
}

# clause-ID -> set(shard paths declaring it)
$clauses = @{}
foreach ($p in $specFiles) {
    $text = Read-FileText $p
    foreach ($m in $clauseRe.Matches($text)) {
        $cid = $m.Value
        if (-not $clauses.ContainsKey($cid)) { $clauses[$cid] = New-Object 'System.Collections.Generic.HashSet[string]' }
        [void]$clauses[$cid].Add($p)
    }
}

$scope = 'whole-corpus'
if ($Manifest) {
    if (-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) {
        Write-Output "FAIL coverage_check: cannot read manifest ${Manifest}: no such file"
        exit 2
    }
    # Restrict the clause set to clause-IDs named in the manifest (one per line, or any
    # clause-IDs matched by clauseIdRegex anywhere in the file — the per-unit shard manifest).
    $manifestText = Read-FileText $Manifest
    $wanted = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($m in $clauseRe.Matches($manifestText)) { [void]$wanted.Add($m.Value) }
    $filtered = @{}
    foreach ($cid in $clauses.Keys) {
        if ($wanted.Contains($cid)) { $filtered[$cid] = $clauses[$cid] }
    }
    $clauses = $filtered
    $scope = "manifest $Manifest"
}

if ($Plan) {
    $tagFiles = Expand-Globs $PlanGlob
    $what = 'test plan'
} else {
    $tagFiles = Expand-Globs $testGlobs
    $what = 'tests'
}

# clause-ID -> set(test/plan paths tagging it)
$tagRe = [regex]([regex]::Escape($tagPrefix) + '\s*(' + $clausePattern + ')')
$tags = @{}
foreach ($p in $tagFiles) {
    $text = Read-FileText $p
    foreach ($m in $tagRe.Matches($text)) {
        $cid = $m.Groups[1].Value
        if (-not $tags.ContainsKey($cid)) { $tags[$cid] = New-Object 'System.Collections.Generic.HashSet[string]' }
        [void]$tags[$cid].Add($p)
    }
}

if ($Manifest) {
    # Per-unit scope: only judge tags for clause-IDs in this manifest. A tag pointing at a
    # real clause OUTSIDE the manifest is another unit's concern, not a dangling tag here.
    $tagsScoped = @{}
    foreach ($cid in $tags.Keys) {
        if ($wanted.Contains($cid)) { $tagsScoped[$cid] = $tags[$cid] }
    }
    $tags = $tagsScoped
}

$clauseIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($clauses.Keys))
$taggedIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($tags.Keys))

$orphans = @($clauses.Keys | Where-Object { -not $taggedIds.Contains($_) } | Sort-Object)
$unknown = @($tags.Keys    | Where-Object { -not $clauseIds.Contains($_) } | Sort-Object)

if ($orphans.Count -eq 0 -and $unknown.Count -eq 0) {
    Write-Output "PASS coverage_check ($what, $scope): $($clauseIds.Count) clauses, all covered."
    exit 0
}

Write-Output "FAIL coverage_check ($what, $scope): $($orphans.Count) uncovered clause(s), $($unknown.Count) dangling tag(s)."
foreach ($cid in $orphans) {
    $where = ($clauses[$cid] | Sort-Object) -join ', '
    Write-Output "  UNCOVERED $cid  (declared in $where)"
}
foreach ($cid in $unknown) {
    $where = ($tags[$cid] | Sort-Object) -join ', '
    Write-Output "  UNKNOWN-CLAUSE $cid  (tagged in $where)"
}
exit 1
