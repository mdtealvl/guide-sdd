#!/usr/bin/env sh
# findings_check - every Validation finding carries a disposition; "accepted" is not one.
#
# Validation writes <unit>.findings.md, one finding per line; the Orchestrator ends each line with its
# disposition. A finding with none, or with any other word (accepted, waived, wontfix...), FAILs.
#
# Line grammar (gates/README.md):
#   F<n> [HIGH|MED|LOW|INFO] <file:line> <claim> | <disposition>
#   disposition = fixed <7-40 hex sha>          the fix commit
#               | defer <evidence>              out of range only; evidence is non-empty text
# The disposition is the text after the LAST ` | ` on the line (a claim may hold a bare |, evidence may not
# hold ` | `). Lines that do not start `F<n> [` are prose and ignored. A line that starts `F<n> [` with a
# severity outside the four is malformed and FAILs.
#
# findings.glob (default **/*.findings.md) finds the files. None = PASS.
#
# Exit 0 PASS, 1 FAIL, 2 config/usage error.
# Usage:  sh gates/findings_check.sh [--config gates/gates.config.json]

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/_common.sh"

GATE=findings_check
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

GLOB=$(read_cfg "$CFG" '.findings.glob' '**/*.findings.md')
FILES=$(expand_globs "$GLOB")
if [ -z "$FILES" ]; then
  echo "PASS $GATE: no findings files ($GLOB)."
  exit 0
fi

BAD=0; TOTAL=0; NFILES=0
OUT=$(printf '%s\n' "$FILES" | while IFS= read -r f; do
  tr -d '\r' < "$f" | grep -n -E '^F[0-9]+ \[' | while IFS= read -r row; do
    n=${row%%:*}; line=${row#*:}
    id=${line%% *}
    why=""
    printf '%s\n' "$line" | grep -q -E '^F[0-9]+ \[(HIGH|MED|LOW|INFO)\]' || why="malformed: severity must be [HIGH], [MED], [LOW] or [INFO]"
    if [ -z "$why" ]; then
      case "$line" in
        *' | '*)
          disp=${line##* | }
          kw=${disp%% *}
          case "$disp" in *' '*) rest=${disp#* } ;; *) rest="" ;; esac
          rest=$(printf '%s' "$rest" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
          case "$kw" in
            fixed)
              case "$rest" in
                ''|*[!0-9a-fA-F]*) why="'fixed' needs a 7-40 hex sha" ;;
                *) if [ "${#rest}" -lt 7 ] || [ "${#rest}" -gt 40 ]; then why="'fixed' needs a 7-40 hex sha"; fi ;;
              esac ;;
            defer) [ -n "$rest" ] || why="'defer' needs evidence" ;;
            *) why="disposition '$kw' is not fixed <sha> or defer <evidence>" ;;
          esac ;;
        *) why="no disposition (end the line with ' | fixed <sha>' or ' | defer <evidence>')" ;;
      esac
    fi
    if [ -n "$why" ]; then echo "BAD $f:$n: $id $why"; else echo "OK"; fi
  done
done)
TOTAL=$(printf '%s\n' "$OUT" | grep -c -E '^(BAD|OK)')
BAD=$(printf '%s\n' "$OUT" | grep -c '^BAD')
NFILES=$(printf '%s\n' "$FILES" | wc -l | tr -d ' ')
if [ "$BAD" -gt 0 ]; then
  echo "FAIL $GATE: $BAD of $TOTAL finding(s) lack a valid disposition:"
  printf '%s\n' "$OUT" | grep '^BAD' | sed 's/^BAD /  /'
  echo "A finding is fixed <sha> or deferred with evidence (out of range only). accepted is not a disposition."
  exit 1
fi
echo "PASS $GATE: $TOTAL finding(s) in $NFILES file(s), all dispositioned."
exit 0
