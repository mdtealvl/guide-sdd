---
name: sdd-update
description: Bring the vendored GUIDE SDD spine in sdd/ to a newer release, carefully merge the project's own files made from templates (carriers, project details, project gates, commands, gate config), then commit the bump by itself.
argument-hint: "[--version vX.Y.Z|latest] [--dest sdd] [--force]"
disable-model-invocation: true
allowed-tools: Bash, Read
---

# /sdd-update — update the spine

Arguments: $ARGUMENTS. Run from the repo root.

1. Run the updater:
   - Windows: `pwsh "${CLAUDE_PLUGIN_ROOT}/bin/install.ps1" update $ARGUMENTS`
   - Linux/macOS: `sh "${CLAUDE_PLUGIN_ROOT}/bin/install.sh" update $ARGUMENTS`
2. If it **refuses**: a dirty tree means commit or stash first; `EDITED` lines mean someone changed spine files locally — those edits belong in `project-config/project-details.md` or `gates/gates.config.json`, never in the spine. Move them, then retry. Only use `--force` when the human says so.
3. Read the `UPDATED` / `ADDED` list and the new `constitution.changelog.md` tail so you can tell the human what changed in the method. Then report the merge of the project's own files, line by line:
   - `REFRESHED` — the file was still the stock template; it now is the new one.
   - `MERGED` — the human's edits are kept and the template's changes applied (three-way, git merge-file). Show the diff.
   - `SKIPPED` — a root carrier or installed command whose first line is not the GUIDE template's: the project's own file, or a GUIDE file whose title line was edited. Left exactly as it is, exit 0 - so tell the human: if it is a GUIDE file with an edited title, the template's changes were not applied; compare it by hand with its template (`sdd/AGENTS.md`, `sdd/CLAUDE.md`, `sdd/.github/copilot-instructions.md`, `sdd/commands/<name>.md`).
   - `CONFIG` — `gates.config.json`: a key added, a default the project never changed updated, or a key the template dropped (kept). The project's own values always win.
   - `CONFLICT` (exit 4) — the project's edit and the template's change overlap. The file is **untouched**; `<file>.guide-merge` holds the merge with conflict markers. Resolve it **with the human**, replace the file, delete the `.guide-merge`.
   - `REVIEW` (exit 4) — no clean three-way merge was possible; `<file>.guide-new` is the new template. Fold in what the project needs with the human, then delete it.
4. Commit the bump **by itself** (`sdd/` plus the merged project files, message "Bump GUIDE SDD spine vA -> vB") before any code, per the spec-edit law. Then run `/sdd-doctor`.
