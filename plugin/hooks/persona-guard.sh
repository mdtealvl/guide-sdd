#!/usr/bin/env sh
# GUIDE SDD persona guard - four passes, one script (the TEA write-time-control shape):
#   --pre  (PreToolUse; default)  engineer: deny Edit/Write/MultiEdit/NotebookEdit to any testGlobs path,
#                                 to any structureGlobs path (the PM-approved member-level diagram; a
#                                 deviation is [NEEDS-PO:structure], never an edit), to the gate directory
#                                 (config + scripts) and to the .persona/.frozen markers;
#                                 FAIL CLOSED (deny) when the gate config cannot be read.
#                                 qa: deny Read/Grep/Glob whose path is under paths.code - QA is blind to the
#                                 implementation (invariant 3); it reads spec + tests only.
#   --post (PostToolUse)          engineer: sweep the working tree after ANY tool (Bash heredocs, sed -i, mv,
#                                 git checkout, NotebookEdit): a test path, structure shard or gate file that
#                                 differs from the frozen base (gates/.frozen) or is dirty/untracked -> exit 2
#                                 naming the paths and the revert command. The write already happened; the
#                                 sweep makes it loud.
#   --stop (Stop)                 engineer: the same sweep at turn end - catches a codegen script that wrote
#                                 files it never named. Skipped when stop_hook_active is set (no loops).
#   --session-end (SessionEnd)    remove this session's marker: a persona is per dispatch, per session, and
#                                 must not outlive the session that set it (see "stale marker").
# Persona source, first match wins: env SDD_PERSONA, else line 1 of the marker file sdd/.persona (written by
# the sdd-persona skill). Anything but engineer / qa allows everything.
# Stale marker (2026-09-17): the hook input carries session_id (shared by a session's sub-agents). The first
# pass that sees an unstamped marker appends "session=<id>"; a pass whose session_id differs treats the
# marker as another session's - dead, or live on a shared checkout - and IGNORES it (allow, note on stderr),
# never obeys or deletes it. Before this, an engineer marker left by a crashed session blocked edits and
# ran the sweep on every tool call of every later session.
# Cost (2026-09-17): builtins only - no $(...), no pipes, no sed/grep/awk. The only processes are git (sweep)
# and rm (session end). On a Windows box where every fork costs ~80 ms and every exec ~200 ms the old
# script spent ~5 s per PreToolUse and >10 min per sweep of a tree with ~500 untracked files; the
# no-persona case now exits before reading stdin. POSIX sh (dash + Git Bash), no bashisms.
# Exit 0 = allow · exit 2 = deny (message on stderr goes back to the agent).
# Tripwire, not proof: the Stage-7 gate test_edit_ban is the proof (it diffs the QA-frozen SHA).

mode=pre
case "${1:-}" in --post) mode=post ;; --stop) mode=stop ;; --session-end) mode=session-end ;; esac
nl='
'

