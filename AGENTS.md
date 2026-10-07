# AGENTS.md — GUIDE SDD always-loaded core (agent-neutral carrier)

<!-- Always-loaded surface for agents that read AGENTS.md natively (OpenAI Codex, Cursor, Gemini CLI, …).
     Claude Code reads CLAUDE.md, which `@`-imports this file; GitHub Copilot needs the
     `.github/copilot-instructions.md` shim. Carrier map + tiers: `sdd/host-adapter.md`. Template wired
     into a target repo at INIT; paths assume the spine lives at `sdd/`. -->

## This project uses GUIDE SDD (Gated, Unified, Intent-Driven Engineering — spec-driven development)

On your first action here, **say so**, then operate under SDD — do NOT continue ad-hoc work.

- **Always:** obey `sdd/constitution.md` (the ten invariants).
- **To do any work:** start at `sdd/PROCESS.md` §0 — the boot protocol / stage router. Load ONLY your
  current stage + the shards it names. Never bulk-load the framework.
- **On boot, check for a newer GUIDE** (cached, one lookup a day): the Claude Code plugin does it at session
  start; elsewhere run `sh sdd/install.sh check --cached` (Windows: `pwsh sdd/install.ps1 check --cached`).
  On `UPDATE` (exit 3), ask the human — update now or later — before other work; never update unasked. On
  yes, run the printed update and report each `REFRESHED` / `MERGED` / `CONFIG` / `CONFLICT` / `REVIEW` line;
  exit 4 means a `<file>.guide-merge` awaits resolution with the human before the bump is committed alone.
- **Project specifics** (seams, stack, tracker, spec home): `sdd/project-config/project-details.md` —
  one section on demand, never the whole file.
- **Bugs in GUIDE itself** (a stage, gate, hook, installer, or spine doc misbehaving — not a project
  problem): file at https://github.com/mdtealvl/guide-sdd/issues (`gh issue create --repo
  mdtealvl/guide-sdd`) with `sdd/VERSION`, the step or command, and the output; work around it on the
  changelog item, never by editing the spine.

## This box's role

SDD role: `$SDD_BOX_ROLE` (default `po`), id `$SDD_BOX_ID`. A **worker** box claims
(`claimed-by:$SDD_BOX_ID`) and executes Ready items, surfaces concerns to the changelog item, and flags
`Ready-for-review`; it never authors specs, decides forks, or merges (`sdd/box-roles.md`). Values still
literal `$SDD_…` ⇒ INIT §1a was not completed: resolve them from the env or
`sdd/project-config/box-role.local`, and say so.

## Your host capability tier (set at INIT — governs the persona loop)

The persona loop (Stages 5–6) needs QA, Engineer, and Validation in contexts that **exclude each
other's work**. How much of that a host delivers is its tier:

- **Tier A — real scoped sub-agents.** Run the persona loop as written: QA / Engineer / Validation as
  isolated sub-agent contexts, each handed only its stage + named shards.
- **Tier B — no sub-agents, fresh sessions available.** Run each persona in a **fresh session**, with the
  changelog item + spec shards as the only channel between them. The `test_edit_ban` + `qa_import_ban`
  gates still enforce the QA⊥Engineer split **structurally**, whichever agent ran.
- **Tier C — single context only.** Persona-loop independence is not achievable; run the **Mechanical
  lane** only and do NOT claim it. Re-triage risky work up to a Tier A/B box.

This host: `$SDD_HOST_TIER`. Mechanism map + how to add a host: `sdd/host-adapter.md`.
