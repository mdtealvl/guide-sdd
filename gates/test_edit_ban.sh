#!/usr/bin/env bash
# test_edit_ban — prove the Engineer's diff touched no test file.
#
# Generic gate. Path-guard over `git diff`: if any changed file matches a test glob,
# FAIL. Globs and base ref come from gates.config.json (testGlobs, baseRef). This is
# what makes QA-perp-Engineer structural: the Engineer *cannot* warp a test it cannot
# write. Disputes are filed to the Orchestrator, never resolved by editing a test.
#
# FAIL CLOSED: an unresolvable base ref FAILs (exit 2), never falls through to PASS.
#
# Run on the Engineer's working tree / branch.
# Usage:  sh gates/test_edit_ban.sh [baseRef] [gates.config.json]
#         sh gates/test_edit_ban.sh [--config gates.config.json] [baseRef]
#   baseRef defaults to .baseRef in config (the QA-frozen commit, or `main`).

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/_common.sh"

GATE=test_edit_ban
require_git "$GATE"
require_jq "$GATE"

# Args: positional [baseRef] [config], plus optional --config <path>.
BASE=""
CFG="gates/gates.config.json"
CFG_SET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --config) CFG="$2"; CFG_SET=1; shift 2 ;;
    --config=*) CFG="${1#--config=}"; CFG_SET=1; shift ;;
    *)
      if [ -z "$BASE" ]; then BASE="$1"
      elif [ "$CFG_SET" = 0 ]; then CFG="$1"; CFG_SET=1
      fi
      shift ;;
  esac
done

[ -f "$CFG" ] || { echo "FAIL $GATE: cannot read config $CFG: no such file"; exit 2; }

[ -n "$BASE" ] || BASE=$(read_cfg "$CFG" '.baseRef' 'main')

# Fail closed: an unresolvable base ref must FAIL (exit 2), never fall through to a
# silent PASS — that would make the QA-perp-Engineer gate fail-open.
git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null 2>&1 || {
  echo "FAIL $GATE: baseRef '$BASE' does not resolve — set baseRef to the QA-frozen commit."
  exit 2
}

# Test globs (newline-separated) from config; fall back to paths.tests then a default.
GLOBS=$(jq -r '(.testGlobs // empty) | if type=="array" then .[] else . end' "$CFG" 2>/dev/null)
[ -n "$GLOBS" ] || GLOBS=$(read_cfg "$CFG" '.paths.tests' 'tests/**')

# All paths changed since BASE (Added/Copied/Modified/Renamed/Deleted).
CHANGED=$(git diff --name-only --diff-filter=ACMRD "$BASE"...HEAD)

if [ -z "$CHANGED" ]; then
  echo "PASS $GATE: no changed files vs $BASE."
  exit 0
fi

# Build a single ERE alternation from the test globs (fnmatch semantics).
# Each glob -> one anchored ERE on its own line; join with '|'.
ALT=$(printf '%s\n' "$GLOBS" | sed '/^$/d' | while IFS= read -r g; do
  fnmatch_to_regex "$g"
done | paste -sd '|' -)

VIOLATIONS=""
if [ -n "$ALT" ]; then
  VIOLATIONS=$(printf '%s\n' "$CHANGED" | sed '/^$/d' | sed 's/[[:space:]]*$//;s/^[[:space:]]*//' | grep -E "$ALT" || true)
fi

if [ -n "$VIOLATIONS" ]; then
  echo "FAIL $GATE: Engineer modified test file(s) vs $BASE:"
  printf '%s\n' "$VIOLATIONS" | sed '/^$/d' | while IFS= read -r v; do echo "  $v"; done
  echo "Tests are frozen for the Engineer. File the dispute to the Orchestrator instead."
  exit 1
fi

echo "PASS $GATE: no test files touched vs $BASE."
exit 0
