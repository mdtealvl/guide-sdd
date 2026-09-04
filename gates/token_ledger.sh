#!/usr/bin/env bash
# token_ledger - the build plan's READ LEDGER (Stage 4b): append rows, verify pins, report token
# spend and savings. A helper like freeze, not a pass/fail gate in the bank; `verify` exits 1 on a
# stale row so a reader never trusts advice written against a file that has since changed.
#
# The ledger is a markdown table under "## Ledger" (the LAST section of <ITEM-ID>.buildplan.md):
#   | kind | by | for | aud | path | range | hash | full | est | note |
#   kind  read  - a read the slice DID (by = that slice); est = tokens admitted.
#         range - advice: a later slice needs only lines a-b of path;      est = tokens of that range.
#         grep  - advice: grep an anchor 'pattern' +/-N lines instead;      est = matches x (2N+1) lines.
#         pin   - advice: the exact signature/constant is in `note`; do not open the file; est = note tokens.
#         skip  - advice: do not open this file at all;                     est = 0.
#   by    the writing slice: P (the Stage-4b planning slice) or S1..Sn.   for   the consuming slice, or *.
#   aud   any | qa | eng - QA rows never point into paths.code (invariant 3); the dispatcher filters.
#   hash  git hash-object of path when the row was written (7 chars).   full  tokens of the whole file.
# Tokens = ceil(chars x buildPlan.tokensPerChar) (default 0.25): an ESTIMATE from bytes admitted,
# never a billed count. Every number the report prints is recomputable from the ledger.
#
# Savings rule (report): for each advice row aimed at slice S on path p - if S recorded no read of p,
# saved += full(p); if S read less than full, saved += full - admitted(S,p); if S read the whole
# file, nothing is saved and the row counts as not honoured. Percent = saved / (admitted + saved).
#
# Usage:
#   sh gates/token_ledger.sh add    --plan <file> --kind <read|range|grep|pin|skip> --by <S> [--for <S|*>]
#                                   [--aud any|qa|eng] --path <p> [--range <a-b|a-|-b|-|'pat' +-N|line>] [--note <t>]
#   Output is ASCII (~ for "about", +- for the grep context) so both OS twins print byte-identical lines.
#   sh gates/token_ledger.sh verify --plan <file> [--for <S>]      # STALE rows -> exit 1
#   sh gates/token_ledger.sh report --plan <file> [--slice <S>]    # the `tokens:` lines for the item
#   --plan omitted: the single file matching buildPlan.glob. [--config gates/gates.config.json]
# Exit 0 ok, 1 stale (verify), 2 usage/config.

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/_common.sh"

GATE=token_ledger
require_git "$GATE"
require_jq "$GATE"

CMD="${1:-}"; [ $# -gt 0 ] && shift
case "$CMD" in add|verify|report) ;; *) echo "FAIL $GATE: usage: token_ledger.sh add|verify|report ..."; exit 2 ;; esac

PLAN=""; KIND=""; BY=""; FOR=""; AUD="any"; P=""; RANGE=""; NOTE=""; SLICE=""; CFG="gates/gates.config.json"
while [ $# -gt 0 ]; do
  case "$1" in
    --plan) PLAN="$2"; shift 2 ;;      --plan=*) PLAN="${1#*=}"; shift ;;
    --kind) KIND="$2"; shift 2 ;;      --kind=*) KIND="${1#*=}"; shift ;;
    --by) BY="$2"; shift 2 ;;          --by=*) BY="${1#*=}"; shift ;;
    --for) FOR="$2"; shift 2 ;;        --for=*) FOR="${1#*=}"; shift ;;
    --aud) AUD="$2"; shift 2 ;;        --aud=*) AUD="${1#*=}"; shift ;;
    --path) P="$2"; shift 2 ;;         --path=*) P="${1#*=}"; shift ;;
    --range) RANGE="$2"; shift 2 ;;    --range=*) RANGE="${1#*=}"; shift ;;
    --note) NOTE="$2"; shift 2 ;;      --note=*) NOTE="${1#*=}"; shift ;;
    --slice) SLICE="$2"; shift 2 ;;    --slice=*) SLICE="${1#*=}"; shift ;;
    --config) CFG="$2"; shift 2 ;;     --config=*) CFG="${1#*=}"; shift ;;
    *) echo "FAIL $GATE: unknown argument '$1'"; exit 2 ;;
  esac
done

[ -f "$CFG" ] || { echo "FAIL $GATE: cannot read config $CFG: no such file"; exit 2; }
CFG=$(CDPATH= cd -- "$(dirname -- "$CFG")" && pwd)/$(basename -- "$CFG")
TOP=$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null) || { echo "FAIL $GATE: not inside a git work tree"; exit 2; }
cd "$TOP" || exit 2
TPC=$(read_cfg "$CFG" '.buildPlan.tokensPerChar' '0.25')

