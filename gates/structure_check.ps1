#!/usr/bin/env pwsh
# structure_check - the PM-approved member-level structure diagram (classes, properties, methods) holds.
#
# Generic gate over STRUCTURE SHARDS: content-only spec shards (structureGlobs, default
# **/*.structure.body.md) holding fenced ```mermaid classDiagram``` blocks at MEMBER level. A transient
# shard is a DELTA under headings "Added" / "Changed" / "Removed"; a canonical shard is the area's
# current state (no headings needed). The mermaid text is the source; the drawing derives.
#
# Modes:
#   -Plan             shape only (Stage 3 / 4b close): every shard in scope has >=1 classDiagram with
#                     >=1 class carrying >=1 member; a class with no members is WARNed (an outline in
#                     disguise, or an existing class named for context). No code is read.
#   -Frozen [sha]     the deviation guard (Stage 6 exit; Stage-7 pre-fold pass): no structureGlobs path
#                     differs from <sha> in the WORKING TREE (committed, staged, unstaged, untracked;
#                     renames not collapsed). <sha> omitted: gates/.frozen. Base must resolve and be an
#                     ancestor of HEAD (exit 2). The PM approved the diagram; it changes only by
#                     [NEEDS-PO:structure] -> PM decision -> PO replaces wholesale -> re-freeze.
#   (default)         forward trace (Stage 7): every class and member named under Added / Changed / an
#                     unlabelled block resolves to an identifier under paths.code (git grep -w, tracked
#                     + untracked); a class under Removed must be ABSENT (FAIL); a removed member still
#                     present is WARNed (the name may live on in another class). FAIL names
#                     <shard>: <Class>.<member>. The reverse trace - no public member in the diff that
#                     the diagram lacks - is a judgement call: Stage-7 Validation lens 2a.
#   -Changed <base>   limit -Plan / default scope to shards that differ from <base> (+ untracked).
#
# Identifier match is by NAME (Class or member), stack-agnostic: it proves "every planned member
# exists somewhere in the code tree", not that it hangs off the planned class.
# Exit 0 PASS, 1 FAIL, 2 config/usage error.
# Usage: pwsh gates/structure_check.ps1 [-Plan | -Frozen [sha]] [-Changed <base>] [-Config gates/gates.config.json]

[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$BaseRef,
    [switch]$Plan,
    [switch]$Frozen,
    [string]$Changed,
    [string]$Config = 'gates/gates.config.json'
)
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_common.ps1"

$GateName = 'structure_check'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Output "FAIL ${GateName}: needs git"; exit 2 }
if (-not (Test-Path -LiteralPath $Config)) { Write-Output "FAIL ${GateName}: cannot read config ${Config}: no such file"; exit 2 }
$Config = (Resolve-Path -LiteralPath $Config).Path
$cfg = Read-Config $Config $GateName

$top = (& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $top) { Write-Output "FAIL ${GateName}: not inside a git work tree"; exit 2 }
$gd = ((& git -C $PSScriptRoot rev-parse --show-prefix) -replace '/$', '')
if (-not $gd) { $gd = '.' }
Set-Location -LiteralPath $top

$globs = @()
$sg = Get-CfgValue $cfg 'structureGlobs' $null
if ($sg) { $globs = @($sg) }
if ($globs.Count -eq 0) { $globs = @('**/*.structure.body.md') }

function Get-ChangedPaths([string]$baseSha, [string]$filter) {
    $tracked = @(git diff --name-only --no-renames --diff-filter=$filter $baseSha -- .)
    $untracked = @(git ls-files --others --exclude-standard --full-name)
    return @(($tracked + $untracked) | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() -replace '\\', '/' } | Sort-Object -Unique)
}

