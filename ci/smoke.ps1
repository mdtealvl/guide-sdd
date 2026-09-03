# GUIDE SDD — CI smoke test (PowerShell twin of ci/smoke.sh). Reproduces project-config/INIT.md §6
# on a throwaway copy of the spine using the .ps1 gates: seed one anchored clause + one tagged test,
# run the generic gates (expect PASS), then the NEGATIVE controls — an unfollowed clause (coverage
# FAIL) and every test_edit_ban bypass the v1.12 hardening closed — then freeze and run the whole bank.
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
    $utf8 = [Text.UTF8Encoding]::new($false)
    # INIT §5: the suite command is mandatory (an unset suiteCmd is exit 2, never a silent skip).
    $cfgObj = Get-Content gates/gates.config.template.json -Raw | ConvertFrom-Json
    $cfgObj.suiteCmd = 'exit 0'
    [IO.File]::WriteAllText("$proj/gates/gates.config.json", ($cfgObj | ConvertTo-Json -Depth 10), $utf8)
    New-Item -ItemType Directory -Force spec, tests | Out-Null
    [IO.File]::WriteAllText("$proj/spec/demo.body.md", "## DEMO.1 smoke {#DEMO.1}`nWhen init runs, the system shall pass the smoke test.`n", $utf8)
    [IO.File]::WriteAllText("$proj/tests/demo.smoke.test", "// @clause:DEMO.1`nok();`n", $utf8)
    git add -A ; git commit -q -m seed

    $script:fails = 0
    $script:lastOut = ''
    $script:lastRc = 0
    function Expect([int]$want, [string]$label, [string[]]$cmd) {
        # $cmd[0] = script path (run in a child pwsh so a gate's `exit` cannot end this runner)
        $out = & pwsh -NoProfile -File @cmd 2>&1 | Out-String
        $rc = $LASTEXITCODE
        $bad = if ($want -eq 0) { $rc -ne 0 } else { $rc -eq 0 }
        if ($bad) {
            Write-Output "FAIL  $label (rc=$rc)"; ($out -split "`n") | ForEach-Object { Write-Output "      $_" }; $script:fails++
        } else { Write-Output "ok    $label" }
        $script:lastOut = $out
        $script:lastRc = $rc
    }
    function Names([string]$label, [string]$needle) {
        if ($script:lastOut -notlike "*$needle*") { Write-Output "FAIL  ${label}: output does not name $needle"; ($script:lastOut -split "`n") | ForEach-Object { Write-Output "      $_" }; $script:fails++ }
    }

    $cfg = 'gates/gates.config.json'
    Expect 0 'coverage_check PASS'  @('gates/coverage_check.ps1', '-Config', $cfg)
    Expect 0 'link_check PASS'      @('gates/link_check.ps1', '-Config', $cfg)
    Expect 0 'prose_check PASS'     @('gates/prose_check.ps1', '-Config', $cfg, '-All')
    Expect 0 'test_edit_ban PASS (HEAD, warns moving ref)' @('gates/test_edit_ban.ps1', 'HEAD', $cfg)
    Names 'test_edit_ban' 'moving ref'

    # Negative control: an unfollowed clause must FAIL coverage, naming it.
    [IO.File]::AppendAllText("$proj/spec/demo.body.md", "`n## DEMO.2 unfollowed {#DEMO.2}`nThe system shall have no test, on purpose.`n", $utf8)
    Expect 1 'coverage_check FAIL on DEMO.2' @('gates/coverage_check.ps1', '-Config', $cfg)
    Names 'coverage_check' 'DEMO.2'
    git checkout -q -- spec
    Expect 0 'coverage_check PASS after revert' @('gates/coverage_check.ps1', '-Config', $cfg)

    # Negative control: a tag in a notes file under tests/ is not coverage; a skipped test is warned.
    [IO.File]::WriteAllText("$proj/tests/NOTES.md", "@clause:DEMO.9`n", $utf8)
    Expect 0 'coverage_check ignores tags in tests/NOTES.md' @('gates/coverage_check.ps1', '-Config', $cfg)
    Remove-Item "$proj/tests/NOTES.md"
    [IO.File]::WriteAllText("$proj/tests/demo.smoke.test", "// @clause:DEMO.1`nit.skip(`"x`");`n", $utf8)
    Expect 0 'coverage_check warns on skip marker' @('gates/coverage_check.ps1', '-Config', $cfg)
    Names 'coverage_check' 'skip/only marker'
    git checkout -q -- tests

    # Negative controls: every test_edit_ban bypass closed in v1.12 must FAIL, naming the path.
    $base = (git rev-parse HEAD).Trim()
    [IO.File]::AppendAllText("$proj/tests/demo.smoke.test", "edited`n", $utf8)
    Expect 1 'test_edit_ban FAIL: uncommitted test edit' @('gates/test_edit_ban.ps1', $base, $cfg)
    Names 'test_edit_ban (uncommitted)' 'tests/demo.smoke.test'
    git checkout -q -- tests
    [IO.File]::WriteAllText("$proj/tests/new.test", "new`n", $utf8)
    Expect 1 'test_edit_ban FAIL: untracked new test' @('gates/test_edit_ban.ps1', $base, $cfg)
    Names 'test_edit_ban (untracked)' 'tests/new.test'
    Remove-Item "$proj/tests/new.test"
    git mv tests/demo.smoke.test demo.moved.test
    Expect 1 'test_edit_ban FAIL: test renamed out of tests/' @('gates/test_edit_ban.ps1', $base, $cfg)
    Names 'test_edit_ban (rename-out)' 'tests/demo.smoke.test'
    git mv demo.moved.test tests/demo.smoke.test
    $tamper = Get-Content $cfg -Raw | ConvertFrom-Json
    $tamper.testGlobs = @('nomatch/**')
    [IO.File]::WriteAllText("$proj/$cfg", ($tamper | ConvertTo-Json -Depth 10), $utf8)
    [IO.File]::AppendAllText("$proj/tests/demo.smoke.test", "edited`n", $utf8)
    Expect 1 'test_edit_ban FAIL: gate config tampered' @('gates/test_edit_ban.ps1', $base, $cfg)
    Names 'test_edit_ban (tamper)' 'gate config/scripts modified'
    git checkout -q -- gates tests
    git commit -q --allow-empty -m 'engineer work'
    Expect 1 'test_edit_ban FAIL: base not an ancestor' @('gates/test_edit_ban.ps1', "$base~1", $cfg)
    if ($script:lastRc -ne 2) { Write-Output "FAIL  base-not-ancestor should exit 2 (rc=$($script:lastRc))"; $script:fails++ }

    # Freeze: record the QA-frozen SHA; the gate then needs no base argument.
    Expect 0 'freeze writes gates/.frozen' @('gates/freeze.ps1', '-Unit', 'DEMO-1')
    Names 'freeze' 'sha='
    git add gates/.frozen ; git commit -q -m 'chore(DEMO-1): freeze tests'
    Expect 0 'test_edit_ban PASS via .frozen (no base arg)' @('gates/test_edit_ban.ps1', '-Config', $cfg)
    [IO.File]::AppendAllText("$proj/tests/demo.smoke.test", "edited`n", $utf8)
    git commit -q -am 'engineer edits a test'
    Expect 1 'test_edit_ban FAIL: committed edit vs .frozen' @('gates/test_edit_ban.ps1', '-Config', $cfg)
    Names 'test_edit_ban (.frozen negative)' 'tests/demo.smoke.test'
    git reset -q --hard HEAD~1

    # suiteCmd is mandatory: the template placeholder must make run_all exit 2.
    $noSuite = Get-Content $cfg -Raw | ConvertFrom-Json
    $noSuite.PSObject.Properties.Remove('suiteCmd')
    [IO.File]::WriteAllText("$proj/$cfg", ($noSuite | ConvertTo-Json -Depth 10), $utf8)
    git commit -q -am 'unset suite'
    Expect 1 'run_all refuses unset suiteCmd' @('gates/run_all.ps1', '-Mechanical')
    Names 'run_all (no suite)' 'suiteCmd is not set'
    if ($script:lastRc -ne 2) { Write-Output "FAIL  unset suiteCmd should exit 2 (rc=$($script:lastRc))"; $script:fails++ }
    git reset -q --hard HEAD~1

    # Whole bank over the clean demo tree (base from .frozen), then with an explicit base.
    Expect 0 'run_all clean (base from .frozen)' @('gates/run_all.ps1')
    Expect 0 'run_all HEAD clean' @('gates/run_all.ps1', 'HEAD')

    if ($script:fails -eq 0) { Write-Output 'SMOKE PASS'; exit 0 } else { Write-Output "SMOKE FAIL ($($script:fails))"; exit 1 }
} finally {
    Set-Location $repo
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
