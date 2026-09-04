#!/usr/bin/env pwsh
# token_ledger - the build plan's READ LEDGER (Stage 4b): append rows, verify pins, report token
# spend and savings. A helper like freeze, not a pass/fail gate in the bank; `verify` exits 1 on a
# stale row so a reader never trusts advice written against a file that has since changed.
#
# The ledger is a markdown table under "## Ledger" (the LAST section of <ITEM-ID>.buildplan.md):
#   | kind | by | for | aud | path | range | hash | full | est | note |
#   kind  read  - a read the slice DID (by = that slice); est = tokens admitted.
#         range - advice: a later slice needs only lines a-b of path;      est = tokens of that range.
#         grep  - advice: grep an anchor 'pattern' +/-N lines instead;      est = matches x (2N+1) lines.
#         pin   - advice: the exact signature/constant is in `note`; do not open the file; est = note tokens.
#         skip  - advice: do not open this file at all;                     est = 0.
#   by    the writing slice: P (the Stage-4b planning slice) or S1..Sn.   for   the consuming slice, or *.
#   aud   any | qa | eng - QA rows never point into paths.code (invariant 3); the dispatcher filters.
#   hash  git hash-object of path when the row was written (7 chars).   full  tokens of the whole file.
# Tokens = ceil(chars x buildPlan.tokensPerChar) (default 0.25): an ESTIMATE from bytes admitted,
# never a billed count. Every number the report prints is recomputable from the ledger.
#
# Savings rule (report): for each advice row aimed at slice S on path p - if S recorded no read of p,
# saved += full(p); if S read less than full, saved += full - admitted(S,p); if S read the whole
# file, nothing is saved and the row counts as not honoured. Percent = saved / (admitted + saved).
#
# Usage:
#   pwsh gates/token_ledger.ps1 add    -Plan <file> -Kind <read|range|grep|pin|skip> -By <S> [-For <S|*>]
#                                      [-Aud any|qa|eng] -Path <p> [-Range <a-b|a-|-b|-|'pat' +-N|line>] [-Note <t>]
#   Output is ASCII (~ for "about", +- for the grep context) so both OS twins print byte-identical lines.
#   pwsh gates/token_ledger.ps1 verify -Plan <file> [-For <S>]      # STALE rows -> exit 1
#   pwsh gates/token_ledger.ps1 report -Plan <file> [-Slice <S>]    # the `tokens:` lines for the item
#   -Plan omitted: the single file matching buildPlan.glob. [-Config gates/gates.config.json]
# Exit 0 ok, 1 stale (verify), 2 usage/config.

[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Command,
    [string]$Plan,
    [string]$Kind,
    [string]$By,
    [string]$For,
    [string]$Aud = 'any',
    [string]$Path,
    [string]$Range,
    [string]$Note,
    [string]$Slice,
    [string]$Config = 'gates/gates.config.json'
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/_common.ps1"

$GateName = 'token_ledger'
if ($Command -notin @('add', 'verify', 'report')) { Write-Output "FAIL ${GateName}: usage: token_ledger.ps1 add|verify|report ..."; exit 2 }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Output "FAIL ${GateName}: needs git"; exit 2 }
if (-not (Test-Path -LiteralPath $Config)) { Write-Output "FAIL ${GateName}: cannot read config ${Config}: no such file"; exit 2 }
$Config = (Resolve-Path -LiteralPath $Config).Path
$cfg = Read-Config $Config $GateName
$top = (& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $top) { Write-Output "FAIL ${GateName}: not inside a git work tree"; exit 2 }
Set-Location -LiteralPath $top

$bp = Get-CfgValue $cfg 'buildPlan' $null
$tpc = [double](Get-CfgValue $bp 'tokensPerChar' 0.25)
$bpGlob = [string](Get-CfgValue $bp 'glob' '**/*.buildplan.md')
if (-not $Plan) {
    $m = @(Expand-Globs $bpGlob)
    if ($m.Count -ne 1) { Write-Output "FAIL ${GateName}: -Plan required ($($m.Count) files match buildPlan.glob '$bpGlob')."; exit 2 }
    $Plan = $m[0]
}
if ($Command -ne 'add' -and -not (Test-Path -LiteralPath $Plan)) { Write-Output "FAIL ${GateName}: build plan '$Plan' not found."; exit 2 }

function Tok([double]$chars) { return [int][math]::Ceiling($chars * $tpc) }
function Fmt([double]$n) { if ($n -ge 1000) { return ('{0:0.0}k' -f ($n / 1000)) } ; return ('{0}' -f [int]$n) }
function Blob([string]$p) { $h = (& git hash-object -- $p 2>$null); if ($h) { return $h.Trim().Substring(0, 7) } ; return '' }
function Get-Bytes([string]$p) { return ([System.IO.FileInfo]$p).Length }

