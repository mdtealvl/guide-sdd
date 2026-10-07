#!/usr/bin/env sh
# GUIDE SDD — installer test: the update check and the careful merge, for each installer twin.
# Builds an "old" (1.0.0) and a "new" (1.0.1) release from this repo, installs the old one into a
# throwaway project, customizes it the way projects do, then updates with the vendored (old) installer.
# Expects: the handoff to the new installer; an untouched template file REFRESHED; a customized one
# MERGED; an overlapping edit left untouched as a CONFLICT with a .guide-merge beside it (exit 4); the
# config merged key by key (new keys added, unchanged defaults updated, your values and deletions
# kept); check's verdicts, its cache, and a clean tree after it. Then the twins must agree byte for byte.
#
# Usage:  sh ci/install_test.sh [sh|ps1|both]     (default both; ps1 needs pwsh)
# Needs: git, jq; pwsh for the ps1 twin. Exit 0 = all expectations met.
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"
WHICH="${1:-both}"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
fails=0
ok()   { echo "ok    $1"; }
bad()  { echo "FAIL  $1"; fails=$((fails+1)); }
has()  { case "$OUT" in *"$2"*) ok "$1" ;; *) bad "$1: output lacks '$2'"; printf '%s\n' "$OUT" | sed 's/^/      /' ;; esac; }
fhas() { if grep -qF -- "$3" "$2"; then ok "$1"; else bad "$1: $2 lacks '$3'"; fi; }
fnot() { if grep -qF -- "$3" "$2"; then bad "$1: $2 still has '$3'"; else ok "$1"; fi; }
jeq()  { got=$(jq -c "$3" "$2"); if [ "$got" = "$4" ]; then ok "$1"; else bad "$1: $3 = $got, want $4"; fi; }

# One release tree: the repo's working tree minus framework-only files (the installer filters the rest).
mkrel() {  # <dir> <version> <tag>
  mkdir -p "$1"
  (cd "$REPO" && tar --exclude=.git --exclude=dist -cf - .) | (cd "$1" && tar -xf -)
  printf '%s\n' "$2" > "$1/VERSION"
  printf '\nTEMPLATE-TAIL %s\n' "$3" >> "$1/AGENTS.md"
  printf '\nCLAUDE-TAIL %s\n' "$3" >> "$1/CLAUDE.md"
  printf '\nDETAILS-TAIL %s\n' "$3" >> "$1/project-config/project-details.template.md"
  printf '# template rev %s\n' "$3" >> "$1/gates/constitution_lint.template.sh"
  printf '# template rev %s\n' "$3" >> "$1/gates/constitution_lint.template.ps1"
  printf '\nCOPILOT-TAIL %s\n' "$3" >> "$1/.github/copilot-instructions.md"
  printf '\nSTASH-TAIL %s\n' "$3" >> "$1/commands/stash.md"
}

# inst <twin> <installer dir> <args...> — run that twin's installer; sets OUT and RC
inst() {
  tw=$1; d=$2; shift 2
  set +e
  if [ "$tw" = sh ]; then OUT=$(sh "$d/install.sh" "$@" 2>&1); RC=$?
  else OUT=$(pwsh -NoProfile -File "$d/install.ps1" "$@" 2>&1); RC=$?; OUT=$(printf '%s' "$OUT" | tr -d '\r'); fi
  set -e
}

