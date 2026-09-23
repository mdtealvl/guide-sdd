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
glob_() { printf '{"tool_name":"Glob","tool_input":{"pattern":"*","path":"%s"}}' "$1"; }
# PG.1: same shapes as edit()/read_() but carrying agent_type, for agent_type-derived personas.
edit_agent() { printf '{"agent_type":"%s","tool_name":"%s","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"}}' "$3" "$1" "$2"; }
read_agent() { printf '{"agent_type":"%s","tool_name":"%s","tool_input":{"file_path":"%s"}}' "$3" "$1" "$2"; }
# PG.4: a plain Bash call (no agent fields) for the qa tripwire cases.
bash_() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }
# PG.5/PG.8: an attributed Bash call — <agent_type> <agent_id> <command> [session_id].
bash_agent() {
  if [ -n "${4:-}" ]; then
    printf '{"session_id":"%s","agent_type":"%s","agent_id":"%s","tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":{}}' "$4" "$1" "$2" "$3"
  else
    printf '{"agent_type":"%s","agent_id":"%s","tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":{}}' "$1" "$2" "$3"
  fi
}
# PG.5b: an Edit/Write-shaped --post/--stop call — <tool> <path> [agent_type] [agent_id].
post_edit() {
  if [ -n "${3:-}" ]; then
    printf '{"agent_type":"%s","agent_id":"%s","tool_name":"%s","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"},"tool_response":{}}' "$3" "${4:-}" "$1" "$2"
  else
    printf '{"tool_name":"%s","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"},"tool_response":{}}' "$1" "$2"
  fi
}
# PG.5c: a Stop-shaped call carrying agent_type/agent_id (no tool_name — Stop events carry none).
stop_agent() { printf '{"agent_type":"%s","agent_id":"%s","stop_hook_active":false}' "$1" "$2"; }

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

echo "-- PG.1 persona source precedence: agent_type first, then env, then marker"
run 2 "PG.1a agent_type=qa denies Read of src (blind), no env/marker" --pre "" "" "$(read_agent Read "$P/src/foo.ts" qa)"
check "$(test -f "$P/sdd/.persona" && echo present || echo absent)" absent "PG.1a agent_type persona (qa) writes no session stamp/marker"
run 2 "PG.1a agent_type=engineer denies Edit of tests, no env/marker" --pre "" "" "$(edit_agent Edit "$P/tests/a.test" engineer)"
check "$(test -f "$P/sdd/.persona" && echo present || echo absent)" absent "PG.1a agent_type persona (engineer) writes no session stamp/marker"
run 2 "PG.1a agent_type=qa-explore (qa- prefix) denies Read of src" --pre "" "" "$(read_agent Read "$P/src/foo.ts" qa-explore)"
run 2 "PG.1a agent_type=engineer-subagent (engineer- prefix) denies Edit tests" --pre "" "" "$(edit_agent Edit "$P/tests/a.test" engineer-subagent)"
run 0 "PG.1a agent_type=qax (no hyphen boundary) is not qa, falls through, allowed" --pre "" "" "$(read_agent Read "$P/src/foo.ts" qax)"
run 0 "PG.1a agent_type=engineerx (no hyphen boundary) is not engineer, falls through, allowed" --pre "" "" "$(edit_agent Edit "$P/tests/a.test" engineerx)"
run 0 "PG.1a agent_type=general-purpose, no env/marker: falls through, allowed" --pre "" "" "$(edit_agent Edit "$P/tests/a.test" general-purpose)"
run 2 "PG.1a agent_type=general-purpose falls through to env engineer" --pre engineer "" "$(edit_agent Edit "$P/tests/a.test" general-purpose)"
run 2 "PG.1a agent_type=Explore falls through to marker engineer" --pre "" engineer "$(edit_agent Edit "$P/tests/a.test" Explore)"
run 2 "PG.1a agent_type=validation falls through to marker engineer" --pre "" engineer "$(edit_agent Edit "$P/tests/a.test" validation)"
run 0 "PG.1a agent_type=qa overrides env engineer (Edit to tests allowed; qa doesn't gate edits)" --pre engineer "" "$(edit_agent Edit "$P/tests/a.test" qa)"
run 2 "PG.1a agent_type=engineer overrides env qa (Edit to tests still denied)" --pre qa "" "$(edit_agent Edit "$P/tests/a.test" engineer)"
run 2 "PG.1a agent_type=qa overrides env engineer (Read of src still denied)" --pre engineer "" "$(read_agent Read "$P/src/foo.ts" qa)"
run 0 "PG.1a agent_type=engineer overrides env qa (Read of src allowed)" --pre qa "" "$(read_agent Read "$P/src/foo.ts" engineer)"
run 2 "PG.1b no agent_type field, env engineer, tests path (fallback confirmed)" --pre engineer "" "$(edit Edit "$P/tests/a.test")"
run 2 "PG.1b agent_type empty string treated as absent, env engineer, tests path" --pre engineer "" "$(edit_agent Edit "$P/tests/a.test" "")"
run 2 "PG.1c no agent_type, no env, marker engineer, tests path (fallback confirmed)" --pre "" engineer "$(edit Edit "$P/tests/a.test")"
run 0 "PG.1c agent_type empty string, no env, marker qa, tests path (qa marker allows edit)" --pre "" qa "$(edit_agent Edit "$P/tests/a.test" "")"