# ---------------------------------------------------------------------------------------------------
# -Frozen: the deviation guard (same working-tree diff as test_edit_ban, over structureGlobs).
if ($Frozen) {
    $base = $BaseRef; $baseSrc = 'argument'
    $frozenPath = Join-Path $gd '.frozen'
    if (-not $base -and (Test-Path -LiteralPath $frozenPath)) {
        $line = (Get-Content -LiteralPath $frozenPath | Where-Object { $_ -match '^sha=([0-9a-fA-F]+)' } | Select-Object -First 1)
        if ($line) { $base = [regex]::Match($line, '^sha=([0-9a-fA-F]+)').Groups[1].Value; $baseSrc = $frozenPath -replace '\\', '/' }
    }
    if (-not $base) { Write-Output "FAIL ${GateName}: no base - pass the QA-frozen SHA or run gates/freeze.ps1 at Stage 5 exit."; exit 2 }
    git rev-parse --verify --quiet "$base^{commit}" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Output "FAIL ${GateName}: base '$base' ($baseSrc) does not resolve."; exit 2 }
    $baseSha = (& git rev-parse "$base^{commit}").Trim()
    git merge-base --is-ancestor $baseSha HEAD 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Output "FAIL ${GateName}: base '$base' ($baseSrc) is not an ancestor of HEAD."; exit 2 }
    # NB: not `$changed` - that is the script's [string] -Changed parameter (names are case-insensitive)
    # and assigning an array to it would coerce the paths into one space-joined string.
    $diffs = Get-ChangedPaths $baseSha 'ACMD'
    $res = @(); foreach ($g in $globs) { if ($g) { $res += ,(ConvertTo-Regex ($g -replace '\\', '/')) } }
    $v = New-Object System.Collections.Generic.List[string]
    foreach ($p in $diffs) { foreach ($re in $res) { if ($re.IsMatch($p)) { $v.Add($p); break } } }
    if ($v.Count -gt 0) {
        Write-Output "FAIL ${GateName}: structure shard(s) differ from the frozen base $base (the PM approved this diagram):"
        foreach ($p in $v) { Write-Output "  $p" }
        Write-Output "A deviation is not an edit: write [NEEDS-PO:structure] <Class.member: proposed signature - why> on the item; the PM decides; the PO replaces the shard wholesale and re-freezes."
        exit 1
    }
    Write-Output "PASS ${GateName}: no structure shard differs from $base (working tree, incl. untracked)."
    exit 0
}

# ---------------------------------------------------------------------------------------------------
# Scope: structure shards (all, or changed vs -Changed base).
$shards = @(Expand-Globs $globs)
if ($Changed) {
    git rev-parse --verify --quiet "$Changed^{commit}" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Output "FAIL ${GateName}: --changed base '$Changed' does not resolve."; exit 2 }
    $ch = Get-ChangedPaths $Changed 'ACM'
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($c in $ch) { [void]$set.Add($c) }
    $shards = @($shards | Where-Object { $set.Contains($_) })
}
if ($shards.Count -eq 0) {
    Write-Output "PASS ${GateName}: no structure shards in scope (a unit with no new public members records 'structure: N/A - <reason>' on the item)."
    exit 0
}

# Parse a shard into records @{sec; cls; mem; line}; mem empty for a class line.
$relRe = [regex]'<\|--|--\|>|<\|\.\.|\.\.\|>|\*--|--\*|o--|--o|-->|<--|\.\.>|<\.\.|--\s|\s--|\.\.\s'
function Get-Ident([string]$s) { $m = [regex]::Match($s, '[A-Za-z_][A-Za-z0-9_]*'); if ($m.Success) { return $m.Value } ; return '' }
function Get-IdentLast([string]$s) {
    $parts = @(([regex]::Replace($s, '[^A-Za-z0-9_]+', ' ')).Trim() -split ' ' | Where-Object { $_ })
    for ($i = $parts.Count - 1; $i -ge 0; $i--) { if ($parts[$i] -match '^[A-Za-z_]') { return $parts[$i] } }
    return ''
}
function Get-MemberName([string]$s) {
    $t = $s -replace '^\s*[+#~-]?\s*', ''
    $t = [regex]::Replace($t, '~[^~]*~', '')
    $t = $t -replace '\s*[*$]+\s*$', ''
    $p = $t.IndexOf('('); if ($p -ge 0) { return Get-IdentLast $t.Substring(0, $p) }
    $p = $t.IndexOf(':'); if ($p -ge 0) { return Get-IdentLast $t.Substring(0, $p) }
    return Get-IdentLast $t
}
function Parse-Shard([string]$file) {
    $recs = New-Object System.Collections.Generic.List[object]
    $fence = $false; $dia = 0; $cls = ''; $sec = 'present'; $n = 0
    foreach ($raw in (Read-FileLines $file)) {
        $n++
        $line = $raw
        if (-not $fence) {
            if ($line -match '^\s*#+\s') {
                $h = $line.ToLowerInvariant()
                if ($h -match 'removed|retired|deleted') { $sec = 'removed' }
                elseif ($h -match 'changed|modified|updated') { $sec = 'changed' }
                elseif ($h -match 'added|new') { $sec = 'added' }
            }
            if ($line -match '^\s*```') { $fence = $true; $dia = if ($line.ToLowerInvariant() -match 'mermaid') { -1 } else { 0 }; $cls = '' }
            continue
        }
        if ($line -match '^\s*```') { $fence = $false; $dia = 0; $cls = ''; continue }
        if ($dia -eq -1) { if ($line -match 'classDiagram') { $dia = 1 } elseif ($line -notmatch '^\s*$' -and $line -notmatch '^\s*%%') { $dia = 0 }; continue }
        if ($dia -ne 1) { continue }
        $t = $line -replace '^\s+', ''
        if ($t -eq '' -or $t -match '^%%') { continue }
        if ($t -match '^(note|direction|link|click|callback|style|classDef|cssClass)\s') { continue }
        if ($t -match '^namespace\s') { continue }
        if ($t -match '^class\s+') {
            $t2 = $t -replace '^class\s+', ''; $c = Get-Ident $t2
            if (-not $c) { continue }
            $recs.Add(@{ sec = $sec; cls = $c; mem = ''; line = $n })
            if ($t2 -match '\{\s*$') { $cls = $c }
            continue
        }
        if ($t -match '^\}') { $cls = ''; continue }
        if ($relRe.IsMatch($t)) { continue }
        if ($t -match '^<<.*>>$') { continue }
        if ($cls) { $m = Get-MemberName $t; if ($m) { $recs.Add(@{ sec = $sec; cls = $cls; mem = $m; line = $n }) }; continue }
        if ($t -match '^[A-Za-z_][A-Za-z0-9_]*\s*:') {
            $c = Get-Ident $t; $rest = $t -replace '^[A-Za-z_][A-Za-z0-9_]*\s*:\s*', ''
            $recs.Add(@{ sec = $sec; cls = $c; mem = ''; line = $n })
            if ($rest -match '^<<.*>>$') { continue }
            $m = Get-MemberName $rest; if ($m) { $recs.Add(@{ sec = $sec; cls = $c; mem = $m; line = $n }) }
        }
    }
    return $recs
}