run_twin() {  # <sh|ps1>
  tw=$1; R="$WORK/$tw"; mkdir -p "$R"
  echo "-- $tw twin"
  mkrel "$R/old" 1.0.0 v1
  jq '.proseCheck.maxParaWords = 100 | .legacyKey = "x"' "$R/old/gates/gates.config.template.json" > "$R/t.json" && cp "$R/t.json" "$R/old/gates/gates.config.template.json"
  mkrel "$R/new" 1.0.1 v2
  jq 'del(.legacyKey) | .proseCheck.maxParaWords = 110 | .proseCheck.newLeaf = 1 | .newBlock = {"enabled": true, "list": ["a"]}' "$R/new/gates/gates.config.template.json" > "$R/t.json" && cp "$R/t.json" "$R/new/gates/gates.config.template.json"
  printf '# release marker\n' >> "$R/new/install.sh"; printf '# release marker\n' >> "$R/new/install.ps1"

  mkdir -p "$R/proj"; cd "$R/proj"
  git init -q -b main . && git config user.email ci@guide-sdd && git config user.name ci && git config core.autocrlf false
  inst "$tw" ../old install --source ../old --carriers claude --commands
  [ "$RC" = 0 ] && ok "install old ($tw)" || { bad "install old ($tw) rc=$RC"; printf '%s\n' "$OUT"; return; }

  # Customize like a project: details filled in (line 1), CLAUDE.md tail edited (overlaps the template's
  # change), AGENTS.md left stock, a concrete project gate copied unchanged, a command edited, config set.
  sed '1s/.*/# PROJECT DETAILS - demo project/' sdd/project-config/project-details.template.md > sdd/project-config/project-details.md
  sed 's/^CLAUDE-TAIL v1$/CLAUDE-TAIL mine/' CLAUDE.md > c.tmp && mv c.tmp CLAUDE.md
  cp sdd/gates/constitution_lint.template.sh sdd/gates/constitution_lint.sh
  printf '\nproject step: sweep the PM queue\n' >> .claude/commands/wrap.md
  # A carrier the project wrote itself (never placed by --carriers claude): must be SKIPPED, never merged.
  mkdir -p .github && printf '# Our own Copilot notes\nNot from GUIDE.\n' > .github/copilot-instructions.md
  # A command checked in with CRLF endings: a refresh must keep it CRLF.
  awk '{ printf "%s\r\n", $0 }' .claude/commands/stash.md > c.tmp && mv c.tmp .claude/commands/stash.md
  jq '.suiteCmd = "make test" | .proseCheck.mode = "strict" | del(.baseRef)' sdd/gates/gates.config.json > c.tmp && mv c.tmp sdd/gates/gates.config.json
  git add -A >/dev/null && git commit -q -m "adopt GUIDE 1.0.0"

  # check: verdicts, the once-a-day cache, and a clean tree afterwards (update refuses a dirty tree).
  export GUIDE_SDD_LATEST=v1.0.2; inst "$tw" sdd check
  [ "$RC" = 3 ] && ok "check: newer release -> exit 3 ($tw)" || bad "check newer rc=$RC ($tw)"
  has "check names the update" "UPDATE    guide-sdd 1.0.2 is available (installed 1.0.0)"
  export GUIDE_SDD_LATEST=v1.0.0; inst "$tw" sdd check --cached
  [ "$RC" = 3 ] && ok "check --cached reuses the day's lookup ($tw)" || bad "check --cached rc=$RC ($tw)"
  inst "$tw" sdd check
  [ "$RC" = 0 ] && ok "check: current -> exit 0 ($tw)" || bad "check current rc=$RC ($tw)"
  has "check says current" "is current (latest 1.0.0)"
  export GUIDE_SDD_LATEST=none; inst "$tw" sdd check
  [ "$RC" = 0 ] && ok "check: offline -> exit 0 ($tw)" || bad "check offline rc=$RC ($tw)"
  has "check offline is skipped" "latest release unknown"
  unset GUIDE_SDD_LATEST
  [ -z "$(git status --porcelain)" ] && ok "check leaves the tree clean ($tw)" || { bad "check dirtied the tree ($tw)"; git status --porcelain; }

  # The plugin's SessionStart hook (sh only - it is a POSIX hook on every OS): silent when current, the
  # ask-first context when a newer release exists, silent outside a GUIDE repo; always exit 0.
  if [ "$tw" = sh ]; then
    hook() { set +e; OUT=$(CLAUDE_PROJECT_DIR="$1" CLAUDE_PLUGIN_ROOT="$REPO/plugin" sh "$REPO/plugin/hooks/update-check.sh" 2>&1); RC=$?; set -e; }
    rm -f "$(git rev-parse --git-path guide-sdd-update-check)"
    export GUIDE_SDD_LATEST=v1.0.0; hook "$R/proj"
    [ "$RC" = 0 ] && [ -z "$OUT" ] && ok "hook: silent when current" || bad "hook current: rc=$RC out='$OUT'"
    rm -f "$(git rev-parse --git-path guide-sdd-update-check)"
    export GUIDE_SDD_LATEST=v1.0.2; hook "$R/proj"
    [ "$RC" = 0 ] && ok "hook: exit 0 when an update exists" || bad "hook update rc=$RC"
    has "hook: names the release" "UPDATE    guide-sdd 1.0.2 is available (installed 1.0.0)"
    has "hook: ask first" "ask the human one question"
    case "$OUT" in *"next      ask"*) bad "hook repeats the installer's next line" ;; *) ok "hook: one set of steps" ;; esac
    hook "$WORK"
    [ "$RC" = 0 ] && [ -z "$OUT" ] && ok "hook: silent outside a GUIDE repo" || bad "hook outside: rc=$RC out='$OUT'"
    unset GUIDE_SDD_LATEST; rm -f "$(git rev-parse --git-path guide-sdd-update-check)"
  fi

  # update with the VENDORED old installer: it must hand off to the new one, then merge.
  inst "$tw" sdd update --source ../new
  printf '%s\n' "$OUT" > "$R/update.out"
  [ "$RC" = 4 ] && ok "update with a conflict -> exit 4 ($tw)" || bad "update rc=$RC, want 4 ($tw)"
  has "handoff to the new installer" "handoff   running the guide-sdd 1.0.1 installer"
  has "stock carrier refreshed" "REFRESHED AGENTS.md (was the stock template)"
  has "stock project gate refreshed" "REFRESHED sdd/gates/constitution_lint.sh"
  has "customized details merged" "MERGED    sdd/project-config/project-details.md"
  has "overlapping edit is a conflict" "CONFLICT  CLAUDE.md: 1 overlapping change(s)"
  has "config: new key added" "CONFIG    sdd/gates/gates.config.json: newBlock (added)"
  has "config: new nested key added" "proseCheck.newLeaf (added)"
  has "config: unchanged default updated" "proseCheck.maxParaWords (template default updated)"
  has "config: dropped key kept and named" "legacyKey (no longer in the template; kept)"
  has "own carrier skipped" "SKIPPED   .github/copilot-instructions.md (first line is not the GUIDE template's: your own file, or its title edited; left alone)"
  has "CRLF command refreshed" "REFRESHED .claude/commands/stash.md"
  has "summary" "merge     3 refreshed, 1 merged, 4 config change(s), 1 to resolve"
  fhas "own carrier untouched" .github/copilot-instructions.md "Not from GUIDE."
  [ ! -e .github/copilot-instructions.md.guide-merge ] && [ ! -e .github/copilot-instructions.md.guide-new ] && ok "own carrier: no merge files" || bad "own carrier got a merge file"
  fhas "CRLF command took the new template" .claude/commands/stash.md "STASH-TAIL v2"
  # Count CRs with tr, not grep: Git Bash's grep drops CRs before matching.
  if [ "$(tr -dc '\r' < .claude/commands/stash.md | wc -c | tr -d ' ')" -gt 0 ]; then ok "CRLF command stays CRLF"; else bad "CRLF command flipped to LF"; fi
  fhas "AGENTS.md has the new template" AGENTS.md "TEMPLATE-TAIL v2"
  fhas "details keep your line 1" sdd/project-config/project-details.md "# PROJECT DETAILS - demo project"
  fhas "details gain the template change" sdd/project-config/project-details.md "DETAILS-TAIL v2"
  fnot "details lose the old template line" sdd/project-config/project-details.md "DETAILS-TAIL v1"
  fhas "CLAUDE.md untouched on conflict" CLAUDE.md "CLAUDE-TAIL mine"
  fhas "conflict copy has markers" CLAUDE.md.guide-merge "<<<<<<< CLAUDE.md (yours)"
  fhas "project gate refreshed" sdd/gates/constitution_lint.sh "# template rev v2"
  fhas "edited command kept (template unchanged)" .claude/commands/wrap.md "project step: sweep the PM queue"
  C=sdd/gates/gates.config.json
  jeq "config keeps suiteCmd" $C .suiteCmd '"make test"'
  jeq "config keeps your mode" $C .proseCheck.mode '"strict"'
  jeq "config takes the new default" $C .proseCheck.maxParaWords '110'
  jeq "config adds the nested key" $C .proseCheck.newLeaf '1'
  jeq "config adds the new block" $C .newBlock '{"enabled":true,"list":["a"]}'
  jeq "config keeps your deletion" $C 'has("baseRef")' 'false'
  jeq "config keeps the dropped key" $C .legacyKey '"x"'
  fhas "manifest is the new version" sdd/.sdd-manifest.json '"version": "1.0.1"'
  mkdir -p "$R/snap" && for f in AGENTS.md CLAUDE.md.guide-merge sdd/project-config/project-details.md sdd/gates/gates.config.json .claude/commands/stash.md; do cp "$f" "$R/snap/$(echo "$f" | tr '/' _)"; done

  # Resolve, commit, update again: nothing left to merge.
  grep -v -E '^(<<<<<<<|=======|>>>>>>>)' CLAUDE.md.guide-merge > CLAUDE.md && rm -f CLAUDE.md.guide-merge
  git add -A >/dev/null && git commit -q -m "bump GUIDE 1.0.1"
  inst "$tw" sdd update --source ../new
  [ "$RC" = 0 ] && ok "second update is clean ($tw)" || bad "second update rc=$RC ($tw)"
  has "second update merges nothing" "merge     0 refreshed, 0 merged, 0 config change(s), 0 to resolve"
  cd "$REPO"
}

