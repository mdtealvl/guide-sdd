#!/usr/bin/env pwsh
# _common.ps1 — shared helpers for the PowerShell gate scripts.
# Dot-sourced by each gate (. "$PSScriptRoot/_common.ps1"). No external deps.
# Goal: reproduce Python's glob.glob(recursive=True), json config reads, and file
# reads so the .ps1 gates match the old .py gates exactly.

$ErrorActionPreference = 'Stop'

function Read-Config {
    param([string]$Path, [string]$GateName)
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        return ($raw | ConvertFrom-Json)
    } catch {
        Write-Output "FAIL ${GateName}: cannot read config ${Path}: $($_.Exception.Message)"
        exit 2
    }
}

function Get-CfgValue {
    # Safe property read with default; works on PSCustomObject from ConvertFrom-Json.
    param($Obj, [string]$Name, $Default = $null)
    if ($null -eq $Obj) { return $Default }
    $prop = $Obj.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }
    $v = $prop.Value
    if ($null -eq $v) { return $Default }
    return $v
}

function Read-FileText {
    param([string]$Path)
    try {
        return [System.IO.File]::ReadAllText($Path)
    } catch {
        return ''
    }
}

function Read-FileLines {
    param([string]$Path)
    try {
        # Keep array semantics; splits on \n, strips a trailing \r so regexes that
        # don't expect CR behave like Python's universal-newline readlines().
        $t = [System.IO.File]::ReadAllText($Path)
        return ($t -split "`n") | ForEach-Object { $_ -replace "`r$", '' }
    } catch {
        return @()
    }
}

function ConvertTo-Regex {
    # Translate one glob (with ** / * / ? / character classes) into a .NET regex
    # anchored to the whole path, matching Python's fnmatch + recursive glob.
    # Paths are normalised to forward slashes before matching.
    param([string]$Glob)
    $g = $Glob -replace '\\', '/'
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('^')
    $i = 0
    $n = $g.Length
    while ($i -lt $n) {
        $c = $g[$i]
        if ($c -eq '*') {
            if ($i + 1 -lt $n -and $g[$i + 1] -eq '*') {
                # '**' — match any chars including '/'
                # consume a trailing '/' after ** so 'a/**/b' also matches 'a/b'
                if ($i + 2 -lt $n -and $g[$i + 2] -eq '/') {
                    [void]$sb.Append('(?:.*/)?')
                    $i += 3
                } else {
                    [void]$sb.Append('.*')
                    $i += 2
                }
            } else {
                # single '*' — match any chars except '/'
                [void]$sb.Append('[^/]*')
                $i += 1
            }
        } elseif ($c -eq '?') {
            [void]$sb.Append('[^/]')
            $i += 1
        } elseif ($c -eq '[') {
            # character class — copy until matching ']'
            $j = $i + 1
            if ($j -lt $n -and ($g[$j] -eq '!' -or $g[$j] -eq '^')) { $j++ }
            if ($j -lt $n -and $g[$j] -eq ']') { $j++ }
            while ($j -lt $n -and $g[$j] -ne ']') { $j++ }
            if ($j -ge $n) {
                # no closing bracket — treat '[' literally
                [void]$sb.Append('\[')
                $i += 1
            } else {
                $cls = $g.Substring($i + 1, $j - $i - 1)
                if ($cls.StartsWith('!')) { $cls = '^' + $cls.Substring(1) }
                [void]$sb.Append('[' + $cls + ']')
                $i = $j + 1
            }
        } else {
            [void]$sb.Append([regex]::Escape([string]$c))
            $i += 1
        }
    }
    [void]$sb.Append('$')
    return [regex]::new($sb.ToString())
}

function ConvertTo-FnmatchRegex {
    # Translate a glob into a regex with Python fnmatch semantics: '*' and '?' DO
    # match '/', and there is NO '**' special form (it is just two '*'). Used by
    # test_edit_ban, which matched changed paths with Python's fnmatch.fnmatch.
    param([string]$Glob)
    $g = $Glob -replace '\\', '/'
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('^')
    $i = 0
    $n = $g.Length
    while ($i -lt $n) {
        $c = $g[$i]
        if ($c -eq '*') {
            [void]$sb.Append('.*'); $i += 1
        } elseif ($c -eq '?') {
            [void]$sb.Append('.'); $i += 1
        } elseif ($c -eq '[') {
            $j = $i + 1
            if ($j -lt $n -and ($g[$j] -eq '!' -or $g[$j] -eq '^')) { $j++ }
            if ($j -lt $n -and $g[$j] -eq ']') { $j++ }
            while ($j -lt $n -and $g[$j] -ne ']') { $j++ }
            if ($j -ge $n) {
                [void]$sb.Append('\['); $i += 1
            } else {
                $cls = $g.Substring($i + 1, $j - $i - 1)
                if ($cls.StartsWith('!')) { $cls = '^' + $cls.Substring(1) }
                [void]$sb.Append('[' + $cls + ']')
                $i = $j + 1
            }
        } else {
            [void]$sb.Append([regex]::Escape([string]$c)); $i += 1
        }
    }
    [void]$sb.Append('$')
    return [regex]::new($sb.ToString(), [System.Text.RegularExpressions.RegexOptions]::Singleline)
}

function Expand-Globs {
    # Accept a single glob string or a list; return matching FILES (recursive),
    # relative to the current directory, forward-slashed, sorted, deduped.
    # Mirrors Python glob.glob(recursive=True) filtered to isfile.
    param($Globs)
    if ($null -eq $Globs) { return @() }
    if ($Globs -is [string]) { $Globs = @($Globs) }

    $root = (Get-Location).Path
    $rootNorm = ($root -replace '\\', '/').TrimEnd('/')

    # Enumerate every file once, store as path relative to root with forward slashes.
    $allFiles = New-Object System.Collections.Generic.List[string]
    Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $full = ($_.FullName -replace '\\', '/')
        if ($full.StartsWith($rootNorm + '/')) {
            $allFiles.Add($full.Substring($rootNorm.Length + 1))
        }
    }

    $result = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($glob in $Globs) {
        if ([string]::IsNullOrEmpty($glob)) { continue }
        $gnorm = ($glob -replace '\\', '/')
        $re = ConvertTo-Regex $gnorm
        foreach ($rel in $allFiles) {
            if ($re.IsMatch($rel)) { [void]$result.Add($rel) }
        }
    }
    return @($result | Sort-Object)
}