if [ -z "$PLAN" ]; then
  G=$(read_cfg "$CFG" '.buildPlan.glob' '**/*.buildplan.md')
  PLAN=$(expand_globs "$G")
  N=$(printf '%s\n' "$PLAN" | sed '/^$/d' | wc -l | tr -d ' ')
  [ "$N" = 1 ] || { echo "FAIL $GATE: --plan required ($N files match buildPlan.glob '$G')."; exit 2; }
fi
[ "$CMD" = add ] || [ -f "$PLAN" ] || { echo "FAIL $GATE: build plan '$PLAN' not found."; exit 2; }

tok() { awk -v c="$1" -v t="$TPC" 'BEGIN { v = c * t; printf "%d", (v == int(v)) ? v : int(v) + 1 }'; }
fmt() { awk -v n="$1" 'BEGIN { if (n >= 1000) printf "%.1fk", n / 1000; else printf "%d", n }'; }
blob() { git hash-object -- "$1" 2>/dev/null | cut -c1-7; }

# rows <plan> -> TSV: n kind by for aud path range hash full est note  (data rows of the ledger table only)
rows() {
  awk -F'|' '
    /^[[:space:]]*\|/ {
      if ($0 ~ /^[[:space:]]*\|[[:space:]]*kind[[:space:]]*\|/) { hdr = 1; next }
      if (!hdr) next
      if ($0 ~ /^[[:space:]]*\|[[:space:]]*-+/) next
      n++
      for (i = 2; i <= 11; i++) { v = $i; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); f[i] = v }
      printf "%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", n, f[2], f[3], f[4], f[5], f[6], f[7], f[8], f[9], f[10], f[11]
      next
    }
    /^[[:space:]]*$/ { next }
    { if (hdr) hdr = 0 }
  ' "$1"
}

# ---------------------------------------------------------------------------------------------------
if [ "$CMD" = add ]; then
  case "$KIND" in read|range|grep|pin|skip) ;; *) echo "FAIL $GATE: --kind must be read|range|grep|pin|skip"; exit 2 ;; esac
  [ -n "$BY" ] || { echo "FAIL $GATE: --by <slice> required (P or S<n>)."; exit 2; }
  [ -n "$P" ] || { echo "FAIL $GATE: --path required."; exit 2; }
  case "$AUD" in any|qa|eng) ;; *) echo "FAIL $GATE: --aud must be any|qa|eng"; exit 2 ;; esac
  P=$(printf '%s' "$P" | sed 's#\\#/#g; s#^\./##')
  [ -f "$P" ] || { echo "FAIL $GATE: path '$P' does not exist (root-relative)."; exit 2; }
  if [ "$KIND" = read ]; then FOR="${FOR:--}"; else FOR="${FOR:-*}"; fi
  if [ "$AUD" = qa ]; then
    CODE=$(read_cfg "$CFG" '.paths.code' 'src/**')
    if printf '%s' "$P" | grep -Eq "$(glob_to_regex "$CODE")"; then
      echo "FAIL $GATE: a qa-audience row may not point into paths.code ($P) - QA is blind to the implementation (invariant 3)."; exit 2
    fi
  fi
  CH=$(wc -c < "$P" | tr -d ' '); FULL=$(tok "$CH"); LINES=$(wc -l < "$P" | tr -d ' '); [ "$LINES" -gt 0 ] || LINES=1
  case "$KIND" in
    skip) EST=0; RANGE="${RANGE:--}" ;;
    pin)  EST=$(tok "$(printf '%s' "$NOTE" | wc -c | tr -d ' ')"); RANGE="${RANGE:--}"
          [ -n "$NOTE" ] || { echo "FAIL $GATE: a pin pastes the signature/constant in --note (pointed at is not pinned)."; exit 2; } ;;
    grep) PAT=$(printf '%s' "$RANGE" | sed -E "s/[[:space:]]*[+±-]+[[:space:]]*[0-9]+[[:space:]]*$//; s/^'//; s/'$//")
          NCTX=$(printf '%s' "$RANGE" | sed -n -E 's/.*[+±-]+[[:space:]]*([0-9]+)[[:space:]]*$/\1/p'); NCTX="${NCTX:-20}"
          [ -n "$PAT" ] || { echo "FAIL $GATE: --range for grep is \"'pattern' +/-N\"."; exit 2; }
          M=$(grep -c -E -- "$PAT" "$P" 2>/dev/null || true); M="${M:-0}"
          EST=$(awk -v m="$M" -v n="$NCTX" -v ch="$CH" -v l="$LINES" -v t="$TPC" -v full="$FULL" 'BEGIN { v = m * (2*n+1) * (ch/l) * t; v = (v == int(v)) ? v : int(v)+1; if (v > full) v = full; printf "%d", v }')
          RANGE="'$PAT' +-$NCTX" ;;
    *)    R="${RANGE:--}"
          case "$R" in
            -) RCH=$CH ;;
            *-*) A=${R%-*}; B=${R#*-}; A="${A:-1}"; B="${B:-\$}"
                 RCH=$(sed -n "${A},${B}p" "$P" | wc -c | tr -d ' ') ;;
            *) RCH=$(sed -n "${R}p" "$P" | wc -c | tr -d ' ') ;;
          esac
          EST=$(tok "$RCH"); RANGE="$R" ;;
  esac
  H=$(blob "$P")
  NOTE=$(printf '%s' "$NOTE" | tr '|\n\r' '/  ')
  if ! grep -q -E '^[[:space:]]*\|[[:space:]]*kind[[:space:]]*\|' "$PLAN" 2>/dev/null; then
    { [ -f "$PLAN" ] && [ -s "$PLAN" ] && printf '\n'
      printf '## Ledger\n\n| kind | by | for | aud | path | range | hash | full | est | note |\n|---|---|---|---|---|---|---|---|---|---|\n'; } >> "$PLAN"
  fi
  printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' "$KIND" "$BY" "$FOR" "$AUD" "$P" "$RANGE" "$H" "$FULL" "$EST" "$NOTE" >> "$PLAN"
  echo "LEDGER $GATE: + $KIND $BY->$FOR [$AUD] $P $RANGE est~$(fmt "$EST") (full~$(fmt "$FULL")) @$H"
  exit 0
