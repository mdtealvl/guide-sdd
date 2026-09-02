#!/usr/bin/env sh
# GUIDE SDD persona guard — PreToolUse hook on Edit|Write|MultiEdit.
# While the active persona is `engineer`, deny edits to files matching gates.config.json testGlobs:
# test_edit_ban (invariant 3) enforced at edit time, not only at gate time.
# Persona source, first match wins: env SDD_PERSONA, else the marker file sdd/.persona (written by the
# sdd-persona skill at Stage 6 entry, cleared at exit). Anything but `engineer` allows the edit.
# Exit 0 = allow · exit 2 = deny (message on stderr goes back to the agent).
persona="${SDD_PERSONA:-}"
root="${CLAUDE_PROJECT_DIR:-$PWD}"; root=$(printf '%s' "$root" | sed 's#\\#/#g; s#/$##')
if [ -z "$persona" ]; then
  for m in "$root/sdd/.persona" "$root/.persona"; do
    if [ -f "$m" ]; then persona=$(tr -d ' \r\n' < "$m"); break; fi
  done
fi
[ "$persona" = engineer ] || exit 0

in=$(cat)
fp=$(printf '%s' "$in" | sed -n 's/.*"file_path":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -n "$fp" ] || exit 0
fp=$(printf '%s' "$fp" | sed 's#\\\\#/#g; s#\\#/#g')
rel=${fp#"$root"/}

cfg=""
for c in "$root/sdd/gates/gates.config.json" "$root/gates/gates.config.json"; do
  if [ -f "$c" ]; then cfg=$c; break; fi
done
[ -n "$cfg" ] || exit 0
globs=$(tr -d '\r\n' < "$cfg" | sed -n 's/.*"testGlobs":[[:space:]]*\[\([^]]*\)\].*/\1/p' | tr ',' '\n' | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//; /^$/d')
[ -n "$globs" ] || exit 0

hit=$(printf '%s\n' "$globs" | while IFS= read -r g; do
  re=$(printf '%s' "$g" | sed 's/[.+^$(){}|]/\\&/g; s#\*\*/#@DS@#g; s#\*\*#@DD@#g; s#\*#[^/]*#g; s#?#[^/]#g; s#@DS@#(.*/)?#g; s#@DD@#.*#g')
  if printf '%s' "$rel" | grep -Eq "^${re}\$" || printf '%s' "$rel" | grep -Eq "^(.*/)?${re}\$"; then
    printf '%s' "$g"; break
  fi
done)
[ -n "$hit" ] || exit 0
echo "GUIDE SDD persona guard: SDD_PERSONA=engineer may not edit test files ($rel matches testGlob '$hit'). Tests belong to QA (invariant 3) - surface the need in the changelog item instead." >&2
exit 2
