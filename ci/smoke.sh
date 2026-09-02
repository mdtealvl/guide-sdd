#!/usr/bin/env sh
# GUIDE SDD — CI smoke test. Reproduces project-config/INIT.md §6 on a throwaway copy of the spine:
# seed one anchored clause + one tagged test, run the four generic gates (expect PASS), add an
# unfollowed clause (expect coverage FAIL), revert, run the whole bank (expect clean).
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
cp gates/gates.config.template.json gates/gates.config.json
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
expect 0 "test_edit_ban PASS"   sh gates/test_edit_ban.sh HEAD $CFG
twin "test_edit_ban" "$LAST_OUT" "$LAST_RC" gates/test_edit_ban.ps1 HEAD $CFG

# Negative control: an unfollowed clause must FAIL coverage, naming it.
printf '\n## DEMO.2 unfollowed {#DEMO.2}\nThe system shall have no test, on purpose.\n' >> spec/demo.body.md
expect 1 "coverage_check FAIL on DEMO.2" sh gates/coverage_check.sh --config $CFG
case "$LAST_OUT" in *DEMO.2*) ;; *) echo "FAIL  coverage_check did not name DEMO.2"; fails=$((fails+1));; esac
twin "coverage_check (negative)" "$LAST_OUT" "$LAST_RC" gates/coverage_check.ps1 -Config $CFG
git checkout -q -- spec
expect 0 "coverage_check PASS after revert" sh gates/coverage_check.sh --config $CFG

# Whole bank over the clean demo tree.
expect 0 "run_all HEAD clean" sh gates/run_all.sh HEAD
twin "run_all" "$LAST_OUT" "$LAST_RC" gates/run_all.ps1 HEAD

if [ "$fails" -eq 0 ]; then echo "SMOKE PASS"; else echo "SMOKE FAIL ($fails)"; exit 1; fi
