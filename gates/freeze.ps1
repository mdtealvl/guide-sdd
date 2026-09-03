#!/usr/bin/env pwsh
# freeze - record the QA-frozen commit that test_edit_ban diffs against (Stage 5 exit).
#
# Run by the Orchestrator after QA's tests are COMMITTED (red + compiling). Writes
# <gates>/.frozen with the current HEAD SHA and prints the line to record on the changelog
# item - the item's copy is the authoritative one; the file is a convenience mirror that
# test_edit_ban and the plugin hook read when no SHA is passed.
#
# Refuses a dirty tree (exit 2): the frozen point must contain QA's tests, not leave them
# uncommitted where the Engineer's tree would later "add" them.
#
# Exit 0 written, 2 refused/usage.
# Usage:  pwsh gates/freeze.ps1 [-Config gates/gates.config.json] [-Unit <ITEM-ID>]

[CmdletBinding()]
param(
    [string]$Config = 'gates/gates.config.json',
    [string]$Unit = ''
)
$ErrorActionPreference = 'Stop'

$GateName = 'freeze'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Output "FAIL ${GateName}: need git"; exit 2 }

$top = (& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $top) { Write-Output "FAIL ${GateName}: not inside a git work tree"; exit 2 }
Set-Location -LiteralPath $top

$dirty = @(git status --porcelain --untracked-files=all | Where-Object { $_ -and $_.Trim() -and ($_ -notmatch ' (sdd/)?gates/\.frozen$') })
if ($dirty.Count -gt 0) {
    Write-Output "FAIL ${GateName}: working tree is dirty - commit QA's tests first, then freeze:"
    foreach ($l in ($dirty | Select-Object -First 20)) { Write-Output "  $l" }
    exit 2
}

$sha = (& git rev-parse HEAD).Trim()
$date = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
$lines = @("sha=$sha", "date=$date")
if ($Unit) { $lines += "unit=$Unit" }
$lines += "# QA-frozen base for test_edit_ban. Mirror of the changelog item's 'frozen:' line; the item is authoritative."
$frozenPath = Join-Path $PSScriptRoot '.frozen'
[System.IO.File]::WriteAllText($frozenPath, (($lines -join "`n") + "`n"))

$rel = ((Resolve-Path -LiteralPath $frozenPath).Path.Substring($top.Length + 1)) -replace '\\', '/'
$unitLabel = if ($Unit) { $Unit } else { '<ITEM-ID>' }
Write-Output "FROZEN ${GateName}: sha=$sha ($rel written)"
Write-Output "  record on the changelog item:  frozen: $sha"
Write-Output "  then commit the marker:        git add $rel && git commit -m `"chore($unitLabel): freeze tests at $($sha.Substring(0,7))`""
exit 0
