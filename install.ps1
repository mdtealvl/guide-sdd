# GUIDE SDD installer — PowerShell twin of install.sh (same verbs, flags, output, exit codes).
# Vendors the spine into a repo, keeps it current, and reports drift.
#   Touches:       <dest>/ spine files, <dest>/.sdd-manifest.json, carriers at the repo root (by flag),
#                  host command dirs (by flag), gates/gates.config.json seeded from the template if absent.
#   Never touches: project-config/project-details.md, gates/gates.config.json once present, concrete
#                  project gates, project-config/box-role.local, INIT's three ASKs, any file not in the source.
#   Never deletes.
#
# Usage:
#   pwsh install.ps1 install [--version vX.Y.Z|latest] [--dest sdd] [--carriers claude,codex,copilot,cursor]
#                            [--commands] [--source <dir|zip>] [--repo owner/repo] [--force]
#   pwsh install.ps1 update  [--version vX.Y.Z|latest] [--dest sdd] [--source <dir|zip>] [--repo owner/repo] [--force]
#   pwsh install.ps1 doctor  [--dest sdd]
#   pwsh install.ps1 --gates-only <target-dir> [--source <dir|zip>] [--repo owner/repo] [--version vX.Y.Z|latest]
# Exit: 0 ok · 1 doctor found drift / update refused · 2 usage or source error.
# Needs: pwsh 7, git. Downloads: gh (works on a private repo) or Invoke-WebRequest (public).
$ErrorActionPreference = 'Stop'
function Usage { Get-Content $PSCommandPath | Select-Object -Skip 1 -First 20 | ForEach-Object { $_ -replace '^# ?', '' } }
$Verb = if ($args.Count -gt 0) { [string]$args[0] } else { '' }
$rest = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }
$GatesTarget = ''
if ($Verb -eq '--gates-only') {
    $GatesTarget = if ($rest.Count -gt 0) { [string]$rest[0] } else { '' }
    $rest = if ($rest.Count -gt 1) { $rest[1..($rest.Count - 1)] } else { @() }
}
$Version = 'latest'; $Dest = 'sdd'; $Carriers = ''; $Commands = $false; $Source = ''; $Repo = 'mdtealvl/guide-sdd'; $Force = $false
for ($i = 0; $i -lt $rest.Count; $i++) {
    switch ($rest[$i]) {
        '--version'  { $Version = $rest[++$i] }
        '--dest'     { $Dest = $rest[++$i] }
        '--carriers' { $Carriers = $rest[++$i] }
        '--commands' { $Commands = $true }
        '--source'   { $Source = $rest[++$i] }
        '--repo'     { $Repo = $rest[++$i] }
        '--force'    { $Force = $true }
        { $_ -in '-h', '--help' } { Usage; exit 0 }
        default { [Console]::Error.WriteLine("install.ps1: unknown argument '$($rest[$i])'"); Usage | ForEach-Object { [Console]::Error.WriteLine($_) }; exit 2 }
    }
}
if ($Verb -notin 'install', 'update', 'doctor', '--gates-only') { Usage | ForEach-Object { [Console]::Error.WriteLine($_) }; exit 2 }
$Dest = $Dest.TrimEnd('/', '\')
$Manifest = Join-Path $Dest '.sdd-manifest.json'
$script:Work = $null
$utf8 = [Text.UTF8Encoding]::new($false)
$excludeRe = '^(\.git/|\.github/workflows/|ci/|plugin/|\.claude-plugin/|\.claude/|dist/|project-config/PROPOSED_CHANGELOG\.md$|\.sdd-manifest\.json$)'

# --- helpers -------------------------------------------------------------------------------------
function Die([string]$msg) { [Console]::Error.WriteLine("install.ps1: $msg"); Cleanup; exit 2 }
function Cleanup { if ($script:Work -and (Test-Path $script:Work)) { Remove-Item -Recurse -Force $script:Work -ErrorAction SilentlyContinue } }
function Sha([string]$path) {  # content hash with CRs stripped, so a CRLF checkout is not drift
    $bytes = [IO.File]::ReadAllBytes($path)
    $ms = [IO.MemoryStream]::new()
    foreach ($b in $bytes) { if ($b -ne 13) { $ms.WriteByte($b) } }
    $hash = [Security.Cryptography.SHA256]::Create().ComputeHash($ms.ToArray())
    ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
}
function SpineFiles([string]$src) {  # relative paths, forward slashes, ordinal sort (= LC_ALL=C sort)
    $root = (Resolve-Path $src).Path
    $list = Get-ChildItem -LiteralPath $root -Recurse -File -Force | ForEach-Object {
        $_.FullName.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/'
    } | Where-Object { $_ -notmatch $excludeRe }
    [string[]]($list | Sort-Object -Property @{ Expression = { $_ } } -Culture '' | ForEach-Object { $_ })
}
function OrdinalSort([string[]]$a) { $l = [Collections.Generic.List[string]]::new($a); $l.Sort([StringComparer]::Ordinal); return [string[]]$l }
function SrcVersion([string]$src) { $v = Join-Path $src 'VERSION'; if (Test-Path $v) { (Get-Content -Raw $v).Trim() } else { 'unknown' } }
function ManifestVersion { (Get-Content $Manifest | Select-String -Pattern '^  "version": "([^"]*)"' | Select-Object -First 1).Matches[0].Groups[1].Value }
function ManifestFiles {  # hashtable path -> hash, preserving order
    $o = [ordered]@{}
    foreach ($line in Get-Content $Manifest) { if ($line -match '^    "([^"]*)": "([0-9a-f]*)",?$') { $o[$Matches[1]] = $Matches[2] } }
    $o
}
function WriteManifest([string]$src, [string]$ver) {
    $files = OrdinalSort (SpineFiles $src)
    $sb = [Text.StringBuilder]::new()
    [void]$sb.Append("{`n  `"name`": `"guide-sdd`",`n  `"version`": `"$ver`",`n  `"installedAt`": `"$([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))`",`n  `"files`": {`n")
    for ($k = 0; $k -lt $files.Count; $k++) {
        $sep = if ($k -eq $files.Count - 1) { '' } else { ',' }
        [void]$sb.Append("    `"$($files[$k])`": `"$(Sha (Join-Path $Dest $files[$k]))`"$sep`n")
    }
    [void]$sb.Append("  }`n}`n")
    [IO.File]::WriteAllText($Manifest, $sb.ToString(), $utf8)
}
function Acquire {  # returns source dir
    if ($Source -and (Test-Path $Source -PathType Container)) { return (Resolve-Path $Source).Path }
    $script:Work = Join-Path ([IO.Path]::GetTempPath()) ('guide-sdd-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $script:Work | Out-Null
    if ($Source) {
        if (-not (Test-Path $Source -PathType Leaf)) { Die "source not found: $Source" }
        $zip = (Resolve-Path $Source).Path
    } else {
        if (Get-Command gh -ErrorAction SilentlyContinue) {
            if ($Version -eq 'latest') { & gh release download -R $Repo -p 'guide-sdd-*.zip' -D $script:Work | Out-Null }
            else { & gh release download $Version -R $Repo -p 'guide-sdd-*.zip' -D $script:Work | Out-Null }
            if ($LASTEXITCODE -ne 0) { Die "gh release download failed" }
        } else {
            $tag = $Version
            if ($tag -eq 'latest') {
                try { $tag = (Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest").tag_name } catch { Die "could not resolve latest release of $Repo" }
            }
            $ver = $tag -replace '^v', ''
            try { Invoke-WebRequest -Uri "https://github.com/$Repo/releases/download/$tag/guide-sdd-$ver.zip" -OutFile (Join-Path $script:Work "guide-sdd-$ver.zip") } catch { Die "download failed for $tag" }
        }
        $zip = Get-ChildItem $script:Work -Filter 'guide-sdd-*.zip' | Select-Object -First 1 -ExpandProperty FullName
        if (-not $zip) { Die "no release asset found" }
    }
    $x = Join-Path $script:Work 'x'
    Expand-Archive -LiteralPath $zip -DestinationPath $x -Force
    if (Test-Path (Join-Path $x 'sdd')) { return (Join-Path $x 'sdd') } else { return $x }
}
function CopyIf([string]$from, [string]$to) {
    if ((Test-Path $to) -and -not $Force) { Write-Output "carrier   $to (kept)" }
    else { $d = Split-Path $to -Parent; if ($d) { New-Item -ItemType Directory -Force $d | Out-Null }; Copy-Item $from $to; Write-Output "carrier   $to (written)" }
}
function PlaceCarriers([string]$src) {
    if (-not $Carriers) { return }
    foreach ($c in $Carriers -split ',') {
        switch ($c) {
            'claude'  { CopyIf (Join-Path $src 'AGENTS.md') 'AGENTS.md'; CopyIf (Join-Path $src 'CLAUDE.md') 'CLAUDE.md' }
            { $_ -in 'codex', 'cursor', 'gemini' } { CopyIf (Join-Path $src 'AGENTS.md') 'AGENTS.md' }
            'copilot' { CopyIf (Join-Path $src 'AGENTS.md') 'AGENTS.md'; CopyIf (Join-Path $src '.github/copilot-instructions.md') '.github/copilot-instructions.md' }
            ''        { }
            default   { Die "unknown carrier '$c' (claude, codex, cursor, gemini, copilot)" }
        }
    }
}
function PlaceCommands([string]$src) {
    if (-not $Commands) { return }
    foreach ($c in $Carriers -split ',') {
        $d = switch ($c) { 'claude' { '.claude/commands' } 'copilot' { '.github/prompts' } 'cursor' { '.cursor/commands' } default { $null } }
        if (-not $d) { continue }
        New-Item -ItemType Directory -Force $d | Out-Null; $n = 0
        foreach ($f in Get-ChildItem (Join-Path $src 'commands') -Filter '*.md' | Sort-Object Name) {
            if ($f.Name -eq 'README.md') { continue }
            $to = Join-Path $d $f.Name
            if (-not (Test-Path $to) -or $Force) { Copy-Item $f.FullName $to; $n++ }
        }
        Write-Output "commands  $d/ ($n written)"
    }
}
function WarnNested {
    # nested git repos: the gate bank resolves its root from its own location (gates/) and cannot see
    # inside a gitlink or a first-level subdir with its own .git (GitHub issue #2)
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return }
    & git rev-parse --is-inside-work-tree 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { return }
    $nested = [Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    foreach ($line in (& git ls-files -s 2>$null)) {
        if ($line -match '^160000\s+\S+\s+\S+\s+(.+)$') { [void]$nested.Add($Matches[1]) }
    }
    foreach ($d in Get-ChildItem -Directory -Force -ErrorAction SilentlyContinue) {
        if (Test-Path (Join-Path $d.FullName '.git')) { [void]$nested.Add($d.Name) }
    }
    foreach ($p in $nested) {
        Write-Output "WARN nested git repo '$p': the gate bank resolves its root from its own location and cannot see inside it; install the gates there too: install.ps1 --gates-only $p"
    }
}
function EnsureGitignore([string]$root) {  # append sdd/.persona + sdd/.persona-state/ if missing (idempotent)
    $gi = Join-Path $root '.gitignore'
    # Built unconditionally, then populated (not assigned from an if/else expression): an empty
    # collection returned from a branch unrolls to $null on assignment, which breaks $lines.Add below.
    $lines = [Collections.Generic.List[string]]::new()
    if (Test-Path $gi) { foreach ($l in (Get-Content $gi)) { $lines.Add($l) } }
    $changed = $false
    foreach ($want in 'sdd/.persona', 'sdd/.persona-state/') {
        if (-not ($lines -contains $want)) { $lines.Add($want); $changed = $true }
    }
    if ($changed -or -not (Test-Path $gi)) { [IO.File]::WriteAllText($gi, (($lines -join "`n") + "`n"), $utf8) }
}

# --- verbs ---------------------------------------------------------------------------------------
function Do-Install {
    if ((Test-Path $Manifest) -and -not $Force) {
        [Console]::Error.WriteLine("install.ps1: $Dest/ already holds guide-sdd $(ManifestVersion); use 'update' (or --force)"); exit 1
    }
    $src = Acquire; $v = SrcVersion $src
    $files = OrdinalSort (SpineFiles $src)
    foreach ($f in $files) {
        $to = Join-Path $Dest $f; $d = Split-Path $to -Parent
        if ($d) { New-Item -ItemType Directory -Force $d | Out-Null }
        Copy-Item (Join-Path $src $f) $to
    }
    WriteManifest $src $v
    Write-Output "install   guide-sdd $v -> $Dest/ ($($files.Count) files)"
    $cfg = Join-Path $Dest 'gates/gates.config.json'
    if (-not (Test-Path $cfg)) { Copy-Item (Join-Path $Dest 'gates/gates.config.template.json') $cfg; Write-Output "config    $Dest/gates/gates.config.json (seeded from template; fill the keys per INIT section 5)" }
    PlaceCarriers $src; PlaceCommands $src
    EnsureGitignore '.'
    Write-Output "next      open $Dest/project-config/INIT.md at section 1a - the box tier/role and the three ASKs are yours"
    WarnNested
}
function Do-Update {
    if (-not (Test-Path $Manifest)) { Die "no $Manifest — run 'install' first" }
    $old = ManifestVersion
    if (-not $Force -and (Get-Command git -ErrorAction SilentlyContinue)) {
        & git rev-parse --is-inside-work-tree 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0 -and (& git status --porcelain)) {
            [Console]::Error.WriteLine("install.ps1: working tree is not clean; commit or stash first (or --force)"); exit 1
        }
    }
    $edited = @()
    $mf = ManifestFiles
    foreach ($f in $mf.Keys) { $p = Join-Path $Dest $f; if ((Test-Path $p) -and (Sha $p) -ne $mf[$f]) { $edited += "  EDITED  $Dest/$f (local change to a spine file)" } }
    if ($edited.Count -gt 0 -and -not $Force) {
        $edited | ForEach-Object { Write-Output $_ }
        [Console]::Error.WriteLine("install.ps1: spine files were edited locally; move the edits out (they belong in project-config/) or --force"); exit 1
    }
    $src = Acquire; $v = SrcVersion $src
    $upd = 0; $add = 0
    foreach ($f in OrdinalSort (SpineFiles $src)) {
        $to = Join-Path $Dest $f; $from = Join-Path $src $f
        if (-not (Test-Path $to)) { $d = Split-Path $to -Parent; if ($d) { New-Item -ItemType Directory -Force $d | Out-Null }; Copy-Item $from $to; Write-Output "  ADDED   $Dest/$f"; $add++ }
        elseif ((Sha $from) -ne (Sha $to)) { Copy-Item $from $to; Write-Output "  UPDATED $Dest/$f"; $upd++ }
    }
    WriteManifest $src $v
    EnsureGitignore '.'
    Write-Output "update    guide-sdd $old -> $v at $Dest/ ($upd updated, $add added, nothing removed)"
    Write-Output "next      commit the spine bump by itself, before any code (spec-edit law)"
    WarnNested
}
function Do-GatesOnly([string]$target) {
    # installs only gates/ into <target>/sdd/gates/ (no spine, no carriers, no manifest)
    if (-not $target) { Die "--gates-only needs a target directory" }
    $target = $target.TrimEnd('/', '\')
    $src = Acquire; $v = SrcVersion $src
    $gd = "$target/sdd/gates"
    $srcGates = Join-Path $src 'gates'
    $files = OrdinalSort (Get-ChildItem -LiteralPath $srcGates -Recurse -File -Force | ForEach-Object {
        $_.FullName.Substring($srcGates.Length).TrimStart('\', '/') -replace '\\', '/'
    })
    foreach ($f in $files) {
        $to = Join-Path $gd $f; $d = Split-Path $to -Parent
        if ($d) { New-Item -ItemType Directory -Force $d | Out-Null }
        Copy-Item (Join-Path $srcGates $f) $to
    }
    Write-Output "gates-only guide-sdd $v -> $gd/ ($($files.Count) files)"
    $cfg = Join-Path $gd 'gates.config.json'
    if (-not (Test-Path $cfg)) { Copy-Item (Join-Path $gd 'gates.config.template.json') $cfg; Write-Output "config    $gd/gates.config.json (seeded from template; fill the keys per INIT section 5)" }
    EnsureGitignore $target
}
function Do-Doctor {
    if (-not (Test-Path $Manifest)) { Die "no $Manifest at $Dest/ — not installed" }
    $v = ManifestVersion; $bad = 0; $total = 0
    Write-Output "doctor    guide-sdd $v at $Dest/"
    $mf = ManifestFiles
    foreach ($f in $mf.Keys) {
        $total++; $p = Join-Path $Dest $f
        if (-not (Test-Path $p)) { Write-Output "  MISSING $Dest/$f"; $bad++ }
        elseif ((Sha $p) -ne $mf[$f]) { Write-Output "  DRIFT   $Dest/$f"; $bad++ }
    }
    foreach ($c in 'AGENTS.md', 'CLAUDE.md', '.github/copilot-instructions.md') { if (Test-Path $c) { Write-Output "  carrier $c" } }
    if (Test-Path (Join-Path $Dest 'gates/gates.config.json')) { Write-Output "  config  $Dest/gates/gates.config.json" }
    if (Test-Path (Join-Path $Dest 'project-config/project-details.md')) { Write-Output "  project $Dest/project-config/project-details.md" }
    if ($bad -eq 0) { Write-Output "  ok      $total files match the manifest" } else { Write-Output "  $bad of $total files differ from the manifest"; Cleanup; exit 1 }
}
try {
    switch ($Verb) { 'install' { Do-Install } 'update' { Do-Update } 'doctor' { Do-Doctor } '--gates-only' { Do-GatesOnly $GatesTarget } }
} finally { Cleanup }
