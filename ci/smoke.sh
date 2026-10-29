#!/usr/bin/env sh
# GUIDE SDD — CI smoke test. Reproduces project-config/INIT.md §6 on a throwaway copy of the spine:
# seed one anchored clause + one tagged test, run the generic gates (expect PASS), then the NEGATIVE
# controls — an unfollowed clause (coverage FAIL), every test_edit_ban bypass the v1.12 hardening
# closed (uncommitted edit, untracked test, rename-out, gate-config tamper, moving base), the v1.13
# structure_check controls (planned member missing, removed class present, memberless diagram, diagram
# edited after freeze) and token_ledger (qa row into code refused, stale row, | in a cell) — then freeze and run the
# whole bank (expect clean).
#
# Usage:  sh ci/smoke.sh [--compare]
#   --compare   also run each gate's .ps1 twin via pwsh and require the same exit code; report
#               output differences (CR-stripped) as WARN lines.
# Needs: git, jq (sh gates); pwsh for --compare. Exit 0 = all expectations met.
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"
COMPARE=0; [ "${1:-}" = "--compare" ] && COMPARE=1
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PROJ="$WORK/proj"; mkdir -p "$PROJ"
# INIT §6 runs from the spine directory, so the throwaway project IS a copy of the spine.
(cd "$REPO" && tar --exclude=.git --exclude=ci --exclude=dist --exclude=.github/workflows -cf - .) | (cd "$PROJ" && tar -xf -)
cd "$PROJ"
git init -q -b main . && git config user.email ci@guide-sdd && git config user.name ci
# INIT §5: the suite and static-check commands are mandatory (unset is exit 2, never a silent skip).
jq '.suiteCmd = "exit 0" | .checkCmd = "exit 0"' gates/gates.config.template.json > gates/gates.config.json
mkdir -p spec tests
printf '## DEMO.1 smoke {#DEMO.1}\nWhen init runs, the system shall pass the smoke test.\n' > spec/demo.body.md
printf '// @clause:DEMO.1\nok();\n' > tests/demo.smoke.test
git add -A >/dev/null && git commit -q -m seed

fails=0
# expect <0|1> <label> <cmd...>   (0 = expect PASS/exit 0, 1 = expect FAIL/non-zero)
expect() {
  want=$1; label=$2; shift 2
  set +e; out=$("$@" 2>&1); rc=$?; set -e
  bad=0
  if [ "$want" = 0 ]; then [ "$rc" -eq 0 ] || bad=1; else [ "$rc" -ne 0 ] || bad=1; fi
  if [ "$bad" = 1 ]; then
    echo "FAIL  $label (rc=$rc)"; printf '%s\n' "$out" | sed 's/^/      /'; fails=$((fails+1))
  else
    echo "ok    $label"
  fi
  LAST_OUT=$out; LAST_RC=$rc
}
# names <label> <needle> — the last output must mention <needle>
names() { case "$LAST_OUT" in *"$2"*) ;; *) echo "FAIL  $1: output does not name $2"; printf '%s\n' "$LAST_OUT" | sed 's/^/      /'; fails=$((fails+1));; esac; }
# twin <label> <sh-out> <sh-rc> <ps1 args...> — run the .ps1 twin, compare rc (+ output as WARN)
twin() {
  [ "$COMPARE" = 1 ] || return 0
  label=$1; shout=$2; shrc=$3; shift 3
  set +e; pout=$(pwsh -NoProfile -File "$@" 2>&1); prc=$?; set -e
  pout=$(printf '%s' "$pout" | tr -d '\r')
  if [ "$prc" -ne "$shrc" ]; then
    echo "FAIL  $label: ps1 rc=$prc vs sh rc=$shrc"; printf '%s\n' "$pout" | sed 's/^/      /'; fails=$((fails+1))
  elif [ "$pout" != "$shout" ]; then
    echo "WARN  $label: ps1 output differs from sh"
    printf '%s\n' "$shout" > "$WORK/a"; printf '%s\n' "$pout" > "$WORK/b"; diff "$WORK/a" "$WORK/b" | sed 's/^/      /' || true
  else
    echo "ok    $label (ps1 twin identical)"
  fi
}

CFG=gates/gates.config.json
expect 0 "coverage_check PASS"  sh gates/coverage_check.sh --config $CFG
twin "coverage_check" "$LAST_OUT" "$LAST_RC" gates/coverage_check.ps1 -Config $CFG
expect 0 "link_check PASS"      sh gates/link_check.sh --config $CFG
twin "link_check" "$LAST_OUT" "$LAST_RC" gates/link_check.ps1 -Config $CFG
# link_check (#14): a link to a repo file that is not a shard fails, unless linkCheck.skipGlobs names
# it (resolved against the linking shard's directory; a leading / is the project root).
mkdir -p spec/lk
printf '# Links\nSee [r](../../docs/research/X.md#s), [y](/docs/Y.md) and [z](../../notes/Z.md).\n' > spec/lk/links.body.md
expect 1 "link_check FAIL: link to a non-shard file" sh gates/link_check.sh --config $CFG
names "link_check (non-shard)" "'../../docs/research/X.md#s' - no such shard"
twin "link_check (non-shard)" "$LAST_OUT" "$LAST_RC" gates/link_check.ps1 -Config $CFG
jq '.linkCheck.skipGlobs = ["docs/**"]' $CFG > lk.smoke.json
expect 1 "link_check FAIL: skipGlobs skips docs/ only" sh gates/link_check.sh --config lk.smoke.json
names "link_check (skipGlobs)" "'../../notes/Z.md' - no such shard"
case "$LAST_OUT" in *docs/*) echo "FAIL  link_check: checked a link under linkCheck.skipGlobs"; fails=$((fails+1));; esac
twin "link_check (skipGlobs)" "$LAST_OUT" "$LAST_RC" gates/link_check.ps1 -Config lk.smoke.json
rm -rf spec/lk lk.smoke.json
expect 0 "prose_check PASS"     sh gates/prose_check.sh --config $CFG --all
twin "prose_check" "$LAST_OUT" "$LAST_RC" gates/prose_check.ps1 -Config $CFG -All
expect 0 "test_edit_ban PASS (HEAD, warns moving ref)" sh gates/test_edit_ban.sh HEAD $CFG
names "test_edit_ban" "moving ref"
twin "test_edit_ban" "$LAST_OUT" "$LAST_RC" gates/test_edit_ban.ps1 HEAD $CFG

# Negative control: an unfollowed clause must FAIL coverage, naming it.
printf '\n## DEMO.2 unfollowed {#DEMO.2}\nThe system shall have no test, on purpose.\n' >> spec/demo.body.md
expect 1 "coverage_check FAIL on DEMO.2" sh gates/coverage_check.sh --config $CFG
names "coverage_check" "DEMO.2"
twin "coverage_check (negative)" "$LAST_OUT" "$LAST_RC" gates/coverage_check.ps1 -Config $CFG
git checkout -q -- spec
expect 0 "coverage_check PASS after revert" sh gates/coverage_check.sh --config $CFG

# --plan: the default plan glob follows paths.spec (issue #6: HTML shards), and paths.plan overrides it.
printf '@clause:DEMO.1 - scenario: smoke passes\n' > spec/demo.plan.body.md
expect 0 "coverage_check --plan PASS (md plan)" sh gates/coverage_check.sh --plan --config $CFG
twin "coverage_check (plan)" "$LAST_OUT" "$LAST_RC" gates/coverage_check.ps1 -Plan -Config $CFG
mkdir -p spec/html
printf '<h2 id="DEMO.1">DEMO.1 smoke</h2><p>When init runs, the system shall pass.</p>\n' > spec/html/a.body.html
printf '<p>@clause:DEMO.1 - scenario: smoke passes</p>\n' > spec/html/a.plan.body.html
jq '.paths.spec = "spec/**/*.body.html"' $CFG > "$WORK/cfg" && cp "$WORK/cfg" $CFG
expect 0 "coverage_check --plan PASS (html plan, glob derived from paths.spec)" sh gates/coverage_check.sh --plan --config $CFG
twin "coverage_check (html plan)" "$LAST_OUT" "$LAST_RC" gates/coverage_check.ps1 -Plan -Config $CFG
jq '.paths.plan = "spec/**/*nomatch*.body.html"' $CFG > "$WORK/cfg" && cp "$WORK/cfg" $CFG
expect 1 "coverage_check --plan FAIL (paths.plan overrides the derived glob)" sh gates/coverage_check.sh --plan --config $CFG
names "coverage_check (paths.plan)" "DEMO.1"
twin "coverage_check (paths.plan)" "$LAST_OUT" "$LAST_RC" gates/coverage_check.ps1 -Plan -Config $CFG
rm -rf spec/html spec/demo.plan.body.md
git checkout -q -- gates

