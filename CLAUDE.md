# CLAUDE.md — Claude Code carrier for GUIDE SDD

Claude Code always loads this file. It **routes to the canonical always-loaded core** in `AGENTS.md`
(the agent-neutral carrier), so there is a single stub to maintain, and `@`-imports the constitution so
the ten invariants are physically in context (Tier A), not merely pointed at. Mechanism map +
capability tiers: `host-adapter.md`. Template — in a target repo this sits at the repo root beside
`AGENTS.md`; the spine lives at `sdd/` (in the framework repo itself the constitution import resolves
via the `sdd` path only after install; the pointer in `AGENTS.md` still applies).

@AGENTS.md
@sdd/constitution.md
