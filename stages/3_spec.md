# Stage 3 — Spec-first (EARS)

**Role:** PO (drafts) → PM (approves). **Loaded with:** constitution + this file + the spec shard(s)
for the home this decision lands in (from the Triage record) + the Stage-1 structure shard (persona
route) + `project-details.md#SPEC-N` (authoring format, shard root, build command). On trigger: `spec-format/README.md` (shard + EARS rules),
`changelog-conventions.md` (the item's seed ACs), `greenfield-vs-brownfield.md` (if unspecified),
`definition-of-done.md` (the fold pin), `box-roles.md` (surface-back).

Active in **every** route — the gate before any test or code. **Write a behaviour decision into the
spec in the same exchange it is made** — never leave a decision as a conversational artifact. Code
does not start until the spec for this slice is frozen and PM-approved.

The changelog item's **EARS acceptance criteria** (`<ITEM-ID>/AC-n`, see `changelog-conventions.md`)
are the **seed clauses**: authoring refines them into canonical spec clauses; on the Stage-7 fold they
are pinned to the item `(§X per <ITEM-ID>, date)` (`definition-of-done.md`). **Spec authoring is
PO-box work** — a worker box that finds the spec inadequate **surfaces back** (`box-roles.md`); it does
not author or patch the canonical spec.

**Brownfield slice:** if no authoritative spec covers this area (`greenfield-vs-brownfield.md`),
reconstruct the spec for the **touched slice only** from existing code + PM-clarified intent, *then*
write code against it — never infer-and-proceed. The PO box reconstructs (arbitrating obvious
behaviour, escalating real decisions to the PM); a worker box surfaces the gap, it does not reconstruct.

## One update method (per SDD-PROP-08, 2026-09-02 — anti-spec-collapse)

Every change to canonical spec text — typo, new section, or wrong claim alike:

1. **Negotiate** the exact inserted / removed / updated text and its location with the PO first.
2. **Replace wholesale.** Old text goes; new text stands in its place. No Errata blocks, in-page addenda,
   DECISION/ruling brackets, strike-throughs, SUPERSEDED/CORRECTED chains, or dated deltas — the shard
   always reads as current ground truth. The **only** in-text annotation is the provenance pin
   `(§X per <unit-id>, YYYY-MM-DD)`, overwritten on each change, never chained. A retired clause-ID keeps a
   one-line lifecycle tag at its anchor, body removed (`lifecycle-states.md`); IDs are never reused.
3. **Commit the spec edit by itself** — message states what changed and why — before the code commits of
   the same slice. History (prior wording, rationale, reconciliation) lives in git and the changelog item,
   never in the document.

Things the chat *surfaces* but the PM has not *committed to* are **not** written until explicitly decided.

## Writing the clauses

- **One subsection = one content-only shard** (`spec/<section>/<subsection>.body.md`, no
  chrome/style/script — see `spec-format/README.md`).
- Behavioural clauses in **EARS**, each **atomic, testable, stably-ID'd**:
  - Ubiquitous — `The system shall …`
  - Event — `When <trigger> the system shall …`
  - State — `While <state> …`
  - Unwanted — `If <cond> then the system shall …`
  - Optional — `Where <feature> …`
- Clause-ID pattern is `clauseIdRegex` from `project-details.md#SPEC-N` (mirrored to
  `gates/gates.config.json`). Clause IDs never renumber — new clauses append.
- **Implementation grade:** every constant, formula, threshold traceable to a source. Outlines are
  spec gaps in disguise.
- **Spec form — terse and factual** (per SDD-PROP-09, 2026-09-02; binds authoring AND the Stage-7 fold):
  1. **Decision, not argument.** Rationale, alternatives, measurements, history → the changelog item /
     build contract / commit message. Never the shard.
  2. **Structured, not narrative.** Numbered/lettered clauses, bullets, tables for value catalogs, code
     blocks for formulas and signatures. A paragraph only where a rule cannot be a line.
  3. **One fact per line**, atomic and testable. EARS semantics in the shortest form — `When X: Y.` —
     the `the system shall` boilerplate is optional where the subject is obvious.
  4. **Name the concrete thing** — class, method signature, config key, constant, file.
  5. **No framing prose** — no preambles, "background", "note that", or restatement of another section;
     cross-ref by anchor.
  6. **Fold preserves form** — Stage 7 carries the draft's structure verbatim, never re-narrated.
  Exemplars: `project-details.md#SPEC-7`.
- Cross-refs use real shard anchors / clause-IDs so `link_check` resolves them.
- Transient working spec destined to fold: pin provenance now `(§X per <unit-id>, YYYY-MM-DD)`.

## The structure shard — approved with the spec

The Stage-1 structure diagram (`<ITEM-ID>.structure.body.md`: member level, delta form —
`stages/1_design.md` step 6) is **part of the spec diff the PM approves here**. Refine it while writing
clauses: every clause that names a class, signature or constant names a member the diagram carries, and
every diagram member is reachable from a clause — a mismatch is a spec defect. **Mechanical route** (no
Stage 1): a unit that adds a class or a public member writes the shard here (usually a few lines);
otherwise record `structure: N/A — <reason>` on the item. From PM approval on, the diagram is the
approved plan: it is **frozen with the tests** at Stage 5 (`structure_check --frozen`, the plugin hook),
the Engineer cannot edit it, and a needed deviation routes `[NEEDS-PO:structure]` to the **PM** — the PO
then replaces the shard wholesale (own commit, the one update method above) and re-freezes.

## Shard manifest (the deterministic input for later stages)

Record, in the transient working spec, the **shard manifest** for this unit: clause-ID ranges → shard
file paths, plus the structure shard's path. Stages 4–7 and every persona dispatch resolve shards from
this manifest by path-glob over the work-item's clause-IDs — no judgement, no whole-spec load.

## Contract-first note

If Stage 0 chose contract-first compose, the **shared contract is the first thing specced and frozen**
here, before the lanes diverge.

## Exit criteria

- [ ] Every decision written to its correct spec home (canonical or transient shard).
- [ ] All new behavioural clauses in EARS with stable IDs; no outline-shaped gaps; all
      constants/formulas sourced.
- [ ] Spec form: decision-only, structured, one fact per line; no rationale, history, or framing prose in
      the shard; changed text replaced wholesale (no strata).
- [ ] Shard manifest recorded (clause-ID ranges → shard paths, + the structure shard).
- [ ] Structure shard final — every public member the clauses name is in the diagram and vice versa —
      or `structure: N/A — <reason>` on the item.
- [ ] Cross-refs resolve; provenance pins present where folding is due.

---
### Gate(s) that close this stage
- `link_check` — run the gate for your OS: `gates/link_check.ps1` (Windows) / `gates/link_check.sh`
  (Linux/macOS); see `gates/README.md`. (PASS required: every cross-ref resolves.)
- `prose_check` — spec form (SDD-PROP-09): `gates/prose_check.ps1` (Windows) / `gates/prose_check.sh`
  (Linux/macOS); scope = shards changed vs base. WARN by default; `proseCheck.mode=strict` makes a touched
  shard over the paragraph-share or longest-paragraph threshold FAIL (migrate-on-contact).
- `structure_check --plan` — `gates/structure_check.ps1 -Plan` (Windows) / `gates/structure_check.sh --plan`
  (Linux/macOS): every structure shard is a member-level `classDiagram` (a memberless class is WARNed).
- PM approves the spec diff **including the structure shard** (pre-code gate, human).
### Return
Return to PROCESS.md §0 and load Stage 4 (test plan) — active in every route. Read that stage file
fully and follow it; this one is done.
