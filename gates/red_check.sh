#!/usr/bin/env sh
# red_check - prove QA's new tests are RED on the frozen tree (tests in, no implementation).
#
# Stage 5 requires the tests "red and compiling at handoff", but nothing verified red: a test that
# passes without the implementation (a poll that times out to a pass, an assertion on a value the
# fixture already sets) is frozen and reaches Validation. Run by the Orchestrator right after `freeze`.
#
# Test files = those ADDED or MODIFIED between the branch point (merge-base of baseRef and the frozen
# SHA) and the frozen SHA, under redCheck.globs (default testGlobs). {tests} in redCheck.cmd becomes
# their file stems (name without the last extension) joined by redCheck.joiner (default |), e.g.
#   cmd "dotnet test --filter \"FullyQualifiedName~{tests}\"", joiner "|FullyQualifiedName~"
# Each output line matching redCheck.passRegex names a test that PASSED: capture group 1 is its name.
# Any passing test no redCheck.allowGreen entry matches FAILs the gate and is listed: route it to QA
# (Stage 5). An allowGreen entry is a glob over the whole test name (* ?; none = exact), for regression
# pins that are legitimately green before the change.
#
# The frozen SHA is --base, else gates/.frozen (baseRef alone is not a freeze: exit 2). The tree must
# hold no paths.code change vs it. An unset redCheck.cmd = "not configured" PASS. The command runs from
# the project root under sh -c; its exit code is ignored (a red run exits non-zero).
#
# Exit 0 PASS, 1 FAIL, 2 config/usage error.
# Usage:  sh gates/red_check.sh [--base <frozen-sha>] [--config gates/gates.config.json]

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/_common.sh"

GATE=red_check
require_jq "$GATE"
require_git "$GATE"

CFG="gates/gates.config.json"
BASE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --config) CFG="$2"; shift 2 ;;
    --config=*) CFG="${1#--config=}"; shift ;;
    --base) BASE="$2"; shift 2 ;;
    --base=*) BASE="${1#--base=}"; shift ;;
    *) CFG="$1"; shift ;;
  esac
done
[ -f "$CFG" ] || { echo "FAIL $GATE: cannot read config $CFG: no such file"; exit 2; }
CFG=$(CDPATH= cd -- "$(dirname -- "$CFG")" && pwd)/$(basename -- "$CFG")

CMD=$(read_cfg "$CFG" '.redCheck.cmd' '')
if [ -z "$CMD" ]; then
  echo "PASS $GATE: not configured (redCheck.cmd unset) - red-first is unverified."
  exit 0
fi
case "$CMD" in *'{tests}'*) ;; *) echo "FAIL $GATE: redCheck.cmd must hold {tests}"; exit 2 ;; esac
RE=$(read_cfg "$CFG" '.redCheck.passRegex' '')
[ -n "$RE" ] || { echo "FAIL $GATE: redCheck.passRegex is unset - it names the passed tests (capture group 1 = test name)"; exit 2; }
case "$RE" in *'('*) ;; *) echo "FAIL $GATE: redCheck.passRegex needs a capture group around the test name"; exit 2 ;; esac
check_regex "$GATE" redCheck.passRegex "$RE" || exit 2
JOIN=$(read_raw "$CFG" '.redCheck.joiner' '|')

TOP=$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null) || { echo "FAIL $GATE: not inside a git work tree"; exit 2; }
GD=$(git -C "$HERE" rev-parse --show-prefix | sed 's#/$##'); [ -n "$GD" ] || GD="."
cd "$TOP" || exit 2

[ -n "$BASE" ] || BASE=$(frozen_sha "$GD")
[ -n "$BASE" ] || { echo "FAIL $GATE: no frozen SHA - run gates/freeze.sh at Stage 5 exit or pass --base <sha>."; exit 2; }
git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null 2>&1 || { echo "FAIL $GATE: frozen SHA '$BASE' does not resolve."; exit 2; }
FROM=$(git merge-base "$(read_cfg "$CFG" '.baseRef' 'main')" "$BASE" 2>/dev/null) || { echo "FAIL $GATE: no merge-base of baseRef and $BASE - set baseRef to the branch the unit started from."; exit 2; }

CODE=$(cfg_list "$CFG" '.paths.code' | glob_specs)
[ -n "$CODE" ] || CODE=$(printf '%s\n' 'src/**' | glob_specs)
if ! eval git diff --quiet '"$BASE"' -- $CODE 2>/dev/null || [ -n "$(eval git ls-files --others --exclude-standard -- $CODE)" ]; then
  echo "FAIL $GATE: paths.code differs from the frozen SHA - red_check runs on the frozen tree, before the Engineer starts."
  exit 2
fi

GLOBS=$(cfg_list "$CFG" '.redCheck.globs'); [ -n "$GLOBS" ] || GLOBS=$(cfg_list "$CFG" '.testGlobs')
[ -n "$GLOBS" ] || GLOBS=$(read_cfg "$CFG" '.paths.tests' 'tests/**')
SPECS=$(printf '%s\n' "$GLOBS" | glob_specs)
FILES=$(eval git diff --name-only --no-renames --diff-filter=AM '"$FROM"' '"$BASE"' -- $SPECS | tr -d '\r' | sort -u)
if [ -z "$FILES" ]; then
  echo "PASS $GATE: no test file added or changed between the branch point and the frozen SHA."
  exit 0
fi

TMP=$(mktemp -d) || { echo "FAIL $GATE: cannot make a temp dir"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
printf '%s\n' "$FILES" > "$TMP/files"
: > "$TMP/stems"
while IFS= read -r f; do
  s=$(file_stem "$f")
  case "$s" in
    ''|*[!A-Za-z0-9_.+-]*) echo "FAIL $GATE: '$f' has a file stem outside [A-Za-z0-9_.+-]; {tests} cannot carry it safely."; exit 2 ;;
  esac
  printf '%s\n' "$s" >> "$TMP/stems"
done < "$TMP/files"
TESTS=""
for s in $(sort -u "$TMP/stems"); do
  if [ -z "$TESTS" ]; then TESTS=$s; else TESTS="$TESTS$JOIN$s"; fi
done

CMD=$(fill_tests "$CMD" "$TESTS")
one_line "$GATE" redCheck.cmd "$CMD" || exit 2
OUT=$(sh -c "$CMD" </dev/null 2>&1)
PASSED=$(printf '%s\n' "$OUT" | tr -d '\r' | capture_group1 "$RE")

cfg_list "$CFG" '.redCheck.allowGreen' > "$TMP/allow"
GREEN=$(printf '%s\n' "$PASSED" | sed '/^$/d' | sort -u | while IFS= read -r name; do
  ok=0
  while IFS= read -r e; do
    case "$name" in $e) ok=1; break ;; esac
  done < "$TMP/allow"
  [ "$ok" -eq 1 ] || printf '%s\n' "$name"
done)

NF=$(printf '%s\n' "$FILES" | wc -l | tr -d ' ')
if [ -n "$GREEN" ]; then
  echo "FAIL $GATE: $(printf '%s\n' "$GREEN" | wc -l | tr -d ' ') test(s) pass on the frozen tree, before any implementation (route to QA, Stage 5; a legitimate regression pin goes in redCheck.allowGreen):"
  printf '%s\n' "$GREEN" | while IFS= read -r g; do echo "  $g"; done
  exit 1
fi
echo "PASS $GATE: $NF new/changed test file(s) run; none passes without the implementation."
exit 0
