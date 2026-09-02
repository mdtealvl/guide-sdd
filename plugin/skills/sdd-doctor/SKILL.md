---
name: sdd-doctor
description: Check the vendored GUIDE SDD install - spine files vs the manifest, carriers present, gate config present - and report drift. Use before trusting the gates or after an update.
argument-hint: "[--dest sdd]"
allowed-tools: Bash, Read
---

# /sdd-doctor — is the spine intact?

Arguments: $ARGUMENTS. Run from the repo root.

1. Run: Windows `pwsh "${CLAUDE_PLUGIN_ROOT}/bin/install.ps1" doctor $ARGUMENTS` · Linux/macOS `sh "${CLAUDE_PLUGIN_ROOT}/bin/install.sh" doctor $ARGUMENTS`.
2. Report the version and the `DRIFT` / `MISSING` lines verbatim. Drift in a spine file is never fixed by editing the spine: either it is an intended project rule that belongs in `project-config/`, or it is an accident — restore it with `/sdd-update --force` after the human agrees.
3. If `AGENTS.md` or `CLAUDE.md` is missing at the repo root, say so: the always-loaded core is not wired (INIT §1).
