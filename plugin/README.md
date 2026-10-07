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

**Hook — persona guard** (`hooks/persona-guard.sh`; persona from the hook input's `agent_type`, else env
`SDD_PERSONA`, else `sdd/.persona` — see PG.1 below), four passes:

| Pass | Event | Engineer persona | QA persona |
|---|---|---|---|
| `--pre` | PreToolUse on Bash/Edit/Write/MultiEdit/NotebookEdit/Read/Grep/Glob | deny edits to `testGlobs` paths, `structureGlobs` paths (the PM-approved structure diagram — a deviation is `[NEEDS-PO:structure]`), the gate bank (`gates/**`), `.persona`, `.frozen`; fail closed if the config is unreadable. An `engineer` sub-agent's Bash call first snapshots the dirty test/structure/gate set (PG.5) | deny Read/Grep/Glob under `paths.code` (QA is blind to the implementation), except files matching `testGlobs` (PG.3b; any `..` segment denied); deny a Bash command with a path token under `paths.code` (PG.4, heuristic) |
| `--post` | PostToolUse and PostToolUseFailure on Bash/Edit/Write/MultiEdit/NotebookEdit | sweep the working tree (status + diff vs `gates/.frozen`): any test, structure or gate path that differs is named with the revert command (exit 2). An `engineer` sub-agent is swept only after Bash, and only for paths changed since its snapshot | — |
| `--stop` | Stop | the same sweep at turn end (catches codegen that wrote files it never named); skipped for an `engineer` sub-agent, whose Bash calls are swept individually | — |
| `--session-end` | SessionEnd | remove this session's marker (a persona never outlives the session that set it) and its `sdd/.persona-state/` snapshots | same |

Runs under `sh`; on Windows that is Git Bash, which Claude Code already requires. A tripwire, not the
proof: the Stage-7 `test_edit_ban` and `structure_check --frozen` gates diff the QA-frozen SHA. Tested by `ci/hook_test.sh`. The marker is stamped `session=<id>` by the first pass that sees it; a marker stamped by another session is ignored, never obeyed (a crashed session cannot leave a persona behind). Builtins only - the only processes are `git` in the sweep and snapshot, `rm` at session end and one `mkdir` per session for the snapshot dir - so a pass costs one shell start (~0.3 s on Windows), a sweep of a 500-path tree ~1 s. Every sweep also reads a nested git repo under a `testGlobs` path (PG.6). Known limits: path compares are case-sensitive, and the qa path normalization has gaps (GitHub issue #5).

**Hook — update check** (`hooks/update-check.sh`, SessionStart on `startup`). In a repo with
`sdd/.sdd-manifest.json` it runs the bundled `install.sh check --cached` — at most one release lookup a day,
cached inside `.git` so the tree stays clean — and prints nothing when the spine is current, offline, or
outside a GUIDE repo. When a newer release exists its lines become session context: the agent asks the human
(update now or later) before any other work, never updates unasked, names a stale plugin
(`/plugin marketplace update guide-sdd`), and gives the update command for this plugin's installer. Always
exits 0. Tested in `ci/install_test.sh`.

**Persona from sub-agent type (PG.1).** The hook input's `agent_type` sets the persona directly when
it's `qa`/`engineer` (or `qa-*`/`engineer-*`) — no marker read or stamped — so QA and Engineer
sub-agents can run **concurrently** without racing on `sdd/.persona`. Any other `agent_type` falls
back to env `SDD_PERSONA`, then the `sdd/.persona` marker file. Pin a sub-agent's type in its
frontmatter, e.g. `.claude/agents/qa.md`:

```yaml
name: qa
description: QA persona — writes tests from spec, blind to the implementation.
model: sonnet
```

Pin `model` there — an unpinned sub-agent inherits the session's model, which can silently drift the
persona onto whatever model started the session.

`bin/install.sh` and `bin/install.ps1` are byte-identical copies of the repo-root installers (CI checks).
Plugin version = the framework `VERSION`; plugin tags are `guide-sdd--vX.Y.Z`.

**License:** MIT, © 2026 Voyager Labs — same as the framework (`../LICENSE`).
