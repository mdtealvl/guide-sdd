#!/usr/bin/env bash
# seam_conformance (TEMPLATE) — project-specific architecture-seam checks.
#
# Same generic rule engine as constitution_lint (a seam violation is just a mechanical
# predicate over the tree), kept as its own gate so principles and architecture
# boundaries stay separately ownable and wired. Rules live in gates.config.json under
# "seamRules", and EACH seam rule's `id` MUST key to an Project Details SEAM-N so the registry
# (Project Details §1) and the gate stay in lockstep.
#
# Copy this file to gates/seam_conformance.sh (no edits) and author "seamRules" in
# gates/gates.config.json. Same four kinds as constitution_lint:
#   must_match | must_not_match | file_exists | pair_requires
#
# Seam-flavoured examples (author as seamRules[] rows):
#   * audit invariant   id=SEAM-2-audit  kind=pair_requires
#                       paths="src/**/Handlers/**/*.cs" pattern="ICommandHandler" expect="IAuditSink"
#   * dispatch registry id=SEAM-1-dispatch kind=pair_requires
#                       paths="src/**/Handlers/**/*.cs" pattern="ICommandHandler" expect="\[Command\("
#   * no manual DI      id=SEAM-1-no-di  kind=must_not_match
#                       paths="src/**/Program.cs" pattern="services\.AddScoped<"
#
# Usage:  sh gates/seam_conformance.sh [--config gates/gates.config.json]
#
# Implementation: shares the rule engine (_rules.sh) with constitution_lint, exactly as
# the .py original imported constitution_lint's runner. Copy both gates at init.

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/_common.sh"
. "$HERE/_rules.sh"

RULES_KEY=seamRules
GATE=seam_conformance
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
