#!/usr/bin/env sh
# GUIDE SDD — CI smoke test. Reproduces project-config/INIT.md §6 on a throwaway copy of the spine:
# seed one anchored clause + one tagged test, run the generic gates (expect PASS), then the NEGATIVE
# controls — an unfollowed clause (coverage FAIL), every test_edit_ban bypass the v1.12 hardening
# closed (uncommitted edit, untracked test, rename-out, gate-config tamper, moving base), the v1.13
# structure_check controls (planned member missing, removed class present, memberless diagram, diagram
# edited after freeze) and token_ledger (qa row into code refused, stale row) — then freeze and run the
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