# Negative control: a tag in a notes file under tests/ is not coverage; a skipped test is warned.
printf '@clause:DEMO.9\n' > tests/NOTES.md
expect 0 "coverage_check ignores tags in tests/NOTES.md" sh gates/coverage_check.sh --config $CFG
twin "coverage_check (md excluded)" "$LAST_OUT" "$LAST_RC" gates/coverage_check.ps1 -Config $CFG
rm tests/NOTES.md
printf '// @clause:DEMO.1\nit.skip("x");\n' > tests/demo.smoke.test
expect 0 "coverage_check warns on skip marker" sh gates/coverage_check.sh --config $CFG
names "coverage_check" "skip/only marker"
twin "coverage_check (skip warn)" "$LAST_OUT" "$LAST_RC" gates/coverage_check.ps1 -Config $CFG
git checkout -q -- tests

# Negative controls: every test_edit_ban bypass closed in v1.12 must FAIL, naming the path.
BASE=$(git rev-parse HEAD)
printf 'edited\n' >> tests/demo.smoke.test
expect 1 "test_edit_ban FAIL: uncommitted test edit" sh gates/test_edit_ban.sh $BASE $CFG
names "test_edit_ban (uncommitted)" "tests/demo.smoke.test"
twin "test_edit_ban (uncommitted)" "$LAST_OUT" "$LAST_RC" gates/test_edit_ban.ps1 $BASE $CFG
git checkout -q -- tests
printf 'new\n' > tests/new.test
expect 1 "test_edit_ban FAIL: untracked new test" sh gates/test_edit_ban.sh $BASE $CFG
names "test_edit_ban (untracked)" "tests/new.test"
twin "test_edit_ban (untracked)" "$LAST_OUT" "$LAST_RC" gates/test_edit_ban.ps1 $BASE $CFG
rm tests/new.test
git mv tests/demo.smoke.test demo.moved.test
expect 1 "test_edit_ban FAIL: test renamed out of tests/" sh gates/test_edit_ban.sh $BASE $CFG
names "test_edit_ban (rename-out)" "tests/demo.smoke.test"
twin "test_edit_ban (rename-out)" "$LAST_OUT" "$LAST_RC" gates/test_edit_ban.ps1 $BASE $CFG
git mv demo.moved.test tests/demo.smoke.test
jq '.testGlobs = ["nomatch/**"]' $CFG > "$WORK/cfg" && cp "$WORK/cfg" $CFG
printf 'edited\n' >> tests/demo.smoke.test
expect 1 "test_edit_ban FAIL: gate config tampered" sh gates/test_edit_ban.sh $BASE $CFG
names "test_edit_ban (tamper)" "gate config/scripts modified"
twin "test_edit_ban (tamper)" "$LAST_OUT" "$LAST_RC" gates/test_edit_ban.ps1 $BASE $CFG
git checkout -q -- gates tests
git commit -q --allow-empty -m "engineer work"
expect 1 "test_edit_ban FAIL: base not an ancestor" sh gates/test_edit_ban.sh "$BASE~1" $CFG 2>/dev/null || true
[ "$LAST_RC" = 2 ] || { echo "FAIL  base-not-ancestor should exit 2 (rc=$LAST_RC)"; fails=$((fails+1)); }

# structure_check: the PM-approved member-level diagram. Shape (--plan), forward trace, and the
# negative controls: a planned member missing from the code, a removed class still present, a
# memberless diagram. Shard + impl are committed BEFORE the freeze so the frozen half can pass below.
mkdir -p spec/working src
printf '<!-- DEMO-1 structure (delta) -->\n## Added\n```mermaid\nclassDiagram\n  class Wallet {\n    +int Balance\n    +Deposit(int amount) bool\n  }\n```\n## Removed\n```mermaid\nclassDiagram\n  class LegacyPurse {\n    +Empty()\n  }\n```\n' > spec/working/DEMO-1.structure.body.md
printf 'public class Wallet {\n  public int Balance; public bool Deposit(int amount) { return true; }\n}\n' > src/wallet.cs
git add -A >/dev/null && git commit -q -m "chore(DEMO-1): structure shard + impl"
expect 0 "structure_check --plan PASS" sh gates/structure_check.sh --plan --config $CFG
twin "structure_check (plan)" "$LAST_OUT" "$LAST_RC" gates/structure_check.ps1 -Plan -Config $CFG
expect 0 "structure_check trace PASS" sh gates/structure_check.sh --config $CFG
twin "structure_check (trace)" "$LAST_OUT" "$LAST_RC" gates/structure_check.ps1 -Config $CFG
sed -i 's/+Deposit(int amount) bool/&\n    +Withdraw(int amount) bool/' spec/working/DEMO-1.structure.body.md
expect 1 "structure_check FAIL: planned member missing from code" sh gates/structure_check.sh --config $CFG
names "structure_check (missing member)" "Wallet.Withdraw"
twin "structure_check (missing member)" "$LAST_OUT" "$LAST_RC" gates/structure_check.ps1 -Config $CFG
git checkout -q -- spec
printf 'public class LegacyPurse { }\n' > src/legacy.cs
expect 1 "structure_check FAIL: removed class still present" sh gates/structure_check.sh --config $CFG
names "structure_check (removed class)" "LegacyPurse"
twin "structure_check (removed class)" "$LAST_OUT" "$LAST_RC" gates/structure_check.ps1 -Config $CFG
rm src/legacy.cs
printf '## Added\n```mermaid\nclassDiagram\n  class Outline\n```\n' > spec/working/DEMO-2.structure.body.md
expect 1 "structure_check --plan FAIL: memberless diagram" sh gates/structure_check.sh --plan --config $CFG
names "structure_check (outline)" "DEMO-2.structure.body.md"
twin "structure_check (outline)" "$LAST_OUT" "$LAST_RC" gates/structure_check.ps1 -Plan -Config $CFG
rm spec/working/DEMO-2.structure.body.md
# structure_check (#13): an HTML shard - <h2> section headings, <pre class="mermaid"> opening on the
# tag line and closing on the last member's line, entities decoded (&lt;&lt;entity&gt;&gt; is a
# stereotype, not a member). Line numbers stay those of the file.
jq '.structureGlobs = ["spec/**/*.structure.body.html"]' $CFG > sc.smoke.json
printf '<h2 id="added">Added</h2>\n<figure class="diagram"><pre class="mermaid">classDiagram\n  class Wallet {\n    &lt;&lt;entity&gt;&gt;\n    +int Balance\n    +Deposit(int amount) bool</pre></figure>\n<h2>Removed</h2>\n<pre class="mermaid">\nclassDiagram\n  class LegacyPurse {\n    +Empty()\n  }\n</pre>\n' > spec/working/DEMO-3.structure.body.html
expect 0 "structure_check --plan PASS: HTML <pre> diagram" sh gates/structure_check.sh --plan --config sc.smoke.json
names "structure_check (html plan)" "1 structure shard(s) at member level (0 warning(s))"
twin "structure_check (html plan)" "$LAST_OUT" "$LAST_RC" gates/structure_check.ps1 -Plan -Config sc.smoke.json
expect 0 "structure_check trace PASS: HTML <pre> diagram" sh gates/structure_check.sh --config sc.smoke.json
twin "structure_check (html trace)" "$LAST_OUT" "$LAST_RC" gates/structure_check.ps1 -Config sc.smoke.json
sed -i 's/+Deposit(int amount) bool</+Withdraw(int amount) bool</' spec/working/DEMO-3.structure.body.html
expect 1 "structure_check FAIL: HTML planned member missing, on its own line" sh gates/structure_check.sh --config sc.smoke.json
names "structure_check (html missing)" "DEMO-3.structure.body.html:6: Wallet.Withdraw"
twin "structure_check (html missing)" "$LAST_OUT" "$LAST_RC" gates/structure_check.ps1 -Config sc.smoke.json
printf 'public class LegacyPurse { }\n' > src/legacy.cs
expect 1 "structure_check FAIL: HTML removed class still present" sh gates/structure_check.sh --config sc.smoke.json
names "structure_check (html removed)" "removed class LegacyPurse"
twin "structure_check (html removed)" "$LAST_OUT" "$LAST_RC" gates/structure_check.ps1 -Config sc.smoke.json
rm -f src/legacy.cs spec/working/DEMO-3.structure.body.html sc.smoke.json