echo "-- PG.2 no env, no marker, no persona agent_type: every pass exits 0"
run 0 "PG.2 --pre Edit tests, fully persona-less" --pre "" "" "$(edit Edit "$P/tests/a.test")"
run 0 "PG.2 --pre Read of code, fully persona-less" --pre "" "" "$(read_ Read "$P/src/foo.ts")"
printf 'dirt\n' >> "$P/tests/a.test"
run 0 "PG.2 --post sweep, fully persona-less, dirty test present" --post "" "" "$BASH"
run 0 "PG.2 --stop sweep, fully persona-less, dirty test present" --stop "" "" "$STOP"
( cd "$P" && git checkout -q -- tests )
run 0 "PG.2 --session-end, fully persona-less" --session-end "" "" "$(printf '{"session_id":"Z1"}')"

echo "-- PG.3 paths.code as a JSON array: qa blindness applies to every glob"
cp "$P/sdd/gates/gates.config.json" "$T/cfg.orig.json"
cat > "$P/sdd/gates/gates.config.json" <<'EOF'
{
  "clauseIdRegex": "\\b[A-Z]{2,}\\.\\d+\\b",
  "testClauseTag": "@clause:",
  "paths": {
    "spec": "spec/**/*.body.md",
    "tests": "tests/**",
    "code": ["src/**", "lib/**"]
  },
  "testGlobs": ["**/tests/**", "**/__tests__/**", "**/__mocks__/**", "**/*.test.*", "**/*.spec.*", "**/*Tests.cs", "**/*.snap", "**/jest.config.*", "**/vitest.config.*", "**/pytest.ini", "**/conftest.py"],
  "testTagExcludeGlobs": ["**/*.md", "**/*.txt"],
  "structureGlobs": ["**/*.structure.body.md"],
  "buildPlan": { "glob": "**/*.buildplan.md", "tokensPerChar": 0.25 },
  "baseRef": "main",
  "suiteCmd": "true",
  "unitIdRegex": "\\b[A-Z]{2,}-\\d+\\b",
  "foldCheck": { "backlogRoot": "backlog", "resolveCmd": null },
  "proseCheck": { "mode": "warn", "maxParaShare": 0.35, "maxParaWords": 100, "minWords": 120, "excludeGlobs": [] },
  "constitutionRules": [],
  "seamRules": [],
  "qaImportRules": []
}
EOF
mkdir -p "$P/lib"; printf 'more code\n' > "$P/lib/bar.ts"
run 2 "PG.3 qa Read denied under first array element (src/**)" --pre qa "" "$(read_ Read "$P/src/foo.ts")"
run 2 "PG.3 qa Read denied under second array element (lib/**)" --pre qa "" "$(read_ Read "$P/lib/bar.ts")"
run 2 "PG.3 qa Grep denied under second array element (lib/**)" --pre qa "" "$(grep_ "$P/lib")"
run 0 "PG.3 qa Read of spec still allowed (array config, unrelated path)" --pre qa "" "$(read_ Read "$P/spec/x.body.md")"
run 0 "PG.3 engineer Read of lib allowed (array config; engineer unaffected)" --pre engineer "" "$(read_ Read "$P/lib/bar.ts")"
cp "$T/cfg.orig.json" "$P/sdd/gates/gates.config.json"
rm -rf "$P/lib"

