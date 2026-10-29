#!/usr/bin/env pwsh
# findings_check - every Validation finding carries a disposition; "accepted" is not one.
#
# Validation writes <unit>.findings.md, one finding per line; the Orchestrator ends each line with its
# disposition. A finding with none, or with any other word (accepted, waived, wontfix...), FAILs.
#
# Line grammar (gates/README.md):
#   F<n> [HIGH|MED|LOW|INFO] <file:line> <claim> | <disposition>
#   disposition = fixed <7-40 hex sha>          the fix commit
#               | defer <evidence>              out of range only; evidence is non-empty text
# The disposition is the text after the LAST ` | ` on the line (a claim may hold a bare |, evidence may not
# hold ` | `). Lines that do not start `F<n> [` are prose and ignored. A line that starts `F<n> [` with a
# severity outside the four is malformed and FAILs.
#
# findings.glob (default **/*.findings.md) finds the files. None = PASS.
#
# Exit 0 PASS, 1 FAIL, 2 config/usage error.
# Usage:  pwsh gates/findings_check.ps1 [-Config gates/gates.config.json]

[CmdletBinding()]
param(
    [string]$Config = 'gates/gates.config.json'
)
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_common.ps1"

$GateName = 'findings_check'
$cfg = Read-Config $Config $GateName
$glob = Get-CfgValue (Get-CfgValue $cfg 'findings' $null) 'glob' '**/*.findings.md'
$files = @(Expand-Globs $glob)
if ($files.Count -eq 0) {
    Write-Output "PASS ${GateName}: no findings files ($glob)."
    exit 0
}

$bad = New-Object System.Collections.Generic.List[string]
$total = 0
foreach ($f in $files) {
    $n = 0
    foreach ($line in (Read-FileLines $f)) {
        $n++
        if ($line -notmatch '^F[0-9]+ \[') { continue }
        $total++
        $id = ($line -split ' ')[0]
        $why = ''
        if ($line -notmatch '^F[0-9]+ \[(HIGH|MED|LOW|INFO)\]') {
            $why = 'malformed: severity must be [HIGH], [MED], [LOW] or [INFO]'
        } elseif ($line.Contains(' | ')) {
            $disp = $line.Substring($line.LastIndexOf(' | ') + 3)
            $sp = $disp.IndexOf(' ')
            $kw = if ($sp -ge 0) { $disp.Substring(0, $sp) } else { $disp }
            $rest = if ($sp -ge 0) { $disp.Substring($sp + 1).Trim() } else { '' }
            if ($kw -ceq 'fixed') {
                if ($rest -notmatch '^[0-9a-fA-F]{7,40}$') { $why = "'fixed' needs a 7-40 hex sha" }
            } elseif ($kw -ceq 'defer') {
                if (-not $rest) { $why = "'defer' needs evidence" }
            } else {
                $why = "disposition '$kw' is not fixed <sha> or defer <evidence>"
            }
        } else {
            $why = "no disposition (end the line with ' | fixed <sha>' or ' | defer <evidence>')"
        }
        if ($why) { $bad.Add("  ${f}:${n}: $id $why") }
    }
}
if ($bad.Count -gt 0) {
    Write-Output "FAIL ${GateName}: $($bad.Count) of $total finding(s) lack a valid disposition:"
    foreach ($b in $bad) { Write-Output $b }
    Write-Output 'A finding is fixed <sha> or deferred with evidence (out of range only). accepted is not a disposition.'
    exit 1
}
Write-Output "PASS ${GateName}: $total finding(s) in $($files.Count) file(s), all dispositioned."
exit 0
