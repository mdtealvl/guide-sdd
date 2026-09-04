#!/usr/bin/env bash
# structure_check - the PM-approved member-level structure diagram (classes, properties, methods) holds.
#
# Generic gate over STRUCTURE SHARDS: content-only spec shards (structureGlobs, default
# **/*.structure.body.md) holding fenced ```mermaid classDiagram``` blocks at MEMBER level. A transient
# shard is a DELTA under headings "Added" / "Changed" / "Removed"; a canonical shard is the area's
# current state (no headings needed). The mermaid text is the source; the drawing derives.
#
# Modes:
#   --plan            shape only (Stage 3 / 4b close): every shard in scope has >=1 classDiagram with
#                     >=1 class carrying >=1 member; a class with no members is WARNed (an outline in
#                     disguise, or an existing class named for context). No code is read.
#   --frozen [sha]    the deviation guard (Stage 6 exit; Stage-7 pre-fold pass): no structureGlobs path
#                     differs from <sha> in the WORKING TREE (committed, staged, unstaged, untracked;
#                     renames not collapsed). <sha> omitted: gates/.frozen. Base must resolve and be an
#                     ancestor of HEAD (exit 2). The PM approved the diagram; it changes only by
#                     [NEEDS-PO:structure] -> PM decision -> PO replaces wholesale -> re-freeze.
#   (default)         forward trace (Stage 7): every class and member named under Added / Changed / an
#                     unlabelled block resolves to an identifier under paths.code (git grep -w, tracked
#                     + untracked); a class under Removed must be ABSENT (FAIL); a removed member still
#                     present is WARNed (the name may live on in another class). FAIL names
#                     <shard>: <Class>.<member>. The reverse trace - no public member in the diff that
#                     the diagram lacks - is a judgement call: Stage-7 Validation lens 2a.
#   --changed <base>  limit --plan / default scope to shards that differ from <base> (+ untracked).
#
# Identifier match is by NAME (Class or member), stack-agnostic: it proves "every planned member
# exists somewhere in the code tree", not that it hangs off the planned class.
# Exit 0 PASS, 1 FAIL, 2 config/usage error.
# Usage: sh gates/structure_check.sh [--plan | --frozen [sha]] [--changed <base>] [--config gates/gates.config.json]

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/_common.sh"

GATE=structure_check
require_git "$GATE"
require_jq "$GATE"

MODE=trace; BASE=""; CHANGED=""; CFG="gates/gates.config.json"
while [ $# -gt 0 ]; do
  case "$1" in
    --plan) MODE=plan; shift ;;
    --frozen) MODE=frozen; shift; if [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; then BASE="$1"; shift; fi ;;
    --frozen=*) MODE=frozen; BASE="${1#--frozen=}"; shift ;;
    --changed) CHANGED="$2"; shift 2 ;;
    --changed=*) CHANGED="${1#--changed=}"; shift ;;
    --config) CFG="$2"; shift 2 ;;
    --config=*) CFG="${1#--config=}"; shift ;;
    *) echo "FAIL $GATE: unknown argument '$1'"; exit 2 ;;
  esac
done

[ -f "$CFG" ] || { echo "FAIL $GATE: cannot read config $CFG: no such file"; exit 2; }
CFG=$(CDPATH= cd -- "$(dirname -- "$CFG")" && pwd)/$(basename -- "$CFG")

TOP=$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null) || { echo "FAIL $GATE: not inside a git work tree"; exit 2; }
GD=$(git -C "$HERE" rev-parse --show-prefix | sed 's#/$##'); [ -n "$GD" ] || GD="."
cd "$TOP" || exit 2

GLOBS=$(jq -r '(.structureGlobs // empty) | if type=="array" then .[] else . end' "$CFG" 2>/dev/null)
[ -n "$GLOBS" ] || GLOBS='**/*.structure.body.md'

# ---------------------------------------------------------------------------------------------------
# --frozen: the deviation guard (same working-tree diff as test_edit_ban, over structureGlobs).
if [ "$MODE" = frozen ]; then
  BASE_SRC="argument"
  if [ -z "$BASE" ] && [ -f "$GD/.frozen" ]; then
    BASE=$(sed -n 's/^sha=\([0-9a-fA-F]*\).*/\1/p' "$GD/.frozen" | head -1); BASE_SRC="$GD/.frozen"
  fi
  [ -n "$BASE" ] || { echo "FAIL $GATE: no base - pass the QA-frozen SHA or run gates/freeze.sh at Stage 5 exit."; exit 2; }
  git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null 2>&1 || { echo "FAIL $GATE: base '$BASE' ($BASE_SRC) does not resolve."; exit 2; }
  BASE_SHA=$(git rev-parse "$BASE^{commit}")
  git merge-base --is-ancestor "$BASE_SHA" HEAD 2>/dev/null || { echo "FAIL $GATE: base '$BASE' ($BASE_SRC) is not an ancestor of HEAD."; exit 2; }
  CH=$( { git diff --name-only --no-renames --diff-filter=ACMD "$BASE_SHA" -- . ; git ls-files --others --exclude-standard --full-name ; } | sed '/^$/d' | sort -u)
  ALT=$(printf '%s\n' "$GLOBS" | sed '/^$/d' | while IFS= read -r g; do glob_to_regex "$g"; done | paste -sd '|' -)
  V=""; [ -n "$CH" ] && [ -n "$ALT" ] && V=$(printf '%s\n' "$CH" | grep -E "$ALT" || true)
  if [ -n "$V" ]; then
    echo "FAIL $GATE: structure shard(s) differ from the frozen base $BASE (the PM approved this diagram):"
    printf '%s\n' "$V" | while IFS= read -r p; do echo "  $p"; done
    echo "A deviation is not an edit: write [NEEDS-PO:structure] <Class.member: proposed signature - why> on the item; the PM decides; the PO replaces the shard wholesale and re-freezes."
    exit 1
  fi
  echo "PASS $GATE: no structure shard differs from $BASE (working tree, incl. untracked)."
  exit 0