echo "-- PG.3b qa may Read/Grep/Glob test files that live inside paths.code, but not other code (issue #4)"
cp "$P/sdd/gates/gates.config.json" "$T/cfg.orig3.json"
cat > "$P/sdd/gates/gates.config.json" <<'EOF'
{
  "clauseIdRegex": "\\b[A-Z]{2,}\\.\\d+\\b",
  "testClauseTag": "@clause:",
  "paths": {
    "spec": "spec/**/*.body.md",
    "tests": "tests/**",
    "code": "src/**"
  },
  "testGlobs": ["**/tests/**", "**/__tests__/**", "**/__mocks__/**", "**/*.test.*", "**/*.spec.*", "**/*Tests.cs", "**/*.snap", "**/jest.config.*", "**/vitest.config.*", "**/pytest.ini", "**/conftest.py", "src/Tests/**"],
  "testTagExcludeGlobs": ["**/*.md", "**/*.txt"],
  "structureGlobs": ["**/*.structure.body.md"],
  "buildPlan": { "glob": "**/*.buildplan.md", "tokensPerChar": 0.25 },
  "baseRef": "main",
  "suiteCmd": "true",
  "unitIdRegex": "\\b[A-Z]{2,}-\\d+\\b",
  "foldCheck": { "backlogRoot": "backlog", "resolveCmd": null },
  "proseCheck": { "mode": "warn", "maxParaShare": 0.35, "maxParaWords": 100, "minWords": 120, "excludeGlobs": [] },
  "constitutionRules": [],
  "seamRules": [],
  "qaImportRules": []
}
EOF
mkdir -p "$P/src/Tests"; printf 'ok\n' > "$P/src/Tests/a.test"
( cd "$P" && git add -A && git commit -q -m "test: PG.3b test dir nested in paths.code" )
run 0 "PG.3b env qa Read of test file inside paths.code allowed (testGlobs carve-out)" --pre qa "" "$(read_ Read "$P/src/Tests/a.test")"
run 2 "PG.3b env qa Read of plain code file under same code dir still denied" --pre qa "" "$(read_ Read "$P/src/foo.ts")"
run 2 "PG.3b env qa Grep on ancestor code dir (src) still denied" --pre qa "" "$(grep_ "$P/src")"
run 2 "PG.3b env qa Glob on ancestor code dir (src) still denied" --pre qa "" "$(glob_ "$P/src")"
run 0 "PG.3b env qa Grep on testGlobs directory prefix (src/Tests) allowed" --pre qa "" "$(grep_ "$P/src/Tests")"
run 0 "PG.3b env qa Glob on testGlobs directory prefix (src/Tests) allowed" --pre qa "" "$(glob_ "$P/src/Tests")"
run 0 "PG.3b env qa Read allowed, backslash-style relative path (slash/backslash equivalent)" --pre qa "" "$(read_ Read "$P/src\\\\Tests\\\\a.test")"
run 2 "PG.3b env qa Read denied, backslash-style relative path (slash/backslash equivalent)" --pre qa "" "$(read_ Read "$P/src\\\\foo.ts")"
run 0 "PG.3b agent_type=qa Read of test file inside paths.code allowed" --pre "" "" "$(read_agent Read "$P/src/Tests/a.test" qa)"
run 2 "PG.3b agent_type=qa Read of plain code file still denied" --pre "" "" "$(read_agent Read "$P/src/foo.ts" qa)"
run 0 "PG.3b marker qa Read of test file inside paths.code allowed" --pre "" qa "$(read_ Read "$P/src/Tests/a.test")"
run 2 "PG.3b marker qa Read of plain code file still denied" --pre "" qa "$(read_ Read "$P/src/foo.ts")"
run 0 "PG.3b engineer Read of test file inside paths.code allowed (unaffected control)" --pre engineer "" "$(read_ Read "$P/src/Tests/a.test")"
cp "$T/cfg.orig3.json" "$P/sdd/gates/gates.config.json"
rm -rf "$P/src/Tests"
( cd "$P" && git add -A && git commit -q -m "test: restore config after PG.3b" )

