#!/usr/bin/env pwsh
# build — assemble content-only spec shards into one navigable HTML index.
#
# No dependencies (native PowerShell). Reads every *.body.md (default, compiled from
# Markdown) and *.body.html (inlined as-is) shard RECURSIVELY under the spec dir, wraps
# them in _layout.html (the single home of page chrome/CSS/JS), generates a TOC from the
# rendered <hN> headings and clause anchors, and writes index.html.
#
# Layout contract: _layout.html must contain the markers
#     <!--TOC-->     (replaced with the generated table of contents)
#     <!--BODY-->    (replaced with the concatenated shards)
# If absent, a minimal default layout is emitted.
#
# Shard order: lexical by path. Prefix shards with an ordering key (0_, 1_...) when
# sequence matters.
#
# Usage:  pwsh spec-format/build.ps1 [spec_dir]   (default: spec)

[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$SpecDir = 'spec'
)
$ErrorActionPreference = 'Stop'

$Layout = Join-Path $SpecDir '_layout.html'
$Out = Join-Path $SpecDir 'index.html'

# <hN ... id="..">title</hN>  — DOTALL, case-insensitive.
$headRe = [regex]::new('<h([1-6])[^>]*?(?:\sid=["'']([^"'']+)["''])?[^>]*>(.*?)</h\1>',
    ([System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline))

function Get-DefaultLayout {
    return ("<!doctype html><html><head><meta charset='utf-8'>" +
            "<title>Spec</title><style>body{font:16px/1.5 system-ui;max-width:50rem;" +
            "margin:2rem auto;padding:0 1rem}nav{border-bottom:1px solid #ccc;" +
            "margin-bottom:2rem}code{background:#f4f4f4;padding:.1em .3em}</style>" +
            "</head><body><nav><!--TOC--></nav><main><!--BODY--></main></body></html>")
}

function Get-HtmlEscaped([string]$s) {
    # Matches Python html.escape(s, quote=True) (the stdlib default).
    if ($null -eq $s) { return '' }
    return $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&#x27;')
}

function Invoke-Inline([string]$s) {
    # Inline Markdown: `code`, **bold**, *italic*, [text](href). NOT escaped wholesale.
    $s = [regex]::Replace($s, '`([^`]+)`', { param($m) '<code>' + (Get-HtmlEscaped $m.Groups[1].Value) + '</code>' })
    $s = [regex]::Replace($s, '\*\*([^*]+)\*\*', '<strong>$1</strong>')
    $s = [regex]::Replace($s, '\*([^*]+)\*', '<em>$1</em>')
    $s = [regex]::Replace($s, '\[([^\]]+)\]\(([^)]+)\)', '<a href="$2">$1</a>')
    return $s
}

function ConvertFrom-Markdown2([string]$md) {
    # Minimal Markdown shim: ATX headings (preserving a trailing {#id} -> <hN id>),
    # fenced ``` code blocks (escaped), blank-line paragraphs, inline set above.
    # Lines starting with '<' (raw HTML) pass through unchanged.
    $lines = $md -split "`n"
    $out = New-Object System.Collections.Generic.List[string]
    $i = 0
    $n = $lines.Count
    $headLine = [regex]'^(#{1,6})\s+(.*?)\s*(?:\{#([^}]+)\})?\s*$'
    while ($i -lt $n) {
        $ln = $lines[$i]
        if ($ln.StartsWith('```')) {
            $i++
            $buf = New-Object System.Collections.Generic.List[string]
            while ($i -lt $n -and (-not $lines[$i].StartsWith('```'))) {
                $buf.Add((Get-HtmlEscaped $lines[$i]))
                $i++
            }
            $out.Add('<pre><code>' + ($buf -join "`n") + '</code></pre>')
            $i++
            continue
        }
        $m = $headLine.Match($ln)
        if ($m.Success) {
            $lvl = $m.Groups[1].Value.Length
            $aid = $m.Groups[3].Value
            $idattr = ''
            if ($aid) { $idattr = ' id="' + (Get-HtmlEscaped $aid) + '"' }
            $out.Add("<h$lvl$idattr>" + (Invoke-Inline $m.Groups[2].Value) + "</h$lvl>")
            $i++
            continue
        }
        if ($ln.Trim() -eq '') {
            $out.Add('')
            $i++
            continue
        }
        if ($ln.TrimStart().StartsWith('<')) {
            $out.Add($ln)
            $i++
            continue
        }
        $para = New-Object System.Collections.Generic.List[string]
        $para.Add($ln)
        $i++
        while ($i -lt $n -and $lines[$i].Trim() -ne '' `
               -and (-not $lines[$i].StartsWith('#')) -and (-not $lines[$i].StartsWith('```')) `
               -and (-not $lines[$i].TrimStart().StartsWith('<'))) {
            $para.Add($lines[$i])
            $i++
        }
        $out.Add('<p>' + (Invoke-Inline ($para -join ' ')) + '</p>')
    }
    return ($out -join "`n")
}

# Collect shards recursively, lexical by path, both extensions, never index.html.
$shards = @(Get-ChildItem -LiteralPath $SpecDir -Recurse -File -Filter '*.body.*' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like '*.body.md' -or $_.Name -like '*.body.html' } |
    Where-Object { $_.Name -ne 'index.html' } |
    Sort-Object { ($_.FullName -replace '\\', '/') })

