---
name: sdd-persona
description: Set or clear the active GUIDE SDD persona marker (sdd/.persona) that the edit-guard hook reads - engineer blocks edits to test files; qa or clear allows them. Orchestrators set engineer at Stage 6 entry and clear it at exit.
argument-hint: "engineer | qa | clear | show"
allowed-tools: Bash, Read, Write
---

# /sdd-persona — who holds the pen?

Argument: $ARGUMENTS.

- `engineer` → write `engineer` to `sdd/.persona`. From now on the plugin's PreToolUse hook denies Edit/Write to any path matching `gates.config.json` `testGlobs` (invariant 3: the Engineer never edits QA's tests). Set this when dispatching the Stage-6 Engineer.
- `qa` → write `qa` (edits to tests allowed; QA still may not import implementation — that stays a gate).
- `clear` → delete `sdd/.persona`.
- `show` → print the marker and whether `SDD_PERSONA` is set in the environment (the env var wins over the file).

Keep `sdd/.persona` out of version control (add it to `.gitignore` once). On Tier-B hosts, export `SDD_PERSONA=engineer` in the Engineer's session instead.
