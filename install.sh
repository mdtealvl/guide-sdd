#!/usr/bin/env sh
# GUIDE SDD installer — POSIX sh twin of install.ps1 (same verbs, flags, output, exit codes).
# Vendors the spine into a repo, keeps it current, and reports drift.
#   Touches:       <dest>/ spine files, <dest>/.sdd-manifest.json, carriers at the repo root (by flag),
#                  host command dirs (by flag), gates/gates.config.json seeded from the template if absent.
#   update merges: project files made from a template (root carriers, project-details.md, concrete project
#                  gates, installed commands: three-way, git merge-file; gates.config.json: key by key, your
#                  values win). A clean merge is written; a conflict never touches your file (<file>.guide-merge).
#   Never touches: project-config/box-role.local, INIT's three ASKs, any file not in the source. Never deletes.
#
# Usage:
#   sh install.sh install [--version vX.Y.Z|latest] [--dest sdd] [--carriers claude,codex,copilot,cursor]
#                         [--commands] [--source <dir|zip>] [--repo owner/repo] [--force]
#   sh install.sh update  [--version vX.Y.Z|latest] [--dest sdd] [--source <dir|zip>] [--repo owner/repo] [--force]
#   sh install.sh check   [--dest sdd] [--repo owner/repo] [--cached]   (--cached: at most one lookup a day)
#   sh install.sh doctor  [--dest sdd]
#   sh install.sh --gates-only <target-dir> [--source <dir|zip>] [--repo owner/repo] [--version vX.Y.Z|latest]
# Exit: 0 ok · 1 doctor found drift / update refused · 2 usage or source error · 3 check: a newer release
#       exists · 4 update applied, merge conflicts to resolve.
# Needs: sh, git, sha256sum or shasum; jq for the config merge. Downloads: gh (private repo) or curl + unzip.
set -eu

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; }
VERB="${1:-}"; [ $# -gt 0 ] && shift
GATES_TARGET=""
if [ "$VERB" = "--gates-only" ]; then GATES_TARGET="${1:-}"; [ $# -gt 0 ] && shift; fi
VERSION=latest; DEST=sdd; CARRIERS=""; COMMANDS=0; SOURCE=""; REPO=mdtealvl/guide-sdd; FORCE=0; CACHED=0
while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION=$2; shift 2 ;;   --dest) DEST=$2; shift 2 ;;   --carriers) CARRIERS=$2; shift 2 ;;
    --commands) COMMANDS=1; shift ;;    --source) SOURCE=$2; shift 2 ;; --repo) REPO=$2; shift 2 ;;
    --force) FORCE=1; shift ;;          --cached) CACHED=1; shift ;;     -h|--help) usage; exit 0 ;;
    *) echo "install.sh: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
  esac
done
case "$VERB" in install|update|check|doctor|--gates-only) ;; *) usage >&2; exit 2 ;; esac
DEST=${DEST%/}
MANIFEST="$DEST/.sdd-manifest.json"
WORK=$(mktemp -d); cleanup() { rm -rf "$WORK"; :; }; trap cleanup EXIT

