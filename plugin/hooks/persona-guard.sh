#!/usr/bin/env sh
# GUIDE SDD persona guard - three passes, one script (the TEA write-time-control shape):
#   --pre  (PreToolUse; default)  engineer: deny Edit/Write/MultiEdit/NotebookEdit to any testGlobs path,
#                                 to the gate directory (config + scripts) and to the .persona/.frozen markers;
#                                 FAIL CLOSED (deny) when the gate config cannot be read.
#                                 qa: deny Read/Grep/Glob whose path is under paths.code - QA is blind to the
#                                 implementation (invariant 3); it reads spec + tests only.
#   --post (PostToolUse)          engineer: sweep the working tree after ANY tool (Bash heredocs, sed -i, mv,
#                                 git checkout, NotebookEdit): a test path or gate file that differs from the
#                                 frozen base (gates/.frozen) or is dirty/untracked -> exit 2 naming the paths
#                                 and the revert command. The write already happened; the sweep makes it loud.
#   --stop (Stop)                 engineer: the same sweep at turn end - catches a codegen script that wrote
#                                 files it never named. Skipped when stop_hook_active is set (no loops).
# Persona source, first match wins: env SDD_PERSONA, else the marker file sdd/.persona (written by the
# sdd-persona skill). Anything but engineer / qa allows everything.
# Exit 0 = allow · exit 2 = deny (message on stderr goes back to the agent).
# Tripwire, not proof: the Stage-7 gate test_edit_ban is the proof (it diffs the QA-frozen SHA).

mode=pre
case "${1:-}" in --post) mode=post ;; --stop) mode=stop ;; esac

persona="${SDD_PERSONA:-}"
root="${CLAUDE_PROJECT_DIR:-}"
[ -n "$root" ] || root=$(git rev-parse --show-toplevel 2>/dev/null)
[ -n "$root" ] || root=$PWD
root=$(printf '%s' "$root" | sed 's#\\#/#g; s#/$##')
if [ -z "$persona" ]; then
  for m in "$root/sdd/.persona" "$root/.persona"; do
    if [ -f "$m" ]; then persona=$(tr -d ' \r\n' < "$m"); break; fi
  done
fi
case "$persona" in engineer|qa) ;; *) exit 0 ;; esac

in=$(cat)
jstr() { printf '%s' "$in" | sed -n "s/.*\"$1\":[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1; }
tool=$(jstr tool_name)

if [ "$mode" = stop ]; then
  case "$in" in *'"stop_hook_active":'*true*) exit 0 ;; esac
fi

# --- config: testGlobs, paths.code, gate dir ---------------------------------------------------
cfg=""
for c in "$root/sdd/gates/gates.config.json" "$root/gates/gates.config.json"; do
  if [ -f "$c" ]; then cfg=$c; break; fi
done
if [ -z "$cfg" ]; then
  if [ "$persona" = engineer ] && [ "$mode" = pre ]; then
    case "$tool" in Edit|Write|MultiEdit|NotebookEdit)
      echo "GUIDE SDD persona guard: persona=engineer but gates.config.json was not found under $root - refusing edits (fail closed). Run INIT section 5 or clear the persona." >&2
      exit 2 ;;
    esac
  fi
  exit 0
