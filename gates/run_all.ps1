#!/usr/bin/env pwsh
# run_all - the full gate bank, mechanical-first, fail-fast. Exits nonzero on the first
# failing gate, so it drops into CI and pre-merge hooks unchanged.
#
# Order (Stage 7 ship):
#   link_check -> prose_check -> coverage_check -> test_edit_ban -> structure_check -> suite_green
#     -> constitution_lint* -> seam_conformance* -> qa_import_ban* -> fold_check
#     -> suite_green (re-run)
# (*) project gates run only if their concrete (non-template) .ps1 script exists.
# structure_check runs its -Frozen half (approved diagram unchanged vs the frozen base) only on
# the persona route's -PreFold pass; the forward trace runs in every pass.
#
# Working directory: the PROJECT ROOT - the git top-level of the tree the gates live in
# (so a spine vendored at sdd/ still resolves `spec/**`, `tests/**` from the repo root).
# Override with `projectRoot` in gates.config.json (relative to the spine directory) for a
# non-git or nested layout. Every config path is root-relative.
#
# suite_green is REQUIRED: an unset suiteCmd is exit 2, never a silent skip - a bank that
# prints ALL GATES PASSED without running the suite proves nothing.
#
# This .ps1 runner invokes the .ps1 siblings (the Windows, dependency-free path).
#
# Usage:  pwsh gates/run_all.ps1 [baseRef] [-PreFold] [-Mechanical] [-Strict]
#   baseRef       the QA-frozen SHA for test_edit_ban / prose_check / fold_check diffs.
#                 Omitted: test_edit_ban reads gates/.frozen, else config baseRef (weak).
#   -PreFold      skip fold_check (and its post-fold suite re-run): the pins it checks
#                 do not exist until the fold happens. Use for the Stage-7 pre-fold pass.
#   -Mechanical   skip test_edit_ban: the mechanical route has no QA/Engineer split, so a
#                 single author legitimately writes tests + code together. The route is
#                 recorded on the changelog item; CI passes this flag from that record.
#   -Strict       forward -Strict to fold_check: a configured resolver that errors/returns
#                 non-zero FAILS instead of degrading. CI should run with -Strict.
#                 Also forwarded to prose_check (spec-form violations FAIL instead of WARN).

[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$BaseRef,
    [switch]$PreFold,
    [switch]$Mechanical,
    [switch]$Strict
)
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_common.ps1"

$HereDir = $PSScriptRoot
$SpineDir = Split-Path -Parent $HereDir

# Resolve the project root: config projectRoot (relative to the spine dir) > git top-level > spine dir.
$RepoRoot = $null
$localCfgPath = Join-Path $HereDir 'gates.config.json'
if (Test-Path -LiteralPath $localCfgPath) {
    try {
        $localCfg = (Get-Content -LiteralPath $localCfgPath -Raw | ConvertFrom-Json)
        $pr = Get-CfgValue $localCfg 'projectRoot' $null
        if ($pr) {
            $cand = Join-Path $SpineDir $pr
            if (-not (Test-Path -LiteralPath $cand)) { Write-Output "FAIL run_all: projectRoot '$pr' does not exist"; exit 2 }
            $RepoRoot = (Resolve-Path -LiteralPath $cand).Path
        }
    } catch { }
}
if (-not $RepoRoot) {
    $top = (& git -C $HereDir rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -eq 0 -and $top) { $RepoRoot = (Resolve-Path -LiteralPath $top).Path } else { $RepoRoot = $SpineDir }
}
Set-Location -LiteralPath $RepoRoot
$hereNorm = ($HereDir -replace '\\', '/').TrimEnd('/')
$rootNorm = ($RepoRoot -replace '\\', '/').TrimEnd('/')
$GD = if ($hereNorm.StartsWith($rootNorm + '/')) { $hereNorm.Substring($rootNorm.Length + 1) } elseif ($hereNorm -eq $rootNorm) { '.' } else { $hereNorm }
$CFG = "$GD/gates.config.json"
if (-not (Test-Path -LiteralPath $CFG)) { Write-Output "FAIL run_all: cannot read config $CFG (cwd $RepoRoot)"; exit 2 }

$base = $BaseRef

function Fail([string]$name) {
    Write-Output ">>> GATE FAILED: $name"
    exit 1
}

function Invoke-Gate([string]$script, [string[]]$gateArgs) {
    # Runs the sibling .ps1, streaming its stdout straight through. Returns nothing -
    # callers check $LASTEXITCODE (set by the child pwsh) to avoid capturing the
    # child's printed lines into a return value.
    $full = Join-Path $HereDir $script
    & pwsh -NoProfile -File $full @gateArgs
}

