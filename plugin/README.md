# GUIDE SDD — Claude Code plugin

Host affordances only. The method lives in the spine vendored into your repo (`sdd/`), which stays
canonical and works without this plugin; the plugin saves copying and adds one mechanical guard.

Install: `/plugin marketplace add mdtealvl/guide-sdd` then `/plugin install guide-sdd@guide-sdd`.

| Skill | Does |
|---|---|
| `/sdd-init` | Runs the bundled installer (`bin/install.*`) to vendor the spine, then INIT from §1a — the three ASKs stay human. |
| `/sdd-update` | Spine-only update; refuses on a dirty tree or locally edited spine files; commit the bump alone. |
| `/sdd-doctor` | Manifest drift, carriers, gate config. |
| `/sdd-gates` | `run_all` for this OS, output filtered to verdict lines (dispatch frugality). |
| `/sdd-persona` | Sets `sdd/.persona` (`engineer` / `qa` / `clear`) read by the hook below. |
| `/wrap` `/stash` `/unstash` | The session-lifecycle commands from `commands/`, as skills. |

**Hook — persona guard** (`hooks/persona-guard.sh`; persona from env `SDD_PERSONA`, else `sdd/.persona`),
three passes:

| Pass | Event | Engineer persona | QA persona |
|---|---|---|---|
| `--pre` | PreToolUse on Edit/Write/MultiEdit/NotebookEdit/Read/Grep/Glob | deny edits to `testGlobs` paths, `structureGlobs` paths (the PM-approved structure diagram — a deviation is `[NEEDS-PO:structure]`), the gate bank (`gates/**`), `.persona`, `.frozen`; fail closed if the config is unreadable | deny Read/Grep/Glob under `paths.code` (QA is blind to the implementation) |
| `--post` | PostToolUse on Bash/Edit/Write/MultiEdit/NotebookEdit | sweep the working tree (status + diff vs `gates/.frozen`): any test or gate path that differs is named with the revert command (exit 2) | — |
| `--stop` | Stop | the same sweep at turn end (catches codegen that wrote files it never named) | — |

Runs under `sh`; on Windows that is Git Bash, which Claude Code already requires. A tripwire, not the
proof: the Stage-7 `test_edit_ban` and `structure_check --frozen` gates diff the QA-frozen SHA. Tested by `ci/hook_test.sh` (41 cases).

`bin/install.sh` and `bin/install.ps1` are byte-identical copies of the repo-root installers (CI checks).
Plugin version = the framework `VERSION`; plugin tags are `guide-sdd--vX.Y.Z`.

**License:** MIT, © 2026 Voyager Labs — same as the framework (`../LICENSE`).
