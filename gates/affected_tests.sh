#!/usr/bin/env sh
# affected_tests - pick the unit's own tests mechanically; never a judgment call.
#
# The two-tier ship gate runs "smoke + the unit's own tests". Left to each orchestrator, "own tests"
# under-selects: a lane changed services whose existing tests it did not run and turned main red.
#
# Keys = the file stems (name without the last extension) of the paths.code files changed vs {base}
# (tracked changes, deletes and untracked files included) plus affectedTests.extraStems.
# Affected tests = the test files under affectedTests.globs (default testGlobs) that are themselves
# changed (since the branch point: merge-base of baseRef and {base}), PLUS every one holding a whole-word
# occurrence of a key (git grep -l -w).
#   --list   print them (key: <stem> / test: <path>) and exit 0.
#   default  run affectedTests.cmd with {tests} = the affected files' stems joined by
#            affectedTests.joiner (else redCheck.joiner, else |); put {tests} inside the quotes the
#            runner's filter needs. Its output is printed; exit 0 when it exits 0, else 1.
# Add a project's always-run category in the cmd itself. An unset cmd = "not configured" PASS (use
# --list). {base}: --base, else gates/.frozen, else config baseRef.
#
# Exit 0 PASS, 1 FAIL (cmd failed), 2 config/usage error.
# Usage:  sh gates/affected_tests.sh [--list] [--base <sha>] [--config gates/gates.config.json]

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/_common.sh"

GATE=affected_tests
require_jq "$GATE"
require_git "$GATE"

CFG="gates/gates.config.json"
BASE=""
LIST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --list) LIST=1; shift ;;
    --config) CFG="$2"; shift 2 ;;
    --config=*) CFG="${1#--config=}"; shift ;;
    --base) BASE="$2"; shift 2 ;;
    --base=*) BASE="${1#--base=}"; shift ;;
    *) CFG="$1"; shift ;;
  esac
done
[ -f "$CFG" ] || { echo "FAIL $GATE: cannot read config $CFG: no such file"; exit 2; }
CFG=$(CDPATH= cd -- "$(dirname -- "$CFG")" && pwd)/$(basename -- "$CFG")

CMD=$(read_cfg "$CFG" '.affectedTests.cmd' '')
if [ "$LIST" -eq 0 ]; then
  if [ -z "$CMD" ]; then
    echo "PASS $GATE: not configured (affectedTests.cmd unset) - use --list to see the affected tests."
    exit 0
  fi
  case "$CMD" in *'{tests}'*) ;; *) echo "FAIL $GATE: affectedTests.cmd must hold {tests}"; exit 2 ;; esac
fi
JOIN=$(read_raw "$CFG" '.affectedTests.joiner' "$(read_raw "$CFG" '.redCheck.joiner' '|')")

TOP=$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null) || { echo "FAIL $GATE: not inside a git work tree"; exit 2; }
GD=$(git -C "$HERE" rev-parse --show-prefix | sed 's#/$##'); [ -n "$GD" ] || GD="."
cd "$TOP" || exit 2

BASEREF=$(read_cfg "$CFG" '.baseRef' 'main')
[ -n "$BASE" ] || BASE=$(frozen_sha "$GD")
[ -n "$BASE" ] || BASE=$BASEREF
git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null 2>&1 || { echo "FAIL $GATE: base '$BASE' does not resolve - pass the QA-frozen SHA."; exit 2; }
TBASE=$(git merge-base "$BASEREF" "$BASE" 2>/dev/null) || TBASE=$BASE

CODE=$(cfg_list "$CFG" '.paths.code' | glob_specs)
[ -n "$CODE" ] || CODE=$(printf '%s\n' 'src/**' | glob_specs)
GLOBS=$(cfg_list "$CFG" '.affectedTests.globs'); [ -n "$GLOBS" ] || GLOBS=$(cfg_list "$CFG" '.testGlobs')
[ -n "$GLOBS" ] || GLOBS=$(read_cfg "$CFG" '.paths.tests' 'tests/**')
TSPEC=$(printf '%s\n' "$GLOBS" | glob_specs)

TMP=$(mktemp -d) || { echo "FAIL $GATE: cannot make a temp dir"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

{ eval git diff --name-only --no-renames '"$BASE"' -- $CODE; eval git ls-files --others --exclude-standard -- $CODE; } 2>/dev/null \
  | tr -d '\r' | sed '/^$/d' | sort -u > "$TMP/codefiles"
: > "$TMP/keys"
while IFS= read -r f; do file_stem "$f"; echo; done < "$TMP/codefiles" > "$TMP/stems"
{ cat "$TMP/stems"; cfg_list "$CFG" '.affectedTests.extraStems'; } | sed '/^$/d' | sort -u > "$TMP/keys"

{ eval git diff --name-only --no-renames --diff-filter=ACMR '"$TBASE"' -- $TSPEC; eval git ls-files --others --exclude-standard -- $TSPEC; } 2>/dev/null \
  | tr -d '\r' | sed '/^$/d' > "$TMP/tests"
if [ -s "$TMP/keys" ]; then
  eval git grep -I -l -w -F -f '"$TMP/keys"' --untracked -- $TSPEC 2>/dev/null | tr -d '\r' >> "$TMP/tests"
fi
sort -u "$TMP/tests" | sed '/^$/d' > "$TMP/affected"
NT=$(wc -l < "$TMP/affected" | tr -d ' ')
NK=$(wc -l < "$TMP/keys" | tr -d ' ')

if [ "$LIST" -eq 1 ]; then
  while IFS= read -r k; do echo "key: $k"; done < "$TMP/keys"
  while IFS= read -r t; do echo "test: $t"; done < "$TMP/affected"
  echo "PASS $GATE: $NK key(s), $NT affected test file(s) vs $(printf '%s' "$BASE" | cut -c1-7)."
  exit 0
fi
if [ "$NT" -eq 0 ]; then
  echo "PASS $GATE: no affected test file ($NK key(s) vs $(printf '%s' "$BASE" | cut -c1-7))."
  exit 0
fi

: > "$TMP/tstems"
while IFS= read -r f; do
  s=$(file_stem "$f")
  case "$s" in
    ''|*[!A-Za-z0-9_.+-]*) echo "FAIL $GATE: '$f' has a file stem outside [A-Za-z0-9_.+-]; {tests} cannot carry it safely."; exit 2 ;;
  esac
  printf '%s\n' "$s" >> "$TMP/tstems"
done < "$TMP/affected"
TESTS=""
for s in $(sort -u "$TMP/tstems"); do
  if [ -z "$TESTS" ]; then TESTS=$s; else TESTS="$TESTS$JOIN$s"; fi
done
CMD=$(fill_tests "$CMD" "$TESTS")
one_line "$GATE" affectedTests.cmd "$CMD" || exit 2

OUT=$(sh -c "$CMD" </dev/null 2>&1); RC=$?
OUT=$(printf '%s\n' "$OUT" | tr -d '\r')
[ -n "$OUT" ] && printf '%s\n' "$OUT"
if [ "$RC" -eq 0 ]; then
  echo "PASS $GATE: affectedTests.cmd exited 0 ($NT test file(s))."
  exit 0
fi
echo "FAIL $GATE: affectedTests.cmd exited $RC ($NT test file(s))."
exit 1
