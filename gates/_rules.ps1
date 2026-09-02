#!/usr/bin/env pwsh
# _rules.ps1 — the shared rule engine for constitution_lint + seam_conformance.
# Dot-sourced by both gates (the .py originals shared run_rule/run_rules the same way:
# seam_conformance imported constitution_lint's engine). No external deps.
# Requires _common.ps1 (Expand-Globs, Read-FileText) to be dot-sourced first.

$ErrorActionPreference = 'Stop'

function Invoke-Rule {
    # Returns a hashtable @{ ok = [bool]; detail = [string] }.
    param($Rule)
    $kind  = Get-CfgValue $Rule 'kind' $null
    $paths = Get-CfgValue $Rule 'paths' @()

    if ($kind -eq 'file_exists') {
        $fs = Expand-Globs $paths
        $ok = ($fs.Count -gt 0)
        $detail = ''
        if (-not $ok) { $detail = "no file matches $paths" }
        return @{ ok = $ok; detail = $detail }
    }

    $patternStr = Get-CfgValue $Rule 'pattern' $null
    if ($null -eq $patternStr) {
        return @{ ok = $false; detail = "bad pattern: 'pattern'" }
    }
    try { $pat = [regex]$patternStr } catch {
        return @{ ok = $false; detail = "bad pattern: $($_.Exception.Message)" }
    }

    $fs = Expand-Globs $paths

    if ($kind -eq 'must_match') {
        $offenders = @($fs | Where-Object { -not $pat.IsMatch((Read-FileText $_)) })
        $ok = ($offenders.Count -eq 0)
        $detail = if ($ok) { '' } else { "pattern absent in: [$([string]::Join(', ', ($offenders | ForEach-Object { "'$_'" })))]" }
        return @{ ok = $ok; detail = $detail }
    }
    if ($kind -eq 'must_not_match') {
        $offenders = @($fs | Where-Object { $pat.IsMatch((Read-FileText $_)) })
        $ok = ($offenders.Count -eq 0)
        $detail = if ($ok) { '' } else { "pattern present in: [$([string]::Join(', ', ($offenders | ForEach-Object { "'$_'" })))]" }
        return @{ ok = $ok; detail = $detail }
    }
    if ($kind -eq 'pair_requires') {
        $expectStr = Get-CfgValue $Rule 'expect' $null
        if ($null -eq $expectStr) {
            return @{ ok = $false; detail = "bad expect: 'expect'" }
        }
        try { $exp = [regex]$expectStr } catch {
            return @{ ok = $false; detail = "bad expect: $($_.Exception.Message)" }
        }
        $offenders = @($fs | Where-Object {
            $t = Read-FileText $_
            $pat.IsMatch($t) -and (-not $exp.IsMatch($t))
        })
        $ok = ($offenders.Count -eq 0)
        $detail = if ($ok) { '' } else { "missing ``$expectStr`` in: [$([string]::Join(', ', ($offenders | ForEach-Object { "'$_'" })))]" }
        return @{ ok = $ok; detail = $detail }
    }
    return @{ ok = $false; detail = "unknown kind '$kind'" }
}

function Invoke-Rules {
    # Generic runner — shared by both gates. Returns the exit code (0/1).
    param($Rules, [string]$GateName)
    $failed = 0
    foreach ($r in $Rules) {
        $res = Invoke-Rule $r
        $id = Get-CfgValue $r 'id' '?'
        $msg = Get-CfgValue $r 'message' ''
        $verdict = if ($res.ok) { 'PASS' } else { 'FAIL' }
        # Print to stdout via the console writer so these lines do NOT enter the
        # function's output pipeline (which would corrupt the returned exit code).
        [Console]::Out.WriteLine("  [$verdict] ${id}: $msg")
        if (-not $res.ok) {
            $failed += 1
            [Console]::Out.WriteLine("         -> $($res.detail)")
        }
    }
    $v = if ($failed -eq 0) { 'PASS' } else { 'FAIL' }
    [Console]::Out.WriteLine("$v ${GateName}: $($Rules.Count) rule(s), $failed failing.")
    if ($failed) { return 1 } else { return 0 }
}