# token_ledger: the Stage-4b read ledger - add rows, report the tokens: lines, refuse a QA row into
# the implementation, and (negative control) flag a stale row once its file changes.
BP=spec/working/DEMO-1.buildplan.md
printf '# DEMO-1 build plan\n' > $BP
expect 0 "token_ledger add read (P)" sh gates/token_ledger.sh add --plan $BP --kind read --by P --path src/wallet.cs --config $CFG
expect 0 "token_ledger add range (P->S2)" sh gates/token_ledger.sh add --plan $BP --kind range --by P --for S2 --aud eng --path src/wallet.cs --range 2-2 --note "members only" --config $CFG
expect 0 "token_ledger add skip (P->S2)" sh gates/token_ledger.sh add --plan $BP --kind skip --by P --for S2 --aud eng --path spec/demo.body.md --config $CFG
expect 0 "token_ledger add read (S2, ranged)" sh gates/token_ledger.sh add --plan $BP --kind read --by S2 --path src/wallet.cs --range 2-2 --config $CFG
expect 1 "token_ledger refuses a qa row into paths.code" sh gates/token_ledger.sh add --plan $BP --kind read --by S1 --aud qa --path src/wallet.cs --config $CFG
[ "$LAST_RC" = 2 ] || { echo "FAIL  qa row into code should exit 2 (rc=$LAST_RC)"; fails=$((fails+1)); }
expect 0 "token_ledger verify PASS" sh gates/token_ledger.sh verify --plan $BP --config $CFG
twin "token_ledger (verify)" "$LAST_OUT" "$LAST_RC" gates/token_ledger.ps1 verify -Plan $BP -Config $CFG
expect 0 "token_ledger report" sh gates/token_ledger.sh report --plan $BP --config $CFG
names "token_ledger (report)" "tokens: plan admitted"
names "token_ledger (report S2)" "tokens: S2 admitted"
twin "token_ledger (report)" "$LAST_OUT" "$LAST_RC" gates/token_ledger.ps1 report -Plan $BP -Config $CFG
git add -A >/dev/null && git commit -q -m "chore(DEMO-1): build plan"
printf '// touched\n' >> src/wallet.cs
expect 1 "token_ledger verify FAIL: stale row after file change" sh gates/token_ledger.sh verify --plan $BP --for S2 --config $CFG
names "token_ledger (stale)" "STALE"
twin "token_ledger (stale)" "$LAST_OUT" "$LAST_RC" gates/token_ledger.ps1 verify -Plan $BP -For S2 -Config $CFG
git checkout -q -- src

# token_ledger (#11): a | in a cell is written as \| and never splits the row - a grep alternation, a
# literal \| and a pin note with | all verify current; a pre-1.16.1 row with a raw | in range still reads.
LP=spec/working/pipes.ledger.md
expect 0 "token_ledger add grep with | (alternation)" sh gates/token_ledger.sh add --plan $LP --kind grep --by P --for S1 --path spec/demo.body.md --range "'DEMO|smoke' +-1" --config $CFG
twin "token_ledger (add grep |)" "$LAST_OUT" "$LAST_RC" gates/token_ledger.ps1 add -Plan spec/working/pipes.twin.md -Kind grep -By P -For S1 -Path spec/demo.body.md -Range "'DEMO|smoke' +-1" -Config $CFG
expect 0 "token_ledger add grep with literal \\|" sh gates/token_ledger.sh add --plan $LP --kind grep --by P --for S1 --path spec/demo.body.md --range "'a\\|b' +-1" --config $CFG
expect 0 "token_ledger add pin with | in note" sh gates/token_ledger.sh add --plan $LP --kind pin --by P --for S1 --path spec/demo.body.md --note "f(x: string | null): int" --config $CFG
printf '| grep | P | S2 | any | spec/demo.body.md | %s | %s | 1 | 1 | legacy |\n' "'x|y' +-1" "$(git hash-object spec/demo.body.md | cut -c1-7)" >> $LP
expect 0 "token_ledger verify PASS with | in cells" sh gates/token_ledger.sh verify --plan $LP --config $CFG
names "token_ledger (pipes)" "4 ledger row(s) current"
twin "token_ledger (verify pipes)" "$LAST_OUT" "$LAST_RC" gates/token_ledger.ps1 verify -Plan $LP -Config $CFG
expect 0 "token_ledger report with | in cells" sh gates/token_ledger.sh report --plan $LP --config $CFG
twin "token_ledger (report pipes)" "$LAST_OUT" "$LAST_RC" gates/token_ledger.ps1 report -Plan $LP -Config $CFG
rm -f $LP spec/working/pipes.twin.md

