# Host Adapter — mapping SDD's load-verbs onto each agent tool

> Demand-loaded spine doc. **The third axis:** spine (the method) × `project-details.md` (this codebase)
> × host-adapter (this agent tool). The spine names load **verbs**; this file is the **one place** agent
> tools are named. Load at INIT, or when bringing a new host under SDD. Cross-links: `AGENTS.md` (the
> agent-neutral carrier), `PROCESS.md` §0 (the tier branch in the persona route), `project-config/INIT.md`.

## The three load-verbs the spine assumes

The spine (`constitution.md`, `PROCESS.md`, `stages/`) is written in these verbs and names no tool. This
table binds each verb to a host mechanism; adding a host means filling one row.

| Verb | What it must achieve | Host mechanism (examples) |
|---|---|---|
| **always-load** | constitution + `PROCESS.md` §0 present in every context | Claude Code: `CLAUDE.md` `@`-imports them (physical injection). AGENTS.md hosts: the pointer stub in `AGENTS.md`, read on first action. Copilot: `.github/copilot-instructions.md` shim. |
| **demand-load** | read one stage / shard, then drop it | Any agent: read the file. A slash-command where the host has one — Claude `.claude/commands/`, Copilot `.github/prompts/`, Cursor `.cursor/commands/` — is an optional convenience, never required. |
| **scoped sub-agent** | QA / Engineer / Validation in a context that **excludes** the transcript + siblings | Claude Code: Task sub-agents (**Tier A**). No spawning but fresh sessions: **Tier B**. Single context: **Tier C**. |

`always-load` and `demand-load` port to every agent — every tool has a rules file and can read files.
Only `scoped sub-agent` varies, and that variance is the **tier**.

## Capability tiers (persona-loop fidelity)

| Tier | Host can… | Persona loop | Independence guarantee |
|---|---|---|---|
| **A** | spawn scoped sub-agents | runs as written | physical context exclusion **+** the structural gates |
| **B** | start fresh sessions, no spawning | each persona in a fresh session; artifacts the only channel | the `test_edit_ban` + `qa_import_ban` gates (structural half), honor-system for the rest |
| **C** | single context only | **not available** — Mechanical lane only | none; risky work re-triaged up to an A/B box |

The gates are the reason Tier B is credible where a pure-prompt method is not: they are pure git/text
with exit codes and know nothing about which agent ran, so the QA⊥Engineer split they prove holds on any
host. Correctness still rests on the fresh Validation pass (Stage 7), as always.

## Carrier file per host — where the always-load stub goes

| Host | Carrier | Tier | Notes |
|---|---|---|---|
| **Claude Code** | `CLAUDE.md` → `@AGENTS.md` | A | Native `@`-import gives physical always-load. May instead `@`-import `constitution.md` + `PROCESS.md` directly. |
| **OpenAI Codex CLI** | `AGENTS.md` | B | Reads `AGENTS.md` natively — zero shim. |
| **Cursor** | `AGENTS.md` (or `.cursor/rules/sdd.mdc`, `alwaysApply: true`) | B | Reads `AGENTS.md`; the `.mdc` rule is an alternative. |
| **Gemini CLI** | `AGENTS.md` (or `GEMINI.md`) | B | Reads `AGENTS.md`. |
| **GitHub Copilot** | `.github/copilot-instructions.md` | B | Does **not** read `AGENTS.md`; the shim is a copy of the stub (or a pointer to `AGENTS.md`). |

One core, many carriers: `AGENTS.md` holds the canonical stub; `CLAUDE.md` is one line (`@AGENTS.md`);
the Copilot shim points at it. No content is duplicated except that one-line Copilot pointer.

## Bundled Tier-A capabilities — session/context lifecycle

SDD ships a session-lifecycle capability (the ritual for externalizing a volatile context before it is
cleared — `session-lifecycle.md`). Its **Tier-A implementation** is the bundled slash-commands in
`commands/` (`/wrap`, `/stash`, `/unstash`): install them into the host's command dir — Claude Code
`.claude/commands/`, Copilot `.github/prompts/`, Cursor `.cursor/commands/`. On **Tier-B/C** hosts (no
slash-commands) the identical rituals are run **by hand** — the discipline is the ordered pass, not the
slash sugar. Either way the commands read/write the project memory directory (`project-details.md#CL-11`,
seeded at INIT). See `commands/README.md` and `session-lifecycle.md`.

**Claude Code plugin** (`plugin/` + marketplace at the repo root; `/plugin marketplace add mdtealvl/guide-sdd` →
`/plugin install guide-sdd@guide-sdd`): the three commands as skills, plus `/sdd-init` (bundled installer, then
INIT from §1a), `/sdd-update`, `/sdd-doctor`, `/sdd-gates` (verdict lines only) and `/sdd-persona`, and a
PreToolUse hook that denies an `engineer` persona any edit to `testGlobs` paths (invariant 3 at edit time).
Host affordance only — the vendored spine stays canonical and every ritual still runs without it.

## Adding a host (the whole procedure)

1. **always-load** — find the host's always-loaded rules file; put the stub there, or point/import it to
   `AGENTS.md`. If the host has native import, prefer it (physical injection > pointer).
2. **tier** — scoped sub-agents ⇒ **A**; fresh sessions only ⇒ **B**; single context ⇒ **C**. Stamp
   `$SDD_HOST_TIER` (env or `project-config/box-role.local`) so `PROCESS.md` §0's persona route reads it.
3. **demand-load** — Read works everywhere; wire the host's slash-command dir only if you want the
   convenience.
4. **gates** — nothing to do. They are host-agnostic (`gates/README.md`); the OS split (`.ps1`/`.sh`) is
   the only axis that matters, and it is orthogonal to the agent.
5. **verify** — run the INIT gate smoke test under that host. Green = the host is adopted.

Never edit the spine to add a host — a host lives entirely in its carrier file + this row + the tier
stamp, exactly as a project lives entirely in `project-details.md` + `gates.config.json`.
