#!/usr/bin/env bash
# link_check — every spec cross-ref/href resolves to a real anchor/shard.
#
# Generic gate. Content-only spec shards keep the parse trivial, so link_check is a
# pure set operation: collect the anchor set (declared anchors UNION clause-IDs) across
# all shards, then assert every internal cross-ref points into it. Skips http/mailto.
#
# A clause-ID is DECLARED only when it appears on an anchored line (id=, name=, {#..},
# <!-- §..) or a heading / bold-or-list definition line; bare prose occurrences are
# citations that must resolve. SAFETY FALLBACK: if nothing is anchored, treat all
# clause-IDs as declared and print a NOTE.
#
# Exit 0 PASS, 1 FAIL, 2 config error.
# Usage:  sh gates/link_check.sh [--config gates/gates.config.json]

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/_common.sh"

GATE=link_check
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

CLAUSE_RAW=$(read_cfg "$CFG" '.clauseIdRegex' '\b[A-Z]{2,}\.\d+\b')
CLAUSE_RE=$(to_awk_ere "$CLAUSE_RAW")        # awk has no \b; strip it, enforce via wmatch
CLAUSE_WB=$(had_word_boundary "$CLAUSE_RAW") # 1 if \b boundaries must be enforced
SPEC_GLOB=$(read_cfg "$CFG" '.paths.spec' 'spec/**/*.body.md')

SHARDS=$(expand_globs "$SPEC_GLOB")
if [ -z "$SHARDS" ]; then
  echo "FAIL $GATE: no spec shards matched $SPEC_GLOB"
  exit 1
fi

N_SHARDS=$(printf '%s\n' "$SHARDS" | sed '/^$/d' | wc -l | tr -d ' ')

US=$(printf '\037')   # unit separator for structured awk output

