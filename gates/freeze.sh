#!/usr/bin/env bash
# freeze - record the QA-frozen commit that test_edit_ban diffs against (Stage 5 exit).
#
# Run by the Orchestrator after QA's tests are COMMITTED (red + compiling). Writes
# <gates>/.frozen with the current HEAD SHA and prints the line to record on the changelog
# item - the item's copy is the authoritative one; the file is a convenience mirror that
# test_edit_ban and the plugin hook read when no SHA is passed.
#
# Refuses a dirty tree (exit 2): the frozen point must contain QA's tests, not leave them
# uncommitted where the Engineer's tree would later "add" them.
#
# Exit 0 written, 2 refused/usage.
# Usage:  sh gates/freeze.sh [--config gates/gates.config.json] [--unit <ITEM-ID>]

set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/_common.sh"

GATE=freeze
require_git "$GATE"

UNIT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --unit) UNIT="$2"; shift 2 ;;
    --unit=*) UNIT="${1#--unit=}"; shift ;;
    --config|--config=*) [ "$1" = "--config" ] && shift; shift ;;   # accepted for run_all symmetry; unused
    *) shift ;;
  esac
done

TOP=$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null) || { echo "FAIL $GATE: not inside a git work tree"; exit 2; }
cd "$TOP" || exit 2
TOP=$(pwd)   # normalise to this shell's path form (Git Bash: /c/… vs C:/…)
REL=$(git -C "$HERE" rev-parse --show-prefix | sed 's#/$##'); [ -n "$REL" ] || REL="."

DIRTY=$( { git status --porcelain --untracked-files=all ; } | sed '/^$/d' | grep -v -E ' (sdd/)?gates/\.frozen$' || true)
if [ -n "$DIRTY" ]; then
  echo "FAIL $GATE: working tree is dirty - commit QA's tests first, then freeze:"
  printf '%s\n' "$DIRTY" | head -20 | while IFS= read -r l; do echo "  $l"; done
  exit 2
fi

SHA=$(git rev-parse HEAD)
DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
{
  echo "sha=$SHA"
  echo "date=$DATE"
  [ -n "$UNIT" ] && echo "unit=$UNIT"
  echo "# QA-frozen base for test_edit_ban. Mirror of the changelog item's 'frozen:' line; the item is authoritative."
} > "$HERE/.frozen"

echo "FROZEN $GATE: sha=$SHA ($REL/.frozen written)"
echo "  record on the changelog item:  frozen: $SHA"
echo "  then commit the marker:        git add $REL/.frozen && git commit -m \"chore(${UNIT:-<ITEM-ID>}): freeze tests at ${SHA%${SHA#???????}}\""
exit 0
