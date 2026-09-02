#!/usr/bin/env sh
# GUIDE SDD installer — POSIX sh twin of install.ps1 (same verbs, flags, output, exit codes).
# Vendors the spine into a repo, keeps it current, and reports drift.
#   Touches:       <dest>/ spine files, <dest>/.sdd-manifest.json, carriers at the repo root (by flag),
#                  host command dirs (by flag), gates/gates.config.json seeded from the template if absent.
#   Never touches: project-config/project-details.md, gates/gates.config.json once present, concrete
#                  project gates, project-config/box-role.local, INIT's three ASKs, any file not in the source.
#   Never deletes.
#
# Usage:
#   sh install.sh install [--version vX.Y.Z|latest] [--dest sdd] [--carriers claude,codex,copilot,cursor]
#                         [--commands] [--source <dir|zip>] [--repo owner/repo] [--force]
#   sh install.sh update  [--version vX.Y.Z|latest] [--dest sdd] [--source <dir|zip>] [--repo owner/repo] [--force]
#   sh install.sh doctor  [--dest sdd]
# Exit: 0 ok · 1 doctor found drift / update refused · 2 usage or source error.
# Needs: sh, git, sha256sum or shasum. Downloads: gh (works on a private repo) or curl + unzip (public).
set -eu

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; }
VERB="${1:-}"; [ $# -gt 0 ] && shift
VERSION=latest; DEST=sdd; CARRIERS=""; COMMANDS=0; SOURCE=""; REPO=mdtealvl/guide-sdd; FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION=$2; shift 2 ;;   --dest) DEST=$2; shift 2 ;;   --carriers) CARRIERS=$2; shift 2 ;;
    --commands) COMMANDS=1; shift ;;    --source) SOURCE=$2; shift 2 ;; --repo) REPO=$2; shift 2 ;;
    --force) FORCE=1; shift ;;          -h|--help) usage; exit 0 ;;
    *) echo "install.sh: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
  esac
done
case "$VERB" in install|update|doctor) ;; *) usage >&2; exit 2 ;; esac
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
  echo "next      open $DEST/project-config/INIT.md at section 1a - the box tier/role and the three ASKs are yours"
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
  upd=0; add=0
  spine_files "$SRC" > "$WORK/list"
  while read -r f; do
    if [ ! -f "$DEST/$f" ]; then mkdir -p "$DEST/$(dirname "$f")"; cp "$SRC/$f" "$DEST/$f"; echo "  ADDED   $DEST/$f"; add=$((add+1))
    elif [ "$(sha "$SRC/$f")" != "$(sha "$DEST/$f")" ]; then cp "$SRC/$f" "$DEST/$f"; echo "  UPDATED $DEST/$f"; upd=$((upd+1)); fi
  done < "$WORK/list"
  write_manifest "$SRC" "$V"
  echo "update    guide-sdd $OLD -> $V at $DEST/ ($upd updated, $add added, nothing removed)"
  echo "next      commit the spine bump by itself, before any code (spec-edit law)"
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
case "$VERB" in install) do_install ;; update) do_update ;; doctor) do_doctor ;; esac