echo "-- PG.4 qa Bash tripwire: paths.code touched by a shell command"
run 2 "PG.4 qa bash cat src file denied (tripwire)" --pre qa "" "$(bash_ "cat src/foo.ts")"
check "$(grep -qi tripwire "$T/err" && echo yes || echo no)" yes "PG.4 tripwire deny message names itself a tripwire"
run 0 "PG.4 qa bash cat src test file allowed (matches testGlobs exception)" --pre qa "" "$(bash_ "cat src/foo.test.ts")"
run 0 "PG.4 qa bash dotnet test filter allowed (no code path token)" --pre qa "" "$(bash_ "dotnet test --filter X")"
run 0 "PG.4 qa bash cat spec file allowed" --pre qa "" "$(bash_ "cat spec/x.body.md")"
run 0 "PG.4 qa bash no path tokens allowed" --pre qa "" "$(bash_ "echo hello world")"
run 2 "PG.4 qa bash backslash-style src path denied (slash/backslash equivalent)" --pre qa "" "$(bash_ "type src\\\\foo.ts")"
run 0 "PG.4 engineer bash cat src file allowed (tripwire is qa-only)" --pre engineer "" "$(bash_ "cat src/foo.ts")"
run 0 "PG.4 qa bash different top dir (src2) is not a prefix match, allowed" --pre qa "" "$(bash_ "cat src2/notes.txt")"
run 2 "PG.4 qa bash directory-only src token denied" --pre qa "" "$(bash_ "rm -rf src/")"
run 2 "PG.4 qa bash mixed args: one token matches testGlobs, one doesn't -> still denied" --pre qa "" "$(bash_ "diff src/foo.ts src/foo.test.ts")"
run 2 "F2 qa bash escaped quotes don't truncate the command (code path still seen)" --pre qa "" "$(bash_ 'echo \"a\", ; cat src/foo.ts')"
run 2 "F2 qa bash embedded fake JSON keys in the command don't confuse parsing (code path still seen)" --pre qa "" "$(bash_ 'echo {\"agent_type\":\"x\"} src/foo.ts')"
run 0 "F2 control: same escaped-quote shape naming only a test path is allowed" --pre qa "" "$(bash_ 'echo \"a\", ; cat tests/a.test')"
run 2 "PG.4 qa bash newline-separated tokens denied (R2)" --pre qa "" "$(bash_ 'ls\nsrc/foo.ts')"
run 2 "PG.4 qa bash tab-separated tokens denied (R2)" --pre qa "" "$(bash_ 'cat\tsrc/foo.ts')"
run 2 "PG.4 qa bash CR-separated tokens denied (R2)" --pre qa "" "$(bash_ 'cat\rsrc/foo.ts')"
run 2 "PG.4 qa bash newline line-continuation still denied (R2)" --pre qa "" "$(bash_ 'cat \\\nsrc/foo.ts')"
run 0 "PG.4 control: newline-separated test-only command allowed (R2)" --pre qa "" "$(bash_ 'ls\ntests/a.test')"