# fold_check (#10): a clause is its definition span. A pin at the end of a multi-line HTML clause
# covers an edit to its first line; a clause-id cited in prose is not a clause; an unchanged clause
# needs no pin; a Mode B backlog resolves a unit by a heading inside a file, or backlogRoot names
# one file. Fixture commits are reset away afterwards.
FB=$(git rev-parse HEAD)
jq '.paths.spec = "spec/**/*.body.html" | .unitIdRegex = "\\bBL-\\d+-\\d+\\b" | .foldCheck.backlogRoot = "docs/backlog.md"' $CFG > fc.smoke.json
mkdir -p spec/fold docs
printf '<ul>\n<li id="DISC.3"><strong>DISC.3</strong> - The system shall log a lock.</li>\n<li id="DISC.4"><strong>DISC.4</strong> - Content of a locked thing is never sent,\n  not its page or record; see DISC.3 and EPI.3.\n  <em>(§DISC per BL-20261006-06, 2026-10-09)</em></li>\n</ul>\n' > spec/fold/a.body.html
printf '# Backlog\n\n## BL-20261006-06 lock content\nbody\n' > docs/backlog.md
git add -A >/dev/null && git commit -q -m "fold fixture"
FB2=$(git rev-parse HEAD)
sed -i 's/is never sent,/is never sent to a browser,/' spec/fold/a.body.html && git commit -q -am "edit DISC.4 line 1"
expect 0 "fold_check PASS: pin at the end of a multi-line clause, single-file backlog" sh gates/fold_check.sh --config fc.smoke.json --base $FB2
twin "fold_check (multi-line)" "$LAST_OUT" "$LAST_RC" gates/fold_check.ps1 -Config fc.smoke.json -Base $FB2
jq '.foldCheck.backlogRoot = "docs"' fc.smoke.json > "$WORK/fc" && cp "$WORK/fc" fc.smoke.json
expect 0 "fold_check PASS: unit resolves by a heading under backlogRoot/" sh gates/fold_check.sh --config fc.smoke.json --base $FB2
twin "fold_check (heading in dir)" "$LAST_OUT" "$LAST_RC" gates/fold_check.ps1 -Config fc.smoke.json -Base $FB2
sed -i 's/log a lock/log every lock/' spec/fold/a.body.html && git commit -q -am "edit DISC.3"
expect 1 "fold_check FAIL: changed clause without a pin" sh gates/fold_check.sh --config fc.smoke.json --base $FB2
names "fold_check (unpinned)" "UNPINNED DISC.3"
case "$LAST_OUT" in *EPI.3*|*DISC.4*) echo "FAIL  fold_check: flagged a cross-reference or a pinned clause"; fails=$((fails+1));; esac
twin "fold_check (unpinned)" "$LAST_OUT" "$LAST_RC" gates/fold_check.ps1 -Config fc.smoke.json -Base $FB2
git reset -q --hard HEAD~1
sed -i 's/BL-20261006-06/BL-20261006-99/' spec/fold/a.body.html && git commit -q -am "unknown unit"
expect 1 "fold_check FAIL: unit with no backlog entry says why" sh gates/fold_check.sh --config fc.smoke.json --base $FB2
names "fold_check (unresolved)" "UNRESOLVED-UNIT BL-20261006-99  (no heading or anchor naming it in docs/backlog.md)"
twin "fold_check (unresolved)" "$LAST_OUT" "$LAST_RC" gates/fold_check.ps1 -Config fc.smoke.json -Base $FB2
git reset -q --hard "$FB"; rm -f fc.smoke.json

# board_check (#12): the stage board and the Mode B backlog agree. Unset = not configured; a directory
# backlog (shipped: line) and a single-file backlog (rows + closed file) each catch every drift kind.
expect 0 "board_check PASS: not configured" sh gates/board_check.sh --config $CFG
names "board_check (off)" "not configured"
twin "board_check (off)" "$LAST_OUT" "$LAST_RC" gates/board_check.ps1 -Config $CFG
mkdir -p bk.smoke/items
printf '# DEMO-1 a\nbody\n' > bk.smoke/items/DEMO-1-a.md
printf '# DEMO-2 b\nshipped: abc1234 2026-10-01\n' > bk.smoke/items/DEMO-2-b.md
printf '# DEMO-3 c\n' > bk.smoke/items/DEMO-3-c.md
printf '{"teams":[],"items":[\n{"k":"DEMO-1","stage":"5"},\n{"k":"DEMO-2","stage":"done"}\n]}\n' > bk.smoke/board.json
jq '.board.file = "bk.smoke/board.json" | .board.store.root = "bk.smoke/items"' $CFG > bk.smoke/cfg.json
expect 0 "board_check PASS: board agrees with a directory backlog" sh gates/board_check.sh --config bk.smoke/cfg.json
twin "board_check (dir)" "$LAST_OUT" "$LAST_RC" gates/board_check.ps1 -Config bk.smoke/cfg.json
printf '{"teams":[],"items":[\n{"k":"DEMO-1","stage":"done"},\n{"k":"DEMO-2","stage":"6"},\n{"k":"DEMO-9","stage":"0"}\n]}\n' > bk.smoke/board.json
expect 1 "board_check FAIL: done-but-open, open-but-shipped, not in backlog" sh gates/board_check.sh --config bk.smoke/cfg.json
names "board_check (drift 1)" "DRIFT DEMO-1  board-done but the backlog item is still open"
names "board_check (drift 2)" "DRIFT DEMO-2  board-open but shipped in the backlog"
names "board_check (drift 9)" "DRIFT DEMO-9  on board but not in the backlog"
twin "board_check (drift)" "$LAST_OUT" "$LAST_RC" gates/board_check.ps1 -Config bk.smoke/cfg.json
printf '# Backlog\n## Open\n- **[DEMO-1]** first\n  detail\n- **[DEMO-2]** second\n  shipped: abc 2026-10-01\n## DEMO-3 heading row\ntext\n' > bk.smoke/backlog.md
printf -- '- **[DEMO-4]** old\n' > bk.smoke/done.md
printf '{"teams":[],"items":[\n{"k":"DEMO-1","stage":"7"},\n{"k":"DEMO-2","stage":"done"},\n{"k":"DEMO-3","stage":"3"},\n{"k":"DEMO-4","stage":"done"}\n]}\n' > bk.smoke/board.json
jq '.board.file = "bk.smoke/board.json" | .board.store.root = "bk.smoke/backlog.md" | .board.store.closed = "bk.smoke/done.md"' $CFG > bk.smoke/cfg.json
expect 0 "board_check PASS: board agrees with a single-file backlog" sh gates/board_check.sh --config bk.smoke/cfg.json
twin "board_check (file)" "$LAST_OUT" "$LAST_RC" gates/board_check.ps1 -Config bk.smoke/cfg.json
expect 1 "board_check --ship FAIL: shipped item still open" sh gates/board_check.sh --config bk.smoke/cfg.json --ship DEMO-1
names "board_check (ship)" "DRIFT DEMO-1  shipped item not done on the board (stage 7)"
twin "board_check (ship)" "$LAST_OUT" "$LAST_RC" gates/board_check.ps1 -Config bk.smoke/cfg.json -Ship DEMO-1
expect 0 "board_check --ship PASS: done and closed" sh gates/board_check.sh --config bk.smoke/cfg.json --ship DEMO-4
twin "board_check (ship ok)" "$LAST_OUT" "$LAST_RC" gates/board_check.ps1 -Config bk.smoke/cfg.json -Ship DEMO-4
rm -rf bk.smoke

