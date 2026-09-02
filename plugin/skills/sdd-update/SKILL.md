---
name: sdd-update
description: Bring the vendored GUIDE SDD spine in sdd/ to a newer release (spine files only; project surface untouched), then commit the bump by itself.
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
3. On success, read the `UPDATED` / `ADDED` list and the new `constitution.changelog.md` tail so you can tell the human what changed in the method.
4. Commit the spine bump **by itself** (`sdd/` only, message "Bump GUIDE SDD spine vA -> vB") before any code, per the spec-edit law. Then run `/sdd-doctor`.
