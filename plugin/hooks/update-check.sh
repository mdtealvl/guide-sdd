#!/usr/bin/env sh
# GUIDE SDD update check - SessionStart (startup). Runs the bundled installer's `check --cached`: at most one
# release lookup a day, cached inside .git so the tree stays clean. Prints nothing when current, offline,
# or not a GUIDE repo. When a newer release exists its lines become session context, and the agent asks the
# human before any other work (AGENTS.md, "On boot"). It never updates anything itself. Always exits 0.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
[ -f sdd/.sdd-manifest.json ] || exit 0
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
out=$(sh "$ROOT/bin/install.sh" check --cached 2>/dev/null) && rc=0 || rc=$?
[ "$rc" = 3 ] || exit 0
latest=$(printf '%s\n' "$out" | sed -n 's/^UPDATE    guide-sdd \([^ ]*\) is available.*/\1/p')
plugin=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$ROOT/.claude-plugin/plugin.json" 2>/dev/null | head -1)
echo "GUIDE SDD update available - this repo's spine is older than the latest release."
printf '%s\n' "$out" | sed '/^next /d'   # the steps below replace the installer's generic next line
if [ -n "$plugin" ] && [ -n "$latest" ] && [ "$plugin" != "$latest" ]; then
  echo "plugin    the guide-sdd plugin is $plugin: run /plugin marketplace update guide-sdd first, so its installer (and merge rules) are the new release's"
fi
echo "Before any other work, ask the human one question: update GUIDE SDD now, or later? Never update unasked."
echo "On yes: sh \"$ROOT/bin/install.sh\" update --version v$latest  (Windows: pwsh \"$ROOT/bin/install.ps1\" update --version v$latest)"
echo "Then report every REFRESHED / MERGED / CONFIG / CONFLICT / REVIEW line. Exit 4 = conflicts: the project file is untouched and a"
echo "<file>.guide-merge beside it holds the merge with markers; resolve with the human, then commit the bump by itself."
exit 0
