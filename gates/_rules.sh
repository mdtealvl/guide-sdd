#!/usr/bin/env bash
# _rules.sh — the shared rule engine for constitution_lint + seam_conformance.
# Sourced by both gates (the .py originals shared run_rule/run_rules the same way).
# Requires _common.sh (expand_globs, to_ere) to be sourced first, plus jq + grep.

# run_rule emits, on stdout, one verdict line:
#   OK            (rule passed)
#   FAIL<TAB>detail
# then, for kind `command` only, the last lines of the command's output (printed under the verdict).
# It is fed one rule as a compact JSON object on argument $1.
run_rule() {
  _rule="$1"
  _kind=$(printf '%s' "$_rule" | jq -r '.kind // empty')

  # command: a real checker (import-linter, dependency-cruiser, ArchUnit tests...) run from the
  # project root; exit 0 passes. The regex kinds below are the no-dependency fallback.
  if [ "$_kind" = "command" ]; then
    _cmd=$(printf '%s' "$_rule" | jq -r '.cmd // empty')
    if [ -z "$_cmd" ]; then printf "FAIL\tbad cmd: 'cmd'\n"; return; fi
    case "$_cmd" in *'
'*|*"$(printf '\r')"*) printf 'FAIL\tcmd must be one line (cmd /c on Windows runs only the first)\n'; return ;; esac
    _out=$(sh -c "$_cmd" </dev/null 2>&1); _rc=$?   # stdin closed: the rule list is on ours
    if [ "$_rc" -eq 0 ]; then printf 'OK\n'; return; fi
    printf 'FAIL\t`%s` exited %s\n' "$_cmd" "$_rc"
    printf '%s\n' "$_out" | tr -d '\r' | sed '/^$/d' | tail -n 10
    return
  fi

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
      printf '%s\n' "$_res" | sed '1d' | sed 's/^/         | /'
    fi
  done
  rm -f "$RULE_TMP" 2>/dev/null || true
  if [ "$_failed" -eq 0 ]; then _v=PASS; else _v=FAIL; fi
  printf '%s %s: %d rule(s), %d failing.\n' "$_v" "$_gate" "$_total" "$_failed"
  [ "$_failed" -eq 0 ] && return 0 || return 1
}
