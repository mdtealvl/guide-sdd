#!/usr/bin/env sh
# Unit test for plugin/hooks/persona-guard.sh: feeds hook JSON on stdin and checks exit codes for the
# four passes (--pre edit/read deny, --post and --stop working-tree sweeps, --session-end marker removal),
# the marker session stamp, and the sweep cost bound.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO/plugin/hooks/persona-guard.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
P="$T/proj"
mkdir -p "$P/sdd/gates" "$P/tests" "$P/src" "$P/spec"
cp "$REPO/gates/gates.config.template.json" "$P/sdd/gates/gates.config.json"
( cd "$P" && git init -q -b main . && git config user.email ci@guide-sdd && git config user.name ci \
  && printf 'ok\n' > tests/a.test && printf 'code\n' > src/foo.ts && printf 'x\n' > spec/x.body.md && printf 's\n' > spec/x.structure.body.md \
  && git add -A && git commit -q -m seed ) || { echo "setup failed"; exit 1; }
fails=0
run() { # <want> <label> <mode> <persona-env> <marker> <json>
  want=$1; label=$2; mode=$3; penv=$4; marker=$5; json=$6
  rm -f "$P/sdd/.persona"; [ -n "$marker" ] && printf '%s\n' "$marker" > "$P/sdd/.persona"
  if [ -n "$penv" ]; then rc=$(printf '%s' "$json" | SDD_PERSONA=$penv CLAUDE_PROJECT_DIR="$P" sh "$HOOK" $mode 2>"$T/err"; echo $?)
  else rc=$(printf '%s' "$json" | CLAUDE_PROJECT_DIR="$P" sh "$HOOK" $mode 2>"$T/err"; echo $?); fi
  if [ "$rc" = "$want" ]; then echo "ok    $label (rc=$rc)"; else echo "FAIL  $label (rc=$rc want $want)"; sed 's/^/      /' "$T/err"; fails=$((fails+1)); fi
}
edit() { printf '{"tool_name":"%s","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"}}' "$1" "$2"; }
read_() { printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2"; }
grep_() { printf '{"tool_name":"Grep","tool_input":{"pattern":"x","path":"%s"}}' "$1"; }

echo "-- pre: engineer edit deny"
run 2 "engineer env + tests/ path"              --pre engineer ""       "$(edit Edit "$P/tests/a.test")"
run 2 "engineer env + *.test.* anywhere"        --pre engineer ""       "$(edit Write "$P/src/deep/foo.test.ts")"
run 2 "engineer env + root-level *.spec.*"      --pre engineer ""       "$(edit Edit "$P/foo.spec.ts")"
run 2 "engineer env + nested tests dir"         --pre engineer ""       "$(edit Edit "$P/packages/api/tests/foo.js")"
run 2 "engineer env + *Tests.cs"                --pre engineer ""       "$(edit Edit "$P/src/FooTests.cs")"
run 2 "engineer env + jest.config"              --pre engineer ""       "$(edit Edit "$P/jest.config.js")"
run 2 "engineer env + gate config"              --pre engineer ""       "$(edit Edit "$P/sdd/gates/gates.config.json")"
run 2 "engineer env + gate script"              --pre engineer ""       "$(edit Write "$P/sdd/gates/test_edit_ban.sh")"
run 2 "engineer env + .frozen marker"           --pre engineer ""       "$(edit Write "$P/sdd/gates/.frozen")"
run 2 "engineer env + .persona marker"          --pre engineer ""       "$(edit Write "$P/sdd/.persona")"
run 2 "engineer + NotebookEdit test path"       --pre engineer ""       "$(printf '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"%s"}}' "$P/tests/nb.ipynb")"
run 0 "engineer env + src path"                 --pre engineer ""       "$(edit Edit "$P/src/foo.ts")"
run 0 "engineer env + spec shard"               --pre engineer ""       "$(edit Edit "$P/spec/x.body.md")"
run 2 "engineer env + structure shard (frozen diagram)" --pre engineer "" "$(edit Edit "$P/spec/x.structure.body.md")"
run 2 "engineer env + new structure shard anywhere" --pre engineer ""   "$(edit Write "$P/spec/working/NEW-1.structure.body.md")"
run 0 "qa env + structure shard"                --pre qa       ""       "$(edit Edit "$P/spec/x.structure.body.md")"
run 0 "engineer Read of a test (allowed)"       --pre engineer ""       "$(read_ Read "$P/tests/a.test")"
run 2 "marker engineer + tests path"            --pre ""       engineer "$(edit Edit "$P/tests/a.test")"
run 2 "engineer + windows-style escaped path"   --pre engineer ""       "$(edit Edit "C:\\\\work\\\\proj\\\\tests\\\\a.test")"
run 0 "no persona + tests path"                 --pre ""       ""       "$(edit Edit "$P/tests/a.test")"
run 0 "qa env + tests path"                     --pre qa       ""       "$(edit Edit "$P/tests/a.test")"
run 0 "marker qa + tests path"                  --pre ""       qa       "$(edit Edit "$P/tests/a.test")"

echo "-- pre: qa read deny (blind to paths.code)"
run 2 "qa Read of src file"                     --pre qa       ""       "$(read_ Read "$P/src/foo.ts")"
run 2 "qa Grep under src"                       --pre qa       ""       "$(grep_ "$P/src")"
run 0 "qa Read of spec shard"                   --pre qa       ""       "$(read_ Read "$P/spec/x.body.md")"
run 0 "qa Read of a test"                       --pre qa       ""       "$(read_ Read "$P/tests/a.test")"
run 0 "engineer Read of src (allowed)"          --pre engineer ""       "$(read_ Read "$P/src/foo.ts")"

echo "-- pre: fail closed without config"
mv "$P/sdd/gates/gates.config.json" "$T/cfg.bak"
run 2 "engineer edit with config missing"       --pre engineer ""       "$(edit Edit "$P/src/foo.ts")"
run 0 "qa read with config missing"             --pre qa       ""       "$(read_ Read "$P/src/foo.ts")"
mv "$T/cfg.bak" "$P/sdd/gates/gates.config.json"

echo "-- post / stop: working-tree sweep"
BASH='{"tool_name":"Bash","tool_input":{"command":"cat > tests/a.test"},"tool_response":{}}'
STOP='{"stop_hook_active":false}'
STOPACTIVE='{"stop_hook_active":true}'
run 0 "post sweep clean tree"                   --post engineer ""      "$BASH"
printf 'edited\n' >> "$P/tests/a.test"
run 2 "post sweep: dirty tracked test"          --post engineer ""      "$BASH"
run 2 "stop sweep: dirty tracked test"          --stop engineer ""      "$STOP"
run 0 "stop sweep skipped when stop_hook_active" --stop engineer ""     "$STOPACTIVE"
run 0 "post sweep: qa persona ignores dirt"     --post qa       ""      "$BASH"
( cd "$P" && git checkout -q -- tests )
printf 'new\n' > "$P/tests/new.test"
run 2 "post sweep: untracked new test"          --post engineer ""      "$BASH"
rm "$P/tests/new.test"
printf 'edited\n' >> "$P/spec/x.structure.body.md"
run 2 "post sweep: dirty structure shard"       --post engineer ""      "$BASH"
run 0 "post sweep: qa persona, dirty structure shard" --post qa  ""      "$BASH"
( cd "$P" && git checkout -q -- spec )
( cd "$P" && git mv tests/a.test src/a_helper.js )
run 2 "post sweep: test renamed out of tests/"  --post engineer ""      "$BASH"
( cd "$P" && git mv src/a_helper.js tests/a.test )
printf '{}\n' > "$P/sdd/gates/gates.config.json.tmp"; mv "$P/sdd/gates/gates.config.json.tmp" "$P/sdd/gates/gates.config.json"
run 2 "post sweep: gate config edited"          --post engineer ""      "$BASH"
( cd "$P" && git checkout -q -- sdd/gates )
# committed edit hidden from git status but visible vs .frozen
( cd "$P" && sha=$(git rev-parse HEAD) && printf 'sha=%s\n' "$sha" > sdd/gates/.frozen && git add sdd/gates/.frozen && git commit -q -m freeze \
  && printf 'edited\n' >> tests/a.test && git commit -q -am "sneaky" )
run 2 "post sweep: committed test edit vs .frozen" --post engineer ""   "$BASH"
run 0 "post sweep: qa persona, committed edit"  --post qa       ""      "$BASH"
( cd "$P" && git reset -q --hard HEAD~2 )

echo "-- marker session stamp (stale marker is ignored, never obeyed)"
sedit() { printf '{"session_id":"%s","tool_name":"%s","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"}}' "$1" "$2" "$3"; }
check() { if [ "$1" = "$2" ]; then echo "ok    $3"; else echo "FAIL  $3 (got [$1] want [$2])"; fails=$((fails+1)); fi; }
run 2 "own-session stamp + tests path"          --pre "" "engineer
session=S1"                                                            "$(sedit S1 Edit "$P/tests/a.test")"
run 0 "foreign-session stamp + tests path"      --pre "" "engineer
session=S1"                                                            "$(sedit S2 Edit "$P/tests/a.test")"
check "$(test -f "$P/sdd/.persona" && echo kept)" kept "foreign-stamped marker is left in place"
run 0 "foreign-session stamp: post sweep skipped" --post "" "engineer
session=S1"                                                            "$(printf '{"session_id":"S2","tool_name":"Bash","tool_input":{"command":"x"}}')"
run 0 "unstamped marker + src path (adopts session)" --pre "" engineer "$(sedit S1 Edit "$P/src/foo.ts")"
check "$(sed -n 's/^session=//p' "$P/sdd/.persona")" S1 "marker stamped with the first session seen"
check "$(head -1 "$P/sdd/.persona" | tr -d '\r\n')" engineer "persona line intact after stamping"
printf 'engineer' > "$P/sdd/.persona"   # no trailing newline (a Write-tool marker)
rc=$(printf '%s' "$(sedit S1 Edit "$P/src/foo.ts")" | CLAUDE_PROJECT_DIR="$P" sh "$HOOK" --pre 2>/dev/null; echo $?)
check "$rc" 0 "unterminated marker + src path"
check "$(head -1 "$P/sdd/.persona" | tr -d '\r\n')" engineer "unterminated marker gains a newline before the stamp"
check "$(sed -n 's/^session=//p' "$P/sdd/.persona")" S1 "unterminated marker stamped"
run 2 "no session_id in input: legacy marker still enforced" --pre "" engineer "$(edit Edit "$P/tests/a.test")"
run 0 "no marker + session_id: allowed"                --pre "" ""       "$(sedit S1 Edit "$P/tests/a.test")"
: > "$P/sdd/.persona"; rc=$(printf '%s' "$(sedit S1 Edit "$P/src/foo.ts")" | CLAUDE_PROJECT_DIR="$P" sh "$HOOK" --pre 2>/dev/null; echo $?)
check "$rc$(cat "$P/sdd/.persona")" 0 "empty marker stays empty (no stamp without a persona)"
run 0 "env persona beats a foreign stamp (qa env, src edit)" --pre qa "engineer
session=S9"                                                            "$(sedit S1 Edit "$P/src/foo.ts")"

echo "-- session-end clears the marker"
run 0 "session-end, unstamped marker"           --session-end "" engineer "$(printf '{"session_id":"S1","reason":"other"}')"
check "$(test -f "$P/sdd/.persona" && echo kept || echo removed)" removed "unstamped marker removed at session end"
run 0 "session-end, own stamp"                  --session-end "" "engineer
session=S1"                                                            "$(printf '{"session_id":"S1","reason":"clear"}')"
check "$(test -f "$P/sdd/.persona" && echo kept || echo removed)" removed "own-stamped marker removed at session end"
run 0 "session-end, foreign stamp"              --session-end "" "engineer
session=S1"                                                            "$(printf '{"session_id":"S2","reason":"other"}')"
check "$(test -f "$P/sdd/.persona" && echo kept || echo removed)" kept "another session's marker survives our session end"
run 0 "session-end, no marker"                  --session-end "" ""      "$(printf '{"session_id":"S1"}')"

echo "-- sweep cost is O(globs), not O(paths)"
mkdir -p "$P/assets"; i=0; while [ $i -lt 500 ]; do printf 'x' > "$P/assets/f$i.png"; i=$((i+1)); done
printf 'new\n' > "$P/tests/new.test"
t0=$(date +%s)
run 2 "post sweep: 500 untracked assets + 1 untracked test" --post engineer "" "$BASH"
t1=$(date +%s)
echo "      sweep over 501 untracked paths took $((t1-t0))s"
check "$(grep -c 'tests/new.test (testGlob' "$T/err")" 1 "sweep names the test once"
check "$(grep -c 'assets/' "$T/err")" 0 "sweep names no asset"
[ $((t1-t0)) -le 30 ] || { echo "FAIL  sweep exceeded 30s"; fails=$((fails+1)); }
rm -rf "$P/assets" "$P/tests/new.test"

if [ "$fails" -eq 0 ]; then echo "HOOK PASS"; else echo "HOOK FAIL ($fails)"; exit 1; fi