function Invoke-Suite {
    $suite = Get-CfgValue $cfgGlobal 'suiteCmd' ''
    if ([string]::IsNullOrEmpty($suite) -or $suite -like '<from project-details*') {
        Write-Output "FAIL suite_green: suiteCmd is not set in $CFG - the bank cannot pass without the project suite (INIT section 5)."
        exit 2
    }
    Write-Output "== suite_green =="
    if ($env:ComSpec) {
        & $env:ComSpec /c $suite
    } else {
        & sh -c $suite
    }
    if ($LASTEXITCODE -ne 0) { Fail 'suite_green' }
}

# Load config once for suiteCmd checks.
$cfgGlobal = Read-Config $CFG 'run_all'

Write-Output "== run_all == (root: $RepoRoot)"
Write-Output "== link_check =="
Invoke-Gate 'link_check.ps1' @('-Config', $CFG)
if ($LASTEXITCODE -ne 0) { Fail 'link_check' }

Write-Output "== prose_check =="
$pcArgs = @('-Config', $CFG)
if ($base) { $pcArgs += @('-Base', $base) }
if ($Strict) { $pcArgs += '-Strict' }
Invoke-Gate 'prose_check.ps1' $pcArgs
if ($LASTEXITCODE -ne 0) { Fail 'prose_check' }

Write-Output "== coverage_check =="
Invoke-Gate 'coverage_check.ps1' @('-Config', $CFG)
if ($LASTEXITCODE -ne 0) { Fail 'coverage_check' }

if ($Mechanical) {
    Write-Output "== test_edit_ban == (skipped: mechanical route, no QA/Engineer split)"
} else {
    Write-Output "== test_edit_ban =="
    $tebArgs = @()
    if ($base) { $tebArgs += $base }
    $tebArgs += @('-Config', $CFG)
    Invoke-Gate 'test_edit_ban.ps1' $tebArgs
    if ($LASTEXITCODE -ne 0) { Fail 'test_edit_ban' }
}

# structure_check: on the persona route's pre-fold pass the PM-approved diagram must equal the frozen
# base (the fold itself rewrites the canonical shard, so the post-fold pass skips this half); the
# forward trace (every diagram class/member exists under paths.code) runs in every pass.
if (-not $Mechanical -and $PreFold) {
    Write-Output "== structure_check --frozen =="
    $scArgs = @('-Frozen')
    if ($base) { $scArgs += $base }
    $scArgs += @('-Config', $CFG)
    Invoke-Gate 'structure_check.ps1' $scArgs
    if ($LASTEXITCODE -ne 0) { Fail 'structure_check' }
}
Write-Output "== structure_check =="
Invoke-Gate 'structure_check.ps1' @('-Config', $CFG)
if ($LASTEXITCODE -ne 0) { Fail 'structure_check' }

Invoke-Suite

# --- project-specific gates: only if copied from template ---
if (Test-Path -LiteralPath (Join-Path $HereDir 'constitution_lint.ps1')) {
    Write-Output "== constitution_lint =="
    Invoke-Gate 'constitution_lint.ps1' @('-Config', $CFG)
    if ($LASTEXITCODE -ne 0) { Fail 'constitution_lint' }
} else {
    Write-Output "== constitution_lint == (skipped: cp constitution_lint.template.ps1 constitution_lint.ps1)"
}

if (Test-Path -LiteralPath (Join-Path $HereDir 'seam_conformance.ps1')) {
    Write-Output "== seam_conformance =="
    Invoke-Gate 'seam_conformance.ps1' @('-Config', $CFG)
    if ($LASTEXITCODE -ne 0) { Fail 'seam_conformance' }
} else {
    Write-Output "== seam_conformance == (skipped: cp seam_conformance.template.ps1 seam_conformance.ps1)"
}

if (Test-Path -LiteralPath (Join-Path $HereDir 'qa_import_ban.ps1')) {
    Write-Output "== qa_import_ban =="
    Invoke-Gate 'qa_import_ban.ps1' @('-Config', $CFG)
    if ($LASTEXITCODE -ne 0) { Fail 'qa_import_ban' }
} else {
    Write-Output "== qa_import_ban == (skipped: cp qa_import_ban.template.ps1 qa_import_ban.ps1)"
}

if ($PreFold) {
    Write-Output "== fold_check == (skipped: --pre-fold pass; runs in the authoritative post-fold pass)"
} else {
    Write-Output "== fold_check =="
    $fcArgs = @('-Config', $CFG)
    if ($base) { $fcArgs += @('-Base', $base) }
    if ($Strict) { $fcArgs += '-Strict' }
    Invoke-Gate 'fold_check.ps1' $fcArgs
    if ($LASTEXITCODE -ne 0) { Fail 'fold_check' }
    Invoke-Suite   # re-run after fold recompiles the spec index
}

Write-Output ">>> ALL GATES PASSED"
