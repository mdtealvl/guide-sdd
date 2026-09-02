#!/usr/bin/env bash
# qa_import_ban (TEMPLATE) — a partial structural proof of QA ⊥ implementation.
#
# QA test files must NOT import/reference production internals beyond the contracted
# surface. This is the structural half of the QA-blind independence guarantee: without it,
# "QA never read the implementation" is honor-system. A rule typically scopes the QA test
# glob and `must_not_match` an import of a production-internal namespace/path.
#
# Project-specific (the production-internal surface differs per project), so it ships as a
# template like constitution_lint / seam_conformance and reuses the SAME rule engine.
# Copy this file to gates/qa_import_ban.sh (no edits) and author the "qaImportRules" array
# in gates/gates.config.json. Same four kinds as the other rule gates:
#   must_match | must_not_match | file_exists | pair_requires
#
# Rule shape (a row in gates.config.json -> qaImportRules[]):
#   { "id": "qa-no-impl-import", "kind": "must_not_match",
#     "paths": "tests/**/*.cs", "pattern": "using\\s+MyApp\\.Internal",
#     "message": "QA tests may not import production internals (test the contracted surface)" }
#
# Usage:  sh gates/qa_import_ban.sh [--config gates/gates.config.json]
#
# Implementation: shares the rule engine (_rules.sh) with constitution_lint /
# seam_conformance. Copy at init alongside the other rule gates.

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/_common.sh"
. "$HERE/_rules.sh"

RULES_KEY=qaImportRules
GATE=qa_import_ban
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

RULES=$(jq -c ".${RULES_KEY}[]?" "$CFG" 2>/dev/null)
N=$(printf '%s\n' "$RULES" | sed '/^$/d' | grep -c . || true)

if [ "$N" -eq 0 ]; then
  echo "PASS $GATE: no rules in $RULES_KEY (nothing to check)."
  exit 0
fi

run_rules "$GATE" <<EOF
$RULES
EOF
exit $?
