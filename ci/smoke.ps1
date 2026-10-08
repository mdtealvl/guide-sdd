# GUIDE SDD — CI smoke test (PowerShell twin of ci/smoke.sh). Reproduces project-config/INIT.md §6
# on a throwaway copy of the spine using the .ps1 gates: seed one anchored clause + one tagged test,
# run the generic gates (expect PASS), then the NEGATIVE controls — an unfollowed clause (coverage
# FAIL), every test_edit_ban bypass the v1.12 hardening closed, the v1.13 structure_check controls
# (planned member missing, removed class present, memberless diagram, diagram edited after freeze) and
# token_ledger (qa row into code refused, stale row) — then freeze and run the whole bank.
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
    # INIT §5: the suite and static-check commands are mandatory (unset is exit 2, never a silent skip).
    $cfgObj = Get-Content gates/gates.config.template.json -Raw | ConvertFrom-Json
    $cfgObj.suiteCmd = 'exit 0'
    $cfgObj.checkCmd = 'exit 0'
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

    # -Plan: the default plan glob follows paths.spec (issue #6: HTML shards), and paths.plan overrides it.
    [IO.File]::WriteAllText("$proj/spec/demo.plan.body.md", "@clause:DEMO.1 - scenario: smoke passes`n", $utf8)
    Expect 0 'coverage_check -Plan PASS (md plan)' @('gates/coverage_check.ps1', '-Plan', '-Config', $cfg)
    New-Item -ItemType Directory -Force "$proj/spec/html" | Out-Null
    [IO.File]::WriteAllText("$proj/spec/html/a.body.html", "<h2 id=`"DEMO.1`">DEMO.1 smoke</h2><p>When init runs, the system shall pass.</p>`n", $utf8)
    [IO.File]::WriteAllText("$proj/spec/html/a.plan.body.html", "<p>@clause:DEMO.1 - scenario: smoke passes</p>`n", $utf8)
    $planCfg = Get-Content $cfg -Raw | ConvertFrom-Json
    $planCfg.paths.spec = 'spec/**/*.body.html'
    [IO.File]::WriteAllText("$proj/$cfg", ($planCfg | ConvertTo-Json -Depth 10), $utf8)
    Expect 0 'coverage_check -Plan PASS (html plan, glob derived from paths.spec)' @('gates/coverage_check.ps1', '-Plan', '-Config', $cfg)
    $planCfg.paths | Add-Member -NotePropertyName plan -NotePropertyValue 'spec/**/*nomatch*.body.html'
    [IO.File]::WriteAllText("$proj/$cfg", ($planCfg | ConvertTo-Json -Depth 10), $utf8)
    Expect 1 'coverage_check -Plan FAIL (paths.plan overrides the derived glob)' @('gates/coverage_check.ps1', '-Plan', '-Config', $cfg)
    Names 'coverage_check (paths.plan)' 'DEMO.1'
    Remove-Item -Recurse -Force "$proj/spec/html", "$proj/spec/demo.plan.body.md"
    git checkout -q -- gates

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

    # structure_check: the PM-approved member-level diagram. Shape (-Plan), forward trace, and the
    # negative controls: a planned member missing from the code, a removed class still present, a
    # memberless diagram. Shard + impl are committed BEFORE the freeze so the frozen half can pass below.
    New-Item -ItemType Directory -Force spec/working, src | Out-Null
    $shard = "$proj/spec/working/DEMO-1.structure.body.md"
    $shardText = "<!-- DEMO-1 structure (delta) -->`n## Added`n``````mermaid`nclassDiagram`n  class Wallet {`n    +int Balance`n    +Deposit(int amount) bool`n  }`n```````n## Removed`n``````mermaid`nclassDiagram`n  class LegacyPurse {`n    +Empty()`n  }`n```````n"
    [IO.File]::WriteAllText($shard, $shardText, $utf8)
    [IO.File]::WriteAllText("$proj/src/wallet.cs", "public class Wallet {`n  public int Balance; public bool Deposit(int amount) { return true; }`n}`n", $utf8)
    git add -A ; git commit -q -m 'chore(DEMO-1): structure shard + impl'
    Expect 0 'structure_check -Plan PASS' @('gates/structure_check.ps1', '-Plan', '-Config', $cfg)
    Expect 0 'structure_check trace PASS' @('gates/structure_check.ps1', '-Config', $cfg)
    [IO.File]::WriteAllText($shard, $shardText.Replace('+Deposit(int amount) bool', "+Deposit(int amount) bool`n    +Withdraw(int amount) bool"), $utf8)
    Expect 1 'structure_check FAIL: planned member missing from code' @('gates/structure_check.ps1', '-Config', $cfg)
    Names 'structure_check (missing member)' 'Wallet.Withdraw'
    git checkout -q -- spec
    [IO.File]::WriteAllText("$proj/src/legacy.cs", "public class LegacyPurse { }`n", $utf8)
    Expect 1 'structure_check FAIL: removed class still present' @('gates/structure_check.ps1', '-Config', $cfg)
    Names 'structure_check (removed class)' 'LegacyPurse'
    Remove-Item "$proj/src/legacy.cs"
    [IO.File]::WriteAllText("$proj/spec/working/DEMO-2.structure.body.md", "## Added`n``````mermaid`nclassDiagram`n  class Outline`n```````n", $utf8)
    Expect 1 'structure_check -Plan FAIL: memberless diagram' @('gates/structure_check.ps1', '-Plan', '-Config', $cfg)
    Names 'structure_check (outline)' 'DEMO-2.structure.body.md'
    Remove-Item "$proj/spec/working/DEMO-2.structure.body.md"

    # token_ledger: the Stage-4b read ledger - add rows, report the tokens: lines, refuse a QA row into
    # the implementation, and (negative control) flag a stale row once its file changes.
    $bp = 'spec/working/DEMO-1.buildplan.md'
    [IO.File]::WriteAllText("$proj/$bp", "# DEMO-1 build plan`n", $utf8)
    Expect 0 'token_ledger add read (P)' @('gates/token_ledger.ps1', 'add', '-Plan', $bp, '-Kind', 'read', '-By', 'P', '-Path', 'src/wallet.cs', '-Config', $cfg)
    Expect 0 'token_ledger add range (P->S2)' @('gates/token_ledger.ps1', 'add', '-Plan', $bp, '-Kind', 'range', '-By', 'P', '-For', 'S2', '-Aud', 'eng', '-Path', 'src/wallet.cs', '-Range', '2-2', '-Note', 'members only', '-Config', $cfg)
    Expect 0 'token_ledger add skip (P->S2)' @('gates/token_ledger.ps1', 'add', '-Plan', $bp, '-Kind', 'skip', '-By', 'P', '-For', 'S2', '-Aud', 'eng', '-Path', 'spec/demo.body.md', '-Config', $cfg)
    Expect 0 'token_ledger add read (S2, ranged)' @('gates/token_ledger.ps1', 'add', '-Plan', $bp, '-Kind', 'read', '-By', 'S2', '-Path', 'src/wallet.cs', '-Range', '2-2', '-Config', $cfg)
    Expect 1 'token_ledger refuses a qa row into paths.code' @('gates/token_ledger.ps1', 'add', '-Plan', $bp, '-Kind', 'read', '-By', 'S1', '-Aud', 'qa', '-Path', 'src/wallet.cs', '-Config', $cfg)
    if ($script:lastRc -ne 2) { Write-Output "FAIL  qa row into code should exit 2 (rc=$($script:lastRc))"; $script:fails++ }
    Expect 0 'token_ledger verify PASS' @('gates/token_ledger.ps1', 'verify', '-Plan', $bp, '-Config', $cfg)
    Expect 0 'token_ledger report' @('gates/token_ledger.ps1', 'report', '-Plan', $bp, '-Config', $cfg)
    Names 'token_ledger (report)' 'tokens: plan admitted'
    Names 'token_ledger (report S2)' 'tokens: S2 admitted'
    git add -A ; git commit -q -m 'chore(DEMO-1): build plan'
    [IO.File]::AppendAllText("$proj/src/wallet.cs", "// touched`n", $utf8)
    Expect 1 'token_ledger verify FAIL: stale row after file change' @('gates/token_ledger.ps1', 'verify', '-Plan', $bp, '-For', 'S2', '-Config', $cfg)
    Names 'token_ledger (stale)' 'STALE'
    git checkout -q -- src

    # Rule engine: a regex is matched line by line (the sh twin's grep -E semantics) - ^ anchors each
    # line, and no match spans a newline. Untracked scratch files, removed before the freeze.
    New-Item -ItemType Directory -Force "$proj/notes" | Out-Null
    [IO.File]::WriteAllText("$proj/rules.smoke.json", '{"constitutionRules":[{"id":"anchored","kind":"must_not_match","paths":"notes/*.txt","pattern":"^FORBIDDEN","message":"m"},{"id":"one-line","kind":"must_not_match","paths":"notes/*.txt","pattern":"^start[^#]*END","message":"m"}]}' + "`n", $utf8)
    [IO.File]::WriteAllText("$proj/notes/a.txt", "ok FORBIDDEN mid-line`nFORBIDDEN at the start of line 2`n", $utf8)
    Expect 1 'constitution_lint FAIL: ^ anchors line 2' @('gates/constitution_lint.template.ps1', '-Config', 'rules.smoke.json')
    Names 'constitution_lint (anchored)' 'anchored'
    [IO.File]::WriteAllText("$proj/notes/a.txt", "ok FORBIDDEN mid-line only`nstart of a line`nEND on the next line`n", $utf8)
    Expect 0 'constitution_lint PASS: mid-line hit is not ^, no match across lines' @('gates/constitution_lint.template.ps1', '-Config', 'rules.smoke.json')
    [IO.File]::WriteAllText("$proj/rules.smoke.json", '{"constitutionRules":[{"id":"no-empty-line","kind":"must_not_match","paths":"notes/*.txt","pattern":"^$","message":"m"}]}' + "`n", $utf8)
    [IO.File]::WriteAllText("$proj/notes/a.txt", "a`n", $utf8)
    Expect 0 'constitution_lint PASS: no phantom empty line after the final newline' @('gates/constitution_lint.template.ps1', '-Config', 'rules.smoke.json')
    Remove-Item -Recurse -Force "$proj/notes", "$proj/rules.smoke.json"

    # static_check (#7): checkCmd is required (unset = exit 2), "none" opts out on the record, the exit
    # code decides, and findingRegex + baseline ratchet. Commands run under both cmd /c and sh -c.
    function St([scriptblock]$f) {
        $o = Get-Content $cfg -Raw | ConvertFrom-Json; & $f $o
        [IO.File]::WriteAllText("$proj/st.smoke.json", ($o | ConvertTo-Json -Depth 10), $utf8)
    }
    St { param($o) $o.PSObject.Properties.Remove('checkCmd') }
    Expect 1 'static_check refuses unset checkCmd' @('gates/static_check.ps1', '-Config', 'st.smoke.json')
    Names 'static_check (unset)' 'checkCmd is not set'
    if ($script:lastRc -ne 2) { Write-Output "FAIL  unset checkCmd should exit 2 (rc=$($script:lastRc))"; $script:fails++ }
    St { param($o) $o.checkCmd = 'none' }
    Expect 0 'static_check PASS: opted out on the record' @('gates/static_check.ps1', '-Config', 'st.smoke.json')
    Names 'static_check (none)' 'opted out'
    St { param($o) $o.checkCmd = 'echo lint clean' }
    Expect 0 'static_check PASS: exit 0' @('gates/static_check.ps1', '-Config', 'st.smoke.json')
    St { param($o) $o.checkCmd = 'echo a.py:1: E1 bad&& exit 3' }
    Expect 1 'static_check FAIL: non-zero exit' @('gates/static_check.ps1', '-Config', 'st.smoke.json')
    Names 'static_check (exit 3)' 'exited 3'
    $lint = 'echo a.py:1: E1 bad&& echo a.py:2: E2 bad&& echo 2 errors&& exit 1'
    St { param($o) $o.checkCmd = $lint; $o.staticCheck.findingRegex = '^a[.]py:[0-9]+:'; $o.staticCheck.baseline = 2 }
    Expect 0 'static_check ratchet PASS: findings = baseline' @('gates/static_check.ps1', '-Config', 'st.smoke.json')
    Names 'static_check (ratchet =)' '2 finding(s) = baseline 2'
    St { param($o) $o.checkCmd = $lint; $o.staticCheck.findingRegex = '^a[.]py:[0-9]+:'; $o.staticCheck.baseline = 3 }
    Expect 0 'static_check ratchet PASS: below baseline, asks to lower it' @('gates/static_check.ps1', '-Config', 'st.smoke.json')
    Names 'static_check (ratchet <)' 'lower staticCheck.baseline to 2'
    St { param($o) $o.checkCmd = $lint; $o.staticCheck.findingRegex = '^a[.]py:[0-9]+:'; $o.staticCheck.baseline = 1 }
    Expect 1 'static_check ratchet FAIL: new findings' @('gates/static_check.ps1', '-Config', 'st.smoke.json')
    Names 'static_check (ratchet >)' '2 finding(s) > baseline 1'
    St { param($o) $o.checkCmd = 'echo crashed&& exit 1'; $o.staticCheck.findingRegex = '^a[.]py:[0-9]+:'; $o.staticCheck.baseline = 5 }
    Expect 1 'static_check ratchet FAIL: non-zero exit, no finding matched' @('gates/static_check.ps1', '-Config', 'st.smoke.json')
    Names 'static_check (no match)' 'no line matched'
    # Review findings (v1.16.0): each was a PASS that should FAIL, or a twin divergence.
    function Rc2([string]$label) { if ($script:lastRc -ne 2) { Write-Output "FAIL  $label should exit 2 (rc=$($script:lastRc))"; $script:fails++ } }
    St { param($o) $o.checkCmd = 'echo a.py:1: E1 bad&& echo Traceback&& exit 4'; $o.staticCheck.findingRegex = '^a[.]py:[0-9]+:'; $o.staticCheck.baseline = 5 }
    Expect 1 'static_check ratchet FAIL: a crash after some findings is not a count' @('gates/static_check.ps1', '-Config', 'st.smoke.json')
    Names 'static_check (crash)' 'not a findings exit code'
    St { param($o) $o.checkCmd = $lint; $o.staticCheck.findingRegex = '^a[.]py:[\d]:'; $o.staticCheck.baseline = 1 }
    Expect 1 'static_check: [\d] inside brackets counts' @('gates/static_check.ps1', '-Config', 'st.smoke.json')
    Names 'static_check (bracket class)' '2 finding(s) > baseline 1'
    St { param($o) $o.checkCmd = 'exit 1'; $o.staticCheck.findingRegex = 'E1[' }
    Expect 1 'static_check: an invalid regex is a config error' @('gates/static_check.ps1', '-Config', 'st.smoke.json')
    Rc2 'static_check (bad regex)'
    St { param($o) $o.checkCmd = 'exit 1'; $o.staticCheck.findingRegex = '(?i)e1' }
    Expect 1 'static_check: an inline flag is outside the portable subset' @('gates/static_check.ps1', '-Config', 'st.smoke.json')
    Rc2 'static_check (inline flag)'
    St { param($o) $o.checkCmd = 'exit 0'; $o.staticCheck.findingRegex = 'x'; $o.staticCheck.baseline = $false }
    Expect 1 'static_check: baseline false is a config error' @('gates/static_check.ps1', '-Config', 'st.smoke.json')
    Rc2 'static_check (baseline false)'
    St { param($o) $o.checkCmd = "echo hi`nexit 4" }
    Expect 1 'static_check: a multi-line checkCmd is a config error' @('gates/static_check.ps1', '-Config', 'st.smoke.json')
    Rc2 'static_check (multi-line)'

    # Rule kind command (#8): a real checker behind a rule row; exit 0 passes, a failure shows its output.
    [IO.File]::WriteAllText("$proj/rules.smoke.json", '{"seamRules":[{"id":"SEAM-1-ok","kind":"command","cmd":"echo fine","message":"m"},{"id":"SEAM-2-layers","kind":"command","cmd":"echo src.ui imports src.db&& exit 3","message":"m"}]}' + "`n", $utf8)
    Expect 1 'seam_conformance FAIL: command rule exits non-zero' @('gates/seam_conformance.template.ps1', '-Config', 'rules.smoke.json')
    Names 'seam_conformance (command)' 'src.ui imports src.db'
    Names 'seam_conformance (command id)' 'SEAM-2-layers: m'
    [IO.File]::WriteAllText("$proj/rules.smoke.json", '{"seamRules":[{"id":"SEAM-1-ok","kind":"command","cmd":"echo fine","message":"m"}]}' + "`n", $utf8)
    Expect 0 'seam_conformance PASS: command rule exits 0' @('gates/seam_conformance.template.ps1', '-Config', 'rules.smoke.json')
    # A command that reads stdin must not eat the rule list (sort reads stdin under sh and cmd alike).
    [IO.File]::WriteAllText("$proj/rules.smoke.json", '{"seamRules":[{"id":"SEAM-1-reads","kind":"command","cmd":"sort","message":"m"},{"id":"SEAM-2-late","kind":"command","cmd":"exit 3","message":"m"}]}' + "`n", $utf8)
    Expect 1 'seam_conformance FAIL: a stdin reader does not swallow later rules' @('gates/seam_conformance.template.ps1', '-Config', 'rules.smoke.json')
    Names 'seam_conformance (stdin)' 'SEAM-2-late: m'
    [IO.File]::WriteAllText("$proj/rules.smoke.json", '{"seamRules":[{"id":"SEAM-1-two","kind":"command","cmd":"echo hi\nexit 4","message":"m"}]}' + "`n", $utf8)
    Expect 1 'seam_conformance FAIL: a multi-line cmd is refused' @('gates/seam_conformance.template.ps1', '-Config', 'rules.smoke.json')
    Names 'seam_conformance (multi-line)' 'must be one line'

    # mutation_check (#9): optional; the exit code decides, or scoreRegex + minScore; {base} is substituted.
    Expect 0 'mutation_check PASS: not configured' @('gates/mutation_check.ps1', '-Config', $cfg)
    Names 'mutation_check (unset)' 'not configured'
    $mut = 'echo Mutation score: 85.5&& exit 1'
    St { param($o) $o.mutation.cmd = $mut; $o.mutation.scoreRegex = 'Mutation score: [0-9.]+'; $o.mutation.minScore = 80 }
    Expect 0 'mutation_check PASS: score >= minScore (exit code ignored)' @('gates/mutation_check.ps1', '-Config', 'st.smoke.json')
    Names 'mutation_check (score)' '85.5 >= minScore 80'
    St { param($o) $o.mutation.cmd = $mut; $o.mutation.scoreRegex = 'Mutation score: [0-9.]+'; $o.mutation.minScore = 90 }
    Expect 1 'mutation_check FAIL: score < minScore' @('gates/mutation_check.ps1', '-Config', 'st.smoke.json')
    Names 'mutation_check (low score)' 'route to QA'
    St { param($o) $o.mutation.cmd = 'echo survived: 3&& exit 2' }
    Expect 1 'mutation_check FAIL: exit code decides without scoreRegex' @('gates/mutation_check.ps1', '-Config', 'st.smoke.json')
    St { param($o) $o.mutation.cmd = 'echo since {base} and {base}' }
    Expect 0 'mutation_check substitutes {base}' @('gates/mutation_check.ps1', '-Base', 'abc123', '-Config', 'st.smoke.json')
    Names 'mutation_check ({base})' 'since abc123 and abc123'
    St { param($o) $o.mutation.cmd = $mut; $o.mutation.scoreRegex = 'score: [\d.]+'; $o.mutation.minScore = 80 }
    Expect 0 'mutation_check: [\d.] inside brackets reads the score' @('gates/mutation_check.ps1', '-Config', 'st.smoke.json')
    Names 'mutation_check (bracket class)' '85.5 >= minScore 80'
    St { param($o) $o.mutation.cmd = $mut; $o.mutation.scoreRegex = 'score: [0-9]+'; $o.mutation.minScore = '.' }
    Expect 1 'mutation_check: minScore "." is a config error' @('gates/mutation_check.ps1', '-Config', 'st.smoke.json')
    Rc2 'mutation_check (minScore .)'
    St { param($o) $o.mutation.cmd = $mut; $o.mutation.scoreRegex = 'score: [0-9]+?' }
    Expect 1 'mutation_check: a lazy quantifier is outside the portable subset' @('gates/mutation_check.ps1', '-Config', 'st.smoke.json')
    Rc2 'mutation_check (lazy)'
    Remove-Item -Force "$proj/st.smoke.json", "$proj/rules.smoke.json"

    # Freeze: record the QA-frozen SHA; the gate then needs no base argument.
    Expect 0 'freeze writes gates/.frozen' @('gates/freeze.ps1', '-Unit', 'DEMO-1')
    Names 'freeze' 'sha='
    git add gates/.frozen ; git commit -q -m 'chore(DEMO-1): freeze tests'
    Expect 0 'test_edit_ban PASS via .frozen (no base arg)' @('gates/test_edit_ban.ps1', '-Config', $cfg)
    # The approved diagram is frozen with the tests: an edit after the freeze FAILs naming the shard.
    Expect 0 'structure_check -Frozen PASS via .frozen' @('gates/structure_check.ps1', '-Frozen', '-Config', $cfg)
    [IO.File]::AppendAllText($shard, "%% deviation`n", $utf8)
    Expect 1 'structure_check -Frozen FAIL: diagram edited after freeze' @('gates/structure_check.ps1', '-Frozen', '-Config', $cfg)
    Names 'structure_check (.frozen negative)' 'DEMO-1.structure.body.md'
    git checkout -q -- spec
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
    # checkCmd is mandatory too: unset, the bank stops at static_check.
    $noCheck = Get-Content $cfg -Raw | ConvertFrom-Json
    $noCheck.PSObject.Properties.Remove('checkCmd')
    [IO.File]::WriteAllText("$proj/$cfg", ($noCheck | ConvertTo-Json -Depth 10), $utf8)
    git commit -q -am 'unset check'
    Expect 1 'run_all refuses unset checkCmd' @('gates/run_all.ps1', '-Mechanical')
    Names 'run_all (no check)' 'checkCmd is not set'
    git reset -q --hard HEAD~1

    # Whole bank over the clean demo tree (base from .frozen), then with an explicit base.
    Expect 0 'run_all clean (base from .frozen)' @('gates/run_all.ps1')
    Names 'run_all (static_check)' 'PASS static_check: checkCmd exited 0'
    Names 'run_all (mutation_check)' 'mutation_check: not configured'
    Expect 0 'run_all HEAD clean' @('gates/run_all.ps1', 'HEAD')
    Expect 0 'run_all -PreFold clean (frozen-diagram half runs)' @('gates/run_all.ps1', '-PreFold')
    Names 'run_all (pre-fold)' 'structure_check --frozen'

    if ($script:fails -eq 0) { Write-Output 'SMOKE PASS'; exit 0 } else { Write-Output "SMOKE FAIL ($($script:fails))"; exit 1 }
} finally {
    Set-Location $repo
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
