#!/usr/bin/env sh
# mutation_check - measure test strength by mutation testing (mutation.cmd), for Validation.
#
# Red-first proves QA's tests fail without an implementation, not that they catch a WRONG one. A
# mutation tool (Stryker, mutmut, cargo-mutants, PIT, go-mutesting...) plants small faults in the code
# and counts the ones the suite kills. A surviving mutant in changed code is a missing test: Validation
# routes it to QA (Stage 5), never to the Engineer.
#
# OPTIONAL: an unset mutation.cmd PASSes with "not configured" (test strength is then unmeasured, and
# the bank says so every run). Mutation runs are slow - scope them to the diff:
#   {base} in mutation.cmd becomes the QA-frozen SHA (--base > gates/.frozen > config baseRef), e.g.
#   "npx stryker run --incremental", "git diff {base} > mut.diff && cargo mutants --in-diff mut.diff",
#   "mutmut run --paths-to-mutate $(git diff --name-only {base} -- src | paste -sd,)".
#
# Verdict:
#   * mutation.scoreRegex unset - mutation.cmd's exit code decides (0 = PASS; most tools take their own
#     threshold, e.g. Stryker thresholds.break, PIT mutationThreshold).
#   * scoreRegex set - the first line matching it carries the score: the first number in the match
#     (e.g. "Mutation score: 85.71" -> 85.71) is compared with mutation.minScore (default 0). The exit code
#     is then ignored (tools exit non-zero when mutants survive); no match at all FAILs.
# The command runs from the project root; its output is printed above the verdict.
#
# Usage:  sh gates/mutation_check.sh [--base <sha>] [--config gates/gates.config.json]

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/_common.sh"

GATE=mutation_check
require_jq "$GATE"

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

CMD=$(read_cfg "$CFG" '.mutation.cmd' '')
if [ -z "$CMD" ]; then
  echo "PASS $GATE: not configured (mutation.cmd unset) - test strength is unmeasured."
  exit 0
fi

case "$CMD" in
  *'{base}'*)
    if [ -z "$BASE" ] && [ -f "$HERE/.frozen" ]; then
      BASE=$(sed -n 's/^sha=\([0-9a-fA-F]*\).*/\1/p' "$HERE/.frozen" | head -1)
    fi
    [ -n "$BASE" ] || BASE=$(read_cfg "$CFG" '.baseRef' '')
    [ -n "$BASE" ] || { echo "FAIL $GATE: mutation.cmd uses {base} but no base is known - pass the frozen SHA or run the freeze gate."; exit 2; }
    _s=$CMD; CMD=""
    while :; do
      case "$_s" in
        *'{base}'*) CMD="$CMD${_s%%'{base}'*}$BASE"; _s=${_s#*'{base}'} ;;
        *) CMD="$CMD$_s"; break ;;
      esac
    done ;;
esac

one_line "$GATE" mutation.cmd "$CMD" || exit 2
MIN=$(read_raw "$CFG" '.mutation.minScore' '0')
case "$MIN" in ''|*[!0-9.]*|.*|*.|*.*.*) echo "FAIL $GATE: mutation.minScore must be a number (got '$MIN')"; exit 2 ;; esac
RE=$(read_cfg "$CFG" '.mutation.scoreRegex' '')
if [ -n "$RE" ]; then check_regex "$GATE" mutation.scoreRegex "$RE" || exit 2; fi

OUT=$(sh -c "$CMD" </dev/null 2>&1); RC=$?
OUT=$(printf '%s\n' "$OUT" | tr -d '\r')
[ -n "$OUT" ] && printf '%s\n' "$OUT"

if [ -z "$RE" ]; then
  if [ "$RC" -eq 0 ]; then echo "PASS $GATE: mutation.cmd exited 0."; exit 0; fi
  echo "FAIL $GATE: mutation.cmd exited $RC - surviving mutants are missing tests (route to QA, Stage 5)."
  exit 1
fi

SCORE=$(printf '%s\n' "$OUT" | grep -oE "$(to_ere "$RE")" | head -n 1 | grep -oE '[0-9]+([.][0-9]+)?' | head -n 1)
if [ -z "$SCORE" ]; then
  echo "FAIL $GATE: no score in the output (mutation.scoreRegex matched nothing; exit $RC) - the tool errored, or the regex no longer fits."
  exit 1
fi
if awk -v s="$SCORE" -v m="$MIN" 'BEGIN { exit !(s + 0 >= m + 0) }'; then
  echo "PASS $GATE: mutation score $SCORE >= minScore $MIN."
  exit 0
fi
echo "FAIL $GATE: mutation score $SCORE < minScore $MIN - surviving mutants are missing tests (route to QA, Stage 5)."
exit 1
