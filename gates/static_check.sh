#!/usr/bin/env sh
# static_check - the project's linter / type checker / formatter check, run as a gate (checkCmd).
#
# The suite proves only what QA thought to test; static analysis is the cheapest net under the rest
# (wrong or unused imports, type errors, dead code, bug patterns, format drift). REQUIRED, like
# suiteCmd: an unset checkCmd is exit 2, never a silent skip. "none" opts out on the record - the bank
# prints it every run.
#
# Verdict:
#   * staticCheck.findingRegex unset - checkCmd's exit code decides (0 = PASS).
#   * findingRegex set (the brownfield ratchet) - the lines of output matching it are counted
#     (grep -E dialect, line by line, as the rule engine) and compared with staticCheck.baseline:
#     more = FAIL (new findings), fewer = PASS with a note to lower the baseline. An exit code
#     outside staticCheck.findingExitCodes (default 0, 1) FAILs: the run did not finish. A non-zero
#     exit with no matching line FAILs: the tool broke, or the regex no longer fits its output.
#   * Commands are one line, and must mean the same under sh -c and cmd /c (else call a script).
# The command runs from the project root (run_all's cwd); its output is printed above the verdict.
#
# Suppressions are the bypass: an inline `eslint-disable` / `noqa` / `#pragma warning disable` in
# paths.code passes this gate. Ban them with a constitutionRules must_not_match row, and list the
# linter's own config under testGlobs so it freezes with the tests (gates/README.md).
#
# Usage:  sh gates/static_check.sh [--config gates/gates.config.json]

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/_common.sh"

GATE=static_check
require_jq "$GATE"

CFG="gates/gates.config.json"
while [ $# -gt 0 ]; do
  case "$1" in
    --config) CFG="$2"; shift 2 ;;
    --config=*) CFG="${1#--config=}"; shift ;;
    *) CFG="$1"; shift ;;
  esac
done
[ -f "$CFG" ] || { echo "FAIL $GATE: cannot read config $CFG: no such file"; exit 2; }

CMD=$(read_cfg "$CFG" '.checkCmd' '')
case "$CMD" in
  ""|"<from project-details"*)
    echo "FAIL $GATE: checkCmd is not set in $CFG - set the project's lint / type-check command, or \"none\" to opt out on the record (INIT section 5)."
    exit 2 ;;
  none)
    echo "PASS $GATE: opted out (checkCmd is \"none\") - no static analysis runs."
    exit 0 ;;
esac

one_line "$GATE" checkCmd "$CMD" || exit 2
RE=$(read_cfg "$CFG" '.staticCheck.findingRegex' '')
BL=$(read_raw "$CFG" '.staticCheck.baseline' '0')
case "$BL" in ''|*[!0-9]*) echo "FAIL $GATE: staticCheck.baseline must be a whole number (got '$BL')"; exit 2 ;; esac
[ "${#BL}" -le 15 ] || { echo "FAIL $GATE: staticCheck.baseline must be a whole number (got '$BL')"; exit 2; }
CODES=$(jq -r '(.staticCheck.findingExitCodes // [0, 1]) | map(tostring) | join(" ")' "$CFG" 2>/dev/null | tr -d '\r')
for c in $CODES; do
  case "$c" in ''|*[!0-9]*) echo "FAIL $GATE: staticCheck.findingExitCodes must be whole numbers (got '$c')"; exit 2 ;; esac
done
if [ -n "$RE" ]; then check_regex "$GATE" staticCheck.findingRegex "$RE" || exit 2; fi

OUT=$(sh -c "$CMD" </dev/null 2>&1); RC=$?
OUT=$(printf '%s\n' "$OUT" | tr -d '\r')
[ -n "$OUT" ] && printf '%s\n' "$OUT"

if [ -z "$RE" ]; then
  if [ "$RC" -eq 0 ]; then echo "PASS $GATE: checkCmd exited 0."; exit 0; fi
  echo "FAIL $GATE: checkCmd exited $RC."
  exit 1
fi

# The ratchet trusts a count only from a run that finished: an exit code outside findingExitCodes
# (default 0 and 1; most linters exit 1 for findings, 2+ for a crash or a config error) FAILs.
ok=0
for c in $CODES; do [ "$RC" -eq "$c" ] && ok=1; done
if [ "$ok" = 0 ]; then
  echo "FAIL $GATE: checkCmd exited $RC, not a findings exit code ($CODES; staticCheck.findingExitCodes) - the tool errored."
  exit 1
fi
N=$(printf '%s\n' "$OUT" | grep -Ec "$(to_ere "$RE")")
case "$N" in ''|*[!0-9]*) echo "FAIL $GATE: staticCheck.findingRegex is not a valid regex"; exit 2 ;; esac
if [ "$RC" -ne 0 ] && [ "$N" -eq 0 ]; then
  echo "FAIL $GATE: checkCmd exited $RC but no line matched staticCheck.findingRegex - the tool errored, or the regex no longer fits its output."
  exit 1
fi
if [ "$N" -gt "$BL" ]; then
  echo "FAIL $GATE: $N finding(s) > baseline $BL - new findings; fix them (the baseline only ratchets down)."
  exit 1
fi
if [ "$N" -lt "$BL" ]; then
  echo "PASS $GATE: $N finding(s) < baseline $BL - lower staticCheck.baseline to $N (ratchet)."
  exit 0
fi
echo "PASS $GATE: $N finding(s) = baseline $BL."
exit 0