case "$WHICH" in sh|ps1) run_twin "$WHICH" ;; both) run_twin sh; run_twin ps1 ;; *) echo "usage: sh ci/install_test.sh [sh|ps1|both]" >&2; exit 2 ;; esac

if [ "$WHICH" = both ]; then
  echo "-- twin parity"
  if diff "$WORK/sh/update.out" "$WORK/ps1/update.out" >/dev/null; then ok "update output identical"; else bad "update output differs"; diff "$WORK/sh/update.out" "$WORK/ps1/update.out" | sed 's/^/      /' || true; fi
  for f in AGENTS.md CLAUDE.md.guide-merge sdd/project-config/project-details.md sdd/gates/gates.config.json .claude/commands/stash.md; do
    s=$(echo "$f" | tr '/' _); a=$(cksum < "$WORK/sh/snap/$s"); b=$(cksum < "$WORK/ps1/snap/$s")   # raw bytes: line endings must agree too
    [ "$a" = "$b" ] && ok "same bytes: $f" || { bad "twins differ: $f"; diff "$WORK/sh/snap/$s" "$WORK/ps1/snap/$s" | sed 's/^/      /' || true; }
  done
fi
if [ "$fails" -eq 0 ]; then echo "INSTALL PASS"; else echo "INSTALL FAIL ($fails)"; exit 1; fi