fi
gd=$(dirname "$cfg"); gd=${gd#"$root"/}
flat=$(tr -d '\r\n' < "$cfg")
arr() { printf '%s' "$flat" | sed -n "s/.*\"$1\":[[:space:]]*\[\([^]]*\)\].*/\1/p" | tr ',' '\n' | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//; /^$/d'; }
globs=$(arr testGlobs)
code=$(printf '%s' "$flat" | sed -n 's/.*"paths":[[:space:]]*{[^}]*"code":[[:space:]]*"\([^"]*\)".*/\1/p')

# glob -> anchored ERE, the bank's one dialect: ** spans directories, * does not.
g2re() { printf '%s' "$1" | sed 's/[.+^$(){}|]/\\&/g; s#\*\*/#@DS@#g; s#\*\*#@DD@#g; s#\*#[^/]*#g; s#?#[^/]#g; s#@DS@#(.*/)?#g; s#@DD@#.*#g'; }
matches_any() { # <path> <globs-newline> -> prints the matching glob
  p=$1
  printf '%s\n' "$2" | while IFS= read -r g; do
    [ -n "$g" ] || continue
    if printf '%s' "$p" | grep -Eq "^$(g2re "$g")\$"; then printf '%s' "$g"; break; fi
  done
}
relpath() { # absolute or relative tool path -> root-relative, forward slashes
  p=$(printf '%s' "$1" | sed 's#\\\\#/#g; s#\\#/#g')
  r=$root
  case "$r" in [A-Za-z]:*) p=$(printf '%s' "$p" | sed 's#^/\([A-Za-z]\)/#\1:/#'); r=$(printf '%s' "$r" | tr 'A-Z' 'a-z'); pl=$(printf '%s' "$p" | tr 'A-Z' 'a-z');;
              *) pl=$p ;; esac
  case "$pl" in "$r"/*) printf '%s' "${p#"${p%"${pl#"$r"/}"}"}" ;; *) printf '%s' "${p#./}" ;; esac
}

# --- pre: edit-time deny --------------------------------------------------------------------------
if [ "$mode" = pre ]; then
  fp=$(jstr file_path); [ -n "$fp" ] || fp=$(jstr notebook_path); [ -n "$fp" ] || fp=$(jstr path)
  [ -n "$fp" ] || exit 0
  rel=$(relpath "$fp")
  if [ "$persona" = engineer ]; then
    case "$tool" in Edit|Write|MultiEdit|NotebookEdit) ;; *) exit 0 ;; esac
    case "$rel" in
      "$gd"/*|"$gd") echo "GUIDE SDD persona guard: SDD_PERSONA=engineer may not edit the gate bank ($rel) - config and scripts are frozen with the tests; test_edit_ban fails on any change." >&2; exit 2 ;;
      *.persona|*/.persona|*.frozen|*/.frozen) echo "GUIDE SDD persona guard: SDD_PERSONA=engineer may not edit the persona/frozen markers ($rel)." >&2; exit 2 ;;
    esac
    hit=$(matches_any "$rel" "$globs")
    [ -n "$hit" ] || exit 0
    echo "GUIDE SDD persona guard: SDD_PERSONA=engineer may not edit test files ($rel matches testGlob '$hit'). Tests belong to QA (invariant 3) - surface the need in the changelog item instead." >&2
    exit 2
  fi
  # qa: blind to the implementation
  case "$tool" in Read|Grep|Glob) ;; *) exit 0 ;; esac
  [ -n "$code" ] || exit 0
  hit=$(matches_any "$rel" "$code")
  [ -n "$hit" ] || { case "$rel" in "${code%%/**}"|"${code%%/**}"/*) hit=$code ;; esac; }
  [ -n "$hit" ] || exit 0
  echo "GUIDE SDD persona guard: SDD_PERSONA=qa is blind to the implementation ($rel is under paths.code '$code'). Expected values come from the spec, never the code (invariant 4); read the spec shards and the test plan." >&2
  exit 2
fi

# --- post / stop: working-tree sweep (engineer only) ---------------------------------------------
[ "$persona" = engineer ] || exit 0
cd "$root" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
sha=""; [ -f "$gd/.frozen" ] && sha=$(sed -n 's/^sha=\([0-9a-fA-F]*\).*/\1/p' "$gd/.frozen" | head -1)
changed=$( {
  git status --porcelain --untracked-files=all 2>/dev/null | cut -c4- \
    | awk '{ n = index($0, " -> "); if (n) { print substr($0, 1, n - 1); print substr($0, n + 4) } else print }'
  [ -n "$sha" ] && git diff --name-only --no-renames "$sha" -- . 2>/dev/null
} | sed 's#\\#/#g; /^$/d' | sort -u)
[ -n "$changed" ] || exit 0
bad=$(printf '%s\n' "$changed" | while IFS= read -r p; do
  case "$p" in "$gd"/.frozen) continue ;; "$gd"/*) echo "$p (gate bank)"; continue ;; esac
  h=$(matches_any "$p" "$globs"); [ -n "$h" ] && echo "$p (testGlob '$h')"
done)
[ -n "$bad" ] || exit 0
{
  echo "GUIDE SDD persona guard ($mode sweep): SDD_PERSONA=engineer - test or gate paths differ from the frozen base${sha:+ $sha}:"
  printf '%s\n' "$bad" | sed 's/^/  /'
  echo "Revert them now (git checkout -- <path>, or rm an untracked file) and surface the need in the changelog item. test_edit_ban will fail at Stage 7 otherwise."
} >&2
exit 2
