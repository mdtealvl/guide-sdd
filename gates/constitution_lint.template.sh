#!/usr/bin/env bash
# constitution_lint (TEMPLATE) — project-specific principle checks.
#
# Project-specific because principles differ per project; the RUNNER is generic and
# ships as-is. Copy this file to gates/constitution_lint.sh (no edits) and author the
# "constitutionRules" array in gates/gates.config.json.
#
# A rule is a mechanical predicate over file text. Supported kinds:
#   must_match      : EVERY file in `paths` matches `pattern`                    (else FAIL)
#   must_not_match  : NO file in `paths` matches `pattern`                       (else FAIL)
#   file_exists     : at least one file matches the `paths` glob                 (else FAIL)
#   pair_requires   : every file matching `pattern` ALSO matches `expect`        (else FAIL)
#
# Rule shape (a row in gates.config.json -> constitutionRules[]):
#   { "id": "no-hardcoded-ui", "kind": "must_not_match",
#     "paths": "src/**/*.tsx", "pattern": ">[A-Z][a-z]+ ",
#     "message": "UI strings go through useLabels()" }
#   pair_requires also needs:  "expect": "<regex that must also be present>"
#
# Usage:  sh gates/constitution_lint.sh [--config gates/gates.config.json]
#         (seam_conformance reuses the same engine with a different rule key)

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/_common.sh"
. "$HERE/_rules.sh"

RULES_KEY=constitutionRules
GATE=constitution_lint
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

# Compact each rule object to a single line.
RULES=$(jq -c ".${RULES_KEY}[]?" "$CFG" 2>/dev/null)
N=$(printf '%s\n' "$RULES" | sed '/^$/d' | grep -c . || true)

if [ "$N" -eq 0 ]; then
  echo "PASS $GATE: no rules in $RULES_KEY (nothing to check)."
  exit 0
fi

# Feed rules via redirect (NOT a pipe) so run_rules' counters survive the loop.
run_rules "$GATE" <<EOF
$RULES
EOF
exit $?
