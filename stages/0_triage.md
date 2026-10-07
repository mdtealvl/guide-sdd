# Stage 0 — Triage / Right-size

- **Role:** Orchestrator. **Loaded with:** constitution + this file.
- Load on trigger: `box-roles.md` (box role), `greenfield-vs-brownfield.md` (spec-coverage stance),
  `definition-of-done.md` (DoR on pickup), `changelog-conventions.md` (filing the item), and
  `project-details.md` sections `#CL-N` / `#SEAM-N` / `#RS-N`.
- Decides how much ceremony a unit gets and produces the records later stages read. The only stage that
  runs every time.

**Know your box role first (`box-roles.md`).**
- A **PO box** does the full Stage 0: triage, route, file/shape the changelog item, mark it ready.
- A **worker box** does not triage — it *picks up* an item the PO marked ready (work-ready state,
  `project-details.md#CL-6`) and FIRST verifies the **Definition of Ready** (`definition-of-done.md`):
  - DoR fails → surface the gap (`[NEEDS-PO]`/`[BLOCKED]` per `changelog-conventions.md`, transition to
    PO-attention state `project-details.md#CL-7`) and do **not** start.
  - DoR holds → load the Triage record's next active stage.

## Is it an item yet?

- A raw request (a sentence, a thread, a bug report, a PRD), not a changelog item → run **`intake.md`**
  first: classify, split to one goal, run the numbered-question loop and the domain screen, write the
  item, record the readiness verdict.
- Triage right-sizes an **item**.

## Right-size it: three questions

Ask in order. **Q0 confirms one goal; Q1 sets rigor; Q2 sets whether to parallelize.**

- **Q0 — one goal?** Does the item hold two or more deliverables reviewable and mergeable independently?
  (Count deliverables, never verbs.) Yes → back to `intake.md` §2: split, or record `kept-whole`.

**Q1 — could a wrong guess slip through?** Is a misread both *expensive* and *not obvious to catch*?
- **No → low-risk:** typo, rename, config tweak, mechanical repoint, values already decided.
- **Yes → high-risk:** money/economy math, combat/sim math, a service contract, a save format, a
  behaviour-preserving refactor of a load-bearing path, a multi-system flow.

**Q2 — can it be cut into independent slices that don't touch the same code?**
- **No → one coupled unit. Yes → independent slices.**

| | one coupled unit | independent slices |
|---|---|---|
| **low-risk** | **Mechanical** — single context `0→3→4→4b→7`; no QA/Engineer split | **Parallel dispatch** — worktree workers (mechanical each); coordinator owns the merge-train |
| **high-risk** | **Persona loop** — full `0–7`: QA writes tests blind to the code, Engineer can't edit them, fresh Validation reviews | **Parallel + persona loop per lane** — pin the shared contract first, then a persona loop per lane |

Worked examples:
- Rename a config key across the repo → low-risk, coupled → **Mechanical.**
- Five unrelated small UI tweaks → low-risk, independent → **Parallel dispatch.**
- Rewrite the damage formula → high-risk, coupled → **Persona loop.**
- A feature spanning frontend + backend → high-risk, independent → **contract-first, persona loop per lane.**

- Conservative default: **touches >1 seam (`project-details.md#SEAM-N`) → at least the persona bar.**
- Project escalations: `project-details.md#RS-N` (e.g. "money path → always persona").
- When in doubt, round up.

## Greenfield or brownfield? (does the spec already exist here?)

**Does the touched area have authoritative spec coverage?**
- **Yes → greenfield** — Stage 3 authors/extends the spec normally.
- **No → brownfield** (`greenfield-vs-brownfield.md`) — Stage 3 (PO box) reconstructs the spec for the
  touched **slice**, or the gap is **surfaced** (`[NEEDS-PO]`), never inferred from code. Record the
  area in the unspecified-surface register; a brownfield unit is **not Ready** until its slice is
  specified. Stance is per-unit.

## Do

1. Classify: state the 2×2 cell AND the greenfield/brownfield stance explicitly.
2. If decomposable: cut the slices; name the shared contract to pin first in Stage 3; cap parallel
   workers at ~3–4.
3. Open/find the changelog item per the binding (`project-details.md#CL-N`): Jira issue (Mode A) or
   on-disk `backlog/CL-####.md` (Mode B). Record the route + ceremony on it.
4. Write the **Triage record** (what stages 1–7 read), naming:
   - the active stages (mechanical activates `0/3/4/4b/7`; persona activates all),
   - the target **spec shard IDs / clause-ID ranges** (seed of the Stage-3 shard manifest).

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