# --- helpers -------------------------------------------------------------------------------------
sha() {  # content hash with CRs stripped, so a CRLF checkout is not drift
  if command -v sha256sum >/dev/null 2>&1; then tr -d '\r' < "$1" | sha256sum | cut -d' ' -f1
  else tr -d '\r' < "$1" | shasum -a 256 | cut -d' ' -f1; fi
}
die() { echo "install.sh: $*" >&2; exit 2; }
# spine_files <srcdir> — relative paths of everything that ships to a project (framework-repo-only
# files excluded), LC_ALL=C sorted.
spine_files() {
  (cd "$1" && find . -type f | sed 's|^\./||' | LC_ALL=C sort) | grep -v -E \
    '^(\.git/|\.github/workflows/|ci/|plugin/|\.claude-plugin/|\.claude/|dist/|project-config/PROPOSED_CHANGELOG\.md$|\.sdd-manifest\.json$)'
}
src_version() { [ -f "$1/VERSION" ] && tr -d ' \r\n' < "$1/VERSION" || echo unknown; }
manifest_version() { sed -n 's/^  "version": "\([^"]*\)".*/\1/p' "$MANIFEST" | head -1; }
manifest_files() { sed -n 's/^    "\([^"]*\)": "\([0-9a-f]*\)",\{0,1\}$/\1 \2/p' "$MANIFEST"; }
write_manifest() {  # <srcdir> <version>
  {
    printf '{\n  "name": "guide-sdd",\n  "version": "%s",\n  "installedAt": "%s",\n  "files": {\n' "$2" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    n=$(spine_files "$1" | wc -l | tr -d ' '); i=0
    spine_files "$1" | while read -r f; do
      i=$((i+1)); sep=","; [ "$i" -eq "$n" ] && sep=""
      printf '    "%s": "%s"%s\n' "$f" "$(sha "$DEST/$f")" "$sep"
    done
    printf '  }\n}\n'
  } > "$MANIFEST"
}
acquire() {  # sets SRC
  if [ -n "$SOURCE" ] && [ -d "$SOURCE" ]; then SRC=$SOURCE; return; fi
  if [ -n "$SOURCE" ]; then
    [ -f "$SOURCE" ] || die "source not found: $SOURCE"
    ZIP=$SOURCE
  else
    if command -v gh >/dev/null 2>&1; then
      if [ "$VERSION" = latest ]; then gh release download -R "$REPO" -p 'guide-sdd-*.zip' -D "$WORK" >/dev/null
      else gh release download "$VERSION" -R "$REPO" -p 'guide-sdd-*.zip' -D "$WORK" >/dev/null; fi
    else
      command -v curl >/dev/null 2>&1 || die "need gh or curl to download"
      TAG=$VERSION
      if [ "$TAG" = latest ]; then
        TAG=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
        [ -n "$TAG" ] || die "could not resolve latest release of $REPO"
      fi
      curl -fsSL -o "$WORK/guide-sdd-${TAG#v}.zip" "https://github.com/$REPO/releases/download/$TAG/guide-sdd-${TAG#v}.zip" || die "download failed for $TAG"
    fi
    ZIP=$(ls "$WORK"/guide-sdd-*.zip 2>/dev/null | head -1); [ -n "$ZIP" ] || die "no release asset found"
  fi
  command -v unzip >/dev/null 2>&1 || die "need unzip"
  mkdir -p "$WORK/x" && unzip -q "$ZIP" -d "$WORK/x"
  if [ -d "$WORK/x/sdd" ]; then SRC="$WORK/x/sdd"; else SRC="$WORK/x"; fi
}
copy_if() {  # <src> <dst> <label>  — write when absent (or --force); report
  if [ -f "$2" ] && [ "$FORCE" = 0 ]; then echo "carrier   $2 (kept)"; else mkdir -p "$(dirname "$2")"; cp "$1" "$2"; echo "carrier   $2 (written)"; fi
}
place_carriers() {  # <srcdir>
  [ -n "$CARRIERS" ] || return 0
  echo "$CARRIERS" | tr ',' '\n' | while read -r c; do
    case "$c" in
      claude)  copy_if "$1/AGENTS.md" AGENTS.md; copy_if "$1/CLAUDE.md" CLAUDE.md ;;
      codex|cursor|gemini) copy_if "$1/AGENTS.md" AGENTS.md ;;
      copilot) copy_if "$1/AGENTS.md" AGENTS.md; copy_if "$1/.github/copilot-instructions.md" .github/copilot-instructions.md ;;
      "") ;;
      *) die "unknown carrier '$c' (claude, codex, cursor, gemini, copilot)" ;;
    esac
  done
}
place_commands() {  # <srcdir>
  [ "$COMMANDS" = 1 ] || return 0
  echo "$CARRIERS" | tr ',' '\n' | while read -r c; do
    case "$c" in claude) d=.claude/commands ;; copilot) d=.github/prompts ;; cursor) d=.cursor/commands ;; *) continue ;; esac
    mkdir -p "$d"; n=0
    for f in "$1"/commands/*.md; do
      case "$f" in */README.md) continue ;; esac
      if [ ! -f "$d/$(basename "$f")" ] || [ "$FORCE" = 1 ]; then cp "$f" "$d/"; n=$((n+1)); fi
    done
    echo "commands  $d/ ($n written)"
  done
}
warn_nested() {  # nested git repos: the gate bank resolves its root from its own location (gates/) and
                 # cannot see inside a gitlink or a first-level subdir with its own .git (GitHub issue #2)
  command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  root=$(pwd); root=${root%/}
  {
    git ls-files -s 2>/dev/null | while read -r mode _ _ p; do [ "$mode" = 160000 ] && printf '%s\n' "$p"; done
    for d in */; do
      d=${d%/}; [ -d "$d" ] || continue
      [ -e "$d/.git" ] && printf '%s\n' "$d"
    done
  } | LC_ALL=C sort -u | while read -r p; do
    echo "WARN nested git repo '$p': the gate bank resolves its root from its own location and cannot see inside it; install the gates there too: install.sh --gates-only $root/$p"
  done
}
ensure_gitignore() {  # <root> — append sdd/.persona + sdd/.persona-state/ if missing (idempotent)
  gi="${1%/}/.gitignore"
  [ -f "$gi" ] || : > "$gi"
  for line in "sdd/.persona" "sdd/.persona-state/"; do
    grep -qxF "$line" "$gi" 2>/dev/null || printf '%s\n' "$line" >> "$gi"
  done
}
ver_cmp() {  # <a> <b> -> 1 if a > b, -1 if a < b, else 0 (X.Y.Z; a leading v ignored; each part's leading digits only, so 1.15.0-rc1 = 1.15.0)
  a=${1#v}; b=${2#v}
  for i in 1 2 3; do
    x=$(printf '%s' "$a" | cut -d. -f"$i" | sed 's/[^0-9].*//'); y=$(printf '%s' "$b" | cut -d. -f"$i" | sed 's/[^0-9].*//')
    x=${x:-0}; y=${y:-0}
    if [ "$x" -gt "$y" ]; then echo 1; return; fi
    if [ "$x" -lt "$y" ]; then echo -1; return; fi
  done
  echo 0
}
latest_tag() {  # the newest release tag of $REPO, or nothing when offline (tests: GUIDE_SDD_LATEST=<tag>|none)
  if [ -n "${GUIDE_SDD_LATEST:-}" ]; then [ "$GUIDE_SDD_LATEST" = none ] || printf '%s' "$GUIDE_SDD_LATEST"; return 0; fi
  t=""
  if command -v curl >/dev/null 2>&1; then   # bounded: 5 s; gh (unbounded) only where curl is missing
    t=$(curl -fsSL -m 5 "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1) || t=""
  elif command -v gh >/dev/null 2>&1; then t=$(gh release view -R "$REPO" --json tagName -q .tagName 2>/dev/null) || t=""; fi
  printf '%s' "$t"
}
stamp_path() {  # where check caches its lookup: inside .git (never dirties the tree), else beside the manifest
  p=""
  if command -v git >/dev/null 2>&1; then p=$(git rev-parse --git-path guide-sdd-update-check 2>/dev/null) || p=""; fi
  printf '%s' "${p:-$DEST/.sdd-update-check}"
}

# --- careful merge of project files made from a template (update) ------------------------------------
# Pairs "<project file>|<template path in the spine>|<fp>", for project files that exist. The OLD template is
# the merge base: snapshot_bases copies it out of the spine before the spine is overwritten. fp marks files
# that may be the project's own (a carrier or command that install kept, or never placed): they are merged
# only when their first line is the template's (the fingerprint); otherwise SKIPPED, never touched.
# project-details.md and the concrete project gates are template copies by INIT's own steps.
merge_pairs() {
  if [ "$DEST" != "." ]; then
    for c in AGENTS.md CLAUDE.md .github/copilot-instructions.md; do [ -f "$c" ] && echo "$c|$c|fp"; done
  fi
  [ -f "$DEST/project-config/project-details.md" ] && echo "$DEST/project-config/project-details.md|project-config/project-details.template.md|"
  for g in constitution_lint seam_conformance qa_import_ban; do
    for x in sh ps1; do [ -f "$DEST/gates/$g.$x" ] && echo "$DEST/gates/$g.$x|gates/$g.template.$x|"; done
  done
  for d in .claude/commands .github/prompts .cursor/commands; do
    for f in "$DEST"/commands/*.md; do
      [ -f "$f" ] || continue; n=$(basename "$f"); [ "$n" = README.md ] && continue
      [ -f "$d/$n" ] && echo "$d/$n|commands/$n|fp"
    done
  done
  return 0
}
first_line() { head -n 1 "$1" | tr -d '\r'; }
has_cr() { [ "$(tr -dc '\r' < "$1" | wc -c | tr -d ' ')" -gt 0 ]; }   # not grep: Git Bash's grep drops CRs
put_like() {  # <src> <like> <dst> - copy src to dst byte for byte, with CR before every LF when <like> uses CRLF
  if has_cr "$2"; then                                    # (a merge never flips line endings)
    tr -d '\r' < "$1" > "$WORK/pl.lf"
    if [ -z "$(tail -c 1 "$WORK/pl.lf")" ]; then fin=1; else fin=0; fi   # keep a missing final newline missing
    LC_ALL=C awk -v fin="$fin" '{ if (NR > 1) printf "\r\n"; printf "%s", $0 } END { if (NR > 0 && fin == 1) printf "\r\n" }' "$WORK/pl.lf" > "$3"
  else cp "$1" "$3"; fi
}
snapshot_bases() {  # pairs file -> $WORK/base/<template> (plus the config template)
  while IFS='|' read -r p t fp; do
    [ -f "$DEST/$t" ] && { mkdir -p "$WORK/base/$(dirname "$t")"; cp "$DEST/$t" "$WORK/base/$t"; }
  done < "$WORK/pairs"
  if [ -f "$DEST/gates/gates.config.template.json" ]; then mkdir -p "$WORK/base/gates"; cp "$DEST/gates/gates.config.template.json" "$WORK/base/gates/"; fi
  return 0
}
NREF=0; NMRG=0; NCFG=0; NCON=0
merge_one() {  # <project file> <template rel> [fp]
  P=$1; B="$WORK/base/$2"; T="$DEST/$2"
  [ -f "$T" ] || return 0                                                   # template left the release: keep yours
  if [ -f "$B" ] && [ "$(sha "$B")" = "$(sha "$T")" ]; then return 0; fi   # template unchanged
  [ "$(sha "$P")" = "$(sha "$T")" ] && return 0                            # already the new template
  if [ "${3:-}" = fp ]; then
    l=$(first_line "$P")
    if [ "$l" != "$(first_line "$T")" ] && { [ ! -f "$B" ] || [ "$l" != "$(first_line "$B")" ]; }; then
      echo "  SKIPPED   $P (first line is not the GUIDE template's: your own file, or its title edited; left alone)"; return 0
    fi
  fi
  if [ -f "$B" ] && [ "$(sha "$P")" = "$(sha "$B")" ]; then
    put_like "$T" "$P" "$WORK/m.out"; cp "$WORK/m.out" "$P"; echo "  REFRESHED $P (was the stock template)"; NREF=$((NREF+1)); return 0
  fi
  if [ -f "$B" ] && command -v git >/dev/null 2>&1; then
    tr -d '\r' < "$P" > "$WORK/m.ours"; tr -d '\r' < "$B" > "$WORK/m.base"; tr -d '\r' < "$T" > "$WORK/m.theirs"
    rc=0; git merge-file -L "$P (yours)" -L "old template" -L "new template" "$WORK/m.ours" "$WORK/m.base" "$WORK/m.theirs" >/dev/null 2>&1 || rc=$?
    if [ "$rc" -eq 0 ]; then
      put_like "$WORK/m.ours" "$P" "$WORK/m.out"; cp "$WORK/m.out" "$P"
      echo "  MERGED    $P (your edits kept, template changes applied)"; NMRG=$((NMRG+1)); return 0
    fi
    if [ "$rc" -lt 128 ]; then
      put_like "$WORK/m.ours" "$P" "$P.guide-merge"
      echo "  CONFLICT  $P: $rc overlapping change(s); your file is untouched - resolve $P.guide-merge, then replace $P with it"
      NCON=$((NCON+1)); return 0
    fi
  fi
  cp "$T" "$P.guide-new"
  echo "  REVIEW    $P: no clean three-way merge; the new template is $P.guide-new - fold in what you need"
  NCON=$((NCON+1))
}
# gates.config.json: keys new in the template are added; a value you never changed (still the old template's)
# follows the new template; every value you set is kept; a key you deleted stays deleted.
CFG_JQ='def m($b; $t; $o):
  if ($o|type) == "object" and ($t|type) == "object" then
    reduce ($t|keys_unsorted[]) as $k ($o;
      if has($k) then .[$k] = m((if ($b|type) == "object" then $b[$k] else null end); $t[$k]; .[$k])
      elif (($b|type) == "object" and ($b|has($k))) then .
      else .[$k] = $t[$k] end)
  elif $o == $b and $t != $b then $t
  else $o end;
def changed($a; $m; $p):
  if ($a|type) == "object" and ($m|type) == "object" then
    ($m|keys_unsorted[]) as $k
    | if ($a|has($k)) then changed($a[$k]; $m[$k]; $p + [$k]) else ($p + [$k] | join(".")) + " (added)" end
  elif $a != $m then ($p | join(".")) + " (template default updated)"
  else empty end;
def gone($b; $t; $o; $p):
  if ($b|type) == "object" and ($t|type) == "object" and ($o|type) == "object" then
    ($b|keys_unsorted[]) as $k
    | if ($t|has($k)) then gone($b[$k]; $t[$k]; $o[$k]; $p + [$k])
      elif ($o|has($k)) then ($p + [$k] | join(".")) + " (no longer in the template; kept)"
      else empty end
  else empty end;'
merge_config() {
  P="$DEST/gates/gates.config.json"; B="$WORK/base/gates/gates.config.template.json"; T="$DEST/gates/gates.config.template.json"
  [ -f "$P" ] && [ -f "$B" ] && [ -f "$T" ] || return 0
  [ "$(sha "$B")" = "$(sha "$T")" ] && return 0
  if ! command -v jq >/dev/null 2>&1 || ! jq -e . "$P" >/dev/null 2>&1; then
    echo "  REVIEW    $P: cannot merge (jq missing or the config is not valid JSON); compare it with $T by hand"
    NCON=$((NCON+1)); return 0
  fi
  # tr: jq on Windows writes CRLF; the merged config and the change lines are LF on every OS.
  jq -n --slurpfile b "$B" --slurpfile t "$T" --slurpfile o "$P" "$CFG_JQ m(\$b[0]; \$t[0]; \$o[0])" | tr -d '\r' > "$WORK/cfg.merged"
  jq -n -r --slurpfile o "$P" --slurpfile m "$WORK/cfg.merged" "$CFG_JQ changed(\$o[0]; \$m[0]; [])" | tr -d '\r' > "$WORK/cfg.changes"
  jq -n -r --slurpfile b "$B" --slurpfile t "$T" --slurpfile o "$P" "$CFG_JQ gone(\$b[0]; \$t[0]; \$o[0]; [])" | tr -d '\r' >> "$WORK/cfg.changes"
  if ! jq -e 'type == "object"' "$WORK/cfg.merged" >/dev/null 2>&1; then   # never write a failed merge over yours
    echo "  REVIEW    $P: cannot merge (jq missing or the config is not valid JSON); compare it with $T by hand"
    NCON=$((NCON+1)); return 0
  fi
  [ -s "$WORK/cfg.changes" ] || return 0
  if ! jq -n -e --slurpfile o "$P" --slurpfile m "$WORK/cfg.merged" '$o[0] == $m[0]' >/dev/null; then
    put_like "$WORK/cfg.merged" "$P" "$WORK/m.out"; cp "$WORK/m.out" "$P"
  fi
  while IFS= read -r line; do echo "  CONFIG    $P: $line"; NCFG=$((NCFG+1)); done < "$WORK/cfg.changes"
}

# --- verbs ---------------------------------------------------------------------------------------
do_install() {
  if [ -f "$MANIFEST" ] && [ "$FORCE" = 0 ]; then
    echo "install.sh: $DEST/ already holds guide-sdd $(manifest_version); use 'update' (or --force)" >&2; exit 1
  fi
  acquire; V=$(src_version "$SRC")
  n=0
  spine_files "$SRC" | while read -r f; do mkdir -p "$DEST/$(dirname "$f")"; cp "$SRC/$f" "$DEST/$f"; done
  n=$(spine_files "$SRC" | wc -l | tr -d ' ')
  write_manifest "$SRC" "$V"
  echo "install   guide-sdd $V -> $DEST/ ($n files)"
  if [ ! -f "$DEST/gates/gates.config.json" ]; then cp "$DEST/gates/gates.config.template.json" "$DEST/gates/gates.config.json"; echo "config    $DEST/gates/gates.config.json (seeded from template; fill the keys per INIT section 5)"; fi
  place_carriers "$SRC"; place_commands "$SRC"
  ensure_gitignore .
  echo "next      open $DEST/project-config/INIT.md at section 1a - the box tier/role and the three ASKs are yours"
  warn_nested
}
do_update() {
  [ -f "$MANIFEST" ] || die "no $MANIFEST — run 'install' first"
  OLD=$(manifest_version)
  if [ "$FORCE" = 0 ] && command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1 && [ -n "$(git status --porcelain)" ]; then
    echo "install.sh: working tree is not clean; commit or stash first (or --force)" >&2; exit 1
  fi
  drift=0
  manifest_files | while read -r f h; do
    if [ -f "$DEST/$f" ] && [ "$(sha "$DEST/$f")" != "$h" ]; then echo "  EDITED  $DEST/$f (local change to a spine file)"; fi
  done | tee "$DEST/.sdd-update.drift" >/dev/null
  if [ -s "$DEST/.sdd-update.drift" ] && [ "$FORCE" = 0 ]; then
    cat "$DEST/.sdd-update.drift"; rm -f "$DEST/.sdd-update.drift"
    echo "install.sh: spine files were edited locally; move the edits out (they belong in project-config/) or --force" >&2; exit 1
  fi
  rm -f "$DEST/.sdd-update.drift"
  acquire; V=$(src_version "$SRC")
  # Hand off to the new release's own installer, so the newest merge rules run (once: the env guard).
  if [ -z "${GUIDE_SDD_HANDOFF:-}" ] && [ -f "$SRC/install.sh" ] && [ "$(sha "$SRC/install.sh")" != "$(sha "$0")" ]; then
    echo "handoff   running the guide-sdd $V installer from the new release"
    set -- update --source "$SRC" --dest "$DEST"; [ "$FORCE" = 1 ] && set -- "$@" --force
    rc=0; GUIDE_SDD_HANDOFF=1 sh "$SRC/install.sh" "$@" || rc=$?
    exit "$rc"
  fi
  merge_pairs > "$WORK/pairs"; snapshot_bases
  upd=0; add=0
  spine_files "$SRC" > "$WORK/list"
  while read -r f; do
    if [ ! -f "$DEST/$f" ]; then mkdir -p "$DEST/$(dirname "$f")"; cp "$SRC/$f" "$DEST/$f"; echo "  ADDED   $DEST/$f"; add=$((add+1))
    elif [ "$(sha "$SRC/$f")" != "$(sha "$DEST/$f")" ]; then cp "$SRC/$f" "$DEST/$f"; echo "  UPDATED $DEST/$f"; upd=$((upd+1)); fi
  done < "$WORK/list"
  write_manifest "$SRC" "$V"
  while IFS='|' read -r p t fp; do merge_one "$p" "$t" "$fp"; done < "$WORK/pairs"
  merge_config
  ensure_gitignore .
  echo "update    guide-sdd $OLD -> $V at $DEST/ ($upd updated, $add added, nothing removed)"
  echo "merge     $NREF refreshed, $NMRG merged, $NCFG config change(s), $NCON to resolve"
  if [ "$NCON" -gt 0 ]; then
    echo "next      resolve each CONFLICT / REVIEW file (then delete its .guide-merge / .guide-new), then commit the bump by itself"
    warn_nested; exit 4
  fi
  echo "next      commit the bump (spine + merged project files) by itself, before any code (spec-edit law)"
  warn_nested
}
do_check() {
  [ -f "$MANIFEST" ] || die "no $MANIFEST at $DEST/ - not installed"
  V=$(manifest_version); STAMP=$(stamp_path); now=$(date +%s); L=""; cached=0
  if [ "$CACHED" = 1 ] && [ -f "$STAMP" ]; then
    ts=""; tag=""; read -r ts tag < "$STAMP" || true
    case "$ts" in ''|*[!0-9]*) ;; *) if [ $((now - ts)) -lt 86400 ]; then L=$tag; cached=1; fi ;; esac
  fi
  if [ "$cached" = 0 ]; then   # cache only a real answer: an offline start must not hide the check for a day
    L=$(latest_tag); [ -n "$L" ] && { printf '%s %s\n' "$now" "$L" > "$STAMP" 2>/dev/null || true; }
  fi
  if [ -z "$L" ]; then echo "check     guide-sdd $V installed; latest release unknown (offline?) - skipped"; return 0; fi
  if [ "$(ver_cmp "$L" "$V")" = 1 ]; then
    echo "UPDATE    guide-sdd ${L#v} is available (installed $V)"
    echo "next      ask the human first; on yes: sh $DEST/install.sh update --version $L  (Windows: pwsh $DEST/install.ps1 update --version $L)"
    exit 3
  fi
  echo "check     guide-sdd $V is current (latest ${L#v})"
}
do_gates_only() {  # <target> — installs only gates/ into <target>/sdd/gates/ (no spine, no carriers, no manifest)
  T="${1:-}"; [ -n "$T" ] || die "--gates-only needs a target directory"
  T=${T%/}
  acquire; V=$(src_version "$SRC")
  GD="$T/sdd/gates"
  (cd "$SRC/gates" && find . -type f | sed 's|^\./||' | LC_ALL=C sort) > "$WORK/gateslist"
  n=$(wc -l < "$WORK/gateslist" | tr -d ' ')
  while read -r f; do mkdir -p "$GD/$(dirname "$f")"; cp "$SRC/gates/$f" "$GD/$f"; done < "$WORK/gateslist"
  echo "gates-only guide-sdd $V -> $GD/ ($n files)"
  if [ ! -f "$GD/gates.config.json" ]; then cp "$GD/gates.config.template.json" "$GD/gates.config.json"; echo "config    $GD/gates.config.json (seeded from template; fill the keys per INIT section 5)"; fi
  ensure_gitignore "$T"
}
do_doctor() {
  [ -f "$MANIFEST" ] || die "no $MANIFEST at $DEST/ — not installed"
  V=$(manifest_version); bad=0; total=0
  echo "doctor    guide-sdd $V at $DEST/"
  manifest_files > "${TMPDIR:-/tmp}/.sdd-doctor.$$"
  while read -r f h; do
    total=$((total+1))
    if [ ! -f "$DEST/$f" ]; then echo "  MISSING $DEST/$f"; bad=$((bad+1))
    elif [ "$(sha "$DEST/$f")" != "$h" ]; then echo "  DRIFT   $DEST/$f"; bad=$((bad+1)); fi
  done < "${TMPDIR:-/tmp}/.sdd-doctor.$$"
  rm -f "${TMPDIR:-/tmp}/.sdd-doctor.$$"
  for c in AGENTS.md CLAUDE.md .github/copilot-instructions.md; do [ -f "$c" ] && echo "  carrier $c" ; done
  [ -f "$DEST/gates/gates.config.json" ] && echo "  config  $DEST/gates/gates.config.json"
  [ -f "$DEST/project-config/project-details.md" ] && echo "  project $DEST/project-config/project-details.md"
  if [ "$bad" -eq 0 ]; then echo "  ok      $total files match the manifest"; else echo "  $bad of $total files differ from the manifest"; exit 1; fi
}
case "$VERB" in install) do_install ;; update) do_update ;; check) do_check ;; doctor) do_doctor ;; --gates-only) do_gates_only "$GATES_TARGET" ;; esac
