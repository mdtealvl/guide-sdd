#!/usr/bin/env bash
# fold_check — every clause changed in this ship carries a resolving provenance pin.
#
# Generic, MODE-BLIND gate (works identically for Mode A external tracker and Mode B
# on-disk backlog). Enforces the fold-on-ship invariant at ship time: every spec clause
# touched by this change is pinned (§X per <unit-id>, YYYY-MM-DD) and the unit-id resolves.
#
# Resolution of <unit-id>:
#   * Mode B (default): a backlog file named <unit-id>* exists under backlogRoot.
#   * Mode A: if foldCheck.resolveCmd is set ({unit} substituted) it is run; exit 0 = resolves.
#     Offline / no resolver -> degrades to "syntactically valid unit-id" + a NOTE.
#
# Scope = spec shards changed since baseRef (git diff). For each NEW or CHANGED clause
# line, require a pin on it or the line directly after.
#
# FAIL CLOSED if git present but base unresolvable (exit 2). git-absent -> all shards + NOTE.
# Exit 0 PASS, 1 FAIL, 2 config/usage error.
#
# --strict: when a resolver IS configured (foldCheck.resolveCmd) but ERRORS or returns
# non-zero, treat the unit as UNRESOLVED (FAIL) instead of degrading to "syntactic pin +
# NOTE". CI MUST run with --strict so an offline/broken resolver cannot fail open. Without
# --strict the degrade-with-NOTE convenience is kept (local/offline). The "no resolver
# configured at all" syntactic-only path is unchanged in both modes.
#
# Usage:  sh gates/fold_check.sh [--config gates/gates.config.json] [--base <ref>] [--strict]

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/_common.sh"

GATE=fold_check
require_jq "$GATE"

CFG="gates/gates.config.json"
BASE=""
STRICT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --config) CFG="$2"; shift 2 ;;
    --config=*) CFG="${1#--config=}"; shift ;;
    --base) BASE="$2"; shift 2 ;;
    --base=*) BASE="${1#--base=}"; shift ;;
    --strict) STRICT=1; shift ;;
    *) BASE="$1"; shift ;;
  esac
done

[ -f "$CFG" ] || { echo "FAIL $GATE: cannot read config $CFG: no such file"; exit 2; }

[ -n "$BASE" ] || BASE=$(read_cfg "$CFG" '.baseRef' 'main')

GIT_OK=0
command -v git >/dev/null 2>&1 && GIT_OK=1

# base_state: git missing -> 'absent'; else base must resolve or FAIL CLOSED (exit 2).
if [ "$GIT_OK" = 1 ]; then
  git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null 2>&1 || {
    echo "FAIL $GATE: baseRef '$BASE' does not resolve — set baseRef to the ship base."
    exit 2
  }
fi

SPEC_GLOB=$(read_cfg "$CFG" '.paths.spec' 'spec/**/*.body.md')
CLAUSE_RAW=$(read_cfg "$CFG" '.clauseIdRegex' '\b[A-Z]{2,}\.\d+\b')
CLAUSE_RE=$(to_awk_ere "$CLAUSE_RAW")          # awk: \b stripped, boundary via wmatch
CLAUSE_WB=$(had_word_boundary "$CLAUSE_RAW")
UNIT_RE=$(to_awk_ere "$(read_cfg "$CFG" '.unitIdRegex' '\b[A-Z]+-\d+\b')")
# pin: \bper\s+(<unit>)\s*,\s*\d{4}-\d{2}-\d{2}  (leading \b dropped for awk; 'per' is
# preceded by '(' or whitespace in real pins, so the boundary is implied by context).
PIN_RE="per[[:space:]]+(${UNIT_RE})[[:space:]]*,[[:space:]]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]"

# All spec shards (normalised, forward-slashed).
ALL_SHARDS=$(expand_globs "$SPEC_GLOB")

# changed_spec_files: shards changed vs base; fall back to ALL shards if git absent.
if [ "$GIT_OK" = 0 ]; then
  echo "NOTE $GATE: git unavailable — checking ALL spec shards."
  FILES="$ALL_SHARDS"
else
  OUT=$(git diff --name-only "$BASE...HEAD" 2>/dev/null)
  if [ $? -ne 0 ]; then
    OUT=$(git diff --name-only "$BASE" 2>/dev/null)
    if [ $? -ne 0 ]; then
      echo "NOTE $GATE: git unavailable — checking ALL spec shards."
      OUT=""
      FILES="$ALL_SHARDS"
      GITFELL=1
    fi
  fi
  if [ "${GITFELL:-0}" != 1 ]; then
    # intersect changed with all shards (both forward-slashed, leading ./ stripped)
    CHANGED=$(printf '%s\n' "$OUT" | sed 's#^\./##;s/[[:space:]]*$//;s/^[[:space:]]*//' | sed '/^$/d' | sort -u)
    # intersection via awk (POSIX sh: no process substitution — dash is /bin/sh on Debian/Ubuntu)
    FILES=$(printf '%s\n' "$CHANGED" | awk -v t="$ALL_SHARDS" 'BEGIN { n = split(t, a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") s[a[i]] = 1 } NF && ($0 in s)' | sort -u)
  fi
fi

FILES=$(printf '%s\n' "$FILES" | sed '/^$/d')
if [ -z "$FILES" ]; then
  echo "PASS $GATE: no spec shards changed this ship."
  exit 0
fi

