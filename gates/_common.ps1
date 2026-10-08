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

function Resolve-FsPath {
    # .NET file APIs resolve a relative path against the PROCESS directory, which Set-Location does
    # not change; resolve against the PowerShell location instead (GitHub issue #1).
    param([string]$Path)
    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Read-FileText {
    param([string]$Path)
    try {
        return [System.IO.File]::ReadAllText((Resolve-FsPath $Path))
    } catch {
        return ''
    }
}

function Read-FileLines {
    param([string]$Path)
    try {
        # Keep array semantics; splits on \n, strips a trailing \r so regexes that
        # don't expect CR behave like Python's universal-newline readlines().
        $t = [System.IO.File]::ReadAllText((Resolve-FsPath $Path))
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

function Invoke-ShellCapture {
    # Run a configured command the way the sh twin's `sh -c` does (cmd /c on Windows) and return
    # @{ rc; out }: stdout + stderr merged, CRs dropped, trailing newlines trimmed as `$(...)` does.
    param([string]$Cmd)
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        # stdin is an empty pipe, as the sh twin's </dev/null: a command that reads stdin gets EOF.
        if ($env:ComSpec) { $lines = @() | & $env:ComSpec /c $Cmd 2>&1 } else { $lines = @() | & sh -c $Cmd 2>&1 }
        $rc = $LASTEXITCODE
    } finally { $ErrorActionPreference = $prev }
    $text = ((@($lines) | ForEach-Object { "$_" }) -join "`n") -replace "`r", ''
    return @{ rc = $rc; out = $text.TrimEnd("`n") }
}

function Get-TailLines {
    # The last $N non-empty lines of $Text (the sh twin: sed '/^$/d' | tail -n N).
    param([string]$Text, [int]$N)
    $l = @($Text.Split([char]10) | Where-Object { $_ -ne '' })
    if ($l.Count -le $N) { return $l }
    return $l[($l.Count - $N)..($l.Count - 1)]
}

function Test-PortableRegex {
    # A configured regex both twins read alike (the sh twin's check_regex), else a FAIL line + $false:
    # no inline flags (?...) or lazy quantifiers, and it must compile.
    param([string]$Gate, [string]$Key, [string]$Re)
    if ($Re -match '\(\?|\*\?|\+\?|\}\?|\?\?') {
        [Console]::Out.WriteLine("FAIL ${Gate}: $Key uses (?...) or a lazy quantifier - outside the portable regex subset (gates/README.md)")
        return $false
    }
    try { [void][regex]$Re } catch { [Console]::Out.WriteLine("FAIL ${Gate}: $Key is not a valid regex"); return $false }
    return $true
}

function Test-OneLine {
    # A configured command must be one line: cmd /c runs only the first line, sh -c runs them all.
    param([string]$Gate, [string]$Key, [string]$Cmd)
    if ($Cmd -match "[`r`n]") { [Console]::Out.WriteLine("FAIL ${Gate}: $Key must be one line (cmd /c on Windows runs only the first)"); return $false }
    return $true
}

function Get-RawText {
    # A config value as the sh twin's read_raw prints it: null/absent -> $Default; booleans as jq
    # spells them (false/true); numbers in invariant culture.
    param($Obj, [string]$Name, [string]$Default)
    if ($null -eq $Obj) { return $Default }
    $p = $Obj.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value -or "$($p.Value)" -eq '') { return $Default }
    $v = $p.Value
    if ($v -is [bool]) { return $(if ($v) { 'true' } else { 'false' }) }
    if ($v -is [array] -or $v -is [System.Management.Automation.PSCustomObject]) { return ($v | ConvertTo-Json -Compress) }
    return [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0}', $v)
}
