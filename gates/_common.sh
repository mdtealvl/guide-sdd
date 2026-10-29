#!/usr/bin/env sh
# _common.sh — shared helpers for the POSIX gate scripts.
# Sourced by each gate (. "$(dirname "$0")/_common.sh"). Requires jq + git (git only
# where a gate uses it). Goal: reproduce the old Python gates' glob/json/file behaviour.

# require_jq <gate-name> — fail(2) with an actionable message if jq is missing.
require_jq() {
  command -v jq >/dev/null 2>&1 || {
    echo "FAIL $1: needs jq (apt/brew install jq)"
    exit 2
  }
}

# require_git <gate-name>
require_git() {
  command -v git >/dev/null 2>&1 || {
    echo "FAIL $1: needs git"
    exit 2
  }
}

# read_cfg <config-path> <jq-filter> <default>
# Print the jq-extracted value, or <default> if null/absent/unreadable.
read_cfg() {
  _cfg="$1"; _filter="$2"; _default="$3"
  _v=$(jq -r "$_filter // empty" "$_cfg" 2>/dev/null)
  if [ -z "$_v" ]; then
    printf '%s' "$_default"
  else
    printf '%s' "$_v"
  fi
}

# to_ere <regex> — make a Python/.NET-style regex safe for grep -E (POSIX ERE).
# The framework's default patterns use \d (PCRE-only) which BSD/GNU grep do not
# accept in ERE; translate the portable subset. \b and \w ARE supported as grep
# extensions on both GNU and BSD, so they pass through untouched. Inside a bracket
# expression the class becomes its range ([\d.] -> [0-9.]), as .NET reads it.
to_ere() {
  printf '%s' "$1" | sed -e ':a' -e 's/\(\[[^]]*\)\\d/\10-9/' -e 's/\(\[[^]]*\)\\w/\1A-Za-z0-9_/' \
    -e 's/\(\[[^]]*\)\\s/\1[:space:]/' -e 'ta' \
    -e 's/\\d/[0-9]/g' -e 's/\\D/[^0-9]/g' -e 's/\\s/[[:space:]]/g' -e 's/\\S/[^[:space:]]/g'
}

# check_regex <gate> <key> <regex> — a configured regex both twins read alike, or a FAIL line and
# return 2: no inline flags (?...) or lazy quantifiers (.NET honours them, grep -E does not), and
# grep -E must accept it.
check_regex() {
  case "$3" in
    *'(?'*|*'*?'*|*'+?'*|*'}?'*|*'??'*)
      echo "FAIL $1: $2 uses (?...) or a lazy quantifier - outside the portable regex subset (gates/README.md)"
      return 2 ;;
  esac
  printf 'x\n' | grep -E "$(to_ere "$3")" >/dev/null 2>&1
  if [ $? -eq 2 ]; then echo "FAIL $1: $2 is not a valid regex"; return 2; fi
  return 0
}

# one_line <gate> <key> <cmd> — a configured command must be one line: the ps1 twin's cmd /c runs
# only the first line, sh -c runs them all.
one_line() {
  case "$3" in
    *'
'*|*"$(printf '\r')"*) echo "FAIL $1: $2 must be one line (cmd /c on Windows runs only the first)"; return 2 ;;
  esac
  return 0
}

# read_raw <config> <jq-path> <default> — a config value as text, `false` and `0` kept (read_cfg's
# `// empty` drops them); null or absent gives <default>.
read_raw() {
  _v=$(jq -r "($2) | if . == null then empty else tostring end" "$1" 2>/dev/null | tr -d '\r')
  if [ -n "$_v" ]; then printf '%s' "$_v"; else printf '%s' "$3"; fi
}

# to_awk_ere <regex> — like to_ere, but for awk, which does NOT support \b / \B word
# boundaries (a match with \b fails outright). We STRIP \b/\B here; the awk gates pair
# this with wmatch() (a boundary-aware matcher) to restore \b semantics. \w/\W also
# become character classes since awk lacks them.
to_awk_ere() {
  # Note: \. -> [.] (awk warns on \. and treats it as bare '.'; [.] is a no-warn
  # literal dot). Order: escape-classes first, then strip boundaries.
  printf '%s' "$1" \
    | sed -e 's/\\d/[0-9]/g' -e 's/\\D/[^0-9]/g' \
          -e 's/\\s/[[:space:]]/g' -e 's/\\S/[^[:space:]]/g' \
          -e 's/\\w/[A-Za-z0-9_]/g' -e 's/\\W/[^A-Za-z0-9_]/g' \
          -e 's/\\\./[.]/g' \
          -e 's/\\b//g' -e 's/\\B//g'
}

# had_word_boundary <regex> — prints 1 if the ORIGINAL regex began/ended with \b
# (so the awk gates know to enforce word boundaries via wmatch); else prints 0.
had_word_boundary() {
  case "$1" in
    '\b'*|*'\b') printf '1' ;;
    *) printf '0' ;;
  esac
}

