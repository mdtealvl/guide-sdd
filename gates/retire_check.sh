#!/usr/bin/env sh
# retire_check - a retired name must not survive in the spec, the tests or the docs.
#
# A unit that renames or retires a name (type, method, event token, state) leaves references to the
# old one behind in spec tables, test titles and docs. Validation finds them as LOW findings, one fix
# round each. This gate finds them with git grep instead.
#
# Retired names are the union of:
#   * gates/.retired (retireCheck.file): one `old -> new` per line (`old` alone is fine; blank lines and
#     # comments are skipped). Explicit names need no other evidence.
#   * auto-derived: a token matching retireCheck.identRegex that is in a REMOVED line of
#     `git diff {base} -- paths.code`, occurs in paths.code at {base}, and has 0 whole-word
#     occurrences in paths.code now (the working tree: HEAD plus uncommitted work).
# retireCheck.allow names are never retired.
#
# A hit is a whole-word occurrence of a retired name, now, in paths.spec, testGlobs or
# retireCheck.extraGlobs, minus retireCheck.excludeGlobs, minus lines matching
# retireCheck.tombstoneRegex (a lifecycle marker: [REMOVED 2026-06-24 ...]). Each prints as
# `file:line: name` (`name -> new` when declared).
#
# mode: warn (default: hits print as WARN, exit 0) | strict (hits FAIL) | off. The retireCheck section
# absent = "not configured" PASS.
# {base}: --base, else gates/.frozen, else config baseRef. Cost: one git diff and a few git grep calls.
#
# Exit 0 PASS, 1 FAIL, 2 config/usage error.
# Usage:  sh gates/retire_check.sh [--base <sha>] [--config gates/gates.config.json]

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/_common.sh"

GATE=retire_check
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

if [ "$(jq -r 'if .retireCheck == null then "no" else "yes" end' "$CFG" 2>/dev/null)" != yes ]; then
  echo "PASS $GATE: not configured (retireCheck section absent) - retired names are unchecked."
  exit 0
fi
MODE=$(read_cfg "$CFG" '.retireCheck.mode' 'warn')
case "$MODE" in
  off) echo "PASS $GATE: mode off."; exit 0 ;;
  warn|strict) ;;
  *) echo "FAIL $GATE: retireCheck.mode must be warn, strict or off (got '$MODE')"; exit 2 ;;
esac

TOP=$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null) || { echo "FAIL $GATE: not inside a git work tree"; exit 2; }
GD=$(git -C "$HERE" rev-parse --show-prefix | sed 's#/$##'); [ -n "$GD" ] || GD="."
cd "$TOP" || exit 2

[ -n "$BASE" ] || BASE=$(frozen_sha "$GD")
[ -n "$BASE" ] || BASE=$(read_cfg "$CFG" '.baseRef' 'main')
if ! git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null 2>&1; then
  if [ "$MODE" = warn ]; then echo "PASS $GATE: no base resolvable - skipped"; exit 0; fi
  echo "FAIL $GATE: base '$BASE' does not resolve - pass the QA-frozen SHA."; exit 2
fi

IDENT=$(read_cfg "$CFG" '.retireCheck.identRegex' '_*[A-Za-z0-9]+_[A-Za-z0-9_]+|[A-Za-z0-9]*[a-z][A-Za-z0-9]*[A-Z][A-Za-z0-9_]*')
TOMB=$(read_cfg "$CFG" '.retireCheck.tombstoneRegex' '\[(DEPRECATED|SUPERSEDED|MOVED|REMOVED) [0-9]{4}-[0-9]{2}-[0-9]{2}')
RFILE=$(read_cfg "$CFG" '.retireCheck.file' "$GD/.retired")

