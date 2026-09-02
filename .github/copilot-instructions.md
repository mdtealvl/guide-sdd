# Copilot instructions — GUIDE SDD (spec-driven development)

<!-- GitHub Copilot always-loads this file but does NOT read AGENTS.md — so this shim carries the SDD
     stub for Copilot. Canonical stub: AGENTS.md (repo root). Mechanism map + tiers: sdd/host-adapter.md.
     Template — paths assume the spine at sdd/. Keep in sync with AGENTS.md. -->

**This project uses GUIDE SDD.** On your first action here, **say so**, then operate under it — do NOT continue
ad-hoc work. Read `AGENTS.md` (repo root) for the full always-loaded core; the essentials:

- **Always:** obey `sdd/constitution.md` (the ten invariants).
- **To do any work:** start at `sdd/PROCESS.md` §0 (boot protocol / stage router) — load ONLY your
  current stage + the shards it names. Never bulk-load the framework.
- **Project specifics:** `sdd/project-config/project-details.md`, one section on demand.
- **Box role:** `$SDD_BOX_ROLE` (default `po`), id `$SDD_BOX_ID` — a worker executes Ready items and
  surfaces concerns to the changelog item; it never authors specs, decides forks, or merges
  (`sdd/box-roles.md`).
- **Host tier:** `$SDD_HOST_TIER` — Copilot is **Tier B**: run the persona loop as fresh sessions; the
  `test_edit_ban` + `qa_import_ban` gates enforce the QA⊥Engineer split structurally (`sdd/host-adapter.md`).