echo "-- PG.5 engineer-agent (agent_type) sweep is attributed to agent_id, snapshotted at --pre on a Bash call"
( cd "$P" && git checkout -q -- tests spec ) 2>/dev/null
printf 'preexisting-dirt-from-someone-else\n' >> "$P/tests/a.test"
run 0 "PG.5 pre snapshot captures pre-existing dirt (agent AG1)" --pre "" "" "$(bash_agent engineer AG1 true)"
run 0 "PG.5 post forgives pre-existing dirt unchanged since snapshot (agent AG1)" --post "" "" "$(bash_agent engineer AG1 true)"
( cd "$P" && git checkout -q -- tests )
run 0 "PG.5 pre snapshot on clean tree (agent AG2)" --pre "" "" "$(bash_agent engineer AG2 true)"
printf 'the attributed call wrote this\n' >> "$P/tests/a.test"
run 2 "PG.5 post denies path dirtied by the attributed call itself (agent AG2)" --post "" "" "$(bash_agent engineer AG2 true)"
( cd "$P" && git checkout -q -- tests )
printf 'baseline dirt\n' >> "$P/tests/a.test"
run 0 "PG.5 pre snapshot with pre-existing dirt (agent AG3)" --pre "" "" "$(bash_agent engineer AG3 true)"
printf 'further changed after snapshot\n' >> "$P/tests/a.test"
run 2 "PG.5 post denies pre-existing path that changed further since snapshot (agent AG3)" --post "" "" "$(bash_agent engineer AG3 true)"
( cd "$P" && git checkout -q -- tests )
printf 'preexisting struct dirt\n' >> "$P/spec/x.structure.body.md"
run 0 "PG.5 pre snapshot captures pre-existing structure dirt (agent AG4)" --pre "" "" "$(bash_agent engineer AG4 true)"
run 0 "PG.5 post forgives pre-existing structure dirt unchanged (agent AG4)" --post "" "" "$(bash_agent engineer AG4 true)"
( cd "$P" && git checkout -q -- spec )
printf 'dirt via marker/env persona (no attribution)\n' >> "$P/tests/a.test"
run 2 "PG.5 marker/env engineer persona keeps whole-tree sweep, unaffected by any snapshot" --post engineer "" "$BASH"
( cd "$P" && git checkout -q -- tests )

echo "-- PG.5a orchestrator ruling: no snapshot (never taken, or cleared) => empty baseline, any dirty test path denied"
printf 'dirty with no snapshot ever taken for this agent_id\n' >> "$P/tests/a.test"
run 2 "PG.5a post denies dirty test with no prior --pre snapshot for this agent_id (empty baseline)" --post "" "" "$(bash_agent engineer AG9 true)"
( cd "$P" && git checkout -q -- tests )

echo "-- PG.5b orchestrator ruling: --post after a non-Bash tool (Edit/Write) does no sweep for agent_type=engineer"
printf 'dirty test, but the --post tool is Edit, not Bash\n' >> "$P/tests/a.test"
run 0 "PG.5b post after non-Bash tool (Edit) for agent_type=engineer does no sweep" --post "" "" "$(post_edit Edit "$P/tests/a.test" engineer AG10)"
run 2 "PG.5b control: marker/env engineer post after Edit still sweeps whole tree (today's behaviour)" --post engineer "" "$(post_edit Edit "$P/tests/a.test")"
( cd "$P" && git checkout -q -- tests )

echo "-- PG.5c orchestrator ruling: --stop does no sweep for agent_type=engineer"
printf 'dirty test for stop no-sweep check\n' >> "$P/tests/a.test"
run 0 "PG.5c stop for agent_type=engineer does no sweep (exit 0 despite dirty test)" --stop "" "" "$(stop_agent engineer AG11)"
run 2 "PG.5c control: marker/env engineer stop still sweeps whole tree (today's behaviour)" --stop engineer "" "$STOP"
( cd "$P" && git checkout -q -- tests )