fi

# ---------------------------------------------------------------------------------------------------
if [ "$CMD" = verify ]; then
  STALE=0; N=0
  TAB=$(printf '\t')
  while IFS="$TAB" read -r n kind by for aud path range hash full est note; do
    [ -n "$kind" ] || continue
    if [ -n "$FOR" ]; then case "$for" in "$FOR"|'*') ;; *) continue ;; esac; fi
    N=$((N+1))
    if [ ! -f "$path" ]; then echo "STALE $GATE: row $n $kind $path (by $by for $for) - file is gone; the row is void."; STALE=$((STALE+1)); continue; fi
    NOW=$(blob "$path")
    if [ "$NOW" != "$hash" ]; then echo "STALE $GATE: row $n $kind $path $range (by $by for $for) - file changed since written (was @$hash, now @$NOW); re-read before trusting."; STALE=$((STALE+1)); fi
  done <<EOF
$(rows "$PLAN")
EOF
  [ "$STALE" -eq 0 ] || { echo "FAIL $GATE: $STALE of $N ledger row(s) stale${FOR:+ for $FOR}. Reconcile (re-read the range, rewrite the row), never assume."; exit 1; }
  echo "PASS $GATE: $N ledger row(s) current${FOR:+ for $FOR}."
  exit 0
fi

# ---------------------------------------------------------------------------------------------------
# report
rows "$PLAN" | awk -F'\t' -v only="$SLICE" '
  function fmt(n) { if (n >= 1000) return sprintf("%.1fk", n / 1000); return sprintf("%d", n) }
  function key(s,   m) { if (s == "P") return "0 000000"; if (match(s, /^S[0-9]+$/)) return sprintf("1 %06d", substr(s, 2) + 0); return "2 " s }
  {
    n = $1; kind = $2; by = $3; fr = $4; path = $6; full = $9 + 0; est = $10 + 0
    if (kind == "read") { adm[by] += est; admp[by, path] += est; slices[by] = 1 }
    else { na++; ak[na] = kind; ab[na] = by; af[na] = fr; ap[na] = path; afull[na] = full; if (fr != "*" && fr != "-") slices[fr] = 1 }
  }
  END {
    for (s in slices) {
      saved = 0; hon = 0; tot = 0; delete seen
      for (i = 1; i <= na; i++) {
        if (!(af[i] == s || (af[i] == "*" && ab[i] != s))) continue
        if ((s, ap[i]) in seen) continue
        seen[s, ap[i]] = 1; tot++
        r = admp[s, ap[i]] + 0
        if (r == 0) { saved += afull[i]; hon++ }
        else if (r < afull[i]) { saved += afull[i] - r; hon++ }
      }
      a = adm[s] + 0; d = a + saved; pct = (d > 0) ? int(saved * 100 / d + 0.5) : 0
      if (only == "" || only == s)
        printf "%s|tokens: %s admitted ~%s; saved ~%s (%d%%); ledger %d/%d honoured\n", key(s), s, fmt(a), fmt(saved), pct, hon, tot
      TA += a; TS += saved
    }
    if (only == "") {
      d = TA + TS; pct = (d > 0) ? int(TS * 100 / d + 0.5) : 0
      printf "9 zzz|tokens: plan admitted ~%s; saved ~%s (%d%%); planning ~%s (P); estimates from bytes admitted, not billed\n", fmt(TA), fmt(TS), pct, fmt(adm["P"] + 0)
    }
  }' | sort | sed 's/^[^|]*|//'
exit 0