# Rule engine (constitution_lint / seam_conformance / qa_import_ban): a regex is matched line by line
# in both twins - ^ anchors each line, and no match spans a newline. Untracked scratch files, removed
# before the freeze.
mkdir -p notes
printf '{"constitutionRules":[{"id":"anchored","kind":"must_not_match","paths":"notes/*.txt","pattern":"^FORBIDDEN","message":"m"},{"id":"one-line","kind":"must_not_match","paths":"notes/*.txt","pattern":"^start[^#]*END","message":"m"}]}\n' > rules.smoke.json
printf 'ok FORBIDDEN mid-line\nFORBIDDEN at the start of line 2\n' > notes/a.txt
expect 1 "constitution_lint FAIL: ^ anchors line 2" sh gates/constitution_lint.template.sh --config rules.smoke.json
names "constitution_lint (anchored)" "anchored"
twin "constitution_lint (anchored)" "$LAST_OUT" "$LAST_RC" gates/constitution_lint.template.ps1 -Config rules.smoke.json
printf 'ok FORBIDDEN mid-line only\nstart of a line\nEND on the next line\n' > notes/a.txt
expect 0 "constitution_lint PASS: mid-line hit is not ^, no match across lines" sh gates/constitution_lint.template.sh --config rules.smoke.json
twin "constitution_lint (line by line)" "$LAST_OUT" "$LAST_RC" gates/constitution_lint.template.ps1 -Config rules.smoke.json
# A final newline ends the last line; it does not start an empty one (grep sees no empty line in "a\n").
printf '{"constitutionRules":[{"id":"no-empty-line","kind":"must_not_match","paths":"notes/*.txt","pattern":"^$","message":"m"}]}\n' > rules.smoke.json
printf 'a\n' > notes/a.txt
expect 0 "constitution_lint PASS: no phantom empty line after the final newline" sh gates/constitution_lint.template.sh --config rules.smoke.json
twin "constitution_lint (final newline)" "$LAST_OUT" "$LAST_RC" gates/constitution_lint.template.ps1 -Config rules.smoke.json
rm -rf notes rules.smoke.json

# static_check (#7): checkCmd is required (unset = exit 2), "none" opts out on the record, the exit code
# decides, and findingRegex + baseline ratchet. Commands are written to run under both sh -c and cmd /c.
st() { jq "$1" $CFG > st.smoke.json; }
st 'del(.checkCmd)'
expect 1 "static_check refuses unset checkCmd" sh gates/static_check.sh --config st.smoke.json
names "static_check (unset)" "checkCmd is not set"
[ "$LAST_RC" = 2 ] || { echo "FAIL  unset checkCmd should exit 2 (rc=$LAST_RC)"; fails=$((fails+1)); }
twin "static_check (unset)" "$LAST_OUT" "$LAST_RC" gates/static_check.ps1 -Config st.smoke.json
st '.checkCmd = "none"'
expect 0 "static_check PASS: opted out on the record" sh gates/static_check.sh --config st.smoke.json
names "static_check (none)" "opted out"
twin "static_check (none)" "$LAST_OUT" "$LAST_RC" gates/static_check.ps1 -Config st.smoke.json
st '.checkCmd = "echo lint clean"'
expect 0 "static_check PASS: exit 0" sh gates/static_check.sh --config st.smoke.json
twin "static_check (exit 0)" "$LAST_OUT" "$LAST_RC" gates/static_check.ps1 -Config st.smoke.json
st '.checkCmd = "echo a.py:1: E1 bad&& exit 3"'
expect 1 "static_check FAIL: non-zero exit" sh gates/static_check.sh --config st.smoke.json
names "static_check (exit 3)" "exited 3"
twin "static_check (exit 3)" "$LAST_OUT" "$LAST_RC" gates/static_check.ps1 -Config st.smoke.json
LINT='echo a.py:1: E1 bad&& echo a.py:2: E2 bad&& echo 2 errors&& exit 1'
st ".checkCmd = \"$LINT\" | .staticCheck.findingRegex = \"^a[.]py:[0-9]+:\" | .staticCheck.baseline = 2"
expect 0 "static_check ratchet PASS: findings = baseline" sh gates/static_check.sh --config st.smoke.json
names "static_check (ratchet =)" "2 finding(s) = baseline 2"
twin "static_check (ratchet =)" "$LAST_OUT" "$LAST_RC" gates/static_check.ps1 -Config st.smoke.json
st ".checkCmd = \"$LINT\" | .staticCheck.findingRegex = \"^a[.]py:[0-9]+:\" | .staticCheck.baseline = 3"
expect 0 "static_check ratchet PASS: below baseline, asks to lower it" sh gates/static_check.sh --config st.smoke.json
names "static_check (ratchet <)" "lower staticCheck.baseline to 2"
twin "static_check (ratchet <)" "$LAST_OUT" "$LAST_RC" gates/static_check.ps1 -Config st.smoke.json
st ".checkCmd = \"$LINT\" | .staticCheck.findingRegex = \"^a[.]py:[0-9]+:\" | .staticCheck.baseline = 1"
expect 1 "static_check ratchet FAIL: new findings" sh gates/static_check.sh --config st.smoke.json
names "static_check (ratchet >)" "2 finding(s) > baseline 1"
twin "static_check (ratchet >)" "$LAST_OUT" "$LAST_RC" gates/static_check.ps1 -Config st.smoke.json
st '.checkCmd = "echo crashed&& exit 1" | .staticCheck.findingRegex = "^a[.]py:[0-9]+:" | .staticCheck.baseline = 5'
expect 1 "static_check ratchet FAIL: non-zero exit, no finding matched" sh gates/static_check.sh --config st.smoke.json
names "static_check (no match)" "no line matched"
twin "static_check (no match)" "$LAST_OUT" "$LAST_RC" gates/static_check.ps1 -Config st.smoke.json
# Review findings (v1.16.0): each was a PASS that should FAIL, or a twin divergence.
rc2() { [ "$LAST_RC" = 2 ] || { echo "FAIL  $1 should exit 2 (rc=$LAST_RC)"; fails=$((fails+1)); }; }
st '.checkCmd = "echo a.py:1: E1 bad&& echo Traceback&& exit 4" | .staticCheck.findingRegex = "^a[.]py:[0-9]+:" | .staticCheck.baseline = 5'
expect 1 "static_check ratchet FAIL: a crash after some findings is not a count" sh gates/static_check.sh --config st.smoke.json
names "static_check (crash)" "not a findings exit code"
twin "static_check (crash)" "$LAST_OUT" "$LAST_RC" gates/static_check.ps1 -Config st.smoke.json
st ".checkCmd = \"$LINT\" | .staticCheck.findingRegex = \"^a[.]py:[\\\\d]:\" | .staticCheck.baseline = 1"
expect 1 "static_check: [\\d] inside brackets counts in both twins" sh gates/static_check.sh --config st.smoke.json
names "static_check (bracket class)" "2 finding(s) > baseline 1"
twin "static_check (bracket class)" "$LAST_OUT" "$LAST_RC" gates/static_check.ps1 -Config st.smoke.json
st '.checkCmd = "exit 1" | .staticCheck.findingRegex = "E1["'
expect 1 "static_check: a regex grep rejects is a config error" sh gates/static_check.sh --config st.smoke.json
rc2 "static_check (bad regex)"
twin "static_check (bad regex)" "$LAST_OUT" "$LAST_RC" gates/static_check.ps1 -Config st.smoke.json
st '.checkCmd = "exit 1" | .staticCheck.findingRegex = "(?i)e1"'
expect 1 "static_check: an inline flag is outside the portable subset" sh gates/static_check.sh --config st.smoke.json
rc2 "static_check (inline flag)"
twin "static_check (inline flag)" "$LAST_OUT" "$LAST_RC" gates/static_check.ps1 -Config st.smoke.json
st '.checkCmd = "exit 0" | .staticCheck.findingRegex = "x" | .staticCheck.baseline = false'
expect 1 "static_check: baseline false is a config error" sh gates/static_check.sh --config st.smoke.json
rc2 "static_check (baseline false)"
twin "static_check (baseline false)" "$LAST_OUT" "$LAST_RC" gates/static_check.ps1 -Config st.smoke.json
st '.checkCmd = "echo hi\nexit 4"'
expect 1 "static_check: a multi-line checkCmd is a config error" sh gates/static_check.sh --config st.smoke.json
rc2 "static_check (multi-line)"
twin "static_check (multi-line)" "$LAST_OUT" "$LAST_RC" gates/static_check.ps1 -Config st.smoke.json