echo "-- F1 / PG.5d: the engineer sweep must also run on a FAILED Bash call, and hooks.json must wire PostToolUseFailure"
HOOKSJSON="$REPO/plugin/hooks/hooks.json"
startln=$(grep -n '"PostToolUseFailure"' "$HOOKSJSON" | head -1 | cut -d: -f1)
if [ -n "$startln" ]; then
  relend=$(tail -n +"$((startln+1))" "$HOOKSJSON" | grep -n '^    "[A-Za-z]*":' | head -1 | cut -d: -f1)
  if [ -n "$relend" ]; then endln=$((startln+relend-1)); else endln=$((startln+20)); fi
  block=$(sed -n "${startln},${endln}p" "$HOOKSJSON")
else
  block=""
fi
if printf '%s\n' "$block" | grep -qi '"matcher".*bash'; then matchok=yes; else matchok=no; fi
check "$matchok" yes "F1 hooks.json PostToolUseFailure matcher includes Bash"
if printf '%s\n' "$block" | grep -Eq '"command":.*--post"[[:space:]]*$'; then cmdok=yes; else cmdok=no; fi
check "$cmdok" yes "F1 hooks.json PostToolUseFailure command ends in --post"
failure_json() { printf '{"hook_event_name":"PostToolUseFailure","agent_type":"%s","agent_id":"%s","tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":{}}' "$1" "$2" "$3"; }
run 0 "F1 pre snapshot before a failed-call post check (agent AGF)" --pre "" "" "$(bash_agent engineer AGF true)"
printf 'dirt introduced by the failed bash call\n' >> "$P/tests/a.test"
run 2 "F1 post denies on a PostToolUseFailure-shaped input (a failed Bash call is still swept)" --post "" "" "$(failure_json engineer AGF true)"
( cd "$P" && git checkout -q -- tests )

echo "-- F3 / PG.5: two concurrent engineer agent_ids in the same session don't collide in the per-agent snapshot state"
( cd "$P" && git checkout -q -- tests ) 2>/dev/null
run 0 "F3 pre snapshot (agent A, session SF3)" --pre "" "" "$(bash_agent engineer AGA true SF3)"
printf 'agent A dirtied this between the two pre snapshots\n' >> "$P/tests/a.test"
run 0 "F3 pre snapshot (agent B, session SF3); tree already shows A's dirt" --pre "" "" "$(bash_agent engineer AGB true SF3)"
run 2 "F3 post denies for agent A (path was new since A's own snapshot)" --post "" "" "$(bash_agent engineer AGA true SF3)"
run 0 "F3 post allows for agent B (same path already dirty at B's snapshot; no cross-agent hash collision)" --post "" "" "$(bash_agent engineer AGB true SF3)"
( cd "$P" && git checkout -q -- tests )

echo "-- PG.6 nested repo under a testGlobs glob: sweeps also check dirty/untracked inside it"
mkdir -p "$P/nested/tests"
( cd "$P/nested" && git init -q -b main . && git config user.email ci@guide-sdd && git config user.name ci \
  && printf 'ok\n' > tests/n.test && git add -A && git commit -q -m seed ) || { echo "FAIL  PG.6 nested repo setup"; fails=$((fails+1)); }
