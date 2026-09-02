# AGENTS.md — SDD always-loaded core (agent-neutral carrier)

<!-- The always-loaded surface for any coding agent that reads AGENTS.md natively (OpenAI Codex,
     Cursor, Gemini CLI, …). Claude Code reads CLAUDE.md, which `@`-imports this file. GitHub Copilot
     does not read AGENTS.md — it needs the `.github/copilot-instructions.md` shim. Carrier map +
     capability tiers: `sdd/host-adapter.md`. This file is the template wired into a target repo at
     INIT; paths below assume the spine lives at `sdd/`. -->

## This project uses Spec-Driven Development (SDD)

On your first action here, **say so**, then operate under SDD — do NOT continue ad-hoc work.

- **Always:** obey `sdd/constitution.md` (the ten invariants).
- **To do any work:** start at `sdd/PROCESS.md` §0 — the boot protocol / stage router. Load ONLY your
  current stage + the shards it names. Never bulk-load the framework.
- **Project specifics** (seams, stack, tracker, spec home): `sdd/project-config/project-details.md` —
  one section on demand, never the whole file.

## This box's role

SDD role: `$SDD_BOX_ROLE` (default `po`), id `$SDD_BOX_ID`. A **worker** box claims
(`claimed-by:$SDD_BOX_ID`) and executes Ready items, surfaces concerns to the changelog item, and flags
`Ready-for-review`; it never authors specs, decides forks, or merges. See `sdd/box-roles.md`.

## Your host capability tier (set at INIT — governs the persona loop)

The persona loop (Stages 5–6) needs QA, Engineer, and Validation to run in contexts that **exclude each
other's work**. How much of that a host can deliver is its tier:

- **Tier A — real scoped sub-agents.** Run the persona loop as written: QA / Engineer / Validation as
  isolated sub-agent contexts, each handed only its stage + named shards.
- **Tier B — no sub-agents, fresh sessions available.** Run each persona in a **fresh session**, with the
  changelog item + spec shards as the only channel between them. The `test_edit_ban` + `qa_import_ban`
  gates enforce the QA⊥Engineer split **structurally**, regardless of which agent ran — so Tier B keeps
  the independence the gates can prove even without physical context isolation.
- **Tier C — single context only.** Persona-loop independence is not achievable; run the **Mechanical
  lane** only and do NOT claim it. Re-triage risky work up to a Tier A/B box.

This host: `$SDD_HOST_TIER`. Mechanism map + how to add a host: `sdd/host-adapter.md`.
