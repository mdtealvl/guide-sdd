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
# INIT §5: the suite command is mandatory (an unset suiteCmd is exit 2, never a silent skip).
jq '.suiteCmd = "exit 0"' gates/gates.config.template.json > gates/gates.config.json
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

# Whole bank over the clean demo tree (base from .frozen).
expect 0 "run_all clean (base from .frozen)" sh gates/run_all.sh
twin "run_all" "$LAST_OUT" "$LAST_RC" gates/run_all.ps1
expect 0 "run_all HEAD clean" sh gates/run_all.sh HEAD
expect 0 "run_all --pre-fold clean (frozen-diagram half runs)" sh gates/run_all.sh --pre-fold
names "run_all (pre-fold)" "structure_check --frozen"
twin "run_all (pre-fold)" "$LAST_OUT" "$LAST_RC" gates/run_all.ps1 -PreFold

if [ "$fails" -eq 0 ]; then echo "SMOKE PASS"; else echo "SMOKE FAIL ($fails)"; exit 1; fi
