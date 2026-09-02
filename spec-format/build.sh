#!/usr/bin/env bash
# build — assemble content-only spec shards into one navigable HTML index.
#
# POSIX-friendly (awk markdown shim). Reads every *.body.md (compiled from Markdown) and
# *.body.html (inlined as-is) shard RECURSIVELY under the spec dir, wraps them in
# _layout.html (the single home of page chrome/CSS/JS), generates a TOC from the rendered
# <hN> headings and clause anchors, and writes index.html.
#
# Layout contract: _layout.html must contain the markers
#     <!--TOC-->     (replaced with the generated table of contents)
#     <!--BODY-->    (replaced with the concatenated shards)
# If absent, a minimal default layout is emitted.
#
# Shard order: lexical by path. Prefix shards with an ordering key (0_, 1_...) when
# sequence matters.
#
# Usage:  sh spec-format/build.sh [spec_dir]   (default: spec)

set -u

SPEC_DIR="${1:-spec}"
LAYOUT="$SPEC_DIR/_layout.html"
OUT="$SPEC_DIR/index.html"

# ---- markdown shim (awk): same rules as the .ps1 / .py build ----
# Reads a *.body.md on stdin, writes compiled HTML on stdout.
md_to_html() {
  awk '
  function esc(s) {
    gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s)
    gsub(/"/, "\\&quot;", s); gsub(/\x27/, "\\&#x27;", s)
    return s
  }
  # inline: `code`, **bold**, *italic*, [text](href)
  function inline(s,   out, rest, pre, code, m) {
    # code spans first (escaped)
    out = ""; rest = s
    while (match(rest, /`[^`]+`/)) {
      pre = substr(rest, 1, RSTART - 1)
      code = substr(rest, RSTART + 1, RLENGTH - 2)
      out = out pre "<code>" esc(code) "</code>"
      rest = substr(rest, RSTART + RLENGTH)
    }
    out = out rest
    s = out
    # **bold**
    out = ""; rest = s
    while (match(rest, /\*\*[^*]+\*\*/)) {
      pre = substr(rest, 1, RSTART - 1)
      m = substr(rest, RSTART + 2, RLENGTH - 4)
      out = out pre "<strong>" m "</strong>"
      rest = substr(rest, RSTART + RLENGTH)
    }
    out = out rest
    s = out
    # *italic*
    out = ""; rest = s
    while (match(rest, /\*[^*]+\*/)) {
      pre = substr(rest, 1, RSTART - 1)
      m = substr(rest, RSTART + 1, RLENGTH - 2)
      out = out pre "<em>" m "</em>"
      rest = substr(rest, RSTART + RLENGTH)
    }
    out = out rest
    s = out
    # [text](href)
    out = ""; rest = s
    while (match(rest, /\[[^]]+\]\([^)]+\)/)) {
      pre = substr(rest, 1, RSTART - 1)
      seg = substr(rest, RSTART, RLENGTH)
      # split seg into text + href
      tb = index(seg, "]")
      txt = substr(seg, 2, tb - 2)
      hrefpart = substr(seg, tb + 2)              # after "]("
      hrefpart = substr(hrefpart, 1, length(hrefpart) - 1)  # drop trailing ")"
      out = out pre "<a href=\"" hrefpart "\">" txt "</a>"
      rest = substr(rest, RSTART + RLENGTH)
    }
    out = out rest
    return out
  }
  BEGIN { n = 0 }
  { lines[++n] = $0 }
  END {
    i = 1
    while (i <= n) {
      ln = lines[i]
      # fenced code block
      if (substr(ln, 1, 3) == "```") {
        i++
        buf = ""; first = 1
        while (i <= n && substr(lines[i], 1, 3) != "```") {
          if (first) { buf = esc(lines[i]); first = 0 }
          else       { buf = buf "\n" esc(lines[i]) }
          i++
        }
        print "<pre><code>" buf "</code></pre>"
        i++
        continue
      }
      # ATX heading, preserving a trailing {#id}
      if (match(ln, /^#{1,6}[ \t]+/)) {
        hashes = substr(ln, 1, RLENGTH)
        sub(/[ \t]+$/, "", hashes)
        lvl = length(hashes)
        body = substr(ln, RLENGTH + 1)
        # trailing optional whitespace
        sub(/[ \t]*$/, "", body)
        aid = ""
        if (match(body, /\{#[^}]+\}[ \t]*$/)) {
          idseg = substr(body, RSTART, RLENGTH)
          body = substr(body, 1, RSTART - 1)
          sub(/[ \t]*$/, "", body)
          aid = idseg
          sub(/^\{#/, "", aid); sub(/\}[ \t]*$/, "", aid)
        }
        idattr = ""
        if (aid != "") idattr = " id=\"" esc(aid) "\""
        print "<h" lvl idattr ">" inline(body) "</h" lvl ">"
        i++
        continue
      }
      # blank line
      if (ln ~ /^[ \t]*$/) { print ""; i++; continue }
      # raw HTML passthrough
      tl = ln; sub(/^[ \t]+/, "", tl)
      if (substr(tl, 1, 1) == "<") { print ln; i++; continue }
      # paragraph: gather until blank / heading / fence / raw-HTML line
      para = ln
      i++
      while (i <= n) {
        nx = lines[i]
        if (nx ~ /^[ \t]*$/) break
        if (substr(nx, 1, 1) == "#") break
        if (substr(nx, 1, 3) == "```") break
        ntl = nx; sub(/^[ \t]+/, "", ntl)
        if (substr(ntl, 1, 1) == "<") break
        para = para " " nx
        i++
      }
      print "<p>" inline(para) "</p>"
    }
  }
  '
}

esc_html() {
  # Python html.escape(s, quote=True)
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#x27;/g"
}

default_layout() {
  printf '%s' "<!doctype html><html><head><meta charset='utf-8'><title>Spec</title><style>body{font:16px/1.5 system-ui;max-width:50rem;margin:2rem auto;padding:0 1rem}nav{border-bottom:1px solid #ccc;margin-bottom:2rem}code{background:#f4f4f4;padding:.1em .3em}</style></head><body><nav><!--TOC--></nav><main><!--BODY--></main></body></html>"
}

# ---- collect shards: recursive, both extensions, never index.html, lexical by path ----
SHARDS=$(find "$SPEC_DIR" -type f \( -name '*.body.md' -o -name '*.body.html' \) 2>/dev/null \
  | grep -v '/index\.html$' \
  | sort)

if [ -z "$SHARDS" ]; then
  echo "build: no shards under $SPEC_DIR/**/*.body.{md,html}"
  exit 1
fi

if [ -f "$LAYOUT" ]; then
  LAYOUT_HTML=$(cat "$LAYOUT")
else
  LAYOUT_HTML=$(default_layout)
fi

case "$LAYOUT_HTML" in
  *"<!--BODY-->"*) : ;;
  *) echo "build: FAIL — _layout.html missing <!--BODY--> marker"; exit 1 ;;
esac

# Build BODY and TOC into temp files (preserves newlines cleanly).
BODY_TMP=$(mktemp 2>/dev/null || printf '/tmp/build_body.%s' "$$")
TOC_TMP=$(mktemp 2>/dev/null || printf '/tmp/build_toc.%s' "$$")
: > "$BODY_TMP"; : > "$TOC_TMP"

NSHARDS=0
while IFS= read -r s; do
  [ -z "$s" ] && continue
  NSHARDS=$((NSHARDS + 1))
  name=$(basename "$s")
  case "$name" in
    *.body.md)   suffix=".body.md" ;;
    *.body.html) suffix=".body.html" ;;
  esac
  slug=${name%"$suffix"}

  if [ "$suffix" = ".body.md" ]; then
    text=$(md_to_html < "$s")
  else
    text=$(cat "$s")
  fi

  {
    printf '<section id="%s" data-shard="%s">\n' "$(esc_html "$slug")" "$(esc_html "$name")"
    printf '%s\n' "$text"
    printf '</section>\n'
  } >> "$BODY_TMP"

  # TOC: extract <hN ... id="..">title</hN> across the rendered text.
  HEADS=$(printf '%s' "$text" | awk '
    BEGIN { RS = "</[hH][1-6]>"; }
    {
      block = $0
      # find an opening <hN ...>
      if (match(block, /<[hH][1-6][^>]*>/)) {
        tagstart = RSTART
        tag = substr(block, RSTART, RLENGTH)
        # level
        match(tag, /[hH][1-6]/); lvl = substr(tag, RSTART + 1, 1)
        # id attr
        aid = ""
        if (match(tag, /[ ]id=("[^"]*"|'\''[^'\'']*'\'')/)) {
          idseg = substr(tag, RSTART, RLENGTH)
          sub(/^[ ]id=("|'\'')/, "", idseg); sub(/("|'\'')$/, "", idseg)
          aid = idseg
        }
        title = substr(block, tagstart + length(tag))
        print lvl "\t" aid "\t" title
      }
    }')

  if [ -n "$HEADS" ]; then
    printf '%s\n' "$HEADS" | while IFS="$(printf '\t')" read -r lvl aid title; do
      [ -z "$lvl" ] && continue
      if [ -n "$aid" ]; then target="$aid"; else target="$slug"; fi
      # strip tags from title, trim
      clean=$(printf '%s' "$title" | sed 's/<[^>]*>//g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      indent=""
      k=1
      while [ "$k" -lt "$lvl" ]; do indent="$indent  "; k=$((k + 1)); done
      printf '%s<a href="#%s" style="display:block">%s</a>\n' "$indent" "$(esc_html "$target")" "$(esc_html "$clean")" >> "$TOC_TMP"
    done
  else
    printf '<a href="#%s" style="display:block">%s</a>\n' "$(esc_html "$slug")" "$(esc_html "$slug")" >> "$TOC_TMP"
  fi
done <<EOF
$SHARDS
EOF

# Join with single newlines exactly like Python "\n".join(parts): strip the trailing
# newline each temp file accumulated.
BODY=$(cat "$BODY_TMP"); rm -f "$BODY_TMP"
TOC=$(cat "$TOC_TMP"); rm -f "$TOC_TMP"

# Substitute the two markers literally (non-regex) over the whole layout buffer.
RESULT=$(LAYOUT_HTML="$LAYOUT_HTML" TOC="$TOC" BODY="$BODY" awk '
BEGIN {
  layout = ENVIRON["LAYOUT_HTML"]
  toc = ENVIRON["TOC"]
  body = ENVIRON["BODY"]
  # replace first/every <!--TOC-->
  out = layout
  res = ""
  while ((p = index(out, "<!--TOC-->")) > 0) {
    res = res substr(out, 1, p - 1) toc
    out = substr(out, p + length("<!--TOC-->"))
  }
  out = res out
  res = ""
  while ((p = index(out, "<!--BODY-->")) > 0) {
    res = res substr(out, 1, p - 1) body
    out = substr(out, p + length("<!--BODY-->"))
  }
  out = res out
  printf "%s", out
}')

printf '%s' "$RESULT" > "$OUT"
echo "build: PASS — $NSHARDS shard(s) -> $OUT"
exit 0
