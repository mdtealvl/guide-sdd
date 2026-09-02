#!/usr/bin/env bash
# prose_check - spec shards are terse and structured, not blocks of prose (SDD-PROP-09).
#
# Generic gate. Measures, per shard, (a) the PARAGRAPH SHARE - words inside paragraph
# text divided by all words - and (b) the LONGEST PARAGRAPH in words. Structured text
# (list items, table cells, code, headings, definition lists) is the spec form the method
# wants; paragraph text is what the form allows only where a rule cannot be a line.
#
#   HTML shards (.html/.htm): <li> <td> <th> <dt> <dd> <pre> <code> <h1>-<h6> <caption> are
#     structured; <p> outside them, and loose text, are paragraph. A <p> nested in a
#     structured element counts as structured for the share but still counts toward the
#     longest-paragraph figure. <script>/<style>/comments are ignored.
#   Markdown shards (anything else): list / numbered / lettered / roman items, headings,
#     table rows, fenced code, and indented continuation lines are structured; other
#     non-blank lines are paragraph (consecutive lines = one paragraph).
#
# Scope = spec shards changed vs baseRef (git diff base...HEAD + working tree + untracked),
# like fold_check - a shard touched this ship must meet the bar (migrate-on-contact).
# --all checks the whole corpus. Run from the repo root (paths.spec is repo-relative).
#
# proseCheck.mode: warn (default - violations print, exit 0) | strict (violations FAIL) |
# off (gate skipped). --strict upgrades warn to strict; off always wins.
# FAIL CLOSED if git is present but the base does not resolve (exit 2) - unless --all.
#
# Exit 0 PASS/WARN, 1 FAIL (strict), 2 config/usage error. Needs jq + awk (+ git for scope).
# Usage:  sh gates/prose_check.sh [--config gates/gates.config.json] [--base <ref>] [--all] [--strict] [--report]

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/_common.sh"

GATE=prose_check
require_jq "$GATE"

CFG="gates/gates.config.json"; BASE=""; ALL=0; STRICT=0; REPORT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --config) CFG="$2"; shift 2 ;;
    --config=*) CFG="${1#--config=}"; shift ;;
    --base) BASE="$2"; shift 2 ;;
    --base=*) BASE="${1#--base=}"; shift ;;
    --all) ALL=1; shift ;;
    --strict) STRICT=1; shift ;;
    --report) REPORT=1; shift ;;
    *) echo "FAIL $GATE: unknown argument $1"; exit 2 ;;
  esac
done
[ -f "$CFG" ] || { echo "FAIL $GATE: cannot read config $CFG: no such file"; exit 2; }

SPEC_GLOBS=$(jq -r '(.paths.spec // empty) | if type=="array" then .[] else . end' "$CFG" 2>/dev/null)
[ -n "$SPEC_GLOBS" ] || SPEC_GLOBS="spec/**/*.body.md"
MODE=$(read_cfg "$CFG" '.proseCheck.mode' 'warn')
MAX_SHARE=$(read_cfg "$CFG" '.proseCheck.maxParaShare' '0.35')
MAX_PARA=$(read_cfg "$CFG" '.proseCheck.maxParaWords' '100')
MIN_WORDS=$(read_cfg "$CFG" '.proseCheck.minWords' '120')
EXCL=$(jq -r '(.proseCheck.excludeGlobs // empty) | if type=="array" then .[] else . end' "$CFG" 2>/dev/null)
MAX_SHARE_PCT=$(awk -v s="$MAX_SHARE" 'BEGIN { printf "%d", int(s * 100 + 0.5) }')

case "$MODE" in
  off) echo "SKIP $GATE: proseCheck.mode=off in config."; exit 0 ;;
  warn|strict) ;;
  *) echo "FAIL $GATE: proseCheck.mode must be warn | strict | off (got '$MODE')."; exit 2 ;;
