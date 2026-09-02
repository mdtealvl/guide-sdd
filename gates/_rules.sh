#!/usr/bin/env bash
# _rules.sh — the shared rule engine for constitution_lint + seam_conformance.
# Sourced by both gates (the .py originals shared run_rule/run_rules the same way).
# Requires _common.sh (expand_globs, to_ere) to be sourced first, plus jq + grep.

# run_rule emits, on stdout, exactly one line:
#   OK            (rule passed)
#   FAIL<TAB>detail
# It is fed one rule as a compact JSON object on argument $1.
run_rule() {
  _rule="$1"
  _kind=$(printf '%s' "$_rule" | jq -r '.kind // empty')
  # paths can be a string or array -> newline list
  _paths=$(printf '%s' "$_rule" | jq -r '(.paths // empty) | if type=="array" then .[] else . end')

  if [ "$_kind" = "file_exists" ]; then
    # shellcheck disable=SC2046
    _matched=$(expand_globs $(printf '%s ' $_paths))
    if [ -n "$_matched" ]; then printf 'OK\n'; else printf 'FAIL\tno file matches %s\n' "$_paths"; fi
    return
  fi

  _pattern=$(printf '%s' "$_rule" | jq -r '.pattern // empty')
  if [ -z "$_pattern" ]; then printf "FAIL\tbad pattern: 'pattern'\n"; return; fi
  _pat=$(to_ere "$_pattern")

  # shellcheck disable=SC2046
  _files=$(expand_globs $(printf '%s ' $_paths))

  case "$_kind" in
    must_match)
      _off=""
      printf '%s\n' "$_files" | sed '/^$/d' | while IFS= read -r f; do
        if ! grep -Eq "$_pat" "$f" 2>/dev/null; then printf "'%s', " "$f"; fi
      done > "$RULE_TMP" 2>/dev/null || true
      _off=$(cat "$RULE_TMP"); : > "$RULE_TMP"
      if [ -z "$_off" ]; then printf 'OK\n'; else printf 'FAIL\tpattern absent in: [%s]\n' "$(printf '%s' "$_off" | sed 's/, $//')"; fi
      ;;
    must_not_match)
      printf '%s\n' "$_files" | sed '/^$/d' | while IFS= read -r f; do
        if grep -Eq "$_pat" "$f" 2>/dev/null; then printf "'%s', " "$f"; fi
      done > "$RULE_TMP" 2>/dev/null || true
      _off=$(cat "$RULE_TMP"); : > "$RULE_TMP"
      if [ -z "$_off" ]; then printf 'OK\n'; else printf 'FAIL\tpattern present in: [%s]\n' "$(printf '%s' "$_off" | sed 's/, $//')"; fi
      ;;
    pair_requires)
      _expect=$(printf '%s' "$_rule" | jq -r '.expect // empty')
      if [ -z "$_expect" ]; then printf "FAIL\tbad expect: 'expect'\n"; return; fi
      _exp=$(to_ere "$_expect")
      printf '%s\n' "$_files" | sed '/^$/d' | while IFS= read -r f; do
        if grep -Eq "$_pat" "$f" 2>/dev/null && ! grep -Eq "$_exp" "$f" 2>/dev/null; then printf "'%s', " "$f"; fi
      done > "$RULE_TMP" 2>/dev/null || true
      _off=$(cat "$RULE_TMP"); : > "$RULE_TMP"
      if [ -z "$_off" ]; then printf 'OK\n'; else printf 'FAIL\tmissing `%s` in: [%s]\n' "$_expect" "$(printf '%s' "$_off" | sed 's/, $//')"; fi
      ;;
    *)
      printf "FAIL\tunknown kind '%s'\n" "$_kind"
      ;;
  esac
}

# run_rules <gate-name> — reads the rules array on stdin as compact JSON lines (one
# rule per line). Prints per-rule verdict + summary; returns 1 if any rule failed.
run_rules() {
  _gate="$1"
  RULE_TMP=$(mktemp 2>/dev/null || printf '/tmp/_rules.%s' "$$")
  : > "$RULE_TMP"
  _total=0
  _failed=0
  while IFS= read -r rule; do
    [ -z "$rule" ] && continue
    _total=$((_total + 1))
    _id=$(printf '%s' "$rule" | jq -r '.id // "?"')
    _msg=$(printf '%s' "$rule" | jq -r '.message // ""')
    _res=$(run_rule "$rule")
    _verdict=$(printf '%s' "$_res" | head -n1 | cut -f1)
    if [ "$_verdict" = "OK" ]; then
      printf '  [PASS] %s: %s\n' "$_id" "$_msg"
    else
      _failed=$((_failed + 1))
      _detail=$(printf '%s' "$_res" | head -n1 | cut -f2-)
      printf '  [FAIL] %s: %s\n' "$_id" "$_msg"
      printf '         -> %s\n' "$_detail"
    fi
  done
  rm -f "$RULE_TMP" 2>/dev/null || true
  if [ "$_failed" -eq 0 ]; then _v=PASS; else _v=FAIL; fi
  printf '%s %s: %d rule(s), %d failing.\n' "$_v" "$_gate" "$_total" "$_failed"
  [ "$_failed" -eq 0 ] && return 0 || return 1
}