cp "$P/sdd/gates/gates.config.json" "$T/cfg.orig2.json"
cat > "$P/sdd/gates/gates.config.json" <<'EOF'
{
  "clauseIdRegex": "\\b[A-Z]{2,}\\.\\d+\\b",
  "testClauseTag": "@clause:",
  "paths": {
    "spec": "spec/**/*.body.md",
    "tests": "tests/**",
    "code": "src/**"
  },
  "testGlobs": ["**/tests/**", "**/__tests__/**", "**/__mocks__/**", "**/*.test.*", "**/*.spec.*", "**/*Tests.cs", "**/*.snap", "**/jest.config.*", "**/vitest.config.*", "**/pytest.ini", "**/conftest.py", "nested/tests/**"],
  "testTagExcludeGlobs": ["**/*.md", "**/*.txt"],
  "structureGlobs": ["**/*.structure.body.md"],
  "buildPlan": { "glob": "**/*.buildplan.md", "tokensPerChar": 0.25 },
  "baseRef": "main",
  "suiteCmd": "true",
  "unitIdRegex": "\\b[A-Z]{2,}-\\d+\\b",
  "foldCheck": { "backlogRoot": "backlog", "resolveCmd": null },
  "proseCheck": { "mode": "warn", "maxParaShare": 0.35, "maxParaWords": 100, "minWords": 120, "excludeGlobs": [] },
  "constitutionRules": [],
  "seamRules": [],
  "qaImportRules": []
}
EOF
( cd "$P" && git add sdd/gates/gates.config.json && git commit -q -m "test: nested testGlobs config" )
run 0 "PG.6 post sweep clean (nested repo committed clean)" --post engineer "" "$BASH"
printf 'edited\n' >> "$P/nested/tests/n.test"
run 2 "PG.6 post sweep detects dirty tracked file inside nested repo" --post engineer "" "$BASH"
( cd "$P/nested" && git checkout -q -- tests )
printf 'new\n' > "$P/nested/tests/new.test"
run 2 "PG.6 post sweep detects untracked new file inside nested repo" --post engineer "" "$BASH"
run 2 "PG.6 stop sweep detects untracked new file inside nested repo" --stop engineer "" "$STOP"
rm "$P/nested/tests/new.test"
printf 'edited\n' >> "$P/nested/tests/n.test"
run 0 "PG.6 post sweep: qa persona ignores nested dirt too" --post qa "" "$BASH"
( cd "$P/nested" && git checkout -q -- tests )
cp "$T/cfg.orig2.json" "$P/sdd/gates/gates.config.json"
( cd "$P" && git add sdd/gates/gates.config.json && git commit -q -m "test: restore config" )

echo "-- PG.7 (regression) satisfied by the unmodified cases above still passing; no new case needed"

echo "-- PG.8 --session-end removes this session's attributed-sweep snapshot state too"
( cd "$P" && git checkout -q -- tests ) 2>/dev/null
printf 'preexisting dirt for session snapshot test\n' >> "$P/tests/a.test"
run 0 "PG.8 pre snapshot before session-end (agent AGZ, session SS1)" --pre "" "" "$(bash_agent engineer AGZ true SS1)"
run 0 "PG.8 post forgives pre-existing dirt while snapshot lives (session SS1)" --post "" "" "$(bash_agent engineer AGZ true SS1)"
run 0 "PG.8 session-end SS1" --session-end "" "" "$(printf '{"session_id":"SS1","reason":"other"}')"
run 2 "PG.8 post no longer forgives same dirt after session-end cleared the snapshot" --post "" "" "$(bash_agent engineer AGZ true SS1)"
( cd "$P" && git checkout -q -- tests )

echo "-- PG.9 cost: --pre for a non-Bash tool with no persona spawns no process (proxy: near-instant, ignores tree size)"
mkdir -p "$P/assets2"; i=0; while [ $i -lt 500 ]; do printf 'x' > "$P/assets2/g$i.png"; i=$((i+1)); done
t0=$(date +%s)
run 0 "PG.9 pre no-persona Read is cheap, ignores untracked tree size" --pre "" "" "$(read_ Read "$P/src/foo.ts")"
t1=$(date +%s)
echo "      no-persona pre over 500 untracked assets took $((t1-t0))s"
[ $((t1-t0)) -le 5 ] || { echo "FAIL  PG.9 no-persona pre exceeded 5s bound (expected near-instant / no process spawn)"; fails=$((fails+1)); }
rm -rf "$P/assets2"

if [ "$fails" -eq 0 ]; then echo "HOOK PASS"; else echo "HOOK FAIL ($fails)"; exit 1; fi
