# GUIDE SDD — CI smoke test (PowerShell twin of ci/smoke.sh). Reproduces project-config/INIT.md §6
# on a throwaway copy of the spine using the .ps1 gates: seed one anchored clause + one tagged test,
# run the four generic gates (expect PASS), add an unfollowed clause (expect coverage FAIL), revert,
# run the whole bank (expect clean).
#
# Usage:  pwsh ci/smoke.ps1
# Needs: git, tar (ships with Windows 10+), pwsh 7. Exit 0 = all expectations met.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ('guide-sdd-smoke-' + [guid]::NewGuid().ToString('N'))
$proj = Join-Path $work 'proj'
New-Item -ItemType Directory -Force $proj | Out-Null
try {
    # INIT §6 runs from the spine directory, so the throwaway project IS a copy of the spine.
    $tar = Join-Path $work 'spine.tar'
    # Windows: use the system bsdtar explicitly (a Git-Bash GNU tar on PATH cannot read C:\ paths).
    $tarExe = if ($IsWindows) { Join-Path $env:SystemRoot 'System32\tar.exe' } else { 'tar' }
    & $tarExe --exclude=.git --exclude=ci --exclude=dist --exclude=.github/workflows -cf $tar -C $repo .
    if ($LASTEXITCODE -ne 0) { throw 'tar failed' }
    & $tarExe -xf $tar -C $proj
    if ($LASTEXITCODE -ne 0) { throw 'untar failed' }
    Set-Location $proj
    git init -q -b main . ; git config user.email ci@guide-sdd ; git config user.name ci
    Copy-Item gates/gates.config.template.json gates/gates.config.json
    New-Item -ItemType Directory -Force spec, tests | Out-Null
    $utf8 = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText("$proj/spec/demo.body.md", "## DEMO.1 smoke {#DEMO.1}`nWhen init runs, the system shall pass the smoke test.`n", $utf8)
    [IO.File]::WriteAllText("$proj/tests/demo.smoke.test", "// @clause:DEMO.1`nok();`n", $utf8)
    git add -A ; git commit -q -m seed

    $script:fails = 0
    $script:lastOut = ''
    function Expect([int]$want, [string]$label, [string[]]$cmd) {
        # $cmd[0] = script path (run in a child pwsh so a gate's `exit` cannot end this runner)
        $out = & pwsh -NoProfile -File @cmd 2>&1 | Out-String
        $rc = $LASTEXITCODE
        $bad = if ($want -eq 0) { $rc -ne 0 } else { $rc -eq 0 }
        if ($bad) {
            Write-Output "FAIL  $label (rc=$rc)"; ($out -split "`n") | ForEach-Object { Write-Output "      $_" }; $script:fails++
        } else { Write-Output "ok    $label" }
        $script:lastOut = $out
    }

    $cfg = 'gates/gates.config.json'
    Expect 0 'coverage_check PASS'  @('gates/coverage_check.ps1', '-Config', $cfg)
    Expect 0 'link_check PASS'      @('gates/link_check.ps1', '-Config', $cfg)
    Expect 0 'prose_check PASS'     @('gates/prose_check.ps1', '-Config', $cfg, '-All')
    Expect 0 'test_edit_ban PASS'   @('gates/test_edit_ban.ps1', 'HEAD', $cfg)

    # Negative control: an unfollowed clause must FAIL coverage, naming it.
    [IO.File]::AppendAllText("$proj/spec/demo.body.md", "`n## DEMO.2 unfollowed {#DEMO.2}`nThe system shall have no test, on purpose.`n", $utf8)
    Expect 1 'coverage_check FAIL on DEMO.2' @('gates/coverage_check.ps1', '-Config', $cfg)
    if ($script:lastOut -notmatch 'DEMO\.2') { Write-Output 'FAIL  coverage_check did not name DEMO.2'; $script:fails++ }
    git checkout -q -- spec
    Expect 0 'coverage_check PASS after revert' @('gates/coverage_check.ps1', '-Config', $cfg)

    # Whole bank over the clean demo tree.
    Expect 0 'run_all HEAD clean' @('gates/run_all.ps1', 'HEAD')

    if ($script:fails -eq 0) { Write-Output 'SMOKE PASS'; exit 0 } else { Write-Output "SMOKE FAIL ($($script:fails))"; exit 1 }
} finally {
    Set-Location $repo
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