# Rule kind command (#8): a real checker behind a rule row; exit 0 passes, a failure shows its output.
printf '{"seamRules":[{"id":"SEAM-1-ok","kind":"command","cmd":"echo fine","message":"m"},{"id":"SEAM-2-layers","kind":"command","cmd":"echo src.ui imports src.db&& exit 3","message":"m"}]}\n' > rules.smoke.json
expect 1 "seam_conformance FAIL: command rule exits non-zero" sh gates/seam_conformance.template.sh --config rules.smoke.json
names "seam_conformance (command)" "src.ui imports src.db"
names "seam_conformance (command id)" "[FAIL] SEAM-2-layers"
twin "seam_conformance (command)" "$LAST_OUT" "$LAST_RC" gates/seam_conformance.template.ps1 -Config rules.smoke.json
printf '{"seamRules":[{"id":"SEAM-1-ok","kind":"command","cmd":"echo fine","message":"m"}]}\n' > rules.smoke.json
expect 0 "seam_conformance PASS: command rule exits 0" sh gates/seam_conformance.template.sh --config rules.smoke.json
twin "seam_conformance (command pass)" "$LAST_OUT" "$LAST_RC" gates/seam_conformance.template.ps1 -Config rules.smoke.json
# A command that reads stdin must not eat the rule list (sort reads stdin under sh and cmd alike).
printf '{"seamRules":[{"id":"SEAM-1-reads","kind":"command","cmd":"sort","message":"m"},{"id":"SEAM-2-late","kind":"command","cmd":"exit 3","message":"m"}]}\n' > rules.smoke.json
expect 1 "seam_conformance FAIL: a stdin reader does not swallow later rules" sh gates/seam_conformance.template.sh --config rules.smoke.json
names "seam_conformance (stdin)" "SEAM-2-late: m"
twin "seam_conformance (stdin)" "$LAST_OUT" "$LAST_RC" gates/seam_conformance.template.ps1 -Config rules.smoke.json
printf '{"seamRules":[{"id":"SEAM-1-two","kind":"command","cmd":"echo hi\\nexit 4","message":"m"}]}\n' > rules.smoke.json
expect 1 "seam_conformance FAIL: a multi-line cmd is refused" sh gates/seam_conformance.template.sh --config rules.smoke.json
names "seam_conformance (multi-line)" "must be one line"
twin "seam_conformance (multi-line)" "$LAST_OUT" "$LAST_RC" gates/seam_conformance.template.ps1 -Config rules.smoke.json

# mutation_check (#9): optional; the exit code decides, or scoreRegex + minScore; {base} is substituted.
expect 0 "mutation_check PASS: not configured" sh gates/mutation_check.sh --config $CFG
names "mutation_check (unset)" "not configured"
twin "mutation_check (unset)" "$LAST_OUT" "$LAST_RC" gates/mutation_check.ps1 -Config $CFG
MUT='echo Mutation score: 85.5&& exit 1'
st ".mutation.cmd = \"$MUT\" | .mutation.scoreRegex = \"Mutation score: [0-9.]+\" | .mutation.minScore = 80"
expect 0 "mutation_check PASS: score >= minScore (exit code ignored)" sh gates/mutation_check.sh --config st.smoke.json
names "mutation_check (score)" "85.5 >= minScore 80"
twin "mutation_check (score)" "$LAST_OUT" "$LAST_RC" gates/mutation_check.ps1 -Config st.smoke.json
st ".mutation.cmd = \"$MUT\" | .mutation.scoreRegex = \"Mutation score: [0-9.]+\" | .mutation.minScore = 90"
expect 1 "mutation_check FAIL: score < minScore" sh gates/mutation_check.sh --config st.smoke.json
names "mutation_check (low score)" "route to QA"
twin "mutation_check (low score)" "$LAST_OUT" "$LAST_RC" gates/mutation_check.ps1 -Config st.smoke.json
st '.mutation.cmd = "echo survived: 3&& exit 2"'
expect 1 "mutation_check FAIL: exit code decides without scoreRegex" sh gates/mutation_check.sh --config st.smoke.json
twin "mutation_check (exit)" "$LAST_OUT" "$LAST_RC" gates/mutation_check.ps1 -Config st.smoke.json
st '.mutation.cmd = "echo since {base} and {base}"'
expect 0 "mutation_check substitutes {base}" sh gates/mutation_check.sh --base abc123 --config st.smoke.json
names "mutation_check ({base})" "since abc123 and abc123"
twin "mutation_check ({base})" "$LAST_OUT" "$LAST_RC" gates/mutation_check.ps1 -Base abc123 -Config st.smoke.json
st ".mutation.cmd = \"$MUT\" | .mutation.scoreRegex = \"score: [\\\\d.]+\" | .mutation.minScore = 80"
expect 0 "mutation_check: [\\d.] inside brackets reads the score in both twins" sh gates/mutation_check.sh --config st.smoke.json
names "mutation_check (bracket class)" "85.5 >= minScore 80"
twin "mutation_check (bracket class)" "$LAST_OUT" "$LAST_RC" gates/mutation_check.ps1 -Config st.smoke.json
st ".mutation.cmd = \"$MUT\" | .mutation.scoreRegex = \"score: [0-9]+\" | .mutation.minScore = \".\""
expect 1 "mutation_check: minScore \".\" is a config error" sh gates/mutation_check.sh --config st.smoke.json
rc2 "mutation_check (minScore .)"
twin "mutation_check (minScore .)" "$LAST_OUT" "$LAST_RC" gates/mutation_check.ps1 -Config st.smoke.json
st ".mutation.cmd = \"$MUT\" | .mutation.scoreRegex = \"score: [0-9]+?\""
expect 1 "mutation_check: a lazy quantifier is outside the portable subset" sh gates/mutation_check.sh --config st.smoke.json
rc2 "mutation_check (lazy)"
twin "mutation_check (lazy)" "$LAST_OUT" "$LAST_RC" gates/mutation_check.ps1 -Config st.smoke.json
rm -f st.smoke.json rules.smoke.json

# --- the review gates (v1.18): retire_check, findings_check, red_check, affected_tests. Each runs in a
# scratch repo that carries a copy of the gates (a gate roots itself at the git top-level of its own dir).
mk_rt() {  # <name> - a scratch repo with the gates copied in
  RT="$WORK/$1"; rm -rf "$RT"; mkdir -p "$RT/src" "$RT/spec" "$RT/tests" "$RT/docs/archive"
  cp -R "$PROJ/gates" "$RT/gates"; rm -f "$RT/gates/.frozen"
  git -C "$RT" init -q -b main . && git -C "$RT" config user.email ci@guide-sdd && git -C "$RT" config user.name ci
}
in_rt() { (cd "$RT" && "$@"); }
twin_rt() { [ "$COMPARE" = 1 ] || return 0; cd "$RT"; twin "$@"; cd "$PROJ"; }
rt_cfg() { jq "$1" "$RT/rt.base.json" > "$RT/rt.json"; }

