#!/usr/bin/env pwsh
# test_edit_ban — prove the Engineer's diff touched no test file.
#
# Generic gate. Path-guard over `git diff`: if any changed file matches a test glob,
# FAIL. Globs and base ref come from gates.config.json (testGlobs, baseRef). This is
# what makes QA-perp-Engineer structural: the Engineer *cannot* warp a test it cannot
# write. Disputes are filed to the Orchestrator, never resolved by editing a test.
#
# FAIL CLOSED: an unresolvable base ref FAILs (exit 2), never falls through to PASS.
#
# Exit 0 PASS, 1 FAIL, 2 config/usage error.
# Usage:  pwsh gates/test_edit_ban.ps1 [baseRef] [-Config gates/gates.config.json]
#   baseRef defaults to .baseRef in config (the QA-frozen commit, or `main`).

[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$BaseRef,
    [Parameter(Position = 1)][string]$Config = 'gates/gates.config.json'
)
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_common.ps1"

$GateName = 'test_edit_ban'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Output "FAIL ${GateName}: need git"
    exit 2
}

$cfg = Read-Config $Config $GateName

$base = $BaseRef
if (-not $base) { $base = Get-CfgValue $cfg 'baseRef' 'main' }

# Fail closed: an unresolvable base ref must FAIL (exit 2), never fall through to a
# silent PASS — that would make the QA-perp-Engineer gate fail-open.
git rev-parse --verify --quiet "$base^{commit}" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Output "FAIL ${GateName}: baseRef '$base' does not resolve — set baseRef to the QA-frozen commit."
    exit 2
}

# Test globs from config; fall back to paths.tests then a default.
$globs = $null
if ($cfg.PSObject.Properties.Name -contains 'testGlobs' -and $cfg.testGlobs) { $globs = @($cfg.testGlobs) }
if (-not $globs) {
    $defTests = 'tests/**'
    if ($cfg.PSObject.Properties.Name -contains 'paths' -and $cfg.paths -and ($cfg.paths.PSObject.Properties.Name -contains 'tests') -and $cfg.paths.tests) { $defTests = $cfg.paths.tests }
    $globs = @($defTests)
}

# All paths changed since BASE (Added/Copied/Modified/Renamed/Deleted).
$changedRaw = git diff --name-only --diff-filter=ACMRD "$base...HEAD"
$changed = @($changedRaw | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })

if ($changed.Count -eq 0) {
    Write-Output "PASS ${GateName}: no changed files vs $base."
    exit 0
}

# Match each changed path against each test glob (fnmatch-style, path-anchored).
$globRes = @()
foreach ($g in $globs) { if ($g) { $globRes += ,(ConvertTo-FnmatchRegex ($g -replace '\\', '/')) } }

$violations = New-Object System.Collections.Generic.List[string]
foreach ($p in $changed) {
    $pn = ($p -replace '\\', '/')
    foreach ($re in $globRes) {
        if ($re.IsMatch($pn)) { $violations.Add($p); break }
    }
}

if ($violations.Count -gt 0) {
    Write-Output "FAIL ${GateName}: Engineer modified test file(s) vs ${base}:"
    foreach ($v in $violations) { Write-Output "  $v" }
    Write-Output "Tests are frozen for the Engineer. File the dispute to the Orchestrator instead."
    exit 1
}

Write-Output "PASS ${GateName}: no test files touched vs $base."
exit 0
