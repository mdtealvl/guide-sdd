#!/usr/bin/env sh
# GUIDE SDD — version consistency check for the framework repo (not a project gate).
# VERSION must equal: README.md header stamp, the first `## vX.Y.Z` heading in
# constitution.changelog.md, plugin/.claude-plugin/plugin.json "version" (when present), and the
# tag being released (optional arg, without the leading v).
# Usage: sh ci/version_check.sh [expected-version]
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO"
V="$(tr -d ' \r\n' < VERSION)"
fails=0
say() { echo "$1  $2"; }
chk() { if [ "$2" = "$V" ]; then say ok "$1 = $2"; else say FAIL "$1 = '$2' (VERSION = $V)"; fails=$((fails+1)); fi; }
chk "README header"   "$(grep -m1 -o -E '\*\*v[0-9]+\.[0-9]+(\.[0-9]+)? — ' README.md | sed -E 's/\*\*v([0-9.]+) — /\1/')"
chk "changelog tail"  "$(grep -o -E '^## v[0-9]+\.[0-9]+(\.[0-9]+)?' constitution.changelog.md | tail -1 | sed 's/^## v//')"
if [ -f plugin/.claude-plugin/plugin.json ]; then
  chk "plugin.json" "$(jq -r .version plugin/.claude-plugin/plugin.json)"
fi
if [ -n "${1:-}" ]; then chk "release tag" "$1"; fi
[ "$fails" -eq 0 ] && echo "VERSION $V consistent" || { echo "VERSION mismatch ($fails)"; exit 1; }
