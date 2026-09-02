#!/usr/bin/env pwsh
# fold_check — every clause changed in this ship carries a resolving provenance pin.
#
# Generic, MODE-BLIND gate (works identically for Mode A external tracker and Mode B
# on-disk backlog). Enforces the fold-on-ship invariant at ship time: every spec clause
# touched by this change is pinned (§X per <unit-id>, YYYY-MM-DD) and the unit-id resolves.
#
# Resolution of <unit-id>:
#   * Mode B (default): a backlog file named <unit-id>* exists under backlogRoot.
#   * Mode A: if foldCheck.resolveCmd is set ({unit} substituted) it is run; exit 0 = resolves.
#     Offline / no resolver -> degrades to "syntactically valid unit-id" + a NOTE.
#
# Scope = spec shards changed since baseRef (git diff). For each NEW or CHANGED clause
# line, require a pin on it or the line directly after.
#
# FAIL CLOSED if git present but base unresolvable (exit 2). git-absent -> all shards + NOTE.
# Exit 0 PASS, 1 FAIL, 2 config/usage error.
#
# -Strict: when a resolver IS configured (foldCheck.resolveCmd) but ERRORS or returns
# non-zero, treat the unit as UNRESOLVED (FAIL) instead of degrading to "syntactic pin +
# NOTE". CI MUST run with -Strict so an offline/broken resolver cannot fail open. Without
# -Strict the current degrade-with-NOTE convenience is kept (local/offline). The
# "no resolver configured at all" syntactic-only path is unchanged in both modes.
#
# Usage:  pwsh gates/fold_check.ps1 [-Config gates/gates.config.json] [-Base <ref>] [-Strict]

[CmdletBinding()]
param(
    [string]$Config = 'gates/gates.config.json',
    [string]$Base,
    [switch]$Strict
)
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_common.ps1"

$cfg = Read-Config $Config 'fold_check'
$base = $Base
if (-not $base) { $base = Get-CfgValue $cfg 'baseRef' 'main' }

$gitAvailable = [bool](Get-Command git -ErrorAction SilentlyContinue)

# base_state: ('absent') if git missing; else whether base resolves.
if ($gitAvailable) {
    git rev-parse --verify --quiet "$base^{commit}" 2>&1 | Out-Null
    $baseOk = ($LASTEXITCODE -eq 0)
    if (-not $baseOk) {
        Write-Output "FAIL fold_check: baseRef '$base' does not resolve — set baseRef to the ship base."
        exit 2
    }
}

$specGlob = 'spec/**/*.body.md'
if ($cfg.PSObject.Properties.Name -contains 'paths' -and $cfg.paths -and ($cfg.paths.PSObject.Properties.Name -contains 'spec') -and $cfg.paths.spec) {
    $specGlob = $cfg.paths.spec
}
$clausePattern = Get-CfgValue $cfg 'clauseIdRegex' '\b[A-Z]{2,}\.\d+\b'
$unitPattern   = Get-CfgValue $cfg 'unitIdRegex' '\b[A-Z]+-\d+\b'
$clauseRe = [regex]$clausePattern
$pinRe = [regex]('\bper\s+(' + $unitPattern + ')\s*,\s*\d{4}-\d{2}-\d{2}')

# changed_spec_files: shards changed vs base (fall back to all shards if git unavailable).
function Get-NormPath([string]$p) { return ($p -replace '\\', '/') }

$allShardsList = Expand-Globs $specGlob
$allShards = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($s in $allShardsList) { [void]$allShards.Add((Get-NormPath $s)) }

function Invoke-GitDiff([string[]]$gitArgs) {
    # Returns the stdout lines on success, or $null if git errored / is absent.
    $out = & git @gitArgs 2>$null
    if ($LASTEXITCODE -eq 0) { return ,@($out) }
    return $null
}