# glob_to_regex <glob> — translate one glob into a POSIX ERE anchored over a whole
# forward-slashed path. Matches Python glob.glob(recursive=True) + fnmatch.
#   **  -> match any chars incl '/'   (with a following '/' made optional)
#   *   -> match any chars except '/'
#   ?   -> one non-'/' char
# Prints the regex on stdout.
glob_to_regex() {
  printf '%s' "$1" | awk '
  {
    g = $0
    out = "^"
    n = length(g)
    i = 1
    while (i <= n) {
      c = substr(g, i, 1)
      if (c == "*") {
        if (substr(g, i+1, 1) == "*") {
          if (substr(g, i+2, 1) == "/") {
            out = out "(.*/)?"
            i += 3
          } else {
            out = out ".*"
            i += 2
          }
        } else {
          out = out "[^/]*"
          i += 1
        }
      } else if (c == "?") {
        out = out "[^/]"
        i += 1
      } else if (index(".\\+(){}|^$", c) > 0) {
        out = out "\\" c
        i += 1
      } else if (c == "[") {
        # copy a character class verbatim until the matching ]
        j = i + 1
        if (substr(g, j, 1) == "!" || substr(g, j, 1) == "^") j++
        if (substr(g, j, 1) == "]") j++
        while (j <= n && substr(g, j, 1) != "]") j++
        if (j > n) {
          out = out "\\["
          i += 1
        } else {
          cls = substr(g, i+1, j-i-1)
          if (substr(cls,1,1) == "!") cls = "^" substr(cls,2)
          out = out "[" cls "]"
          i = j + 1
        }
      } else {
        out = out c
        i += 1
      }
    }
    out = out "$"
    print out
  }'
}

# fnmatch_to_regex <glob> — translate a glob into an ERE with Python fnmatch
# semantics: '*' and '?' DO match '/', no '**' special form. Used by test_edit_ban,
# which matched changed paths with Python's fnmatch.fnmatch.
fnmatch_to_regex() {
  printf '%s' "$1" | awk '
  {
    g = $0; out = "^"; n = length(g); i = 1
    while (i <= n) {
      c = substr(g, i, 1)
      if (c == "*") { out = out ".*"; i++ }
      else if (c == "?") { out = out "."; i++ }
      else if (c == "[") {
        j = i + 1
        if (substr(g, j, 1) == "!" || substr(g, j, 1) == "^") j++
        if (substr(g, j, 1) == "]") j++
        while (j <= n && substr(g, j, 1) != "]") j++
        if (j > n) { out = out "\\["; i++ }
        else {
          cls = substr(g, i+1, j-i-1)
          if (substr(cls,1,1) == "!") cls = "^" substr(cls,2)
          out = out "[" cls "]"; i = j + 1
        }
      }
      else if (index(".\\+(){}|^$", c) > 0) { out = out "\\" c; i++ }
      else { out = out c; i++ }
    }
    out = out "$"; print out
  }'
}

# expand_globs <glob1> [glob2 ...] — print matching FILES, one per line, relative to
# the current dir, forward-slashed, sorted, deduped. Recursive, isfile-only.
expand_globs() {
  # Build a regex alternation from all globs, then filter the file list once.
  _alt=""
  for _g in "$@"; do
    [ -z "$_g" ] && continue
    _re=$(glob_to_regex "$_g")
    if [ -z "$_alt" ]; then _alt="$_re"; else _alt="$_alt|$_re"; fi
  done
  [ -z "$_alt" ] && return 0
  # List all files relative to '.', strip leading './', match against the alternation.
  find . -type f 2>/dev/null \
    | sed 's#^\./##' \
    | grep -E "$_alt" \
    | sort -u
}

# cfg_list <config> <jq-path> — a config value that is a string or an array, one item per line
# (CRs dropped, blanks skipped); nothing when null/absent.
cfg_list() {
  jq -r "(($2) // empty) | if type == \"array\" then .[] else . end" "$1" 2>/dev/null | tr -d '\r' | sed '/^$/d'
}

# glob_specs [exclude] — globs on stdin, one per line, as git pathspecs for `eval git ... -- $specs`:
# each single-quoted with :(glob) magic (** spans directories, * does not - the bank's dialect), or
# :(exclude,glob) with the argument. A glob holding a single quote is skipped.
glob_specs() {
  _mag=":(glob)"; [ "${1:-}" = "exclude" ] && _mag=":(exclude,glob)"
  while IFS= read -r _g; do
    case "$_g" in ''|*"'"*) continue ;; esac
    printf " '%s%s'" "$_mag" "$_g"
  done
}

# file_stem <path> — the file name without its last extension (WriterIntake.cs -> WriterIntake).
file_stem() {
  _b=${1##*/}
  case "$_b" in ?*.*) _b=${_b%.*} ;; esac
  printf '%s' "$_b"
}

# frozen_sha <gate-dir> — the sha= line of <gate-dir>/.frozen, if any.
frozen_sha() {
  [ -f "$1/.frozen" ] && sed -n 's/^sha=\([0-9a-fA-F]*\).*/\1/p' "$1/.frozen" | head -1
}

# capture_group1 <regex> — stdin lines: for each line the regex matches, print its capture group 1
# (the first match; lines without a match print nothing). Control characters stand in for the sed
# delimiter and the group markers.
capture_group1() {
  _d=$(printf '\003'); _m1=$(printf '\001'); _m2=$(printf '\002')
  sed -n -E "s${_d}$(to_ere "$1")${_d}${_m1}\\1${_m2}${_d}p" \
    | sed -e "s/^[^${_m1}]*${_m1}//" -e "s/${_m2}.*\$//"
}

# fill_tests <cmd> <tests> — <cmd> with every {tests} replaced by <tests>.
fill_tests() {
  _s=$1; _o=""
  while :; do
    case "$_s" in
      *'{tests}'*) _o="$_o${_s%%'{tests}'*}$2"; _s=${_s#*'{tests}'} ;;
      *) _o="$_o$_s"; break ;;
    esac
  done
  printf '%s' "$_o"
}