# --- builtin helpers -------------------------------------------------------------------------------
fs() { # $1 -> R: backslashes to slashes, runs of slashes squeezed
  R=""; fs_s=$1
  while case $fs_s in *\\*) true ;; *) false ;; esac; do R="$R${fs_s%%\\*}/"; fs_s=${fs_s#*\\}; done
  R="$R$fs_s"
  while case $R in *//*) true ;; *) false ;; esac; do R="${R%%//*}/${R#*//}"; done
}
trim() { # $1 -> T: strip leading/trailing blanks and CR
  T=$1
  while case $T in [[:space:]]*) true ;; *) false ;; esac; do T=${T#?}; done
  while case $T in *[[:space:]]) true ;; *) false ;; esac; do T=${T%?}; done
}
jstr() { # $1 key -> J: the first "key": "string" in the hook input ("" if absent)
  J=""
  case $in in *"\"$1\":"*) ;; *) return 0 ;; esac
  J=${in#*"\"$1\":"}
  while case $J in [[:space:]]*) true ;; *) false ;; esac; do J=${J#?}; done
  case $J in \"*) J=${J#\"}; J=${J%%\"*} ;; *) J="" ;; esac
}
gmatch() { # <path> <glob> -> 0 when the glob matches the whole path: ** spans directories, * and ? do not
  case $2 in
    '')     [ -z "$1" ] ;;
    '**')   return 0 ;;
    '**/'*) gmatch "$1" "${2#\*\*/}" && return 0
            case $1 in */*) gmatch "${1#*/}" "$2" ;; *) return 1 ;; esac ;;
    */*)    case $1 in */*) ;; *) return 1 ;; esac
            case ${1%%/*} in ${2%%/*}) gmatch "${1#*/}" "${2#*/}" ;; *) return 1 ;; esac ;;
    *)      case $1 in */*) return 1 ;; esac
            case $1 in $2) return 0 ;; *) return 1 ;; esac ;;
  esac
}
coarse() { # $1 glob -> C: a case pattern that over-matches it (** and **/ become *) - the cheap prefilter
  C=$1
  while case $C in *\*\*/*) true ;; *) false ;; esac; do C="${C%%\*\*/*}*${C#*\*\*/}"; done
  while case $C in *\*\**) true ;; *) false ;; esac; do C="${C%%\*\**}*${C#*\*\*}"; done
}
first_match() { # <path> <globs-nl> <coarse-nl> -> HIT: the first glob matching the path ("" if none)
  HIT=""; fm_l=$2; fm_c=$3
  while [ -n "$fm_l" ]; do
    fm_g=${fm_l%%"$nl"*}; fm_l=${fm_l#*"$nl"}
    C=${fm_c%%"$nl"*}; fm_c=${fm_c#*"$nl"}
    [ -n "$fm_g" ] || continue
    case $1 in $C) if gmatch "$1" "$fm_g"; then HIT=$fm_g; return 0; fi ;; esac
  done
  return 1
}
arr() { # $1 key -> A: the strings of the JSON array "key": [ ... ] in the gate config, one per line;
        # AC: their coarse patterns in the same order
  A=""; AC=""
  case $cfgtxt in *"\"$1\":"*) ;; *) return 0 ;; esac
  a_x=${cfgtxt#*"\"$1\":"}
  while case $a_x in [[:space:]]*) true ;; *) false ;; esac; do a_x=${a_x#?}; done
  case $a_x in \[*) ;; *) return 0 ;; esac
  a_x=${a_x#\[}; a_x=${a_x%%\]*}
  while :; do
    a_e=${a_x%%,*}
    trim "$a_e"; a_e=${T#\"}; a_e=${a_e%\"}
    [ -n "$a_e" ] && { coarse "$a_e"; A="$A$a_e$nl"; AC="$AC$C$nl"; }
    case $a_x in *,*) a_x=${a_x#*,} ;; *) break ;; esac
  done
}

# --- root + marker + input (PG.1: agent_type is in stdin, so stdin is read before the no-persona exit) --
root=${CLAUDE_PROJECT_DIR:-}
[ -n "$root" ] || root=$(git rev-parse --show-toplevel 2>/dev/null)
[ -n "$root" ] || root=$PWD
fs "$root"; root=${R%/}
case $root in /[A-Za-z]/*) r_d=${root#/}; r_d=${r_d%%/*}; root="$r_d:${root#/?}" ;; esac   # MSYS /c/x -> c:/x
marker=""
for m in "$root/sdd/.persona" "$root/.persona"; do
  if [ -f "$m" ]; then marker=$m; break; fi
done

in=""; while IFS= read -r l || [ -n "$l" ]; do in="$in$l"; done
jstr tool_name; tool=$J
jstr session_id; sid=$J
jstr agent_type; apersona=""
case $J in qa|qa-*) apersona=qa ;; engineer|engineer-*) apersona=engineer ;; esac   # PG.1a
sdir="$root/sdd/.persona-state/${sid:-_}"   # PG.5 snapshots, per session

if [ "$mode" != session-end ] && [ -z "$apersona" ] && [ -z "${SDD_PERSONA:-}" ] && [ -z "$marker" ]; then
  exit 0   # PG.2
fi

persona=${SDD_PERSONA:-}; first=""; stamped=""; unterminated=0
if [ -n "$marker" ] && { [ -z "$apersona" ] || [ "$mode" = session-end ]; }; then
  n=0
  while IFS= read -r l || { [ -n "$l" ] && unterminated=1; }; do
    n=$((n+1)); [ $n = 1 ] && first=$l
    case $l in session=*) [ -n "$stamped" ] || stamped=${l#session=} ;; esac
  done < "$marker"
  trim "$first"; first=$T; trim "$stamped"; stamped=$T
fi

if [ "$mode" = session-end ]; then
  # remove our own (or an unstamped) marker; never another live session's
  if [ -n "$marker" ] && { [ -z "$stamped" ] || [ "$stamped" = "$sid" ]; }; then rm -f "$marker"; fi
  if [ -d "$sdir" ]; then rm -rf "$sdir"; fi   # PG.8
  exit 0
fi

if [ -n "$apersona" ]; then persona=$apersona; else [ -n "$persona" ] || persona=$first; fi
case "$persona" in engineer|qa) ;; *) exit 0 ;; esac
if [ -z "$apersona" ] && [ -z "${SDD_PERSONA:-}" ] && [ -n "$sid" ]; then
  # marker-sourced persona - session stamp: adopt on first sight; a marker stamped by another session is
  # ignored, not obeyed (stale after a crash, or another live session on a shared checkout - use
  # SDD_PERSONA or a worktree for that)
  if [ -z "$stamped" ]; then
    [ $unterminated = 0 ] || printf '\n' >> "$marker"
    printf 'session=%s\n' "$sid" >> "$marker"
  elif [ "$stamped" != "$sid" ]; then
    echo "GUIDE SDD persona guard: ignoring '$persona' marker stamped by session $stamped (this session is $sid). Re-run /sdd-persona at the next dispatch." >&2
    exit 0
  fi
fi

if [ "$mode" = stop ]; then
  case "$in" in *'"stop_hook_active":'*true*) exit 0 ;; esac
fi

# --- config: testGlobs, structureGlobs, paths.code, gate dir --------------------------------------
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
gd=${cfg%/*}; gd=${gd#"$root"/}
cfgtxt=""; while IFS= read -r l || [ -n "$l" ]; do cfgtxt="$cfgtxt$l"; done < "$cfg"
arr testGlobs; globs=$A; cglobs=$AC
arr structureGlobs; sglobs=$A; csglobs=$AC
codes=""; ccodes=""   # PG.3: paths.code is a string or an array of globs -> one per line
case $cfgtxt in *'"paths":'*)
  p_x=${cfgtxt#*'"paths":'}; p_x=${p_x%%\}*}
  case $p_x in *'"code":'*)
    p_s=${p_x#*'"code":'}
    while case $p_s in [[:space:]]*) true ;; *) false ;; esac; do p_s=${p_s#?}; done
    case $p_s in
      \"*) p_s=${p_s#\"}; p_s=${p_s%%\"*}
           if [ -n "$p_s" ]; then coarse "$p_s"; codes="$p_s$nl"; ccodes="$C$nl"; fi ;;
      \[*) c_sv=$cfgtxt; cfgtxt=$p_x; arr code; codes=$A; ccodes=$AC; cfgtxt=$c_sv ;;
    esac ;;
  esac ;;
esac

relpath() { # $1 absolute or relative tool path -> REL: root-relative, forward slashes
  fs "$1"; rp=$R
  case $rp in /[A-Za-z]/*) rp_d=${rp#/}; rp_d=${rp_d%%/*}; rp="$rp_d:${rp#/?}" ;; esac   # MSYS /c/x -> c:/x
  case $rp in
    "$root"/*) REL=${rp#"$root"/} ;;
    *) REL=${rp#./}
       case $root in [A-Za-z]:*)   # same path, drive letter differs only in case
         r2=${root#?}
         case ${rp#?} in "$r2"/*) REL=${rp#?}; REL=${REL#"$r2"/} ;; esac ;;
       esac ;;
  esac
}

litdir() { # $1 glob -> LD: its literal directory prefix (the part before the first wildcard, cut back to a
           # whole segment; no trailing slash). "src/**" -> src, "src/a*.ts" -> src, "**/x" -> ""
  LD=${1%%[*?[]*}
  if [ "$LD" != "$1" ]; then case $LD in */*) LD=${LD%/*} ;; *) LD="" ;; esac; fi
  LD=${LD%/}
}

# --- pre, Bash: qa tripwire (PG.4) ----------------------------------------------------------------
amode=""
if [ "$mode" = pre ] && [ "$tool" = Bash ]; then
  if [ "$persona" = qa ]; then
    [ -n "$codes" ] || exit 0
    case $in in *'"command":'*) ;; *) exit 0 ;; esac
    b_c=${in#*'"command":'}; b_c=${b_c%%'"}'*}; b_c=${b_c%%'",'*}   # the raw JSON string; escapes stay
    set -f; o_ifs=$IFS; IFS=" 	;|&()<>\"'=\`"; set -- $b_c; IFS=$o_ifs; set +f
    for tok in "$@"; do
      relpath "$tok"; tok=$REL
      q_l=$codes
      while [ -n "$q_l" ]; do
        q_g=${q_l%%"$nl"*}; q_l=${q_l#*"$nl"}
        litdir "$q_g"; [ -n "$LD" ] || continue
        case $tok in "$LD"|"$LD"/*)
          first_match "$tok" "$globs" "$cglobs" && continue   # a test file under the code dir is QA's own
          echo "GUIDE SDD persona guard: SDD_PERSONA=qa is blind to the implementation - this Bash command names '$tok', under paths.code '$q_g'. This is a heuristic tripwire on path tokens, not proof; QA reads spec + tests only (invariant 3)." >&2
          exit 2 ;;
        esac
      done
    done
    exit 0
  fi
  [ -n "$apersona" ] || exit 0   # an agent_type engineer falls through to the PG.5 snapshot below
fi

# --- pre: edit-time deny --------------------------------------------------------------------------
if [ "$mode" = pre ] && [ "$tool" != Bash ]; then
  jstr file_path; fp=$J
  [ -n "$fp" ] || { jstr notebook_path; fp=$J; }
  [ -n "$fp" ] || { jstr path; fp=$J; }
  [ -n "$fp" ] || exit 0
  relpath "$fp"; rel=$REL
  if [ "$persona" = engineer ]; then
    case "$tool" in Edit|Write|MultiEdit|NotebookEdit) ;; *) exit 0 ;; esac
    case "$rel" in
      "$gd"/*|"$gd") echo "GUIDE SDD persona guard: SDD_PERSONA=engineer may not edit the gate bank ($rel) - config and scripts are frozen with the tests; test_edit_ban fails on any change." >&2; exit 2 ;;
      *.persona|*/.persona|*.frozen|*/.frozen) echo "GUIDE SDD persona guard: SDD_PERSONA=engineer may not edit the persona/frozen markers ($rel)." >&2; exit 2 ;;
    esac
    if first_match "$rel" "$sglobs" "$csglobs"; then
      echo "GUIDE SDD persona guard: SDD_PERSONA=engineer may not edit the approved structure diagram ($rel matches structureGlob '$HIT'). A deviation is [NEEDS-PO:structure] on the item - the PM decides, the PO replaces the shard wholesale and re-freezes." >&2
      exit 2
    fi
    first_match "$rel" "$globs" "$cglobs" || exit 0
    echo "GUIDE SDD persona guard: SDD_PERSONA=engineer may not edit test files ($rel matches testGlob '$HIT'). Tests belong to QA (invariant 3) - surface the need in the changelog item instead." >&2
    exit 2
  fi
  # qa: blind to the implementation - every paths.code glob (PG.3)
  case "$tool" in Read|Grep|Glob) ;; *) exit 0 ;; esac
  [ -n "$codes" ] || exit 0
  if first_match "$rel" "$codes" "$ccodes"; then code=$HIT
  else
    code=""; q_l=$codes
    while [ -n "$q_l" ]; do
      q_g=${q_l%%"$nl"*}; q_l=${q_l#*"$nl"}
      base=${q_g%/\*\*}   # "src/**" or a bare "src": the directory itself and anything under it
      case "$rel" in "$base"|"$base"/*) code=$q_g; break ;; esac
    done
    [ -n "$code" ] || exit 0
  fi
  echo "GUIDE SDD persona guard: SDD_PERSONA=qa is blind to the implementation ($rel is under paths.code '$code'). Expected values come from the spec, never the code (invariant 4); read the spec shards and the test plan." >&2
  exit 2
fi

# --- post / stop: working-tree sweep (engineer only) ---------------------------------------------
[ "$persona" = engineer ] || exit 0
if [ -n "$apersona" ]; then   # PG.5: an agent_type engineer is swept around its own Bash calls only
  [ "$tool" = Bash ] || exit 0   # PG.5b (a Stop event carries no tool_name: PG.5c)
  case $mode in pre) amode=snap ;; post) amode=check ;; *) exit 0 ;; esac
  jstr agent_id; sf="$sdir/${J:-_}"; hf="$sdir/.hash"
fi
cd "$root" 2>/dev/null || exit 0
[ -e .git ] || exit 0
sha=""
if [ -f "$gd/.frozen" ]; then
  while IFS= read -r l || [ -n "$l" ]; do
    case $l in sha=*) [ -n "$sha" ] || { trim "${l#sha=}"; sha=$T; } ;; esac
  done < "$gd/.frozen"
  case $sha in *[!0-9A-Fa-f]*) sha=${sha%%[!0-9A-Fa-f]*} ;; esac
fi
hashes() { # $1 nl-list of paths -> HS: "<blob hash> <path>" per path, same order ("-" for an absent file,
           # "?" when git gave no hash); one git hash-object for them all, its output read from $hf
  HS=""; h_all=$1; h_l=$1; set --
  while [ -n "$h_l" ]; do h_p=${h_l%%"$nl"*}; h_l=${h_l#*"$nl"}; [ -e "$h_p" ] && set -- "$@" "$h_p"; done
  h_o=""
  if [ $# -gt 0 ]; then
    git hash-object --no-filters -- "$@" > "$hf" 2>/dev/null
    while IFS= read -r l || [ -n "$l" ]; do h_o="$h_o$l$nl"; done < "$hf"
  fi
  h_l=$h_all
  while [ -n "$h_l" ]; do
    h_p=${h_l%%"$nl"*}; h_l=${h_l#*"$nl"}
    if [ -e "$h_p" ]; then h=${h_o%%"$nl"*}; h_o=${h_o#*"$nl"}; else h=-; fi
    HS="$HS${h:-?} $h_p$nl"
  done
}
# git's output is read by a subshell (the only fork): classify every path with the builtin matcher,
# first label per path wins, gate bank first. The pipeline's status is that subshell's exit.
{
  git status --porcelain --untracked-files=all 2>/dev/null
  n_l=$globs   # PG.6: a testGlob whose first segment is a nested repo - the outer status cannot see inside it
  while [ -n "$n_l" ]; do
    n_g=${n_l%%"$nl"*}; n_l=${n_l#*"$nl"}
    case $n_g in */*) ;; *) continue ;; esac
    n_d=${n_g%%/*}
    case $n_d in ''|*[*?[]*) continue ;; esac
    [ -e "$n_d/.git" ] || continue
    litdir "$n_g"; n_r=${LD#"$n_d"}; n_r=${n_r#/}
    echo "@@nest $n_d"
    git -C "$n_d" status --porcelain --untracked-files=all -- "${n_r:-.}" 2>/dev/null
  done
  if [ -n "$sha" ]; then echo "@@diff"; git diff --name-only --no-renames "$sha" -- . 2>/dev/null; fi
} | {
  seen=$nl; bad=""; bp=""; indiff=0; pfx=""
  while IFS= read -r l || [ -n "$l" ]; do
    if [ "$l" = "@@diff" ]; then indiff=1; pfx=""; continue; fi
    case $l in "@@nest "*) pfx="${l#@@nest }/"; continue ;; esac
    if [ $indiff = 1 ]; then p1=$l; p2=""
    else
      l=${l#???}
      case $l in *" -> "*) p1=${l%% -> *}; p2=${l#* -> } ;; *) p1=$l; p2="" ;; esac
    fi
    for p in "$p1" "$p2"; do
      [ -n "$p" ] || continue
      case $p in *\\*) fs "$p"; p=$R ;; esac
      case $p in \"*\") p=${p#\"}; p=${p%\"} ;; esac
      p="$pfx$p"
      if [ $indiff = 1 ]; then case $seen in *"$nl$p$nl"*) continue ;; esac; fi   # status paths are unique
      seen="$seen$p$nl"
      lb=""
      case $p in
        "$gd"/.frozen) continue ;;
        "$gd"/*) lb="gate bank" ;;
        *) if first_match "$p" "$sglobs" "$csglobs"; then lb="structureGlob '$HIT'"
           elif first_match "$p" "$globs" "$cglobs"; then lb="testGlob '$HIT'"; fi ;;
      esac
      [ -n "$lb" ] || continue
      bad="$bad  $p ($lb)$nl"; bp="$bp$p$nl"
    done
  done
  if [ "$amode" = snap ]; then   # PG.5: record this agent's baseline before its Bash call runs
    [ -d "$sdir" ] || mkdir -p "$sdir" || exit 0
    hashes "$bp"; printf '%s' "$HS" > "$sf"
    exit 0
  fi
  [ -n "$bad" ] || exit 0
  if [ "$amode" = check ] && [ -f "$sf" ]; then   # PG.5: forgive what is unchanged since the snapshot
    snap=$nl; while IFS= read -r l || [ -n "$l" ]; do snap="$snap$l$nl"; done < "$sf"
    hashes "$bp"; h_l=$HS; b_l=$bad; bad=""      # PG.5a: no snapshot file -> nothing is forgiven
    while [ -n "$h_l" ]; do
      h=${h_l%%"$nl"*}; h_l=${h_l#*"$nl"}; b=${b_l%%"$nl"*}; b_l=${b_l#*"$nl"}
      case $h in '?'*) bad="$bad$b$nl"; continue ;; esac
      case $snap in *"$nl$h$nl"*) ;; *) bad="$bad$b$nl" ;; esac
    done
    [ -n "$bad" ] || exit 0
  fi
  {
    echo "GUIDE SDD persona guard ($mode sweep): SDD_PERSONA=engineer - test or gate paths differ from the frozen base${sha:+ $sha}${amode:+ and changed during this agent's Bash call}:"
    printf '%s' "$bad"
    echo "Revert them now (git checkout -- <path>, or rm an untracked file) and surface the need in the changelog item. test_edit_ban will fail at Stage 7 otherwise."
  } >&2
  exit 2
}