$files = @()
if (-not $gitAvailable) {
    Write-Output "NOTE fold_check: git unavailable — checking ALL spec shards."
    $files = @($allShards | Sort-Object)
} else {
    $out = Invoke-GitDiff @('diff', '--name-only', "$base...HEAD")
    if ($null -eq $out) {
        $out = Invoke-GitDiff @('diff', '--name-only', "$base")
    }
    if ($null -eq $out) {
        Write-Output "NOTE fold_check: git unavailable — checking ALL spec shards."
        $files = @($allShards | Sort-Object)
    } else {
        $changed = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($line in $out) {
            if ($null -eq $line) { continue }
            $t = ([string]$line).Trim()
            if ($t) { [void]$changed.Add((Get-NormPath $t)) }
        }
        $files = @($changed | Where-Object { $allShards.Contains($_) } | Sort-Object)
    }
}

if ($files.Count -eq 0) {
    Write-Output "PASS fold_check: no spec shards changed this ship."
    exit 0
}

$unpinned = New-Object System.Collections.Generic.List[object]
$seenUnits = New-Object 'System.Collections.Generic.HashSet[string]'

foreach ($f in $files) {
    $lines = Read-FileLines $f
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        foreach ($m in $clauseRe.Matches($line)) {
            $cid = $m.Value
            $next = ''
            if ($i + 1 -lt $lines.Count) { $next = $lines[$i + 1] }
            $window = $line + $next
            $pm = $pinRe.Match($window)
            if (-not $pm.Success) {
                $unpinned.Add([pscustomobject]@{ file = $f; cid = $cid })
            } else {
                [void]$seenUnits.Add($pm.Groups[1].Value)
            }
        }
    }
}

# resolve each seen unit-id.
function Resolve-Unit([string]$unit, $cfg, [bool]$strict) {
    $fc = Get-CfgValue $cfg 'foldCheck' $null
    $cmd = $null
    if ($fc) { $cmd = Get-CfgValue $fc 'resolveCmd' $null }
    if ($cmd) {
        $expanded = $cmd -replace '\{unit\}', $unit
        $rc = $null
        try {
            if ($env:ComSpec) {
                # Windows: run through cmd.exe (shell=True analogue).
                & $env:ComSpec /c $expanded 2>&1 | Out-Null
            } else {
                # POSIX pwsh: run through /bin/sh.
                & sh -c $expanded 2>&1 | Out-Null
            }
            $rc = $LASTEXITCODE
        } catch {
            # Resolver could not even be launched / threw — treat like a non-zero result.
            $rc = 1
        }
        if ($rc -eq 0) { return $true }
        # Configured resolver errored or returned non-zero.
        #   strict     -> UNRESOLVED (FAIL): a broken/offline resolver cannot pass open.
        #   non-strict -> degrade to the syntactic pin + NOTE (local/offline convenience).
        if ($strict) {
            [Console]::Out.WriteLine("FAIL fold_check: resolveCmd errored/non-zero for $unit — strict mode treats this as unresolved.")
            return $false
        }
        [Console]::Out.WriteLine("NOTE fold_check: resolveCmd failed for $unit — accepting syntactic pin.")
        return $true
    }
    $root = 'backlog'
    if ($fc) { $root = Get-CfgValue $fc 'backlogRoot' 'backlog' }
    if (Test-Path -LiteralPath $root -PathType Container) {
        $hits = @(Get-ChildItem -LiteralPath $root -Filter "$unit*" -Force -ErrorAction SilentlyContinue)
        return ($hits.Count -gt 0)
    }
    [Console]::Out.WriteLine("NOTE fold_check: no resolver and no $root/ — accepting syntactic pin for $unit.")
    return $true
}

$unresolved = New-Object System.Collections.Generic.List[string]
foreach ($unit in ($seenUnits | Sort-Object)) {
    if (-not (Resolve-Unit $unit $cfg ([bool]$Strict))) { $unresolved.Add($unit) }
}

if ($unpinned.Count -eq 0 -and $unresolved.Count -eq 0) {
    Write-Output "PASS fold_check: $($files.Count) changed shard(s); all clauses pinned and resolved."
    exit 0
}

Write-Output "FAIL fold_check: $($unpinned.Count) unpinned clause(s), $($unresolved.Count) unresolved unit(s)."
foreach ($u in $unpinned) {
    Write-Output "  UNPINNED $($u.cid)  in $($u.file)  (add: (§… per <unit-id>, YYYY-MM-DD))"
}
foreach ($unit in $unresolved) {
    Write-Output "  UNRESOLVED-UNIT $unit  (no backlog file / tracker entry)"
}
exit 1