esac
[ "$STRICT" = 1 ] && MODE=strict

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t prose_check)
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------- shard set
# Enumerate only under each glob's static prefix directory (spec corpora sit beside very
# large trees; walking the whole root is wasteful). Mirrors Expand-GlobsUnder in the .ps1.
: > "$TMP/all"
printf '%s\n' "$SPEC_GLOBS" | sed '/^$/d' | while IFS= read -r g; do
  g=$(printf '%s' "$g" | sed 's#\\#/#g')
  static=$(printf '%s' "$g" | sed 's/[*?[].*$//')
  case "$static" in
    */*) dir="${static%/*}" ;;
    *)   dir="." ;;
  esac
  [ -n "$dir" ] || dir="."
  [ -e "$dir" ] || continue
  re=$(glob_to_regex "$g")
  find "$dir" -type f 2>/dev/null | sed 's#^\./##' | grep -E "$re" >> "$TMP/all" || true
done
LC_ALL=C sort -u "$TMP/all" > "$TMP/all2"
if [ -n "$EXCL" ]; then
  ALT=$(printf '%s\n' "$EXCL" | sed '/^$/d' | while IFS= read -r g; do
    glob_to_regex "$(printf '%s' "$g" | sed 's#\\#/#g')"
  done | paste -sd '|' -)
  if [ -n "$ALT" ]; then
    grep -Ev "$ALT" "$TMP/all2" > "$TMP/all3" || true
    mv "$TMP/all3" "$TMP/all2"
  fi
fi
[ -s "$TMP/all2" ] || { echo "FAIL $GATE: no spec shards matched $(printf '%s\n' "$SPEC_GLOBS" | paste -sd ',' - | sed 's/,/, /g')"; exit 1; }

# ---------------------------------------------------------------- scope
if [ "$ALL" = 1 ]; then
  cp "$TMP/all2" "$TMP/files"; SCOPE="all shards"
elif ! command -v git >/dev/null 2>&1; then
  echo "NOTE $GATE: git unavailable - checking ALL spec shards."
  cp "$TMP/all2" "$TMP/files"; SCOPE="all shards (no git)"
else
  [ -n "$BASE" ] || BASE=$(read_cfg "$CFG" '.baseRef' 'main')
  git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null 2>&1 || {
    echo "FAIL $GATE: baseRef '$BASE' does not resolve - set baseRef to the ship base, or run with --all."
    exit 2
  }
  if git diff --name-only "$BASE...HEAD" > "$TMP/ch" 2>/dev/null || git diff --name-only "$BASE" > "$TMP/ch" 2>/dev/null; then
    git diff --name-only HEAD >> "$TMP/ch" 2>/dev/null || true
    git ls-files --others --exclude-standard >> "$TMP/ch" 2>/dev/null || true
    sed 's#\\#/#g; s/[[:space:]]*$//; s/^[[:space:]]*//; /^$/d' "$TMP/ch" | LC_ALL=C sort -u > "$TMP/ch2"
    grep -Fx -f "$TMP/ch2" "$TMP/all2" > "$TMP/files" || true
    SCOPE="changed vs $BASE"
  else
    echo "NOTE $GATE: git diff failed - checking ALL spec shards."
    cp "$TMP/all2" "$TMP/files"; SCOPE="all shards (git diff failed)"
  fi
fi