# Rows: data rows of the ledger table -> objects
function Get-Rows([string]$file) {
    $out = New-Object System.Collections.Generic.List[object]
    $hdr = $false; $n = 0
    foreach ($line in (Read-FileLines $file)) {
        if ($line -match '^\s*\|') {
            if ($line -match '^\s*\|\s*kind\s*\|') { $hdr = $true; continue }
            if (-not $hdr) { continue }
            if ($line -match '^\s*\|\s*-+') { continue }
            $n++
            $f = @($line -split '\|' | ForEach-Object { $_.Trim() })
            while ($f.Count -lt 12) { $f += '' }
            $out.Add([pscustomobject]@{ n = $n; kind = $f[1]; by = $f[2]; for = $f[3]; aud = $f[4]; path = $f[5]; range = $f[6]; hash = $f[7]; full = [int]($f[8] -as [int]); est = [int]($f[9] -as [int]); note = $f[10] })
            continue
        }
        if ($line -match '^\s*$') { continue }
        if ($hdr) { $hdr = $false }
    }
    return $out
}

# ---------------------------------------------------------------------------------------------------
if ($Command -eq 'add') {
    if ($Kind -notin @('read', 'range', 'grep', 'pin', 'skip')) { Write-Output "FAIL ${GateName}: -Kind must be read|range|grep|pin|skip"; exit 2 }
    if (-not $By) { Write-Output "FAIL ${GateName}: -By <slice> required (P or S<n>)."; exit 2 }
    if (-not $Path) { Write-Output "FAIL ${GateName}: -Path required."; exit 2 }
    if ($Aud -notin @('any', 'qa', 'eng')) { Write-Output "FAIL ${GateName}: -Aud must be any|qa|eng"; exit 2 }
    $p = ($Path -replace '\\', '/') -replace '^\./', ''
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { Write-Output "FAIL ${GateName}: path '$p' does not exist (root-relative)."; exit 2 }
    if (-not $For) { $For = if ($Kind -eq 'read') { '-' } else { '*' } }
    if ($Aud -eq 'qa') {
        $code = 'src/**'
        if ($cfg.PSObject.Properties.Name -contains 'paths' -and $cfg.paths -and ($cfg.paths.PSObject.Properties.Name -contains 'code') -and $cfg.paths.code) { $code = $cfg.paths.code }
        if ((ConvertTo-Regex $code).IsMatch($p)) { Write-Output "FAIL ${GateName}: a qa-audience row may not point into paths.code ($p) - QA is blind to the implementation (invariant 3)."; exit 2 }
    }
    $ch = [double](Get-Bytes $p); $full = Tok $ch
    $lines = @(Read-FileLines $p)
    if ($lines.Count -gt 0 -and $lines[-1] -eq '') { $lines = @($lines[0..($lines.Count - 2)]) }   # trailing newline, like wc -l
    $nl = [math]::Max(1, $lines.Count)
    $est = 0; $range = $Range
    switch ($Kind) {
        'skip' { $est = 0; if (-not $range) { $range = '-' } }
        'pin'  {
            if (-not $Note) { Write-Output "FAIL ${GateName}: a pin pastes the signature/constant in -Note (pointed at is not pinned)."; exit 2 }
            $est = Tok ([System.Text.Encoding]::UTF8.GetByteCount($Note)); if (-not $range) { $range = '-' }
        }
        'grep' {
            $pat = ($Range -replace '\s*[+±-]+\s*\d+\s*$', '') -replace "^'", '' -replace "'$", ''
            $mm = [regex]::Match($Range, '[+±-]+\s*(\d+)\s*$'); $nctx = if ($mm.Success) { [int]$mm.Groups[1].Value } else { 20 }
            if (-not $pat) { Write-Output "FAIL ${GateName}: -Range for grep is `"'pattern' +/-N`"."; exit 2 }
            $mcount = @($lines | Where-Object { $_ -match $pat }).Count
            $v = [math]::Ceiling($mcount * (2 * $nctx + 1) * ($ch / $nl) * $tpc); if ($v -gt $full) { $v = $full }
            $est = [int]$v; $range = "'$pat' +-$nctx"
        }
        default {
            $r = if ($Range) { $Range } else { '-' }
            $rch = $ch
            if ($r -ne '-') {
                if ($r -match '^(\d*)-(\d*)$') {
                    $a = if ($Matches[1]) { [int]$Matches[1] } else { 1 }
                    $b = if ($Matches[2]) { [int]$Matches[2] } else { $lines.Count }
                } elseif ($r -match '^\d+$') { $a = [int]$r; $b = [int]$r }
                else { Write-Output "FAIL ${GateName}: bad -Range '$r' (a-b | a- | -b | - | line)."; exit 2 }
                $a = [math]::Max(1, $a); $b = [math]::Min($lines.Count, $b)
                $rch = 0; if ($b -ge $a) { for ($i = $a - 1; $i -le $b - 1; $i++) { $rch += [System.Text.Encoding]::UTF8.GetByteCount($lines[$i]) + 1 } }
            }
            $est = Tok $rch; $range = $r
        }
    }
    $h = Blob $p
    $note = ($Note -replace '\|', '/') -replace '[\r\n]', ' '
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $hasHdr = (Test-Path -LiteralPath $Plan) -and ((Read-FileText $Plan) -match '(?m)^\s*\|\s*kind\s*\|')
    if (-not $hasHdr) {
        $pre = ''
        if ((Test-Path -LiteralPath $Plan) -and (Get-Bytes $Plan) -gt 0) { $pre = "`n" }
        [System.IO.File]::AppendAllText($Plan, $pre + "## Ledger`n`n| kind | by | for | aud | path | range | hash | full | est | note |`n|---|---|---|---|---|---|---|---|---|---|`n", $utf8)
    }
    [System.IO.File]::AppendAllText($Plan, "| $Kind | $By | $For | $Aud | $p | $range | $h | $full | $est | $note |`n", $utf8)
    Write-Output "LEDGER ${GateName}: + $Kind $By->$For [$Aud] $p $range est~$(Fmt $est) (full~$(Fmt $full)) @$h"
    exit 0
}

# ---------------------------------------------------------------------------------------------------
if ($Command -eq 'verify') {
    $stale = 0; $n = 0
    foreach ($r in (Get-Rows $Plan)) {
        if (-not $r.kind) { continue }
        if ($For -and -not ($r.for -eq $For -or $r.for -eq '*')) { continue }
        $n++
        if (-not (Test-Path -LiteralPath $r.path -PathType Leaf)) { Write-Output "STALE ${GateName}: row $($r.n) $($r.kind) $($r.path) (by $($r.by) for $($r.for)) - file is gone; the row is void."; $stale++; continue }
        $now = Blob $r.path
        if ($now -ne $r.hash) { Write-Output "STALE ${GateName}: row $($r.n) $($r.kind) $($r.path) $($r.range) (by $($r.by) for $($r.for)) - file changed since written (was @$($r.hash), now @$now); re-read before trusting."; $stale++ }
    }
    $sfx = if ($For) { " for $For" } else { '' }
    if ($stale -gt 0) { Write-Output "FAIL ${GateName}: $stale of $n ledger row(s) stale$sfx. Reconcile (re-read the range, rewrite the row), never assume."; exit 1 }
    Write-Output "PASS ${GateName}: $n ledger row(s) current$sfx."
    exit 0
}

# ---------------------------------------------------------------------------------------------------
# report
$rows = Get-Rows $Plan
$adm = @{}; $admp = @{}; $slices = @{}; $advice = @()
foreach ($r in $rows) {
    if ($r.kind -eq 'read') { $adm[$r.by] = ($adm[$r.by] -as [int]) + $r.est; $k = "$($r.by)`t$($r.path)"; $admp[$k] = ($admp[$k] -as [int]) + $r.est; $slices[$r.by] = 1 }
    else { $advice += $r; if ($r.for -ne '*' -and $r.for -ne '-') { $slices[$r.for] = 1 } }
}
function Key([string]$s) { if ($s -eq 'P') { return '0 000000' } ; if ($s -match '^S(\d+)$') { return ('1 {0:d6}' -f [int]$Matches[1]) } ; return "2 $s" }
$outLines = @(); $TA = 0; $TS = 0
foreach ($s in $slices.Keys) {
    $saved = 0; $hon = 0; $tot = 0; $seen = @{}
    foreach ($a in $advice) {
        if (-not ($a.for -eq $s -or ($a.for -eq '*' -and $a.by -ne $s))) { continue }
        if ($seen.ContainsKey($a.path)) { continue }
        $seen[$a.path] = 1; $tot++
        $rd = ($admp["$s`t$($a.path)"] -as [int])
        if ($rd -eq 0) { $saved += $a.full; $hon++ }
        elseif ($rd -lt $a.full) { $saved += ($a.full - $rd); $hon++ }
    }
    $adv = ($adm[$s] -as [int]); $d = $adv + $saved; $pct = if ($d -gt 0) { [int][math]::Round($saved * 100 / $d) } else { 0 }
    if (-not $Slice -or $Slice -eq $s) { $outLines += ("{0}|tokens: {1} admitted ~{2}; saved ~{3} ({4}%); ledger {5}/{6} honoured" -f (Key $s), $s, (Fmt $adv), (Fmt $saved), $pct, $hon, $tot) }
    $TA += $adv; $TS += $saved
}
if (-not $Slice) {
    $d = $TA + $TS; $pct = if ($d -gt 0) { [int][math]::Round($TS * 100 / $d) } else { 0 }
    $outLines += ("9 zzz|tokens: plan admitted ~{0}; saved ~{1} ({2}%); planning ~{3} (P); estimates from bytes admitted, not billed" -f (Fmt $TA), (Fmt $TS), $pct, (Fmt (($adm['P'] -as [int]))))
}
foreach ($l in ($outLines | Sort-Object)) { Write-Output ($l -replace '^[^|]*\|', '') }
exit 0