N_FILES=$(printf '%s\n' "$FILES" | sed '/^$/d' | wc -l | tr -d ' ')

# Scan each changed shard: for each clause-ID on a line, the pin may sit on that line
# or the one directly after. Emit unpinned clauses and the set of seen unit-ids.
WORK=$(printf '%s\n' "$FILES" | while IFS= read -r f; do
  [ -z "$f" ] && continue
  awk -v clause="$CLAUSE_RE" -v wb="$CLAUSE_WB" -v pin="$PIN_RE" -v file="$f" '
  function isword(c) { return (c ~ /[A-Za-z0-9_]/) }
  # boundary-aware match (awk lacks \b); sets WSTART/WLEN.
  function wmatch(s, re, off,   tail, base, ms, me, before, after) {
    base = off
    while (1) {
      tail = substr(s, base)
      if (!match(tail, re)) { WSTART = 0; WLEN = 0; return 0 }
      ms = base + RSTART - 1; me = ms + RLENGTH - 1
      if (wb != 1) { WSTART = ms; WLEN = RLENGTH; return WSTART }
      before = (ms > 1) ? substr(s, ms - 1, 1) : ""
      after  = (me < length(s)) ? substr(s, me + 1, 1) : ""
      if ((before == "" || !isword(before)) && (after == "" || !isword(after))) {
        WSTART = ms; WLEN = RLENGTH; return WSTART
      }
      base = ms + 1
      if (base > length(s)) { WSTART = 0; WLEN = 0; return 0 }
    }
  }
  { lines[NR] = $0 }
  END {
    for (i = 1; i <= NR; i++) {
      line = lines[i]
      window = line ((i+1) <= NR ? lines[i+1] : "")
      off = 1
      while (wmatch(line, clause, off) > 0) {
        cid = substr(line, WSTART, WLEN)
        if (match(window, pin)) {
          # the matched pin segment; re-extract the unit-id (group 1) after "per ".
          seg = substr(window, RSTART, RLENGTH)
          if (match(seg, /per[[:space:]]+/)) {
            uid = substr(seg, RSTART + RLENGTH)
            sub(/[[:space:]]*,.*$/, "", uid)
            print "UNIT\t" uid
          }
        } else {
          print "UNPIN\t" file "\t" cid
        }
        off = WSTART + (WLEN > 0 ? WLEN : 1)
      }
    }
  }' "$f"
done)

UNPINNED=$(printf '%s\n' "$WORK" | grep '^UNPIN' || true)
SEEN_UNITS=$(printf '%s\n' "$WORK" | grep '^UNIT' | cut -f2 | sort -u | sed '/^$/d')

# Resolve each seen unit-id.
RESOLVE_CMD=$(read_cfg "$CFG" '.foldCheck.resolveCmd' '')
BACKLOG_ROOT=$(read_cfg "$CFG" '.foldCheck.backlogRoot' 'backlog')

UNRESOLVED=""
if [ -n "$SEEN_UNITS" ]; then
  while IFS= read -r unit; do
    [ -z "$unit" ] && continue
    if [ -n "$RESOLVE_CMD" ]; then
      cmd=$(printf '%s' "$RESOLVE_CMD" | sed "s/{unit}/$unit/g")
      if sh -c "$cmd" >/dev/null 2>&1; then
        :
      elif [ "$STRICT" = 1 ]; then
        # Strict: a configured resolver that errors / returns non-zero is UNRESOLVED.
        echo "FAIL $GATE: resolveCmd errored for $unit — strict mode treats this as unresolved."
        UNRESOLVED="$UNRESOLVED$unit
"
      else
        # Non-strict: degrade to the syntactic pin + NOTE (local/offline convenience).
        echo "NOTE $GATE: resolveCmd failed for $unit — accepting syntactic pin."
      fi
    elif [ -d "$BACKLOG_ROOT" ]; then
      # Mode B: a file/dir named <unit>* directly under backlogRoot.
      if ls -d "$BACKLOG_ROOT/$unit"* >/dev/null 2>&1; then
        :
      else
        UNRESOLVED="$UNRESOLVED$unit
"
      fi
    else
      echo "NOTE $GATE: no resolver and no $BACKLOG_ROOT/ — accepting syntactic pin for $unit."
    fi
  done <<EOF
$SEEN_UNITS
EOF
fi

UNRESOLVED=$(printf '%s' "$UNRESOLVED" | sed '/^$/d')

N_UNPIN=$(printf '%s\n' "$UNPINNED" | sed '/^$/d' | grep -c . || true)
N_UNRES=$(printf '%s\n' "$UNRESOLVED" | sed '/^$/d' | grep -c . || true)

if [ "$N_UNPIN" -eq 0 ] && [ "$N_UNRES" -eq 0 ]; then
  echo "PASS $GATE: $N_FILES changed shard(s); all clauses pinned and resolved."
  exit 0
fi

echo "FAIL $GATE: $N_UNPIN unpinned clause(s), $N_UNRES unresolved unit(s)."
printf '%s\n' "$UNPINNED" | sed '/^$/d' | while IFS="$(printf '\t')" read -r _tag file cid; do
  echo "  UNPINNED $cid  in $file  (add: (§… per <unit-id>, YYYY-MM-DD))"
done
printf '%s\n' "$UNRESOLVED" | sed '/^$/d' | while IFS= read -r unit; do
  echo "  UNRESOLVED-UNIT $unit  (no backlog file / tracker entry)"
done
exit 1
