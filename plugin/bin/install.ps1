# GUIDE SDD installer — PowerShell twin of install.sh (same verbs, flags, output, exit codes).
# Vendors the spine into a repo, keeps it current, and reports drift.
#   Touches:       <dest>/ spine files, <dest>/.sdd-manifest.json, carriers at the repo root (by flag),
#                  host command dirs (by flag), gates/gates.config.json seeded from the template if absent.
#   update merges: project files made from a template (root carriers, project-details.md, concrete project
#                  gates, installed commands: three-way, git merge-file; gates.config.json: key by key, your
#                  values win). A clean merge is written; a conflict never touches your file (<file>.guide-merge).
#   Never touches: project-config/box-role.local, INIT's three ASKs, any file not in the source. Never deletes.
#
# Usage:
#   pwsh install.ps1 install [--version vX.Y.Z|latest] [--dest sdd] [--carriers claude,codex,copilot,cursor]
#                            [--commands] [--source <dir|zip>] [--repo owner/repo] [--force]
#   pwsh install.ps1 update  [--version vX.Y.Z|latest] [--dest sdd] [--source <dir|zip>] [--repo owner/repo] [--force]
#   pwsh install.ps1 check   [--dest sdd] [--repo owner/repo] [--cached]   (--cached: at most one lookup a day)
#   pwsh install.ps1 doctor  [--dest sdd]
#   pwsh install.ps1 --gates-only <target-dir> [--source <dir|zip>] [--repo owner/repo] [--version vX.Y.Z|latest]
# Exit: 0 ok · 1 doctor found drift / update refused · 2 usage or source error · 3 check: a newer release
#       exists · 4 update applied, merge conflicts to resolve.
# Needs: pwsh 7, git. Downloads: gh (works on a private repo) or Invoke-WebRequest (public).
$ErrorActionPreference = 'Stop'
function Usage { Get-Content $PSCommandPath | Select-Object -First 19 | ForEach-Object { $_ -replace '^# ?', '' } }
$Verb = if ($args.Count -gt 0) { [string]$args[0] } else { '' }
$rest = @(if ($args.Count -gt 1) { $args[1..($args.Count - 1)] })  # @(...) outside: an if-expression unrolls a one-flag array to a string
$GatesTarget = ''
if ($Verb -eq '--gates-only') {
    $GatesTarget = if ($rest.Count -gt 0) { [string]$rest[0] } else { '' }
    $rest = @(if ($rest.Count -gt 1) { $rest[1..($rest.Count - 1)] })
}
$Version = 'latest'; $Dest = 'sdd'; $Carriers = ''; $Commands = $false; $Source = ''; $Repo = 'mdtealvl/guide-sdd'; $Force = $false; $CachedFlag = $false
for ($i = 0; $i -lt $rest.Count; $i++) {
    switch ($rest[$i]) {
        '--version'  { $Version = $rest[++$i] }
        '--dest'     { $Dest = $rest[++$i] }
        '--carriers' { $Carriers = $rest[++$i] }
        '--commands' { $Commands = $true }
        '--source'   { $Source = $rest[++$i] }
        '--repo'     { $Repo = $rest[++$i] }
        '--force'    { $Force = $true }
        '--cached'   { $CachedFlag = $true }
        { $_ -in '-h', '--help' } { Usage; exit 0 }
        default { [Console]::Error.WriteLine("install.ps1: unknown argument '$($rest[$i])'"); Usage | ForEach-Object { [Console]::Error.WriteLine($_) }; exit 2 }
    }
}
if ($Verb -notin 'install', 'update', 'check', 'doctor', '--gates-only') { Usage | ForEach-Object { [Console]::Error.WriteLine($_) }; exit 2 }
$Dest = $Dest.TrimEnd('/', '\')
$Manifest = Join-Path $Dest '.sdd-manifest.json'
$script:Work = $null
$utf8 = [Text.UTF8Encoding]::new($false)
$excludeRe = '^(\.git/|\.github/workflows/|ci/|plugin/|\.claude-plugin/|\.claude/|dist/|project-config/PROPOSED_CHANGELOG\.md$|\.sdd-manifest\.json$)'

# --- helpers -------------------------------------------------------------------------------------
function Die([string]$msg) { [Console]::Error.WriteLine("install.ps1: $msg"); Cleanup; exit 2 }
function Cleanup {
    foreach ($w in $script:Work, $script:MW) { if ($w -and (Test-Path $w)) { Remove-Item -Recurse -Force $w -ErrorAction SilentlyContinue } }
}
function Sha([string]$path) {  # content hash with CRs stripped, so a CRLF checkout is not drift
    $bytes = [IO.File]::ReadAllBytes($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path))  # PS location, not the process dir
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
    [IO.File]::WriteAllText((FullPath $Manifest), $sb.ToString(), $utf8)
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
    $root = (Get-Location).Path.TrimEnd('/', '\') -replace '\\', '/'
    foreach ($p in $nested) {
        Write-Output "WARN nested git repo '$p': the gate bank resolves its root from its own location and cannot see inside it; install the gates there too: install.ps1 --gates-only $root/$p"
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
    if ($changed -or -not (Test-Path $gi)) { [IO.File]::WriteAllText((FullPath $gi), (($lines -join "`n") + "`n"), $utf8) }
}
function VerCmp([string]$a, [string]$b) {  # 1 if a > b, -1 if a < b, else 0 (X.Y.Z; a leading v ignored; each part's leading digits only, so 1.15.0-rc1 = 1.15.0)
    $pa = ($a -replace '^v', '').Split('.'); $pb = ($b -replace '^v', '').Split('.')
    for ($i = 0; $i -lt 3; $i++) {
        $x = if ($i -lt $pa.Count) { $pa[$i] -replace '^([0-9]*).*$', '$1' } else { '' }; if (-not $x) { $x = '0' }
        $y = if ($i -lt $pb.Count) { $pb[$i] -replace '^([0-9]*).*$', '$1' } else { '' }; if (-not $y) { $y = '0' }
        if ([decimal]$x -gt [decimal]$y) { return 1 }
        if ([decimal]$x -lt [decimal]$y) { return -1 }
    }
    return 0
}
function LatestTag {  # the newest release tag of $Repo, or '' when offline (tests: GUIDE_SDD_LATEST=<tag>|none)
    if ($env:GUIDE_SDD_LATEST) { if ($env:GUIDE_SDD_LATEST -eq 'none') { return '' } else { return [string]$env:GUIDE_SDD_LATEST } }
    $t = ''
    try { $t = [string](Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -TimeoutSec 5).tag_name } catch { $t = '' }
    return $t.Trim()
}
function StampPath {  # where check caches its lookup: inside .git (never dirties the tree), else beside the manifest
    $p = ''
    if (Get-Command git -ErrorAction SilentlyContinue) { $p = [string](& git rev-parse --git-path guide-sdd-update-check 2>$null); if ($LASTEXITCODE -ne 0) { $p = '' } }
    if ($p) { return $p.Trim() } else { return (Join-Path $Dest '.sdd-update-check') }
}

# --- careful merge of project files made from a template (update) ------------------------------------
# Pairs (project file, template path in the spine, fp), for project files that exist. The OLD template is the
# merge base: SnapshotBases copies it out of the spine before the spine is overwritten. fp marks files that
# may be the project's own (a carrier or command that install kept, or never placed): they are merged only
# when their first line is the template's (the fingerprint); otherwise SKIPPED, never touched.
# project-details.md and the concrete project gates are template copies by INIT's own steps.
$script:MW = $null; $script:NRef = 0; $script:NMrg = 0; $script:NCfg = 0; $script:NCon = 0
function MergePairs {
    $pairs = [Collections.Generic.List[object]]::new()
    if ($Dest -ne '.') {
        foreach ($c in 'AGENTS.md', 'CLAUDE.md', '.github/copilot-instructions.md') { if (Test-Path -LiteralPath $c -PathType Leaf) { $pairs.Add(@($c, $c, 'fp')) } }
    }
    $pd = "$Dest/project-config/project-details.md"
    if (Test-Path -LiteralPath $pd -PathType Leaf) { $pairs.Add(@($pd, 'project-config/project-details.template.md', '')) }
    foreach ($g in 'constitution_lint', 'seam_conformance', 'qa_import_ban') {
        foreach ($x in 'sh', 'ps1') { $p = "$Dest/gates/$g.$x"; if (Test-Path -LiteralPath $p -PathType Leaf) { $pairs.Add(@($p, "gates/$g.template.$x", '')) } }
    }
    $cmdDir = Join-Path $Dest 'commands'
    $names = if (Test-Path $cmdDir) { OrdinalSort @(Get-ChildItem -LiteralPath $cmdDir -Filter '*.md' -File | ForEach-Object { $_.Name }) } else { @() }
    foreach ($d in '.claude/commands', '.github/prompts', '.cursor/commands') {
        foreach ($n in $names) { if ($n -ne 'README.md' -and (Test-Path -LiteralPath "$d/$n" -PathType Leaf)) { $pairs.Add(@("$d/$n", "commands/$n", 'fp')) } }
    }
    return ,$pairs
}
function SnapshotBases($pairs) {
    foreach ($pr in $pairs) {
        $from = Join-Path $Dest $pr[1]
        if (Test-Path -LiteralPath $from -PathType Leaf) { $to = Join-Path $script:MW "base/$($pr[1])"; New-Item -ItemType Directory -Force (Split-Path $to -Parent) | Out-Null; Copy-Item -LiteralPath $from $to }
    }
    $ct = Join-Path $Dest 'gates/gates.config.template.json'
    if (Test-Path -LiteralPath $ct) { New-Item -ItemType Directory -Force (Join-Path $script:MW 'base/gates') | Out-Null; Copy-Item -LiteralPath $ct (Join-Path $script:MW 'base/gates/gates.config.template.json') }
}
function FullPath([string]$p) { return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($p) }
function StripCr([string]$from, [string]$to) {
    $bytes = [IO.File]::ReadAllBytes((FullPath $from))
    $ms = [IO.MemoryStream]::new(); foreach ($b in $bytes) { if ($b -ne 13) { $ms.WriteByte($b) } }
    [IO.File]::WriteAllBytes((FullPath $to), $ms.ToArray())
}
function FirstLine([string]$p) {  # the raw bytes of line 1, CRs dropped (Latin-1 keeps every byte, a BOM included, as head -n 1 does)
    $bytes = [IO.File]::ReadAllBytes((FullPath $p)); $i = [Array]::IndexOf($bytes, [byte]10); if ($i -lt 0) { $i = $bytes.Length }
    return ([Text.Encoding]::Latin1.GetString($bytes, 0, $i) -replace "`r", '')
}
function PutLike([string]$src, [string]$like, [string]$dst) {  # copy src to dst byte for byte, with CR before every LF
    $bytes = [IO.File]::ReadAllBytes((FullPath $src))           # when <like> uses CRLF (a merge never flips line endings)
    if ([IO.File]::ReadAllBytes((FullPath $like)) -contains 13) {
        $ms = [IO.MemoryStream]::new()
        foreach ($b in $bytes) { if ($b -eq 13) { continue }; if ($b -eq 10) { $ms.WriteByte(13) }; $ms.WriteByte($b) }
        $bytes = $ms.ToArray()
    }
    [IO.File]::WriteAllBytes((FullPath $dst), $bytes)
}
function MergeOne([string]$p, [string]$t, [string]$fp) {
    $b = Join-Path $script:MW "base/$t"; $tt = Join-Path $Dest $t
    if (-not (Test-Path -LiteralPath $tt -PathType Leaf)) { return }                       # template left the release: keep yours
    $hasB = Test-Path -LiteralPath $b -PathType Leaf
    if ($hasB -and (Sha $b) -eq (Sha $tt)) { return }                                     # template unchanged
    if ((Sha $p) -eq (Sha $tt)) { return }                                                # already the new template
    if ($fp -eq 'fp') {
        $l = FirstLine $p
        if ($l -cne (FirstLine $tt) -and (-not $hasB -or $l -cne (FirstLine $b))) { Write-Output "  SKIPPED   $p (first line is not the GUIDE template's: your own file, or its title edited; left alone)"; return }
    }
    if ($hasB -and (Sha $p) -eq (Sha $b)) {
        PutLike $tt $p $p; Write-Output "  REFRESHED $p (was the stock template)"; $script:NRef++; return
    }
    if ($hasB -and (Get-Command git -ErrorAction SilentlyContinue)) {
        $o = Join-Path $script:MW 'm.ours'; $mb = Join-Path $script:MW 'm.base'; $mt = Join-Path $script:MW 'm.theirs'
        StripCr $p $o; StripCr $b $mb; StripCr $tt $mt
        & git merge-file -L "$p (yours)" -L 'old template' -L 'new template' $o $mb $mt 2>&1 | Out-Null
        $rc = $LASTEXITCODE
        if ($rc -eq 0) { PutLike $o $p $p; Write-Output "  MERGED    $p (your edits kept, template changes applied)"; $script:NMrg++; return }
        if ($rc -gt 0 -and $rc -lt 128) {
            PutLike $o $p "$p.guide-merge"
            Write-Output "  CONFLICT  ${p}: $rc overlapping change(s); your file is untouched - resolve $p.guide-merge, then replace $p with it"
            $script:NCon++; return
        }
    }
    MergeReview $p $tt
}
function MergeReview([string]$p, [string]$tt) {  # also the landing for any error: never abort halfway, never touch yours
    Copy-Item -LiteralPath $tt "$p.guide-new" -Force
    Write-Output "  REVIEW    ${p}: no clean three-way merge; the new template is $p.guide-new - fold in what you need"
    $script:NCon++
}
# gates.config.json: keys new in the template are added; a value you never changed (still the old template's)
# follows the new template; every value you set is kept; a key you deleted stays deleted. jq's semantics:
# objects compare by content (key order ignored), arrays and scalars by value.
function IsObj($x) { return ($x -is [Management.Automation.PSCustomObject]) }
function HasKey($x, [string]$k) { return ((IsObj $x) -and (@($x.PSObject.Properties.Name) -ccontains $k)) }
function Canon($x) {  # canonical text for jq-style deep equality
    if ($null -eq $x) { return 'null' }
    if (IsObj $x) {
        $parts = foreach ($n in (OrdinalSort @($x.PSObject.Properties.Name))) { (ConvertTo-Json $n -Compress) + ':' + (Canon $x.$n) }
        return '{' + (@($parts) -join ',') + '}'
    }
    if ($x -is [Collections.IList]) { $parts = foreach ($e in $x) { Canon $e }; return '[' + (@($parts) -join ',') + ']' }
    if ($x -is [bool]) { return $(if ($x) { 'true' } else { 'false' }) }
    if ($x -is [string]) { return (ConvertTo-Json $x -Compress) }
    return ([decimal]$x).ToString([Globalization.CultureInfo]::InvariantCulture)
}
function CfgMerge($b, $t, $o) {
    if ((IsObj $o) -and (IsObj $t)) {
        foreach ($k in @($t.PSObject.Properties.Name)) {
            if (HasKey $o $k) { $bk = if (HasKey $b $k) { $b.$k } else { $null }; $o.$k = (CfgMerge $bk $t.$k $o.$k) }
            elseif (HasKey $b $k) { }
            else { $o | Add-Member -NotePropertyName $k -NotePropertyValue $t.$k }
        }
        return ,$o
    }
    if ((Canon $o) -eq (Canon $b) -and (Canon $t) -ne (Canon $b)) { return ,$t }
    return ,$o
}
function CfgChanged($a, $m, [string[]]$p, $acc) {
    if ((IsObj $a) -and (IsObj $m)) {
        foreach ($k in @($m.PSObject.Properties.Name)) {
            if (HasKey $a $k) { CfgChanged $a.$k $m.$k ($p + $k) $acc } else { $acc.Add((($p + $k) -join '.') + ' (added)') }
        }
    } elseif ((Canon $a) -ne (Canon $m)) { $acc.Add(($p -join '.') + ' (template default updated)') }
}
function CfgGone($b, $t, $o, [string[]]$p, $acc) {
    if ((IsObj $b) -and (IsObj $t) -and (IsObj $o)) {
        foreach ($k in @($b.PSObject.Properties.Name)) {
            if (HasKey $t $k) { $ok = if (HasKey $o $k) { $o.$k } else { $null }; CfgGone $b.$k $t.$k $ok ($p + $k) $acc }
            elseif (HasKey $o $k) { $acc.Add((($p + $k) -join '.') + ' (no longer in the template; kept)') }
        }
    }
}
function MergeConfig {
    $p = "$Dest/gates/gates.config.json"; $b = Join-Path $script:MW 'base/gates/gates.config.template.json'; $t = Join-Path $Dest 'gates/gates.config.template.json'
    if (-not ((Test-Path -LiteralPath $p) -and (Test-Path -LiteralPath $b) -and (Test-Path -LiteralPath $t))) { return }
    if ((Sha $b) -eq (Sha $t)) { return }
    # Strings stay strings where pwsh has -DateKind (7.5+; every pwsh turns an ISO date into [DateTime]); any failure -
    # a pre-7.5 pwsh meeting a date, keys differing only in case - lands in REVIEW, never a half-done update.
    $cfj = @{}; if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $cfj.DateKind = 'String' }
    $review = { Write-Output "  REVIEW    ${p}: cannot merge (jq missing or the config is not valid JSON); compare it with $t by hand"; $script:NCon++ }
    try {
        $oj = Get-Content -Raw -LiteralPath $p | ConvertFrom-Json @cfj
        if (-not (IsObj $oj)) { & $review; return }
        $bj = Get-Content -Raw -LiteralPath $b | ConvertFrom-Json @cfj; $tj = Get-Content -Raw -LiteralPath $t | ConvertFrom-Json @cfj
        $orig = Get-Content -Raw -LiteralPath $p | ConvertFrom-Json @cfj
        $merged = CfgMerge $bj $tj $oj
        $acc = [Collections.Generic.List[string]]::new()
        CfgChanged $orig $merged @() $acc
        $fresh = Get-Content -Raw -LiteralPath $p | ConvertFrom-Json @cfj
        CfgGone $bj $tj $fresh @() $acc
        if ($acc.Count -eq 0) { return }
        $json = $null
        if ((Canon $orig) -ne (Canon $merged)) { $json = ((ConvertTo-Json $merged -Depth 100) -replace "`r`n", "`n") + "`n" }
    } catch { & $review; return }
    if ($json) {
        $tmp = Join-Path $script:MW 'cfg.merged'; [IO.File]::WriteAllText($tmp, $json, $utf8); PutLike $tmp $p $p
    }
    foreach ($line in $acc) { Write-Output "  CONFIG    ${p}: $line"; $script:NCfg++ }
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
    # Hand off to the new release's own installer, so the newest merge rules run (once: the env guard).
    $srcInst = Join-Path $src 'install.ps1'
    if (-not $env:GUIDE_SDD_HANDOFF -and (Test-Path -LiteralPath $srcInst) -and (Sha $srcInst) -ne (Sha $PSCommandPath)) {
        Write-Output "handoff   running the guide-sdd $v installer from the new release"
        $a = @('update', '--source', $src, '--dest', $Dest); if ($Force) { $a += '--force' }
        $env:GUIDE_SDD_HANDOFF = '1'   # for the child only: cleared below, so an in-process session can hand off again
        try { & (Get-Process -Id $PID).Path -NoProfile -File $srcInst @a; $rc = $LASTEXITCODE } finally { Remove-Item Env:GUIDE_SDD_HANDOFF -ErrorAction SilentlyContinue }
        Cleanup; exit $rc
    }
    $script:MW = Join-Path ([IO.Path]::GetTempPath()) ('guide-sdd-merge-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $script:MW | Out-Null
    $pairs = MergePairs; SnapshotBases $pairs
    $upd = 0; $add = 0
    foreach ($f in OrdinalSort (SpineFiles $src)) {
        $to = Join-Path $Dest $f; $from = Join-Path $src $f
        if (-not (Test-Path $to)) { $d = Split-Path $to -Parent; if ($d) { New-Item -ItemType Directory -Force $d | Out-Null }; Copy-Item $from $to; Write-Output "  ADDED   $Dest/$f"; $add++ }
        elseif ((Sha $from) -ne (Sha $to)) { Copy-Item $from $to; Write-Output "  UPDATED $Dest/$f"; $upd++ }
    }
    WriteManifest $src $v
    foreach ($pr in $pairs) { try { MergeOne $pr[0] $pr[1] $pr[2] } catch { MergeReview $pr[0] (Join-Path $Dest $pr[1]) } }
    MergeConfig
    EnsureGitignore '.'
    Write-Output "update    guide-sdd $old -> $v at $Dest/ ($upd updated, $add added, nothing removed)"
    Write-Output "merge     $($script:NRef) refreshed, $($script:NMrg) merged, $($script:NCfg) config change(s), $($script:NCon) to resolve"
    if ($script:NCon -gt 0) {
        Write-Output "next      resolve each CONFLICT / REVIEW file (then delete its .guide-merge / .guide-new), then commit the bump by itself"
        WarnNested; Cleanup; exit 4
    }
    Write-Output "next      commit the bump (spine + merged project files) by itself, before any code (spec-edit law)"
    WarnNested
}
function Do-Check {
    if (-not (Test-Path $Manifest)) { Die "no $Manifest at $Dest/ - not installed" }
    $v = ManifestVersion; $stamp = StampPath; $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); $l = ''; $fromCache = $false
    if ($CachedFlag -and (Test-Path -LiteralPath $stamp)) {
        $line = ((Get-Content -Raw -LiteralPath $stamp) -replace "`r", '') -replace "`n.*$", ''
        $sp = $line.IndexOf(' ')
        $ts = if ($sp -ge 0) { $line.Substring(0, $sp) } else { $line }
        $tag = if ($sp -ge 0) { $line.Substring($sp + 1).Trim() } else { '' }
        if ($ts -match '^[0-9]+$' -and ($now - [long]$ts) -lt 86400) { $l = $tag; $fromCache = $true }
    }
    if (-not $fromCache) {   # cache only a real answer: an offline start must not hide the check for a day
        $l = LatestTag
        if ($l) { try { [IO.File]::WriteAllText($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($stamp), "$now $l`n", $utf8) } catch { } }
    }
    if (-not $l) { Write-Output "check     guide-sdd $v installed; latest release unknown (offline?) - skipped"; return }
    if ((VerCmp $l $v) -eq 1) {
        Write-Output "UPDATE    guide-sdd $($l -replace '^v', '') is available (installed $v)"
        Write-Output "next      ask the human first; on yes: sh $Dest/install.sh update --version $l  (Windows: pwsh $Dest/install.ps1 update --version $l)"
        Cleanup; exit 3
    }
    Write-Output "check     guide-sdd $v is current (latest $($l -replace '^v', ''))"
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
    switch ($Verb) { 'install' { Do-Install } 'update' { Do-Update } 'check' { Do-Check } 'doctor' { Do-Doctor } '--gates-only' { Do-GatesOnly $GatesTarget } }
} finally { Cleanup }
