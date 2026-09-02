#!/usr/bin/env sh
# Unit test for plugin/hooks/persona-guard.sh: feeds PreToolUse JSON on stdin and checks exit codes.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO/plugin/hooks/persona-guard.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/proj/sdd/gates"
cp "$REPO/gates/gates.config.template.json" "$T/proj/sdd/gates/gates.config.json"
fails=0
case_() { # <want> <label> <persona-env> <marker> <path>
  want=$1; label=$2; penv=$3; marker=$4; path=$5
  rm -f "$T/proj/sdd/.persona"; [ -n "$marker" ] && printf '%s\n' "$marker" > "$T/proj/sdd/.persona"
  json=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"}}' "$path")
  if [ -n "$penv" ]; then rc=$(printf '%s' "$json" | SDD_PERSONA=$penv CLAUDE_PROJECT_DIR="$T/proj" sh "$HOOK" 2>"$T/err"; echo $?)
  else rc=$(printf '%s' "$json" | CLAUDE_PROJECT_DIR="$T/proj" sh "$HOOK" 2>"$T/err"; echo $?); fi
  if [ "$rc" = "$want" ]; then echo "ok    $label (rc=$rc)"; else echo "FAIL  $label (rc=$rc want $want)"; sed 's/^/      /' "$T/err"; fails=$((fails+1)); fi
}
P="$T/proj"
case_ 2 "engineer env + tests/ path"            engineer ""       "$P/tests/a.test"
case_ 2 "engineer env + *.test.* anywhere"      engineer ""       "$P/src/deep/foo.test.ts"
case_ 2 "engineer env + *Tests.cs"              engineer ""       "$P/src/FooTests.cs"
case_ 0 "engineer env + src path"               engineer ""       "$P/src/foo.ts"
case_ 0 "qa env + tests path"                   qa       ""       "$P/tests/a.test"
case_ 0 "no persona + tests path"               ""       ""       "$P/tests/a.test"
case_ 2 "marker engineer + tests path"          ""       engineer "$P/tests/a.test"
case_ 0 "marker qa + tests path"                ""       qa       "$P/tests/a.test"
case_ 2 "engineer + windows-style escaped path" engineer ""       "C:\\\\work\\\\proj\\\\tests\\\\a.test"
case_ 0 "engineer + spec shard"                 engineer ""       "$P/spec/x.body.md"
if [ "$fails" -eq 0 ]; then echo "HOOK PASS"; else echo "HOOK FAIL ($fails)"; exit 1; fi
