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

**Hook — persona edit-guard** (`hooks/persona-guard.sh`, PreToolUse on Edit/Write/MultiEdit): while the
persona is `engineer` (env `SDD_PERSONA`, else `sdd/.persona`), any edit to a path matching
`gates.config.json` `testGlobs` is denied with the reason. Runs under `sh`; on Windows that is Git Bash,
which Claude Code already requires. Tested by `ci/hook_test.sh`.

`bin/install.sh` and `bin/install.ps1` are byte-identical copies of the repo-root installers (CI checks).
Plugin version = the framework `VERSION`; plugin tags are `guide-sdd--vX.Y.Z`.

**License:** MIT, © 2026 Voyager Labs — same as the framework (`../LICENSE`).