TMP=$(mktemp -d) || { echo "FAIL $GATE: cannot make a temp dir"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
for _re in "$IDENT" "$TOMB"; do
  git grep --no-index -q -E -e "$_re" -- "$GD/_common.sh" >/dev/null 2>&1
  [ $? -le 1 ] || { echo "FAIL $GATE: '$_re' is not a regex git grep -E accepts (retireCheck.identRegex / tombstoneRegex)"; exit 2; }
done

CODE=$(cfg_list "$CFG" '.paths.code' | glob_specs)
[ -n "$CODE" ] || CODE=$(printf '%s\n' 'src/**' | glob_specs)

# 1. explicit names -> $TMP/names.tsv (name TAB new)
: > "$TMP/names.tsv"
if [ -f "$RFILE" ]; then
  tr -d '\r' < "$RFILE" | awk '
    /^[ \t]*(#|$)/ { next }
    { line = $0; nw = ""
      if (match(line, /[ \t]*->[ \t]*/)) { nw = substr(line, RSTART + RLENGTH); line = substr(line, 1, RSTART - 1) }
      gsub(/^[ \t]+|[ \t]+$/, "", line); gsub(/^[ \t]+|[ \t]+$/, "", nw)
      if (line != "" && line !~ /[ \t]/) print line "\t" nw }' > "$TMP/names.tsv"
fi

# 2. auto-derived: removed-line tokens present at the base and gone now
eval git diff --no-renames --no-color -U0 '"$BASE"' -- $CODE 2>/dev/null | tr -d '\r' | awk '
  /^diff --git/ { hdr = 1; next }
  /^@@/ { hdr = 0; next }
  !hdr && /^-/ { print substr($0, 2) }' | grep -oE "$IDENT" | awk 'length($0) >= 4' | sort -u > "$TMP/cand"
if [ -s "$TMP/cand" ]; then
  eval git grep -h -o -w -F -f '"$TMP/cand"' '"$BASE"' -- $CODE 2>/dev/null | sort -u > "$TMP/atbase"
  : > "$TMP/atnow"
  if [ -s "$TMP/atbase" ]; then
    eval git grep -h -o -w -F -f '"$TMP/atbase"' --untracked -- $CODE 2>/dev/null | sort -u > "$TMP/atnow"
  fi
  awk 'FILENAME == ARGV[1] { a[$0] = 1; next } !($0 in a) { print $0 "\t" }' "$TMP/atnow" "$TMP/atbase" >> "$TMP/names.tsv"
fi

# 3. drop allowed names, dedupe (an explicit entry, listed first, wins)
cfg_list "$CFG" '.retireCheck.allow' > "$TMP/allow"
awk -F'\t' 'FILENAME == ARGV[1] { a[$0] = 1; next } !($1 in a) && !($1 in s) { s[$1] = 1; print }' "$TMP/allow" "$TMP/names.tsv" > "$TMP/n2"
mv "$TMP/n2" "$TMP/names.tsv"
if [ ! -s "$TMP/names.tsv" ]; then echo "PASS $GATE: no retired names vs $BASE."; exit 0; fi
cut -f1 "$TMP/names.tsv" > "$TMP/names.txt"

# 4. whole-word hits in spec, tests and extra globs, minus tombstone lines
SCOPE=$( { cfg_list "$CFG" '.paths.spec'; cfg_list "$CFG" '.testGlobs'; cfg_list "$CFG" '.retireCheck.extraGlobs'; } | glob_specs)
[ -n "$SCOPE" ] || { echo "PASS $GATE: no paths.spec, testGlobs or extraGlobs to check."; exit 0; }
SCOPE="$SCOPE$(cfg_list "$CFG" '.retireCheck.excludeGlobs' | glob_specs exclude)$(printf '%s\n' "$RFILE" | glob_specs exclude)"
eval git grep -I --untracked -n -o -w -F -f '"$TMP/names.txt"' -- $SCOPE 2>/dev/null | tr -d '\r' | sort -u > "$TMP/hits"
eval git grep -I --untracked -n -E -e '"$TOMB"' -- $SCOPE 2>/dev/null | cut -d: -f1,2 | sort -u > "$TMP/tomb"
awk -F: 'FILENAME == ARGV[1] { t[$1 ":" $2] = 1; next } !(($1 ":" $2) in t)' "$TMP/tomb" "$TMP/hits" > "$TMP/live"

N=$(wc -l < "$TMP/live" | tr -d ' ')
if [ "$N" -eq 0 ]; then
  echo "PASS $GATE: no retired name survives ($(wc -l < "$TMP/names.tsv" | tr -d ' ') checked vs $BASE)."
  exit 0
fi
if [ "$MODE" = strict ]; then V=FAIL; else V=WARN; fi
echo "$V $GATE: $N reference(s) to a retired name (a name that lives on goes in retireCheck.allow):"
sort -t: -k1,1 -k2,2n "$TMP/live" | awk -F: -v f="$TMP/names.tsv" '
  BEGIN { while ((getline l < f) > 0) { split(l, p, "\t"); nw[p[1]] = p[2] } }
  { printf "  %s:%s: %s%s\n", $1, $2, $3, (nw[$3] != "" ? " -> " nw[$3] : "") }'
if [ "$MODE" = strict ]; then exit 1; fi
echo "PASS $GATE: warn mode - not enforced (retireCheck.mode = strict fails the gate)."
exit 0