# retire_check (#18)
mk_rt rt1
printf 'class WriterIntake { void submit_old() {} void KeepMe() {} }\n' > "$RT/src/WriterIntake.cs"
printf 'The WriterIntake calls submit_old.\n[REMOVED 2026-01-01 - submit_old retired]\n' > "$RT/spec/s.md"
printf '// test submit_old\n' > "$RT/tests/DoorTests.cs"
printf 'see submit_old and KeepMe\n' > "$RT/docs/d.md"
printf 'submit_old\n' > "$RT/docs/archive/a.md"
echo '{"baseRef":"main","paths":{"spec":"spec/**/*.md","code":"src/**"},"testGlobs":["tests/**"],"retireCheck":{"mode":"strict","extraGlobs":["docs/**"],"excludeGlobs":["docs/archive/**"]}}' > "$RT/rt.base.json"
git -C "$RT" add -A >/dev/null && git -C "$RT" commit -q -m seed
printf 'class WriterIntake { void submit_new() {} void KeepMe() {} }\n' > "$RT/src/WriterIntake.cs"
rt_cfg '.'
expect 1 "retire_check FAIL: a name removed from the code survives in spec, tests and docs" in_rt sh gates/retire_check.sh --config rt.json
names "retire_check (spec)" "spec/s.md:1: submit_old"
names "retire_check (test)" "tests/DoorTests.cs:1: submit_old"
names "retire_check (extraGlobs)" "docs/d.md:1: submit_old"
case "$LAST_OUT" in *docs/archive*|*"spec/s.md:2"*|*KeepMe*) echo "FAIL  retire_check: reported an excluded, tombstoned or still-live name"; fails=$((fails+1));; esac
twin_rt "retire_check" "$LAST_OUT" "$LAST_RC" gates/retire_check.ps1 -Config rt.json
rt_cfg '.retireCheck.mode = "warn"'
expect 0 "retire_check warn mode: hits print, exit 0" in_rt sh gates/retire_check.sh --config rt.json
names "retire_check (warn)" "WARN retire_check: 3 reference(s)"
twin_rt "retire_check (warn)" "$LAST_OUT" "$LAST_RC" gates/retire_check.ps1 -Config rt.json
printf '# declared\nKeepMe -> KeepNew\n' > "$RT/gates/.retired"
rt_cfg '.'
expect 1 "retire_check FAIL: a declared name, with its replacement" in_rt sh gates/retire_check.sh --config rt.json
names "retire_check (declared)" "docs/d.md:1: KeepMe -> KeepNew"
twin_rt "retire_check (declared)" "$LAST_OUT" "$LAST_RC" gates/retire_check.ps1 -Config rt.json
rm -f "$RT/gates/.retired"
rt_cfg '.retireCheck.allow = ["submit_old"]'
expect 0 "retire_check PASS: an allowed name" in_rt sh gates/retire_check.sh --config rt.json
twin_rt "retire_check (allow)" "$LAST_OUT" "$LAST_RC" gates/retire_check.ps1 -Config rt.json
for f in spec/s.md tests/DoorTests.cs docs/d.md; do sed 's/submit_old/submit_new/g' "$RT/$f" > "$RT/x.tmp" && mv "$RT/x.tmp" "$RT/$f"; done
rt_cfg '.'
expect 0 "retire_check PASS: the references are renamed" in_rt sh gates/retire_check.sh --config rt.json
names "retire_check (clean)" "no retired name survives"
twin_rt "retire_check (clean)" "$LAST_OUT" "$LAST_RC" gates/retire_check.ps1 -Config rt.json
rt_cfg 'del(.retireCheck)'
expect 0 "retire_check PASS: not configured" in_rt sh gates/retire_check.sh --config rt.json
names "retire_check (unset)" "not configured"
twin_rt "retire_check (unset)" "$LAST_OUT" "$LAST_RC" gates/retire_check.ps1 -Config rt.json

# findings_check (#21)
rt_cfg '.'
printf '# unit findings\nprose is ignored\nF1 [LOW] a.cs:3 stale name | fixed abc1234\nF2 [HIGH] b.cs:9 a | b claim | defer out of range: tracked in X-9\n' > "$RT/u.findings.md"
expect 0 "findings_check PASS: fixed <sha> and defer <evidence>" in_rt sh gates/findings_check.sh --config rt.json
names "findings_check (pass)" "2 finding(s) in 1 file(s)"
twin_rt "findings_check (pass)" "$LAST_OUT" "$LAST_RC" gates/findings_check.ps1 -Config rt.json
printf 'F3 [LOW] c.cs:1 nit | accepted\nF4 [MED] d.cs:2 no disposition at all\nF5 [LOW] e.cs:3 bad sha | fixed xyz\nF6 [LOW] f.cs:4 no evidence | defer \nF7 [BLOCKER] g.cs:5 bad severity | fixed abc1234\n' >> "$RT/u.findings.md"
expect 1 "findings_check FAIL: accepted, none, a bad sha, empty evidence, a bad severity" in_rt sh gates/findings_check.sh --config rt.json
for n in F3 F4 F5 F6 F7; do names "findings_check ($n)" "$n "; done
names "findings_check (accepted)" "disposition 'accepted'"
case "$LAST_OUT" in *"F1 "*|*"F2 "*) echo "FAIL  findings_check: flagged a valid disposition"; fails=$((fails+1));; esac
twin_rt "findings_check (fail)" "$LAST_OUT" "$LAST_RC" gates/findings_check.ps1 -Config rt.json
rm -f "$RT/u.findings.md"
expect 0 "findings_check PASS: no findings files" in_rt sh gates/findings_check.sh --config rt.json
twin_rt "findings_check (none)" "$LAST_OUT" "$LAST_RC" gates/findings_check.ps1 -Config rt.json

# red_check (#19) and affected_tests (#20): a unit branch with QA's tests frozen, then the Engineer's change
mk_rt rt2
printf 'class Writer {}\n' > "$RT/src/Writer.cs"
printf 'uses Writer\n' > "$RT/tests/DoorTests.cs"
printf 'nothing\n' > "$RT/tests/Unrelated.cs"
echo '{"baseRef":"main","paths":{"code":"src/**"},"testGlobs":["tests/**"]}' > "$RT/rt.base.json"
git -C "$RT" add -A >/dev/null && git -C "$RT" commit -q -m seed && git -C "$RT" checkout -q -b unit
printf 'qa test\n' > "$RT/tests/NewTests.cs"
git -C "$RT" add -A >/dev/null && git -C "$RT" commit -q -m qa
FROZEN=$(git -C "$RT" rev-parse HEAD)
rt_cfg '.redCheck = {"cmd":"echo Failed  Alpha&& echo Passed  Beta_pin&& echo Passed  Gamma && echo {tests}","passRegex":"^Passed +([A-Za-z_]+)"}'
expect 1 "red_check FAIL: a test passes before any implementation" in_rt sh gates/red_check.sh --base "$FROZEN" --config rt.json
names "red_check (Gamma)" "  Gamma"
names "red_check (Beta)" "  Beta_pin"
twin_rt "red_check" "$LAST_OUT" "$LAST_RC" gates/red_check.ps1 -Base "$FROZEN" -Config rt.json
rt_cfg '.redCheck = {"cmd":"echo Failed  Alpha&& echo Passed  Beta_pin&& echo Passed  Gamma && echo {tests}","passRegex":"^Passed +([A-Za-z_]+)","allowGreen":["Beta_*","Gamma"]}'
expect 0 "red_check PASS: the green tests are allowGreen entries (glob or exact)" in_rt sh gates/red_check.sh --base "$FROZEN" --config rt.json
twin_rt "red_check (allowGreen)" "$LAST_OUT" "$LAST_RC" gates/red_check.ps1 -Base "$FROZEN" -Config rt.json
rt_cfg '.redCheck = {"cmd":"echo Passed {tests}","passRegex":"^Passed +(.*)$","joiner":"+"}'
expect 1 "red_check: {tests} is the stems of the added test files" in_rt sh gates/red_check.sh --base "$FROZEN" --config rt.json
names "red_check ({tests})" "  NewTests"
case "$LAST_OUT" in *DoorTests*) echo "FAIL  red_check: ran a test file QA did not touch"; fails=$((fails+1));; esac
twin_rt "red_check ({tests})" "$LAST_OUT" "$LAST_RC" gates/red_check.ps1 -Base "$FROZEN" -Config rt.json
rt_cfg '.redCheck = {"cmd":"echo Passed Beta","passRegex":"^Passed +([A-Za-z_]+)"}'
expect 1 "red_check: a cmd without {tests} is a config error" in_rt sh gates/red_check.sh --base "$FROZEN" --config rt.json
rc2 "red_check (no {tests})"
rt_cfg '.'
expect 0 "red_check PASS: not configured" in_rt sh gates/red_check.sh --base "$FROZEN" --config rt.json
names "red_check (unset)" "not configured"
twin_rt "red_check (unset)" "$LAST_OUT" "$LAST_RC" gates/red_check.ps1 -Base "$FROZEN" -Config rt.json