# ---------------------------------------------------------------------------------------------------
# -Plan: shape only.
if ($Plan) {
    $fails = 0; $warns = 0; $n = 0
    foreach ($s in $shards) {
        $n++
        $recs = Parse-Shard $s
        $classes = @($recs | Where-Object { -not $_.mem } | ForEach-Object { $_.cls } | Sort-Object -Unique)
        $members = @($recs | Where-Object { $_.mem })
        if ($classes.Count -eq 0 -or $members.Count -eq 0) {
            Write-Output "FAIL ${GateName}: $s has no member-level classDiagram (classes=$($classes.Count) members=$($members.Count)) - the diagram must name every class and its public members."
            $fails++; continue
        }
        $withMembers = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($r in $members) { [void]$withMembers.Add($r.cls) }
        foreach ($c in $classes) {
            if (-not $withMembers.Contains($c)) { Write-Output "WARN ${GateName}: ${s}: class $c lists no members (an outline in disguise, or an existing class named for context)."; $warns++ }
        }
    }
    if ($fails -gt 0) { exit 1 }
    Write-Output "PASS ${GateName}: $n structure shard(s) at member level ($warns warning(s))."
    exit 0
}

# ---------------------------------------------------------------------------------------------------
# default: forward trace into paths.code.
$code = 'src/**'
if ($cfg.PSObject.Properties.Name -contains 'paths' -and $cfg.paths -and ($cfg.paths.PSObject.Properties.Name -contains 'code') -and $cfg.paths.code) { $code = $cfg.paths.code }
$prefix = ([regex]::Match($code, '^[^*?\[]*')).Value.TrimEnd('/')
if (-not $prefix) { $prefix = '.' }
if (-not (Test-Path -LiteralPath $prefix)) { Write-Output "FAIL ${GateName}: paths.code '$code' resolves to '$prefix', which does not exist."; exit 2 }
$pathspec = @($prefix); foreach ($g in $globs) { $pathspec += ":(exclude,glob)$g" }

$fails = 0; $warns = 0; $checked = 0
foreach ($s in $shards) {
    $recs = Parse-Shard $s
    if ($recs.Count -eq 0) { Write-Output "FAIL ${GateName}: $s has no classDiagram block."; $fails++; continue }
    foreach ($r in $recs) {
        if (-not $r.cls) { continue }
        $name = if ($r.mem) { $r.mem } else { $r.cls }
        $label = if ($r.mem) { "$($r.cls).$($r.mem)" } else { $r.cls }
        & git grep -I -w -q --untracked -e $name -- @pathspec 2>$null
        $found = ($LASTEXITCODE -eq 0)
        if ($r.sec -eq 'removed') {
            if ($found) {
                if (-not $r.mem) { Write-Output "FAIL ${GateName}: ${s}:$($r.line): removed class $($r.cls) is still present under $prefix."; $fails++ }
                else { Write-Output "WARN ${GateName}: ${s}:$($r.line): removed member $label still names something under $prefix (retire it, or it lives on in another class)."; $warns++ }
            }
        } elseif (-not $found) {
            Write-Output "FAIL ${GateName}: ${s}:$($r.line): $label is in the approved diagram but no identifier '$name' exists under $prefix."; $fails++
        }
        $checked++
    }
}
if ($fails -gt 0) { Write-Output "FAIL ${GateName}: $fails diagram entr(y/ies) do not hold in the code ($checked checked). The diagram is the approved plan: conform the code, or route the deviation to the PM."; exit 1 }
Write-Output "PASS ${GateName}: every class and member in $($shards.Count) structure shard(s) resolves under $prefix ($checked checked, $warns warning(s))."
exit 0
