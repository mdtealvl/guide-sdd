#!/usr/bin/env pwsh
# test_edit_ban - prove the tree under review differs from the QA-frozen commit in no test file.
#
# Generic gate. Compares the QA-frozen base against the WORKING TREE (committed + staged +
# unstaged + untracked), never commit-to-commit only, so an uncommitted edit cannot hide.
# Renames are not collapsed (--no-renames), so moving a test out of a test path shows as a
# delete. The gate directory itself (config, scripts) must be unchanged vs the base, so the
# globs and suite command the bank reads are the ones QA froze - only `.frozen` may be added.
#
# Base resolution (first that applies):
#   1. positional <baseRef>  - the QA-frozen SHA recorded on the changelog item (authoritative;
#                              what the Orchestrator / CI passes);
#   2. <gates>/.frozen        - written by gates/freeze.ps1 at Stage 5 exit (a mirror of 1);
#   3. config baseRef         - a moving branch name is WEAK (warned): it can be advanced past
#                              the frozen point. Pass the SHA.
# The base must resolve AND be an ancestor of HEAD; otherwise exit 2 (fail closed).
#
# Trust boundary (be honest): anything inside the repo can be rewritten by whoever holds git.
# The proof is "given the SHA the Orchestrator recorded on the item, no test path differs".
# The `.frozen` file and the plugin hook are tripwires for the Engineer persona, not the proof.
#
# Exit 0 PASS, 1 FAIL, 2 config/usage error.
# Usage:  pwsh gates/test_edit_ban.ps1 [baseRef] [-Config gates/gates.config.json]

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

if (-not (Test-Path -LiteralPath $Config)) {
    Write-Output "FAIL ${GateName}: cannot read config ${Config}: no such file"
    exit 2
}
$Config = (Resolve-Path -LiteralPath $Config).Path
$cfg = Read-Config $Config $GateName

$top = (& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $top) { Write-Output "FAIL ${GateName}: not inside a git work tree"; exit 2 }
$gd = ((& git -C $PSScriptRoot rev-parse --show-prefix) -replace '/$', '')   # gate dir relative to the repo top
if (-not $gd) { $gd = '.' }
Set-Location -LiteralPath $top

$base = $BaseRef
$baseSrc = 'argument'
$frozenPath = Join-Path $gd '.frozen'
if (-not $base -and (Test-Path -LiteralPath $frozenPath)) {
    $line = (Get-Content -LiteralPath $frozenPath | Where-Object { $_ -match '^sha=([0-9a-fA-F]+)' } | Select-Object -First 1)
    if ($line) { $base = [regex]::Match($line, '^sha=([0-9a-fA-F]+)').Groups[1].Value; $baseSrc = $frozenPath -replace '\\', '/' }
}
if (-not $base) { $base = Get-CfgValue $cfg 'baseRef' 'main'; $baseSrc = 'config baseRef' }
if (-not $base) { Write-Output "FAIL ${GateName}: no base - pass the QA-frozen SHA or run gates/freeze.ps1 at Stage 5 exit."; exit 2 }

# Fail closed: an unresolvable base must FAIL (exit 2), never fall through to PASS.
git rev-parse --verify --quiet "$base^{commit}" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Output "FAIL ${GateName}: base '$base' ($baseSrc) does not resolve - pass the QA-frozen SHA."
    exit 2
}
$baseSha = (& git rev-parse "$base^{commit}").Trim()
git merge-base --is-ancestor $baseSha HEAD 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Output "FAIL ${GateName}: base '$base' ($baseSrc) is not an ancestor of HEAD - the frozen point must be on this branch."
    exit 2
}
if ($base -notmatch '^[0-9a-fA-F]+$') {
    Write-Output "WARN ${GateName}: base '$base' ($baseSrc) is a moving ref, not a SHA - it can be advanced past the frozen point. Pass the QA-frozen SHA."
}

# Test globs from config; fall back to paths.tests then a default.
$globs = $null
if ($cfg.PSObject.Properties.Name -contains 'testGlobs' -and $cfg.testGlobs) { $globs = @($cfg.testGlobs) }
if (-not $globs) {
    $defTests = 'tests/**'
    if ($cfg.PSObject.Properties.Name -contains 'paths' -and $cfg.paths -and ($cfg.paths.PSObject.Properties.Name -contains 'tests') -and $cfg.paths.tests) { $defTests = $cfg.paths.tests }
    $globs = @($defTests)
}

# Everything that differs between the base commit and the working tree (tracked changes,
# committed/staged/unstaged, deletes included, renames NOT collapsed) plus untracked files.
$tracked = @(git diff --name-only --no-renames --diff-filter=ACMD $baseSha -- .)
$untracked = @(git ls-files --others --exclude-standard --full-name)
$changed = @(($tracked + $untracked) | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() -replace '\\', '/' } | Sort-Object -Unique)

if ($changed.Count -eq 0) {
    Write-Output "PASS ${GateName}: no changed files vs $base (working tree, incl. untracked)."
    exit 0
}

# 1. Gate-dir tamper check: config + scripts must equal the base. Only `.frozen` may be ADDED.
$gdNorm = ($gd -replace '\\', '/')
$tamper = @($changed | Where-Object { $_.StartsWith("$gdNorm/") -and $_ -ne "$gdNorm/.frozen" })
if ($tamper.Count -gt 0) {
    Write-Output "FAIL ${GateName}: gate config/scripts modified vs $base (the bank must run on what QA froze):"
    foreach ($v in $tamper) { Write-Output "  $v" }
    exit 1
}

# 2. Test-path check. One glob dialect for the whole bank: ConvertTo-Regex (** spans dirs, * does not).
$globRes = @()
foreach ($g in $globs) { if ($g) { $globRes += ,(ConvertTo-Regex ($g -replace '\\', '/')) } }

$violations = New-Object System.Collections.Generic.List[string]
foreach ($p in $changed) {
    foreach ($re in $globRes) {
        if ($re.IsMatch($p)) { $violations.Add($p); break }
    }
}

if ($violations.Count -gt 0) {
    Write-Output "FAIL ${GateName}: test file(s) differ from the frozen base ${base}:"
    foreach ($v in $violations) { Write-Output "  $v" }
    Write-Output "Tests are frozen for the Engineer. Revert them (git checkout -- <path> / rm <path>) and file the dispute to the Orchestrator."
    exit 1
}

Write-Output "PASS ${GateName}: no test files touched vs $base (working tree, incl. untracked)."
exit 0