printf 'class Writer { int x; }\n' > "$RT/src/Writer.cs"
rt_cfg '.redCheck = {"cmd":"echo Passed {tests}","passRegex":"^Passed +(.*)$"}'
expect 1 "red_check refuses a tree with paths.code changes" in_rt sh gates/red_check.sh --base "$FROZEN" --config rt.json
rc2 "red_check (dirty code)"
twin_rt "red_check (dirty)" "$LAST_OUT" "$LAST_RC" gates/red_check.ps1 -Base "$FROZEN" -Config rt.json

rt_cfg '.affectedTests = {"cmd":"echo ran {tests}","joiner":"+","extraStems":["Extra"]}'
printf 'Extra here\n' > "$RT/tests/ExtraTests.cs"
expect 0 "affected_tests --list: changed tests plus whole-word key hits" in_rt sh gates/affected_tests.sh --list --base "$FROZEN" --config rt.json
names "affected_tests (key)" "key: Writer"
names "affected_tests (extra key)" "key: Extra"
names "affected_tests (hit)" "test: tests/DoorTests.cs"
names "affected_tests (hit extra)" "test: tests/ExtraTests.cs"
names "affected_tests (changed)" "test: tests/NewTests.cs"
case "$LAST_OUT" in *Unrelated*) echo "FAIL  affected_tests: listed an unrelated test"; fails=$((fails+1));; esac
twin_rt "affected_tests --list" "$LAST_OUT" "$LAST_RC" gates/affected_tests.ps1 -List -Base "$FROZEN" -Config rt.json
expect 0 "affected_tests PASS: runs cmd with {tests} and passes its exit code" in_rt sh gates/affected_tests.sh --base "$FROZEN" --config rt.json
names "affected_tests (run)" "ran DoorTests+ExtraTests+NewTests"
twin_rt "affected_tests (run)" "$LAST_OUT" "$LAST_RC" gates/affected_tests.ps1 -Base "$FROZEN" -Config rt.json
rt_cfg '.affectedTests = {"cmd":"echo ran {tests}&& exit 3","joiner":"+"}'
expect 1 "affected_tests FAIL: the cmd exits non-zero" in_rt sh gates/affected_tests.sh --base "$FROZEN" --config rt.json
names "affected_tests (fail)" "exited 3"
twin_rt "affected_tests (fail)" "$LAST_OUT" "$LAST_RC" gates/affected_tests.ps1 -Base "$FROZEN" -Config rt.json
rt_cfg '.'
expect 0 "affected_tests PASS: not configured" in_rt sh gates/affected_tests.sh --base "$FROZEN" --config rt.json
names "affected_tests (unset)" "not configured"
twin_rt "affected_tests (unset)" "$LAST_OUT" "$LAST_RC" gates/affected_tests.ps1 -Base "$FROZEN" -Config rt.json
cd "$PROJ"

# Freeze: record the QA-frozen SHA; the gate then needs no base argument.
expect 0 "freeze writes gates/.frozen" sh gates/freeze.sh --unit DEMO-1
names "freeze" "sha="
twin "freeze" "$LAST_OUT" "$LAST_RC" gates/freeze.ps1 -Unit DEMO-1
git add gates/.frozen && git commit -q -m "chore(DEMO-1): freeze tests"
expect 0 "test_edit_ban PASS via .frozen (no base arg)" sh gates/test_edit_ban.sh --config $CFG
twin "test_edit_ban (.frozen)" "$LAST_OUT" "$LAST_RC" gates/test_edit_ban.ps1 -Config $CFG
# The approved diagram is frozen with the tests: an edit after the freeze FAILs naming the shard.
expect 0 "structure_check --frozen PASS via .frozen" sh gates/structure_check.sh --frozen --config $CFG
twin "structure_check (.frozen)" "$LAST_OUT" "$LAST_RC" gates/structure_check.ps1 -Frozen -Config $CFG
printf '%%%% deviation\n' >> spec/working/DEMO-1.structure.body.md
expect 1 "structure_check --frozen FAIL: diagram edited after freeze" sh gates/structure_check.sh --frozen --config $CFG
names "structure_check (.frozen negative)" "DEMO-1.structure.body.md"
twin "structure_check (.frozen negative)" "$LAST_OUT" "$LAST_RC" gates/structure_check.ps1 -Frozen -Config $CFG
git checkout -q -- spec
printf 'edited\n' >> tests/demo.smoke.test && git commit -q -am "engineer edits a test"
expect 1 "test_edit_ban FAIL: committed edit vs .frozen" sh gates/test_edit_ban.sh --config $CFG
names "test_edit_ban (.frozen negative)" "tests/demo.smoke.test"
twin "test_edit_ban (.frozen negative)" "$LAST_OUT" "$LAST_RC" gates/test_edit_ban.ps1 -Config $CFG
git reset -q --hard HEAD~1

# suiteCmd is mandatory: the template placeholder must make run_all exit 2.
jq 'del(.suiteCmd)' $CFG > "$WORK/cfg2" && cp "$WORK/cfg2" $CFG && git commit -q -am "unset suite"
expect 1 "run_all refuses unset suiteCmd" sh gates/run_all.sh --mechanical
names "run_all (no suite)" "suiteCmd is not set"
[ "$LAST_RC" = 2 ] || { echo "FAIL  unset suiteCmd should exit 2 (rc=$LAST_RC)"; fails=$((fails+1)); }
git reset -q --hard HEAD~1
# checkCmd is mandatory too: unset, the bank stops at static_check.
jq 'del(.checkCmd)' $CFG > "$WORK/cfg2" && cp "$WORK/cfg2" $CFG && git commit -q -am "unset check"
expect 1 "run_all refuses unset checkCmd" sh gates/run_all.sh --mechanical
names "run_all (no check)" "checkCmd is not set"
git reset -q --hard HEAD~1

# Whole bank over the clean demo tree (base from .frozen).
expect 0 "run_all clean (base from .frozen)" sh gates/run_all.sh
names "run_all (static_check)" "PASS static_check: checkCmd exited 0"
names "run_all (mutation_check)" "mutation_check: not configured"
twin "run_all" "$LAST_OUT" "$LAST_RC" gates/run_all.ps1
expect 0 "run_all HEAD clean" sh gates/run_all.sh HEAD
expect 0 "run_all --pre-fold clean (frozen-diagram half runs)" sh gates/run_all.sh --pre-fold
names "run_all (pre-fold)" "structure_check --frozen"
twin "run_all (pre-fold)" "$LAST_OUT" "$LAST_RC" gates/run_all.ps1 -PreFold

if [ "$fails" -eq 0 ]; then echo "SMOKE PASS"; else echo "SMOKE FAIL ($fails)"; exit 1; fi