# One awk pass over every shard. awk emits, on stdout:
#   NOTE                                   (safety fallback fired)
#   BROKEN<US>src<US>ref<US>why            (one per unresolved reference, Python order)
# Shards are passed as file args so FILENAME gives the source path per line.
# SQ is the single-quote char, passed in via -v SQ=\' so the awk program body needs
# no embedded single quotes; quote-bearing regexes are built dynamically from SQ.
RESULT=$(awk -v clause="$CLAUSE_RE" -v wb="$CLAUSE_WB" -v US="$US" -v SQ=\' '
function basename(p,   n, a) { n = split(p, a, "/"); return a[n] }

# isword(c): is c a word char [A-Za-z0-9_]?
function isword(c) { return (c ~ /[A-Za-z0-9_]/) }

# wmatch(s, re, off): find the next match of re in s starting at 1-based off, honouring
# word-boundary semantics when wb==1 (awk lacks \b). Sets globals WSTART (absolute, or 0
# if none) and WLEN. Returns WSTART.
function wmatch(s, re, off,   tail, base, ms, me, before, after) {
  base = off
  while (1) {
    tail = substr(s, base)
    if (!match(tail, re)) { WSTART = 0; WLEN = 0; return 0 }
    ms = base + RSTART - 1            # absolute start (1-based)
    me = ms + RLENGTH - 1            # absolute end
    if (wb != 1) { WSTART = ms; WLEN = RLENGTH; return WSTART }
    before = (ms > 1) ? substr(s, ms - 1, 1) : ""
    after  = (me < length(s)) ? substr(s, me + 1, 1) : ""
    if ((before == "" || !isword(before)) && (after == "" || !isword(after))) {
      WSTART = ms; WLEN = RLENGTH; return WSTART
    }
    # boundary failed; advance past this start to find the next candidate
    base = ms + 1
    if (base > length(s)) { WSTART = 0; WLEN = 0; return 0 }
  }
}

# collect every clause match (boundary-aware) of re in s into arr[] + global allclauses[].
function collect(s, re, arr,   off, m) {
  off = 1
  while (wmatch(s, re, off) > 0) {
    m = substr(s, WSTART, WLEN)
    arr[m] = 1
    allclauses[m] = 1
    off = WSTART + (WLEN > 0 ? WLEN : 1)
  }
}

BEGIN {
  # Dynamic, quote-aware patterns (double OR single quoted attribute values).
  q = "(\"[^\"]*\"|" SQ "[^" SQ "]*" SQ ")"   # a quoted value
  idname_re = "(id|name)[ \t]*=[ \t]*" q
  href_re   = "href[ \t]*=[ \t]*" q
}

{
  line = $0
  name = basename(FILENAME)
  shardseen[name] = 1

  # ---- declared anchors on this line (4 families) -> anchors[], pershard[] ----
  # id="..."  /  name="..."  (or single-quoted)
  rest = line
  while (match(rest, idname_re)) {
    seg = substr(rest, RSTART, RLENGTH)
    val = seg
    sub("^(id|name)[ \t]*=[ \t]*(\"|" SQ ")", "", val)
    sub("(\"|" SQ ")$", "", val)
    if (val != "") { anchors[val] = 1; pershard[name SUBSEP val] = 1 }
    rest = substr(rest, RSTART + RLENGTH)
  }
  # {#anchor}  (anchor = non-} non-space)
  rest = line
  while (match(rest, /\{#[^} \t]+\}/)) {
    seg = substr(rest, RSTART, RLENGTH)
    val = seg; sub(/^\{#/, "", val); sub(/\}$/, "", val)
    if (val != "") { anchors[val] = 1; pershard[name SUBSEP val] = 1 }
    rest = substr(rest, RSTART + RLENGTH)
  }
  # <!-- §anchor   (anchor = non-space run)
  rest = line
  while (match(rest, /<!--[ \t]*§[ \t]*[^ \t]+/)) {
    seg = substr(rest, RSTART, RLENGTH)
    val = seg; sub(/^<!--[ \t]*§[ \t]*/, "", val)
    if (val != "") { anchors[val] = 1; pershard[name SUBSEP val] = 1 }
    rest = substr(rest, RSTART + RLENGTH)
  }

  # is this an anchored line? (any of the 4 families present)
  is_anchored = (line ~ idname_re) ||
                (line ~ /\{#[^} \t]+\}/) ||
                (line ~ /<!--[ \t]*§[ \t]*[^ \t]+/)
  is_heading = (line ~ /^[ \t]*#{1,6}[ \t]/)
  is_defn    = (line ~ ("^[ \t]*[-*]?[ \t]*[*]*" clause))

  # clause-IDs on this line
  delete lc
  collect(line, clause, lc)
  for (c in lc) { anchors[c] = 1; pershard[name SUBSEP c] = 1; cites[++ncite] = name SUBSEP c }
  if (is_anchored || is_heading || is_defn) for (c in lc) declared[c] = 1

  # ---- hrefs on this line (2 families), in encounter order ----
  # Markdown ](target)   target = run of non-) non-space
  rest = line
  while (match(rest, /\][ \t]*\([ \t]*[^) \t]+[ \t]*\)/)) {
    seg = substr(rest, RSTART, RLENGTH)
    tgt = seg
    sub(/^\][ \t]*\([ \t]*/, "", tgt)
    sub(/[ \t]*\)$/, "", tgt)
    hrefs[++nhref] = name SUBSEP tgt
    rest = substr(rest, RSTART + RLENGTH)
  }
  # HTML href="target"  (or single-quoted)
  rest = line
  while (match(rest, href_re)) {
    seg = substr(rest, RSTART, RLENGTH)
    tgt = seg
    sub("^href[ \t]*=[ \t]*(\"|" SQ ")", "", tgt)
    sub("(\"|" SQ ")$", "", tgt)
    hrefs[++nhref] = name SUBSEP tgt
    rest = substr(rest, RSTART + RLENGTH)
  }
}

END {
  # SAFETY FALLBACK: nothing declared -> all clause-IDs declared.
  nd = 0; for (d in declared) nd++
  if (nd == 0) { for (c in allclauses) declared[c] = 1; print "NOTE" }

  # ordered shard list (first-seen across hrefs then cites — but per-shard grouping
  # below reproduces the Python order: for s in shards (sorted), hrefs then cites.
  nsh = 0
  for (i = 1; i <= nhref; i++) { split(hrefs[i], a, SUBSEP); if (!(a[1] in so)) { so[a[1]] = ++nsh; ord[nsh] = a[1] } }
  for (i = 1; i <= ncite; i++) { split(cites[i], a, SUBSEP); if (!(a[1] in so)) { so[a[1]] = ++nsh; ord[nsh] = a[1] } }

  for (oi = 1; oi <= nsh; oi++) {
    s = ord[oi]
    for (i = 1; i <= nhref; i++) {
      split(hrefs[i], a, SUBSEP); if (a[1] != s) continue
      href = a[2]
      if (href ~ /^(https?:\/\/|mailto:|tel:)/) continue
      hi = index(href, "#")
      if (hi > 0) { fp = substr(href, 1, hi - 1); frag = substr(href, hi + 1) }
      else        { fp = href; frag = "" }
      if (fp != "") {
        tname = basename(fp)
        if (!(tname in shardseen)) { print "BROKEN" US s US href US "no such shard"; continue }
        if (frag != "" && !((tname SUBSEP frag) in pershard)) print "BROKEN" US s US href US "shard has no anchor #" frag
      } else if (frag != "") {
        if (!(frag in anchors)) print "BROKEN" US s US href US "no anchor #" frag " anywhere"
      }
    }
    for (i = 1; i <= ncite; i++) {
      split(cites[i], a, SUBSEP); if (a[1] != s) continue
      cid = a[2]
      if (!(cid in declared)) print "BROKEN" US s US cid US "cited clause-ID not declared (no anchored declaration found)"
    }
  }
}
' $(printf '%s ' $SHARDS))

if printf '%s\n' "$RESULT" | grep -q '^NOTE$'; then
  echo "NOTE $GATE: no anchored clause declarations found; treating all clause-IDs as declared."
fi

BROKEN=$(printf '%s\n' "$RESULT" | grep '^BROKEN' || true)
N_BROKEN=$(printf '%s\n' "$BROKEN" | sed '/^$/d' | grep -c . || true)

if [ "$N_BROKEN" -eq 0 ]; then
  echo "PASS $GATE: $N_SHARDS shard(s), all cross-refs resolve."
  exit 0
fi

echo "FAIL $GATE: $N_BROKEN unresolved reference(s):"
printf '%s\n' "$BROKEN" | sed '/^$/d' | while IFS= read -r row; do
  src=$(printf '%s' "$row" | awk -F"$US" '{print $2}')
  ref=$(printf '%s' "$row" | awk -F"$US" '{print $3}')
  why=$(printf '%s' "$row" | awk -F"$US" '{print $4}')
  echo "  $src: '$ref' — $why"
done
exit 1