# ---------------------------------------------------------------- measure
# One awk program, two modes (-v mode=html|md). Prints: total para maxPara pct.
AWK_PROG=$(cat <<'AWKEOF'
function wc(s,   n) { n = 0; while (match(s, /[^ \t\r\n\f\v]+/)) { n++; s = substr(s, RSTART + RLENGTH) }; return n }
function closePara() { if (cur > maxPara) maxPara = cur; cur = 0 }
function indent(s,   i, c, k) { k = 0; for (i = 1; i <= length(s); i++) { c = substr(s, i, 1); if (c == " ") k++; else if (c == "\t") k += 4; else break }; return k }
function htext(seg,   w) { w = wc(seg); if (w > 0 && skipDepth == 0) { total += w; if (structDepth == 0) para += w; if (inP) cur += w } }
function htag(tag,   k, isClose, name, c, selfClose) {
  k = 2; isClose = 0
  if (substr(tag, k, 1) == "/") { isClose = 1; k++ }
  name = ""
  while (k <= length(tag)) { c = substr(tag, k, 1); if (c ~ /[A-Za-z0-9]/) { name = name c; k++ } else break }
  if (name == "") return
  name = tolower(name)
  selfClose = (substr(tag, length(tag) - 1, 2) == "/>") ? 1 : 0
  if (name == "script" || name == "style") { if (isClose) { if (skipDepth > 0) skipDepth-- } else if (!selfClose) skipDepth++; return }
  if (name == "p") {
    if (isClose) { if (inP) { closePara(); inP = 0 } }
    else if (!selfClose) { if (inP) closePara(); inP = 1 }
    return
  }
  if (inP && (name in BLOCK)) { closePara(); inP = 0 }
  if (name in STRUCT) { if (isClose) { if (structDepth > 0) structDepth-- } else if (!selfClose) structDepth++ }
}
function hline(s,   i, j, e) {
  while (length(s) > 0) {
    if (inComment) { e = index(s, "-->"); if (e == 0) return; s = substr(s, e + 3); inComment = 0; continue }
    if (inTag) { j = index(s, ">"); if (j == 0) { tagbuf = tagbuf s; return }; tagbuf = tagbuf substr(s, 1, j); s = substr(s, j + 1); inTag = 0; htag(tagbuf); tagbuf = ""; continue }
    i = index(s, "<")
    if (i == 0) { htext(s); return }
    if (i > 1) htext(substr(s, 1, i - 1))
    s = substr(s, i)
    if (substr(s, 1, 4) == "<!--") { s = substr(s, 5); inComment = 1; continue }
    inTag = 1; tagbuf = "<"; s = substr(s, 2)
  }
}
BEGIN {
  n = split("li td th dt dd pre code h1 h2 h3 h4 h5 h6 caption", a, " "); for (i = 1; i <= n; i++) STRUCT[a[i]] = 1
  n = split("p div section article ul ol dl table blockquote hr li dt dd pre h1 h2 h3 h4 h5 h6 tr td th thead tbody figure aside nav header footer details summary", b, " "); for (i = 1; i <= n; i++) BLOCK[b[i]] = 1
  total = 0; para = 0; maxPara = 0; cur = 0; structDepth = 0; skipDepth = 0; inP = 0; inTag = 0; inComment = 0; tagbuf = ""
  inFence = 0; contIndent = -1; prevBlank = 1
  FENCE = "^[ \t]*(\140\140\140|~~~)"
}
NR == 1 { if (substr($0, 1, 3) == "\357\273\277") $0 = substr($0, 4) }
mode == "html" { hline($0 "\n"); next }
{
  line = $0
  if (line ~ FENCE) { inFence = !inFence; closePara(); contIndent = -1; prevBlank = 0; next }
  if (inFence) { total += wc(line); next }
  if (line ~ /^[ \t]*$/) { closePara(); contIndent = -1; prevBlank = 1; next }
  w = wc(line)
  if (match(line, /^[ \t]*([-*+][ \t]+|[0-9]+[.)][ \t]+|[A-Za-z][.)][ \t]+|[ivxlcIVXLC]+[.)][ \t]+|#+[ \t]+|\|)/)) {
    total += w; closePara()
    t = line; sub(/^[ \t]+/, "", t)
    if (substr(t, 1, 1) == "#" || substr(t, 1, 1) == "|") contIndent = -1; else contIndent = RLENGTH
    prevBlank = 0; next
  }
  ind = indent(line)
  if (!prevBlank && contIndent >= 0 && ind >= contIndent) { total += w; next }
  total += w; para += w; cur += w; prevBlank = 0; contIndent = -1
}
END {
  if (mode == "html") { if (inP) closePara() } else closePara()
  pct = (total > 0) ? int((para * 200 + total) / (2 * total)) : 0
  printf "%d %d %d %d\n", total, para, maxPara, pct
}
AWKEOF
)

N=$(grep -c . "$TMP/files" || true)
echo "$GATE: scope=$SCOPE ($N shard(s)); thresholds share<=${MAX_SHARE_PCT}% para<=${MAX_PARA}w (share applies at >=${MIN_WORDS}w); mode=$MODE"
[ "$N" -gt 0 ] || { echo "PASS $GATE: no spec shards in scope."; exit 0; }

OVER=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in *.html|*.htm) mode=html ;; *) mode=md ;; esac
  set -- $(awk -v mode="$mode" "$AWK_PROG" "$f")
  total=$1; para=$2; mp=$3; pct=$4
  reasons=""
  if [ "$total" -ge "$MIN_WORDS" ] && [ "$pct" -gt "$MAX_SHARE_PCT" ]; then reasons="share>${MAX_SHARE_PCT}%"; fi
  if [ "$mp" -gt "$MAX_PARA" ]; then
    if [ -n "$reasons" ]; then reasons="$reasons, para>${MAX_PARA}w"; else reasons="para>${MAX_PARA}w"; fi
  fi
  if [ -n "$reasons" ]; then
    OVER=$((OVER + 1))
    printf '  OVER  %3d%%  %5dw  %s  [%s]\n' "$pct" "$mp" "$f" "$reasons"
  elif [ "$REPORT" = 1 ]; then
    note=""
    [ "$total" -lt "$MIN_WORDS" ] && note="  (share n/a: ${total}w < ${MIN_WORDS}w)"
    printf '  ok    %3d%%  %5dw  %s%s\n' "$pct" "$mp" "$f" "$note"
  fi
done < "$TMP/files"

if [ "$OVER" -eq 0 ]; then
  echo "PASS $GATE: $N shard(s) checked, 0 over threshold."
  exit 0
fi
if [ "$MODE" = strict ]; then
  echo "FAIL $GATE: $N shard(s) checked, $OVER over threshold - restructure per stages/3_spec.md 'Spec form' (decisions only; lists/tables/code; one fact per line)."
  exit 1
fi
echo "WARN $GATE: $N shard(s) checked, $OVER over threshold (mode=warn - set proseCheck.mode=strict or pass --strict to enforce)."
exit 0
