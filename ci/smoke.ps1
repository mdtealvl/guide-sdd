# GUIDE SDD — CI smoke test (PowerShell twin of ci/smoke.sh). Reproduces project-config/INIT.md §6
# on a throwaway copy of the spine using the .ps1 gates: seed one anchored clause + one tagged test,
# run the generic gates (expect PASS), then the NEGATIVE controls — an unfollowed clause (coverage
# FAIL), every test_edit_ban bypass the v1.12 hardening closed, the v1.13 structure_check controls
# (planned member missing, removed class present, memberless diagram, diagram edited after freeze) and
# token_ledger (qa row into code refused, stale row, | in a cell) — then freeze and run the whole bank.
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
    # link_check (#14): a link to a repo file that is not a shard fails, unless linkCheck.skipGlobs
    # names it (resolved against the linking shard's directory; a leading / is the project root).
    New-Item -ItemType Directory -Force "$proj/spec/lk" | Out-Null
    [IO.File]::WriteAllText("$proj/spec/lk/links.body.md", "# Links`nSee [r](../../docs/research/X.md#s), [y](/docs/Y.md) and [z](../../notes/Z.md).`n", $utf8)
    Expect 1 'link_check FAIL: link to a non-shard file' @('gates/link_check.ps1', '-Config', $cfg)
    Names 'link_check (non-shard)' "'../../docs/research/X.md#s' - no such shard"
    $lkCfg = Get-Content $cfg -Raw | ConvertFrom-Json
    $lkCfg.linkCheck.skipGlobs = @('docs/**')
    [IO.File]::WriteAllText("$proj/lk.smoke.json", ($lkCfg | ConvertTo-Json -Depth 10), $utf8)
    Expect 1 'link_check FAIL: skipGlobs skips docs/ only' @('gates/link_check.ps1', '-Config', 'lk.smoke.json')
    Names 'link_check (skipGlobs)' "'../../notes/Z.md' - no such shard"
    if ($script:lastOut -like '*docs/*') { Write-Output 'FAIL  link_check: checked a link under linkCheck.skipGlobs'; $script:fails++ }
    Remove-Item -Recurse -Force "$proj/spec/lk", "$proj/lk.smoke.json"
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
    # structure_check (#13): an HTML shard - <h2> section headings, <pre class="mermaid"> opening on the
    # tag line and closing on the last member's line, entities decoded (&lt;&lt;entity&gt;&gt; is a
    # stereotype, not a member). Line numbers stay those of the file.
    $scCfg = Get-Content $cfg -Raw | ConvertFrom-Json
    $scCfg.structureGlobs = @('spec/**/*.structure.body.html')
    [IO.File]::WriteAllText("$proj/sc.smoke.json", ($scCfg | ConvertTo-Json -Depth 10), $utf8)
    $htmlShard = "$proj/spec/working/DEMO-3.structure.body.html"
    $htmlText = "<h2 id=`"added`">Added</h2>`n<figure class=`"diagram`"><pre class=`"mermaid`">classDiagram`n  class Wallet {`n    &lt;&lt;entity&gt;&gt;`n    +int Balance`n    +Deposit(int amount) bool</pre></figure>`n<h2>Removed</h2>`n<pre class=`"mermaid`">`nclassDiagram`n  class LegacyPurse {`n    +Empty()`n  }`n</pre>`n"
    [IO.File]::WriteAllText($htmlShard, $htmlText, $utf8)
    Expect 0 'structure_check -Plan PASS: HTML <pre> diagram' @('gates/structure_check.ps1', '-Plan', '-Config', 'sc.smoke.json')
    Names 'structure_check (html plan)' '1 structure shard(s) at member level (0 warning(s))'
    Expect 0 'structure_check trace PASS: HTML <pre> diagram' @('gates/structure_check.ps1', '-Config', 'sc.smoke.json')
    [IO.File]::WriteAllText($htmlShard, $htmlText.Replace('+Deposit(int amount) bool<', '+Withdraw(int amount) bool<'), $utf8)
    Expect 1 'structure_check FAIL: HTML planned member missing, on its own line' @('gates/structure_check.ps1', '-Config', 'sc.smoke.json')
    Names 'structure_check (html missing)' 'DEMO-3.structure.body.html:6: Wallet.Withdraw'
    [IO.File]::WriteAllText("$proj/src/legacy.cs", "public class LegacyPurse { }`n", $utf8)
    Expect 1 'structure_check FAIL: HTML removed class still present' @('gates/structure_check.ps1', '-Config', 'sc.smoke.json')
    Names 'structure_check (html removed)' 'removed class LegacyPurse'
    Remove-Item "$proj/src/legacy.cs", $htmlShard, "$proj/sc.smoke.json"

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

    # token_ledger (#11): a | in a cell is written as \| and never splits the row - a grep alternation, a
    # literal \| and a pin note with | all verify current; a pre-1.16.1 row with a raw | in range still reads.
    $lp = 'spec/working/pipes.ledger.md'
    Expect 0 'token_ledger add grep with | (alternation)' @('gates/token_ledger.ps1', 'add', '-Plan', $lp, '-Kind', 'grep', '-By', 'P', '-For', 'S1', '-Path', 'spec/demo.body.md', '-Range', "'DEMO|smoke' +-1", '-Config', $cfg)
    Expect 0 'token_ledger add grep with literal \|' @('gates/token_ledger.ps1', 'add', '-Plan', $lp, '-Kind', 'grep', '-By', 'P', '-For', 'S1', '-Path', 'spec/demo.body.md', '-Range', "'a\|b' +-1", '-Config', $cfg)
    Expect 0 'token_ledger add pin with | in note' @('gates/token_ledger.ps1', 'add', '-Plan', $lp, '-Kind', 'pin', '-By', 'P', '-For', 'S1', '-Path', 'spec/demo.body.md', '-Note', 'f(x: string | null): int', '-Config', $cfg)
    $h = (git hash-object spec/demo.body.md).Substring(0, 7)
    [IO.File]::AppendAllText("$proj/$lp", "| grep | P | S2 | any | spec/demo.body.md | 'x|y' +-1 | $h | 1 | 1 | legacy |`n", $utf8)
    Expect 0 'token_ledger verify PASS with | in cells' @('gates/token_ledger.ps1', 'verify', '-Plan', $lp, '-Config', $cfg)
    Names 'token_ledger (pipes)' '4 ledger row(s) current'
    Expect 0 'token_ledger report with | in cells' @('gates/token_ledger.ps1', 'report', '-Plan', $lp, '-Config', $cfg)
    Remove-Item "$proj/$lp"

    # fold_check (#10): a clause is its definition span. A pin at the end of a multi-line HTML clause
    # covers an edit to its first line; a clause-id cited in prose is not a clause; an unchanged clause
    # needs no pin; a Mode B backlog resolves a unit by a heading inside a file, or backlogRoot names
    # one file. Fixture commits are reset away afterwards.
    $fb = (git rev-parse HEAD)
    $fcObj = Get-Content $cfg -Raw | ConvertFrom-Json
    $fcObj.paths.spec = 'spec/**/*.body.html'
    $fcObj.unitIdRegex = '\bBL-\d+-\d+\b'
    $fcObj.foldCheck.backlogRoot = 'docs/backlog.md'
    [IO.File]::WriteAllText("$proj/fc.smoke.json", ($fcObj | ConvertTo-Json -Depth 10), $utf8)
    New-Item -ItemType Directory -Force "$proj/spec/fold", "$proj/docs" | Out-Null
    $fold = "$proj/spec/fold/a.body.html"
    [IO.File]::WriteAllText($fold, "<ul>`n<li id=`"DISC.3`"><strong>DISC.3</strong> - The system shall log a lock.</li>`n<li id=`"DISC.4`"><strong>DISC.4</strong> - Content of a locked thing is never sent,`n  not its page or record; see DISC.3 and EPI.3.`n  <em>(§DISC per BL-20261006-06, 2026-10-09)</em></li>`n</ul>`n", $utf8)
    [IO.File]::WriteAllText("$proj/docs/backlog.md", "# Backlog`n`n## BL-20261006-06 lock content`nbody`n", $utf8)
    git add -A ; git commit -q -m 'fold fixture'
    $fb2 = (git rev-parse HEAD)
    function Edit-Fold([string]$from, [string]$to) { [IO.File]::WriteAllText($fold, ([IO.File]::ReadAllText($fold)).Replace($from, $to), $utf8) }
    Edit-Fold 'is never sent,' 'is never sent to a browser,'
    git commit -q -am 'edit DISC.4 line 1'
    Expect 0 'fold_check PASS: pin at the end of a multi-line clause, single-file backlog' @('gates/fold_check.ps1', '-Config', 'fc.smoke.json', '-Base', $fb2)
    $fcObj.foldCheck.backlogRoot = 'docs'
    [IO.File]::WriteAllText("$proj/fc.smoke.json", ($fcObj | ConvertTo-Json -Depth 10), $utf8)
    Expect 0 'fold_check PASS: unit resolves by a heading under backlogRoot/' @('gates/fold_check.ps1', '-Config', 'fc.smoke.json', '-Base', $fb2)
    Edit-Fold 'log a lock' 'log every lock'
    git commit -q -am 'edit DISC.3'
    Expect 1 'fold_check FAIL: changed clause without a pin' @('gates/fold_check.ps1', '-Config', 'fc.smoke.json', '-Base', $fb2)
    Names 'fold_check (unpinned)' 'UNPINNED DISC.3'
    if ($script:lastOut -like '*EPI.3*' -or $script:lastOut -like '*DISC.4*') { Write-Output 'FAIL  fold_check: flagged a cross-reference or a pinned clause'; $script:fails++ }
    git reset -q --hard HEAD~1
    Edit-Fold 'BL-20261006-06' 'BL-20261006-99'
    git commit -q -am 'unknown unit'
    Expect 1 'fold_check FAIL: unit with no backlog entry says why' @('gates/fold_check.ps1', '-Config', 'fc.smoke.json', '-Base', $fb2)
    Names 'fold_check (unresolved)' 'UNRESOLVED-UNIT BL-20261006-99  (no heading or anchor naming it in docs/backlog.md)'
    git reset -q --hard $fb; Remove-Item -Force "$proj/fc.smoke.json" -ErrorAction SilentlyContinue

    # board_check (#12): the stage board and the Mode B backlog agree. Unset = not configured; a directory
    # backlog (shipped: line) and a single-file backlog (rows + closed file) each catch every drift kind.
    Expect 0 'board_check PASS: not configured' @('gates/board_check.ps1', '-Config', $cfg)
    Names 'board_check (off)' 'not configured'
    New-Item -ItemType Directory -Force "$proj/bk.smoke/items" | Out-Null
    [IO.File]::WriteAllText("$proj/bk.smoke/items/DEMO-1-a.md", "# DEMO-1 a`nbody`n", $utf8)
    [IO.File]::WriteAllText("$proj/bk.smoke/items/DEMO-2-b.md", "# DEMO-2 b`nshipped: abc1234 2026-10-01`n", $utf8)
    [IO.File]::WriteAllText("$proj/bk.smoke/items/DEMO-3-c.md", "# DEMO-3 c`n", $utf8)
    $bkb = "$proj/bk.smoke/board.json"
    [IO.File]::WriteAllText($bkb, "{`"teams`":[],`"items`":[`n{`"k`":`"DEMO-1`",`"stage`":`"5`"},`n{`"k`":`"DEMO-2`",`"stage`":`"done`"}`n]}`n", $utf8)
    $bkObj = Get-Content $cfg -Raw | ConvertFrom-Json
    $bkObj | Add-Member -Force -NotePropertyName board -NotePropertyValue ([pscustomobject]@{ file = 'bk.smoke/board.json'; store = [pscustomobject]@{ root = 'bk.smoke/items'; closed = $null } })
    [IO.File]::WriteAllText("$proj/bk.smoke/cfg.json", ($bkObj | ConvertTo-Json -Depth 10), $utf8)
    Expect 0 'board_check PASS: board agrees with a directory backlog' @('gates/board_check.ps1', '-Config', 'bk.smoke/cfg.json')
    [IO.File]::WriteAllText($bkb, "{`"teams`":[],`"items`":[`n{`"k`":`"DEMO-1`",`"stage`":`"done`"},`n{`"k`":`"DEMO-2`",`"stage`":`"6`"},`n{`"k`":`"DEMO-9`",`"stage`":`"0`"}`n]}`n", $utf8)
    Expect 1 'board_check FAIL: done-but-open, open-but-shipped, not in backlog' @('gates/board_check.ps1', '-Config', 'bk.smoke/cfg.json')
    Names 'board_check (drift 1)' 'DRIFT DEMO-1  board-done but the backlog item is still open'
    Names 'board_check (drift 2)' 'DRIFT DEMO-2  board-open but shipped in the backlog'
    Names 'board_check (drift 9)' 'DRIFT DEMO-9  on board but not in the backlog'
    [IO.File]::WriteAllText("$proj/bk.smoke/backlog.md", "# Backlog`n## Open`n- **[DEMO-1]** first`n  detail`n- **[DEMO-2]** second`n  shipped: abc 2026-10-01`n## DEMO-3 heading row`ntext`n", $utf8)
    [IO.File]::WriteAllText("$proj/bk.smoke/done.md", "- **[DEMO-4]** old`n", $utf8)
    [IO.File]::WriteAllText($bkb, "{`"teams`":[],`"items`":[`n{`"k`":`"DEMO-1`",`"stage`":`"7`"},`n{`"k`":`"DEMO-2`",`"stage`":`"done`"},`n{`"k`":`"DEMO-3`",`"stage`":`"3`"},`n{`"k`":`"DEMO-4`",`"stage`":`"done`"}`n]}`n", $utf8)
    $bkObj.board.store.root = 'bk.smoke/backlog.md'
    $bkObj.board.store.closed = 'bk.smoke/done.md'
    [IO.File]::WriteAllText("$proj/bk.smoke/cfg.json", ($bkObj | ConvertTo-Json -Depth 10), $utf8)
    Expect 0 'board_check PASS: board agrees with a single-file backlog' @('gates/board_check.ps1', '-Config', 'bk.smoke/cfg.json')
    Expect 1 'board_check -Ship FAIL: shipped item still open' @('gates/board_check.ps1', '-Config', 'bk.smoke/cfg.json', '-Ship', 'DEMO-1')
    Names 'board_check (ship)' 'DRIFT DEMO-1  shipped item not done on the board (stage 7)'
    Expect 0 'board_check -Ship PASS: done and closed' @('gates/board_check.ps1', '-Config', 'bk.smoke/cfg.json', '-Ship', 'DEMO-4')
    Remove-Item -Recurse -Force "$proj/bk.smoke"

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

    # --- the review gates (v1.18): retire_check, findings_check, red_check, affected_tests. Each runs in a
    # scratch repo that carries a copy of the gates (a gate roots itself at the git top-level of its own dir).
    function New-Rt([string]$name) {
        $script:rt = Join-Path $work $name
        if (Test-Path $script:rt) { Remove-Item -Recurse -Force $script:rt }
        New-Item -ItemType Directory -Force "$($script:rt)/src", "$($script:rt)/spec", "$($script:rt)/tests", "$($script:rt)/docs/archive" | Out-Null
        Copy-Item -Recurse "$proj/gates" "$($script:rt)/gates"
        Remove-Item -Force "$($script:rt)/gates/.frozen" -ErrorAction SilentlyContinue
        git -C $script:rt init -q -b main . ; git -C $script:rt config user.email ci@guide-sdd ; git -C $script:rt config user.name ci
    }
    function W([string]$rel, [string]$text) { [IO.File]::WriteAllText("$($script:rt)/$rel", $text, $utf8) }
    function RtCfg([scriptblock]$f) {
        $o = Get-Content "$($script:rt)/rt.base.json" -Raw | ConvertFrom-Json
        if ($f) { & $f $o }
        [IO.File]::WriteAllText("$($script:rt)/rt.json", ($o | ConvertTo-Json -Depth 10), $utf8)
    }
    function InRt([scriptblock]$b) { Push-Location $script:rt; try { & $b } finally { Pop-Location } }
    function Not-Names([string]$label, [string]$needle) { if ($script:lastOut -like "*$needle*") { Write-Output "FAIL  ${label}: output names $needle"; $script:fails++ } }

    # retire_check (#18)
    New-Rt 'rt1'
    W 'src/WriterIntake.cs' "class WriterIntake { void submit_old() {} void KeepMe() {} }`n"
    W 'spec/s.md' "The WriterIntake calls submit_old.`n[REMOVED 2026-01-01 - submit_old retired]`n"
    W 'tests/DoorTests.cs' "// test submit_old`n"
    W 'docs/d.md' "see submit_old and KeepMe`n"
    W 'docs/archive/a.md' "submit_old`n"
    W 'rt.base.json' '{"baseRef":"main","paths":{"spec":"spec/**/*.md","code":"src/**"},"testGlobs":["tests/**"],"retireCheck":{"mode":"strict","extraGlobs":["docs/**"],"excludeGlobs":["docs/archive/**"]}}'
    git -C $rt add -A | Out-Null ; git -C $rt commit -q -m seed
    W 'src/WriterIntake.cs' "class WriterIntake { void submit_new() {} void KeepMe() {} }`n"
    RtCfg $null
    InRt {
        Expect 1 'retire_check FAIL: a name removed from the code survives in spec, tests and docs' @('gates/retire_check.ps1', '-Config', 'rt.json')
        Names 'retire_check (spec)' 'spec/s.md:1: submit_old'
        Names 'retire_check (test)' 'tests/DoorTests.cs:1: submit_old'
        Names 'retire_check (extraGlobs)' 'docs/d.md:1: submit_old'
        Not-Names 'retire_check (archive)' 'docs/archive'
        Not-Names 'retire_check (tombstone)' 'spec/s.md:2'
        Not-Names 'retire_check (live)' 'KeepMe'
    }
    RtCfg { param($o) $o.retireCheck.mode = 'warn' }
    InRt {
        Expect 0 'retire_check warn mode: hits print, exit 0' @('gates/retire_check.ps1', '-Config', 'rt.json')
        Names 'retire_check (warn)' 'WARN retire_check: 3 reference(s)'
    }
    W 'gates/.retired' "# declared`nKeepMe -> KeepNew`n"
    RtCfg $null
    InRt {
        Expect 1 'retire_check FAIL: a declared name, with its replacement' @('gates/retire_check.ps1', '-Config', 'rt.json')
        Names 'retire_check (declared)' 'docs/d.md:1: KeepMe -> KeepNew'
    }
    Remove-Item -Force "$rt/gates/.retired"
    RtCfg { param($o) $o.retireCheck | Add-Member -NotePropertyName allow -NotePropertyValue @('submit_old') }
    InRt { Expect 0 'retire_check PASS: an allowed name' @('gates/retire_check.ps1', '-Config', 'rt.json') }
    foreach ($f in 'spec/s.md', 'tests/DoorTests.cs', 'docs/d.md') { W $f ((Get-Content "$rt/$f" -Raw) -replace 'submit_old', 'submit_new') }
    RtCfg $null
    InRt {
        Expect 0 'retire_check PASS: the references are renamed' @('gates/retire_check.ps1', '-Config', 'rt.json')
        Names 'retire_check (clean)' 'no retired name survives'
    }
    RtCfg { param($o) $o.PSObject.Properties.Remove('retireCheck') }
    InRt {
        Expect 0 'retire_check PASS: not configured' @('gates/retire_check.ps1', '-Config', 'rt.json')
        Names 'retire_check (unset)' 'not configured'
    }

    RtCfg { param($o) $o.baseRef = 'no-such-ref'; $o.retireCheck.mode = 'warn' }
    InRt {
        Expect 0 'retire_check warn mode: an unresolvable base is skipped' @('gates/retire_check.ps1', '-Config', 'rt.json')
        Names 'retire_check (no base)' 'PASS retire_check: no base resolvable - skipped'
    }
    RtCfg { param($o) $o.baseRef = 'no-such-ref' }
    InRt {
        Expect 1 'retire_check strict mode: an unresolvable base is exit 2' @('gates/retire_check.ps1', '-Config', 'rt.json')
        Rc2 'retire_check (strict, no base)'
    }

    # findings_check (#21)
    RtCfg $null
    W 'u.findings.md' "# unit findings`nprose is ignored`nF1 [LOW] a.cs:3 stale name | fixed abc1234`nF2 [HIGH] b.cs:9 a | b claim | defer out of range: tracked in X-9`n"
    InRt {
        Expect 0 'findings_check PASS: fixed <sha> and defer <evidence>' @('gates/findings_check.ps1', '-Config', 'rt.json')
        Names 'findings_check (pass)' '2 finding(s) in 1 file(s)'
    }
    [IO.File]::AppendAllText("$rt/u.findings.md", "F3 [LOW] c.cs:1 nit | accepted`nF4 [MED] d.cs:2 no disposition at all`nF5 [LOW] e.cs:3 bad sha | fixed xyz`nF6 [LOW] f.cs:4 no evidence | defer `nF7 [BLOCKER] g.cs:5 bad severity | fixed abc1234`n", $utf8)
    InRt {
        Expect 1 'findings_check FAIL: accepted, none, a bad sha, empty evidence, a bad severity' @('gates/findings_check.ps1', '-Config', 'rt.json')
        foreach ($n in 'F3', 'F4', 'F5', 'F6', 'F7') { Names "findings_check ($n)" "$n " }
        Names 'findings_check (accepted)' "disposition 'accepted'"
        Not-Names 'findings_check (F1)' 'F1 '
        Not-Names 'findings_check (F2)' 'F2 '
    }
    Remove-Item -Force "$rt/u.findings.md"
    InRt { Expect 0 'findings_check PASS: no findings files' @('gates/findings_check.ps1', '-Config', 'rt.json') }

    # red_check (#19) and affected_tests (#20): a unit branch with QA's tests frozen, then the Engineer's change
    New-Rt 'rt2'
    W 'src/Writer.cs' "class Writer {}`n"
    W 'tests/DoorTests.cs' "uses Writer`n"
    W 'tests/Unrelated.cs' "nothing`n"
    W 'rt.base.json' '{"baseRef":"main","paths":{"code":"src/**"},"testGlobs":["tests/**"]}'
    git -C $rt add -A | Out-Null ; git -C $rt commit -q -m seed ; git -C $rt checkout -q -b unit
    W 'tests/NewTests.cs' "qa test`n"
    git -C $rt add -A | Out-Null ; git -C $rt commit -q -m qa
    $frozen = (git -C $rt rev-parse HEAD).Trim()
    RtCfg { param($o) $o | Add-Member -NotePropertyName redCheck -NotePropertyValue ([pscustomobject]@{ cmd = 'echo Failed  Alpha&& echo Passed  Beta_pin&& echo Passed  Gamma && echo {tests}'; passRegex = '^Passed +([A-Za-z_]+)' }) }
    InRt {
        Expect 1 'red_check FAIL: a test passes before any implementation' @('gates/red_check.ps1', '-Base', $frozen, '-Config', 'rt.json')
        Names 'red_check (Gamma)' '  Gamma'
        Names 'red_check (Beta)' '  Beta_pin'
    }
    RtCfg { param($o) $o | Add-Member -NotePropertyName redCheck -NotePropertyValue ([pscustomobject]@{ cmd = 'echo Failed  Alpha&& echo Passed  Beta_pin&& echo Passed  Gamma && echo {tests}'; passRegex = '^Passed +([A-Za-z_]+)'; allowGreen = @('Beta_*', 'Gamma') }) }
    InRt { Expect 0 'red_check PASS: the green tests are allowGreen entries (glob or exact)' @('gates/red_check.ps1', '-Base', $frozen, '-Config', 'rt.json') }
    RtCfg { param($o) $o | Add-Member -NotePropertyName redCheck -NotePropertyValue ([pscustomobject]@{ cmd = 'echo Passed {tests}'; passRegex = '^Passed +(.*)$'; joiner = '+' }) }
    InRt {
        Expect 1 'red_check: {tests} is the stems of the added test files' @('gates/red_check.ps1', '-Base', $frozen, '-Config', 'rt.json')
        Names 'red_check ({tests})' '  NewTests'
        Not-Names 'red_check (untouched)' 'DoorTests'
    }
    RtCfg { param($o) $o | Add-Member -NotePropertyName redCheck -NotePropertyValue ([pscustomobject]@{ cmd = 'echo Passed Beta'; passRegex = '^Passed +([A-Za-z_]+)' }) }
    InRt {
        Expect 1 'red_check: a cmd without {tests} is a config error' @('gates/red_check.ps1', '-Base', $frozen, '-Config', 'rt.json')
        Rc2 'red_check (no {tests})'
    }
    RtCfg $null
    InRt {
        Expect 0 'red_check PASS: not configured' @('gates/red_check.ps1', '-Base', $frozen, '-Config', 'rt.json')
        Names 'red_check (unset)' 'not configured'
    }

    W 'src/Writer.cs' "class Writer { int x; }`n"
    RtCfg { param($o) $o | Add-Member -NotePropertyName redCheck -NotePropertyValue ([pscustomobject]@{ cmd = 'echo Passed {tests}'; passRegex = '^Passed +(.*)$' }) }
    InRt {
        Expect 1 'red_check refuses a tree with paths.code changes' @('gates/red_check.ps1', '-Base', $frozen, '-Config', 'rt.json')
        Rc2 'red_check (dirty code)'
    }

    RtCfg { param($o) $o | Add-Member -NotePropertyName affectedTests -NotePropertyValue ([pscustomobject]@{ cmd = 'echo ran {tests}'; joiner = '+'; extraStems = @('Extra') }) }
    W 'tests/ExtraTests.cs' "Extra here`n"
    InRt {
        Expect 0 'affected_tests --list: changed tests plus whole-word key hits' @('gates/affected_tests.ps1', '-List', '-Base', $frozen, '-Config', 'rt.json')
        Names 'affected_tests (key)' 'key: Writer'
        Names 'affected_tests (extra key)' 'key: Extra'
        Names 'affected_tests (hit)' 'test: tests/DoorTests.cs'
        Names 'affected_tests (hit extra)' 'test: tests/ExtraTests.cs'
        Names 'affected_tests (changed)' 'test: tests/NewTests.cs'
        Not-Names 'affected_tests (unrelated)' 'Unrelated'
        Expect 0 'affected_tests PASS: runs cmd with {tests} and passes its exit code' @('gates/affected_tests.ps1', '-Base', $frozen, '-Config', 'rt.json')
        Names 'affected_tests (run)' 'ran DoorTests+ExtraTests+NewTests'
    }
    RtCfg { param($o) $o | Add-Member -NotePropertyName affectedTests -NotePropertyValue ([pscustomobject]@{ cmd = 'echo ran {tests}&& exit 3'; joiner = '+' }) }
    InRt {
        Expect 1 'affected_tests FAIL: the cmd exits non-zero' @('gates/affected_tests.ps1', '-Base', $frozen, '-Config', 'rt.json')
        Names 'affected_tests (fail)' 'exited 3'
    }
    RtCfg $null
    InRt {
        Expect 0 'affected_tests PASS: not configured' @('gates/affected_tests.ps1', '-Base', $frozen, '-Config', 'rt.json')
        Names 'affected_tests (unset)' 'not configured'
    }
    Set-Location $proj

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
