#!/usr/bin/env bash
# coverage_check — every behavioural clause-ID resolves to >=1 test-ID, both directions.
#
# Generic gate. Stack-agnostic: pure text scan parameterised by gates.config.json.
#
# Default mode  : clauses from spec shards (paths.spec); tags from test files (testGlobs).
# --plan mode   : tags from the Stage-4 test plan (a *plan*.body.md shard tagged with
#                 @clause: lines), so the plan is coverage-checked before any test exists.
#
# Clause-set scope:
#   default        = WHOLE-CORPUS — every clause in paths.spec needs a test. This is the
#                    SHIP-TIME invariant; run it with no flag at Stage 5/7.
#   --manifest <f> = PER-UNIT — restrict the clause set to the clause-IDs listed in the
#                    shard manifest <f> (one clause-ID per line, OR any text whose clause-IDs
#                    are matched by clauseIdRegex). For fast in-loop feedback on a single
#                    shard/unit; NOT a substitute for the whole-corpus ship check.
#
# A clause CB.12 is "covered" when some test/plan file contains the literal tag
# "<testClauseTag>CB.12" (default tag prefix "@clause:").
#
# PASS when clauses == tagged (no orphan clauses, no tags for unknown clauses).
# Exit 0 PASS, 1 FAIL, 2 config/usage error.
#
# Usage:
#   sh gates/coverage_check.sh [--config gates/gates.config.json] [--plan]
#      [--plan-glob 'spec/**/*plan*.body.md'] [--manifest <file>]

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/_common.sh"

GATE=coverage_check
require_jq "$GATE"

CFG="gates/gates.config.json"
PLAN=0
PLAN_GLOB='spec/**/*plan*.body.md'
MANIFEST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --config) CFG="$2"; shift 2 ;;
    --config=*) CFG="${1#--config=}"; shift ;;
    --plan) PLAN=1; shift ;;
    --plan-glob) PLAN_GLOB="$2"; shift 2 ;;
    --plan-glob=*) PLAN_GLOB="${1#--plan-glob=}"; shift ;;
    --manifest) MANIFEST="$2"; shift 2 ;;
    --manifest=*) MANIFEST="${1#--manifest=}"; shift ;;
    *) CFG="$1"; shift ;;
  esac
done

[ -f "$CFG" ] || { echo "FAIL $GATE: cannot read config $CFG: no such file"; exit 2; }

CLAUSE_RE=$(to_ere "$(read_cfg "$CFG" '.clauseIdRegex' '\b[A-Z]{2,}\.\d+\b')")
TAG_PREFIX=$(read_cfg "$CFG" '.testClauseTag' '@clause:')
SPEC_GLOB=$(read_cfg "$CFG" '.paths.spec' 'spec/**/*.body.md')

# testGlobs (array) -> newline list; fall back to paths.tests then default.
TEST_GLOBS=$(jq -r '(.testGlobs // empty) | if type=="array" then .[] else . end' "$CFG" 2>/dev/null)
if [ -z "$TEST_GLOBS" ]; then
  TEST_GLOBS=$(read_cfg "$CFG" '.paths.tests' 'tests/**')
fi

SPEC_FILES=$(expand_globs "$SPEC_GLOB")
if [ -z "$SPEC_FILES" ]; then
  echo "FAIL $GATE: no spec shards matched $SPEC_GLOB"
  exit 1
fi

# Per-unit manifest scope: clause-IDs named in the manifest restrict what we judge.
SCOPE="whole-corpus"
WANTED=""
if [ -n "$MANIFEST" ]; then
  [ -f "$MANIFEST" ] || { echo "FAIL $GATE: cannot read manifest $MANIFEST: no such file"; exit 2; }
  # one clause-ID per line, OR any clause-IDs matched by clauseIdRegex anywhere in the file.
  WANTED=$(grep -oE "$CLAUSE_RE" "$MANIFEST" 2>/dev/null | sort -u | sed '/^$/d')
  SCOPE="manifest $MANIFEST"
fi

# keep_wanted — filter "clause-id<TAB>file" lines to those whose clause-id is in WANTED.
keep_wanted() {
  if [ -z "$MANIFEST" ]; then cat; return; fi
  awk -F'\t' -v want="$WANTED" '
    BEGIN { n = split(want, a, "\n"); for (i=1;i<=n;i++) if (a[i] != "") w[a[i]] = 1 }
    NF && ($1 in w) { print }
  '
}