if ($shards.Count -eq 0) {
    Write-Output "build: no shards under $SpecDir/**/*.body.{md,html}"
    exit 1
}

if (Test-Path -LiteralPath $Layout) {
    $layout = [System.IO.File]::ReadAllText($Layout)
} else {
    $layout = Get-DefaultLayout
}
if ($layout -notlike '*<!--BODY-->*') {
    Write-Output "build: FAIL — _layout.html missing <!--BODY--> marker"
    exit 1
}

$bodyParts = New-Object System.Collections.Generic.List[string]
$tocParts = New-Object System.Collections.Generic.List[string]

foreach ($s in $shards) {
    if ($s.Name.EndsWith('.body.md')) { $suffix = '.body.md' } else { $suffix = '.body.html' }
    $slug = $s.Name.Substring(0, $s.Name.Length - $suffix.Length)
    $raw = [System.IO.File]::ReadAllText($s.FullName)
    if ($suffix -eq '.body.md') { $text = ConvertFrom-Markdown2 $raw } else { $text = $raw }

    $bodyParts.Add('<section id="' + (Get-HtmlEscaped $slug) + '" data-shard="' + (Get-HtmlEscaped $s.Name) + '">' + "`n" + $text + "`n" + '</section>')

    $anyHead = $false
    foreach ($hm in $headRe.Matches($text)) {
        $anyHead = $true
        $lvl = $hm.Groups[1].Value
        $anchor = $hm.Groups[2].Value
        $title = $hm.Groups[3].Value
        $target = if ($anchor) { $anchor } else { $slug }
        $clean = ([regex]::Replace($title, '<[^>]+>', '')).Trim()
        $indent = '  ' * ([int]$lvl - 1)
        $tocParts.Add($indent + '<a href="#' + (Get-HtmlEscaped $target) + '" style="display:block">' + (Get-HtmlEscaped $clean) + '</a>')
    }
    if (-not $anyHead) {
        $tocParts.Add('<a href="#' + (Get-HtmlEscaped $slug) + '" style="display:block">' + (Get-HtmlEscaped $slug) + '</a>')
    }
}

$result = $layout.Replace('<!--TOC-->', ($tocParts -join "`n")).Replace('<!--BODY-->', ($bodyParts -join "`n"))
[System.IO.File]::WriteAllText($Out, $result)
Write-Output "build: PASS — $($shards.Count) shard(s) -> $Out"
exit 0
