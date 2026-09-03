#!/usr/bin/env bash
# test_edit_ban - prove the tree under review differs from the QA-frozen commit in no test file.
#
# Generic gate. Compares the QA-frozen base against the WORKING TREE (committed + staged +
# unstaged + untracked), never commit-to-commit only, so an uncommitted edit cannot hide.
# Renames are not collapsed (--no-renames), so moving a test out of a test path shows as a
# delete. The gate directory itself (config, scripts) must be unchanged vs the base, so the
# globs and suite command the bank reads are the ones QA froze - only `.frozen` may be added.
#
# Base resolution (first that applies):
#   1. positional <baseRef>  - the QA-frozen SHA recorded on the changelog item (authoritative;
#                              what the Orchestrator / CI passes);
#   2. <gates>/.frozen        - written by gates/freeze.sh at Stage 5 exit (a mirror of 1);
#   3. config baseRef         - a moving branch name is WEAK (warned): it can be advanced past
#                              the frozen point. Pass the SHA.
# The base must resolve AND be an ancestor of HEAD; otherwise exit 2 (fail closed).
#
# Trust boundary (be honest): anything inside the repo can be rewritten by whoever holds git.
# The proof is "given the SHA the Orchestrator recorded on the item, no test path differs".
# The `.frozen` file and the plugin hook are tripwires for the Engineer persona, not the proof.
#
# Exit 0 PASS, 1 FAIL, 2 config/usage error.
# Usage:  sh gates/test_edit_ban.sh [baseRef] [--config gates/gates.config.json]

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/_common.sh"

GATE=test_edit_ban
require_git "$GATE"
require_jq "$GATE"

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
CFG=$(CDPATH= cd -- "$(dirname -- "$CFG")" && pwd)/$(basename -- "$CFG")

TOP=$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null) || { echo "FAIL $GATE: not inside a git work tree"; exit 2; }
GD=$(git -C "$HERE" rev-parse --show-prefix | sed 's#/$##')   # gate dir relative to the repo top, e.g. gates or sdd/gates
[ -n "$GD" ] || GD="."
cd "$TOP" || exit 2

BASE_SRC="argument"
if [ -z "$BASE" ] && [ -f "$GD/.frozen" ]; then
  BASE=$(sed -n 's/^sha=\([0-9a-fA-F]*\).*/\1/p' "$GD/.frozen" | head -1)
  BASE_SRC="$GD/.frozen"
fi
if [ -z "$BASE" ]; then
  BASE=$(read_cfg "$CFG" '.baseRef' 'main')
  BASE_SRC="config baseRef"
fi
[ -n "$BASE" ] || { echo "FAIL $GATE: no base - pass the QA-frozen SHA or run gates/freeze.sh at Stage 5 exit."; exit 2; }

# Fail closed: an unresolvable base must FAIL (exit 2), never fall through to PASS.
git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null 2>&1 || {
  echo "FAIL $GATE: base '$BASE' ($BASE_SRC) does not resolve - pass the QA-frozen SHA."
  exit 2
}
BASE_SHA=$(git rev-parse "$BASE^{commit}")
git merge-base --is-ancestor "$BASE_SHA" HEAD 2>/dev/null || {
  echo "FAIL $GATE: base '$BASE' ($BASE_SRC) is not an ancestor of HEAD - the frozen point must be on this branch."
  exit 2
}
case "$BASE" in
  *[!0-9a-fA-F]*|"") echo "WARN $GATE: base '$BASE' ($BASE_SRC) is a moving ref, not a SHA - it can be advanced past the frozen point. Pass the QA-frozen SHA." ;;
esac

# Test globs (newline-separated) from config; fall back to paths.tests then a default.
GLOBS=$(jq -r '(.testGlobs // empty) | if type=="array" then .[] else . end' "$CFG" 2>/dev/null)
[ -n "$GLOBS" ] || GLOBS=$(read_cfg "$CFG" '.paths.tests' 'tests/**')

# Everything that differs between the base commit and the working tree: tracked changes
# (committed, staged, unstaged; deletes included; renames NOT collapsed) plus untracked files.
CHANGED=$( { git diff --name-only --no-renames --diff-filter=ACMD "$BASE_SHA" -- . ;
             git ls-files --others --exclude-standard --full-name ; } | sed '/^$/d' | sort -u)

if [ -z "$CHANGED" ]; then
  echo "PASS $GATE: no changed files vs $BASE (working tree, incl. untracked)."
  exit 0
fi

# 1. Gate-dir tamper check: config + scripts must equal the base. Only `.frozen` may be ADDED.
TAMPER=$(printf '%s\n' "$CHANGED" | grep -E "^${GD}/" | grep -v -E "^${GD}/\.frozen$" || true)
if [ -n "$TAMPER" ]; then
  echo "FAIL $GATE: gate config/scripts modified vs $BASE (the bank must run on what QA froze):"
  printf '%s\n' "$TAMPER" | while IFS= read -r v; do echo "  $v"; done
  exit 1
fi

# 2. Test-path check. One glob dialect for the whole bank: glob_to_regex (** spans dirs, * does not).
ALT=$(printf '%s\n' "$GLOBS" | sed '/^$/d' | while IFS= read -r g; do
  glob_to_regex "$g"
done | paste -sd '|' -)

VIOLATIONS=""
if [ -n "$ALT" ]; then
  VIOLATIONS=$(printf '%s\n' "$CHANGED" | grep -E "$ALT" || true)
fi

if [ -n "$VIOLATIONS" ]; then
  echo "FAIL $GATE: test file(s) differ from the frozen base $BASE:"
  printf '%s\n' "$VIOLATIONS" | while IFS= read -r v; do echo "  $v"; done
  echo "Tests are frozen for the Engineer. Revert them (git checkout -- <path> / rm <path>) and file the dispute to the Orchestrator."
  exit 1
fi

echo "PASS $GATE: no test files touched vs $BASE (working tree, incl. untracked)."
exit 0
