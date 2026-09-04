# Stage 0 — Triage / Right-size

**Role:** Orchestrator. **Loaded with:** constitution + this file. On trigger, load when it says:
`box-roles.md` (box role), `greenfield-vs-brownfield.md` (spec-coverage stance), `definition-of-done.md`
(DoR on pickup), `changelog-conventions.md` (filing the item), and `project-details.md` sections
`#CL-N` / `#SEAM-N` / `#RS-N`.

Decide how much ceremony a unit gets and produce the records later stages read. The only stage that
runs every time.

**Know your box role first (`box-roles.md`).** A **PO box** does the full Stage 0: triage, route,
file/shape the changelog item, mark it ready. A **worker box** does not triage — it *picks up* an item
the PO marked ready (work-ready state, `project-details.md#CL-6`). On pickup the worker FIRST verifies
the **Definition of Ready** (`definition-of-done.md`): if DoR fails, surface the gap back
(`[NEEDS-PO]`/`[BLOCKED]` per `changelog-conventions.md`, transition to PO-attention state
`project-details.md#CL-7`) and do **not** start; if DoR holds, read the Triage record's route and load
its next active stage.

## Is it an item yet?

If the input is a raw request (a sentence, a thread, a bug report, a PRD) rather than a changelog item,
run **`intake.md`** first — classify the input, split to one goal, run the numbered-question loop and the
domain screen, write the item, record the readiness verdict. Triage right-sizes an **item**.

## Right-size it: three questions

Ask in order. **Q0 confirms one goal; Q1 sets rigor; Q2 sets whether to parallelize.**

**Q0 — one goal?** Does the item hold two or more deliverables reviewable and mergeable independently?
(Count deliverables, never verbs.) Yes → back to `intake.md` §2: split, or record `kept-whole`.

**Q1 — could a wrong guess slip through?** Is a misread both *expensive* and *not obvious to catch*?
- **No → low-risk:** typo, rename, config tweak, mechanical repoint, values already decided.
- **Yes → high-risk:** money/economy math, combat/sim math, a service contract, a save format, a
  behaviour-preserving refactor of a load-bearing path, a multi-system flow.

**Q2 — can it be cut into independent slices that don't touch the same code?**
- **No → one coupled unit. Yes → independent slices.**

| | one coupled unit | independent slices |
|---|---|---|
| **low-risk** | **Mechanical** — just do it, single context `0→3→4→4b→7`; no QA/Engineer split | **Parallel dispatch** — fan out worktree workers (mechanical each); coordinator owns the merge-train |
| **high-risk** | **Persona loop** — full `0–7`: QA writes tests blind to the code, Engineer can't edit them, fresh Validation reviews | **Parallel + persona loop per lane** — pin the shared contract first, then a persona loop in each lane |

Worked examples:
- Rename a config key across the repo → low-risk, coupled → **Mechanical.**
- Five unrelated small UI tweaks → low-risk, independent → **Parallel dispatch.**
- Rewrite the damage formula → high-risk, coupled → **Persona loop.**
- A feature spanning frontend + backend → high-risk, independent → **contract-first, persona loop per lane.**

Conservative default: **touches >1 seam (`project-details.md#SEAM-N`) → at least the persona bar.**
Check `project-details.md#RS-N` for project escalations (e.g. "money path → always persona"). When in
doubt, round up.

## Greenfield or brownfield? (does the spec already exist here?)

**Does the touched area have authoritative spec coverage?**
- **Yes → greenfield** — Stage 3 authors/extends the spec normally.
- **No → brownfield** (`greenfield-vs-brownfield.md`) — Stage 3 (PO box) reconstructs the spec for the
  touched **slice**, or the gap is **surfaced** (`[NEEDS-PO]`), never inferred from code. Record the
  area in the unspecified-surface register; a brownfield unit is **not Ready** until its slice is
  specified. Stance is per-unit — can differ across units in the same repo.

## Do

1. Classify: state the 2×2 cell AND the greenfield/brownfield stance explicitly.
2. If decomposable: cut the slices; name the shared contract to pin first in Stage 3; cap parallel
   workers at ~3–4.
3. Open/find the changelog item per the changelog binding (`project-details.md#CL-N`): Jira issue
   (Mode A) or on-disk `backlog/CL-####.md` (Mode B). Record the chosen route + ceremony on it.
4. Write the **Triage record** (the output stages 1–7 read), naming:
   - the active stages (mechanical activates `0/3/4/4b/7`; persona activates all),
   - the target **spec shard IDs / clause-ID ranges** this work touches (seed of the Stage-3 shard manifest).

## Exit criteria

- [ ] 2×2 cell named and recorded on the changelog item.
- [ ] Greenfield/brownfield stance recorded; brownfield → slice scoped for Stage-3 reconstruction, or the gap surfaced.
- [ ] For decomposable work: slices listed, shared contract identified, worker cap set.
- [ ] Triage record written: active stages + target shard IDs.
- [ ] Ceremony level fixed (changing it later is an explicit re-triage, recorded).

---
### Gate(s) that close this stage
- Routing decision + Triage record recorded on the changelog item (no script gate).
### Return
Return to PROCESS.md §0 and load the route's next active stage: Stage 1 (design) for the persona
route, Stage 3 (spec) for the mechanical route. Read that stage file fully and follow it; this one is done.
