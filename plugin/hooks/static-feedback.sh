#!/usr/bin/env sh
# GUIDE SDD static feedback - PostToolUse (Edit|Write|MultiEdit). Runs staticCheck.fileCmd on the file just
# written and hands its findings to the agent at once: exit 2 puts them in front of the agent; the edit
# itself stands. This is only the fast loop - the proof is static_check in the gate bank. Silent (exit 0)
# when fileCmd is unset, jq or the gates are missing, the file is outside staticCheck.fileGlobs (default:
# paths.code), or the command passes. {file} in fileCmd becomes the root-relative path, already
# single-quoted: write it bare (`eslint {file}`), never inside quotes.
in=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
cfg=""
for c in sdd/gates/gates.config.json gates/gates.config.json; do [ -f "$c" ] && { cfg=$c; break; }; done
[ -n "$cfg" ] || exit 0
gd=${cfg%/gates.config.json}
[ -f "$gd/_common.sh" ] || exit 0
cmd=$(jq -r '.staticCheck.fileCmd // empty' "$cfg" 2>/dev/null)
[ -n "$cmd" ] || exit 0
fp=$(printf '%s' "$in" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$fp" ] || exit 0

# Root-relative path: backslashes to /, MSYS /c/ to c:/, then strip the root (drive letter case-blind).
# The root is tried in both spellings MSYS has (pwd: /tmp/x, pwd -W: C:/.../Temp/x); elsewhere pwd -W fails.
norm() { printf '%s' "$1" | sed -e 's#\\#/#g' -e 's#^/\([A-Za-z]\)/#\1:/#' -e 's#/$##'; }
low() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
nfp=$(norm "$fp"); lfp=$(low "$nfp"); rel=""
for r in "$(pwd)" "$(pwd -W 2>/dev/null)"; do
  [ -n "$r" ] || continue
  nroot=$(norm "$r")
  case "$lfp" in
    "$(low "$nroot")"/*)   # strip the root by length in the shell's own units (bash: chars, dash: bytes)
      rel=$nfp; i=0; n=$((${#nroot} + 1))
      while [ "$i" -lt "$n" ]; do rel=${rel#?}; i=$((i + 1)); done
      break ;;
  esac
done
if [ -z "$rel" ]; then
  case "$nfp" in /*|[A-Za-z]:/*) exit 0 ;; esac   # outside the project
  rel=${nfp#./}
fi

. "$gd/_common.sh"
globs=$(jq -r '(.staticCheck.fileGlobs // []) | .[]' "$cfg" 2>/dev/null)
[ -n "$globs" ] || globs=$(jq -r '.paths.code // empty' "$cfg" 2>/dev/null)
[ -n "$globs" ] || exit 0
hit=0; set -f
for g in $globs; do
  printf '%s\n' "$rel" | grep -Eq "$(glob_to_regex "$g")" && { hit=1; break; }
done
[ "$hit" = 1 ] || exit 0

q="'$(printf '%s' "$rel" | sed "s/'/'\\\\''/g")'"
run=""; s=$cmd
while :; do
  case "$s" in
    *'{file}'*) run="$run${s%%'{file}'*}$q"; s=${s#*'{file}'} ;;
    *) run="$run$s"; break ;;
  esac
done
out=$(sh -c "$run" </dev/null 2>&1) && exit 0
{
  echo "GUIDE SDD static feedback: staticCheck.fileCmd found problems in $rel - fix them now (static_check gates the ship):"
  printf '%s\n' "$out" | tr -d '\r' | sed '/^$/d' | tail -n 30
} >&2
exit 2