fi

# ---------------------------------------------------------------------------------------------------
# Scope: structure shards (all, or changed vs --changed base).
SHARDS=$(printf '%s\n' "$GLOBS" | sed '/^$/d' | while IFS= read -r g; do expand_globs "$g"; done | sort -u)
if [ -n "$CHANGED" ]; then
  git rev-parse --verify --quiet "$CHANGED^{commit}" >/dev/null 2>&1 || { echo "FAIL $GATE: --changed base '$CHANGED' does not resolve."; exit 2; }
  CH=$( { git diff --name-only --no-renames --diff-filter=ACM "$CHANGED" -- . ; git ls-files --others --exclude-standard --full-name ; } | sed '/^$/d' | sort -u)
  printf '%s\n' "$CH" > "${TMPDIR:-/tmp}/.sc-ch.$$"
  SHARDS=$(printf '%s\n' "$SHARDS" | grep -F -x -f "${TMPDIR:-/tmp}/.sc-ch.$$" || true)
  rm -f "${TMPDIR:-/tmp}/.sc-ch.$$"
fi
if [ -z "$SHARDS" ]; then
  echo "PASS $GATE: no structure shards in scope (a unit with no new public members records 'structure: N/A - <reason>' on the item)."
  exit 0
fi

# parse_shard <file> -> records "section|class|member|line" (pipe-separated: identifiers never contain
# one, and a shell read over tabs would collapse the empty member field); member empty for a class line.
# section: added | changed | removed | present (no heading). Mermaid classDiagram, member level:
#   class Foo {            +String owner          +deposit(amount) bool       Foo : +bar()
#   <<stereotype>>, %% comments and relationship lines are skipped.
parse_shard() {
  awk '
  function ident(s) { if (match(s, /[A-Za-z_][A-Za-z0-9_]*/)) return substr(s, RSTART, RLENGTH); return "" }
  function ident_last(s,   n, a, i, r) {
    gsub(/[^A-Za-z0-9_]+/, " ", s); n = split(s, a, " "); r = ""
    for (i = n; i >= 1; i--) if (a[i] ~ /^[A-Za-z_]/) { r = a[i]; break }
    return r
  }
  function member_name(s,   t, p) {
    t = s
    sub(/^[[:space:]]*[+#~-]?[[:space:]]*/, "", t)
    gsub(/~[^~]*~/, "", t)
    sub(/[[:space:]]*[*$]+[[:space:]]*$/, "", t)
    if (t ~ /\(/) { p = index(t, "("); return ident_last(substr(t, 1, p - 1)) }
    if (t ~ /:/)  { p = index(t, ":"); return ident_last(substr(t, 1, p - 1)) }
    return ident_last(t)
  }
  BEGIN { fence = 0; dia = 0; cls = ""; sec = "present" }
  {
    line = $0; sub(/\r$/, "", line)
    if (!fence) {
      if (line ~ /^[[:space:]]*#+[[:space:]]/) {
        h = tolower(line)
        if (h ~ /removed|retired|deleted/) sec = "removed"
        else if (h ~ /changed|modified|updated/) sec = "changed"
        else if (h ~ /added|new/) sec = "added"
      }
      if (line ~ /^[[:space:]]*```/) { fence = 1; dia = (tolower(line) ~ /mermaid/) ? -1 : 0; cls = "" }
      next
    }
    if (line ~ /^[[:space:]]*```/) { fence = 0; dia = 0; cls = ""; next }
    if (dia == -1) { if (line ~ /classDiagram/) dia = 1; else if (line !~ /^[[:space:]]*$/ && line !~ /^[[:space:]]*%%/) dia = 0; next }
    if (dia != 1) next
    t = line; sub(/^[[:space:]]+/, "", t)
    if (t == "" || t ~ /^%%/) next
    if (t ~ /^(note|direction|link|click|callback|style|classDef|cssClass)[[:space:]]/) next
    if (t ~ /^namespace[[:space:]]/) next
    if (t ~ /^class[[:space:]]+/) {
      sub(/^class[[:space:]]+/, "", t); c = ident(t)
      if (c == "") next
      printf "%s|%s||%d\n", sec, c, NR
      if (t ~ /\{[[:space:]]*$/) cls = c
      next
    }
    if (t ~ /^\}/) { cls = ""; next }
    if (t ~ /<\|--|--\|>|<\|\.\.|\.\.\|>|\*--|--\*|o--|--o|-->|<--|\.\.>|<\.\.|--[[:space:]]|[[:space:]]--|\.\.[[:space:]]/) next
    if (t ~ /^<<.*>>$/) next
    if (cls != "") { m = member_name(t); if (m != "") printf "%s|%s|%s|%d\n", sec, cls, m, NR; next }
    if (t ~ /^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:/) {
      c = ident(t); rest = t; sub(/^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:[[:space:]]*/, "", rest)
      printf "%s|%s||%d\n", sec, c, NR
      if (rest ~ /^<<.*>>$/) next
      m = member_name(rest); if (m != "") printf "%s|%s|%s|%d\n", sec, c, m, NR
    }
  }' "$1"
}

# ---------------------------------------------------------------------------------------------------
# --plan: shape only.
if [ "$MODE" = plan ]; then
  FAILS=0; WARNS=0; N=0
  for s in $SHARDS; do
    N=$((N+1))
    REC=$(parse_shard "$s")
    NC=$(printf '%s\n' "$REC" | awk -F'|' '$2!="" && $3=="" {print $2}' | sort -u | wc -l | tr -d ' ')
    NM=$(printf '%s\n' "$REC" | awk -F'|' '$3!=""' | wc -l | tr -d ' ')
    if [ "$NC" -eq 0 ] || [ "$NM" -eq 0 ]; then
      echo "FAIL $GATE: $s has no member-level classDiagram (classes=$NC members=$NM) - the diagram must name every class and its public members."
      FAILS=$((FAILS+1)); continue
    fi
    EMPTY=$(printf '%s\n' "$REC" | awk -F'|' '$3=="" {c[$2]=1} $3!="" {m[$2]=1} END {for (k in c) if (!(k in m)) print k}' | sort -u)
    for c in $EMPTY; do echo "WARN $GATE: $s: class $c lists no members (an outline in disguise, or an existing class named for context)."; WARNS=$((WARNS+1)); done
  done
  [ "$FAILS" -eq 0 ] || exit 1
  echo "PASS $GATE: $N structure shard(s) at member level ($WARNS warning(s))."
  exit 0
fi

# ---------------------------------------------------------------------------------------------------
# default: forward trace into paths.code.
CODE=$(read_cfg "$CFG" '.paths.code' 'src/**')
PREFIX=${CODE%%[\*\?\[]*}; PREFIX=${PREFIX%/}
[ -n "$PREFIX" ] || PREFIX="."
[ -e "$PREFIX" ] || { echo "FAIL $GATE: paths.code '$CODE' resolves to '$PREFIX', which does not exist."; exit 2; }
PATHSPEC="$PREFIX"
for g in $GLOBS; do PATHSPEC="$PATHSPEC :(exclude,glob)$g"; done

TMP="${TMPDIR:-/tmp}/.sc.$$"
FAILS=0; WARNS=0; CHECKED=0
NSHARDS=0
for s in $SHARDS; do
  NSHARDS=$((NSHARDS+1))
  REC=$(parse_shard "$s")
  [ -n "$REC" ] || { echo "FAIL $GATE: $s has no classDiagram block."; FAILS=$((FAILS+1)); continue; }
  printf '%s\n' "$REC" | while IFS='|' read -r sec cls mem ln; do
    [ -n "$cls" ] || continue
    name=${mem:-$cls}; label="$cls${mem:+.$mem}"
    # shellcheck disable=SC2086
    if git grep -I -w -q --untracked -e "$name" -- $PATHSPEC 2>/dev/null; then found=1; else found=0; fi
    case "$sec" in
      removed)
        if [ "$found" = 1 ]; then
          if [ -z "$mem" ]; then echo "FAIL $GATE: $s:$ln: removed class $cls is still present under $PREFIX."; echo F
          else echo "WARN $GATE: $s:$ln: removed member $label still names something under $PREFIX (retire it, or it lives on in another class)."; echo W; fi
        fi ;;
      *)
        if [ "$found" = 0 ]; then echo "FAIL $GATE: $s:$ln: $label is in the approved diagram but no identifier '$name' exists under $PREFIX."; echo F; fi ;;
    esac
    echo C
  done > "$TMP"
  FAILS=$((FAILS + $(grep -c '^F$' "$TMP" || true)))
  WARNS=$((WARNS + $(grep -c '^W$' "$TMP" || true)))
  CHECKED=$((CHECKED + $(grep -c '^C$' "$TMP" || true)))
  grep -v -E '^[FWC]$' "$TMP" || true
  rm -f "$TMP"
done
[ "$FAILS" -eq 0 ] || { echo "FAIL $GATE: $FAILS diagram entr(y/ies) do not hold in the code ($CHECKED checked). The diagram is the approved plan: conform the code, or route the deviation to the PM."; exit 1; }
echo "PASS $GATE: every class and member in $NSHARDS structure shard(s) resolves under $PREFIX ($CHECKED checked, $WARNS warning(s))."
exit 0