# Escape the tag prefix for use as a literal ERE prefix.
TAG_ESC=$(printf '%s' "$TAG_PREFIX" | sed 's/[.[\\*^$()+?{}|]/\\&/g')

# clauses: clause-id <TAB> file   (one line per declaring file)
# In manifest mode, keep_wanted restricts the clause set to the manifest's clause-IDs.
CLAUSES=$(printf '%s\n' "$SPEC_FILES" | while IFS= read -r f; do
  [ -z "$f" ] && continue
  grep -oE "$CLAUSE_RE" "$f" 2>/dev/null | while IFS= read -r cid; do
    [ -n "$cid" ] && printf '%s\t%s\n' "$cid" "$f"
  done
done | keep_wanted)

if [ "$PLAN" = 1 ]; then
  TAG_FILES=$(expand_globs "$PLAN_GLOB")
  WHAT="test plan"
else
  # shellcheck disable=SC2086
  set -- $TEST_GLOBS
  TAG_FILES=$(expand_globs "$@")
  WHAT="tests"
fi

# tags: clause-id <TAB> file  (tag prefix immediately followed by optional ws + clause)
# In manifest mode, keep_wanted scopes tags too: a tag for a real clause outside this
# manifest is another unit's concern, not a dangling tag here.
TAGS=$(printf '%s\n' "$TAG_FILES" | while IFS= read -r f; do
  [ -z "$f" ] && continue
  grep -oE "${TAG_ESC}[[:space:]]*(${CLAUSE_RE})" "$f" 2>/dev/null \
    | grep -oE "$CLAUSE_RE" | while IFS= read -r cid; do
        [ -n "$cid" ] && printf '%s\t%s\n' "$cid" "$f"
      done
done | keep_wanted)

CLAUSE_IDS=$(printf '%s\n' "$CLAUSES" | awk -F'\t' 'NF{print $1}' | sort -u | sed '/^$/d')
TAGGED_IDS=$(printf '%s\n' "$TAGS"    | awk -F'\t' 'NF{print $1}' | sort -u | sed '/^$/d')

# Set differences via awk (POSIX sh: no process substitution — dash is /bin/sh on Debian/Ubuntu).
ORPHANS=$(printf '%s\n' "$CLAUSE_IDS" | awk -v t="$TAGGED_IDS" 'BEGIN { n = split(t, a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") s[a[i]] = 1 } NF && !($0 in s)')
UNKNOWN=$(printf '%s\n' "$TAGGED_IDS" | awk -v t="$CLAUSE_IDS" 'BEGIN { n = split(t, a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") s[a[i]] = 1 } NF && !($0 in s)')

N_CLAUSE=$(printf '%s\n' "$CLAUSE_IDS" | sed '/^$/d' | wc -l | tr -d ' ')
N_ORPHAN=$(printf '%s\n' "$ORPHANS" | sed '/^$/d' | grep -c . || true)
N_UNKNOWN=$(printf '%s\n' "$UNKNOWN" | sed '/^$/d' | grep -c . || true)

if [ "$N_ORPHAN" -eq 0 ] && [ "$N_UNKNOWN" -eq 0 ]; then
  echo "PASS $GATE ($WHAT, $SCOPE): $N_CLAUSE clauses, all covered."
  exit 0
fi

echo "FAIL $GATE ($WHAT, $SCOPE): $N_ORPHAN uncovered clause(s), $N_UNKNOWN dangling tag(s)."
# join lines with ", " (Python ", ".join), not paste's alternating delimiters.
join_comma() { awk 'NR==1{printf "%s",$0; next}{printf ", %s",$0}'; }

printf '%s\n' "$ORPHANS" | sed '/^$/d' | while IFS= read -r cid; do
  WHERE=$(printf '%s\n' "$CLAUSES" | awk -F'\t' -v c="$cid" '$1==c{print $2}' | sort -u | join_comma)
  echo "  UNCOVERED $cid  (declared in $WHERE)"
done
printf '%s\n' "$UNKNOWN" | sed '/^$/d' | while IFS= read -r cid; do
  WHERE=$(printf '%s\n' "$TAGS" | awk -F'\t' -v c="$cid" '$1==c{print $2}' | sort -u | join_comma)
  echo "  UNKNOWN-CLAUSE $cid  (tagged in $WHERE)"
done
exit 1
