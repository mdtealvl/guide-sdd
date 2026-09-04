# Stage 4b — Build Plan (files, sequence, read ledger)

**Role:** Orchestrator/PO — the dispatcher. **Loaded with:** constitution + this file + the Stage-3
shard manifest + the approved **structure shard** (`<ITEM-ID>.structure.body.md`, or the item's
`structure: N/A — <reason>` line) + the Stage-4 matrix + `project-details.md#STK-N` (layout) and
`#TOOL-6` (quiet gate idioms). **Not** the codebase at large: plan from the structure shard and targeted
greps; every file this stage opens is a `read` row in the ledger, so the plan's own cost is measured.

Active in **every** route, after the spec + structure diagram are PM-approved and the test plan is
closed. This stage decides **how** the unit is built — which files, in what order, in which context —
and it is the one place that **optimizes tokens**: what each later context reads, and what it is told
not to. Mechanical route: one slice, a file map + ranges, ≤ 10 lines — the ledger still records `P`
and `S1` so the readout exists.

## The artifact — `<ITEM-ID>.buildplan.md`

One file in the transient working-spec home (`project-details.md#SPEC-4`; `buildPlan.glob` in
`gates.config.json` finds it). Archived at ship, never folded — a build record, not behaviour. Four
sections in this order; the ledger is **last** so rows append.

### 1. File map

| path | action | slice | classes (from the structure shard) | clause-IDs | full ≈tok |
|---|---|---|---|---|---|

`create` / `edit` / `delete`. Every class in the structure shard lands in exactly one path; every path
has one owner slice; `full` is the whole-file read cost (`token_ledger add` computes it — never by hand).

### 2. Sequence — slices `S1…Sn`

A **slice** is one dispatchable step: one persona context × one ordered write set.

| slice | stage / persona | writes | reads (path:range) | do-not-open | gates (filtered) | after | budget ≈tok |
|---|---|---|---|---|---|---|---|

Persona route: the QA slice (Stage 5), one or more Engineer slices (Stage 6), the ship slice (Stage 7,
Orchestrator). Parallel route: one build plan per lane; cross-lane rows travel via the item (worktrees
do not share working files); the Orchestrator concatenates lane ledgers at merge for the plan readout.

### 3. Briefs — what the dispatcher hands each slice, and nothing else

Its stage file + the shard-manifest **slice** (its clause-IDs' shards only) + the ledger rows **for its
audience** + the pinned, output-filtered gate commands (`#TOOL-6`) + its budget. Audience: QA receives
`qa` rows only; the Engineer `eng` + `any`; **Validation receives no ledger rows** — the diff and the
clauses are its whole world (`stages/7_ship.md` §2, invariant 3).

### 4. Ledger — append-only, machine-read by `gates/token_ledger.*`

| kind | by | for | aud | path | range | hash | full | est | note |
|---|---|---|---|---|---|---|---|---|---|

- `read` — a read a slice **did** (`by` = that slice; `est` = tokens admitted).
- `range` · `grep` · `pin` · `skip` — advice for a later slice (`for` = `S6`, or `*`): read only lines
  a–b; grep an anchor ±N lines; the signature/constant is pasted in `note`, do not open the file; do
  not open the file at all.
- `aud` — `any` · `qa` · `eng`. A `qa` row never points into `paths.code` (the script refuses it).
- `hash` — the file's blob hash when the row was written. `token_ledger verify` names any row whose
  file has since changed; a stale row is **reconciled, never trusted** (as an unstash pin).

Rows are written with `token_ledger add` (it computes `hash`, `full`, `est`); `report` prints the
`tokens:` lines; every number is recomputable from the table. Tokens are `chars × tokensPerChar` —
an estimate of what a context admits, never a billed count.

## Do

1. **Map classes to files.** From the structure shard: each Added/Changed class → its path; delete
   rows for Removed. Grep to locate an existing class (`grep -n "class Foo"`), do not open the file.
2. **Order the slices.** Dependencies first (a shared contract, a base type, a migration); then by
   **locality** — consecutive slices share files, and a warm context re-reads nothing: **resume a live
   agent over re-dispatching**, unless the persona must be blind or fresh (QA, the hunt pass,
   Validation — invariant 3).
3. **Seed the ledger** with this stage's own reads (`by=P`).
4. **Write the advice rows** — for every file two slices touch, and for every file a slice would
   plausibly open but must not. Apply the optimizations below; each is a row kind or a sequence rule.
5. **Set a budget per slice** (Σ planned reads); the slice readout compares against it.
6. **Close:** `structure_check --plan`, `token_ledger verify`, `token_ledger report`. Record the plan
   line on the item as the **planned** `tokens:` figure.

## Token optimizations — apply every one that fits

- **Read once, range thereafter.** The first slice to open a large file writes a `range` row for each
  later slice that needs it: *"S6: lines 700–1200; 1–699 are DI wiring, irrelevant to CB.07."*
- **Pins beat reads.** A later slice that needs one signature or constant gets a `pin` — three lines
  pasted, not three hundred read.
- **Name the negative space.** `skip` rows for the files a slice would open out of habit: unchanged
  dependencies, siblings, generated code. Most waste is a file that was never needed.
- **Anchors over line numbers.** If an earlier slice will edit the file before the reader arrives,
  write a `grep` row (`'class RewardBag' ±40`) — line numbers drift, anchors do not.
- **Per-slice shard manifest.** Each brief carries only the shards of its clause-IDs; pre-compute it.
- **Test-body pins.** The QA slice pins each test's name + assertion lines per clause (`aud=eng`) so
  the Engineer reads the assertion, not the fixture scaffolding.
- **Spine load list.** Per slice, the exact spine docs it needs (its stage file + named shards).
- **Stale-pin guard.** Every brief opens with `token_ledger verify --for Sn`; a STALE row is re-read
  and rewritten before anything is built on it.
- **Budget, then readout.** Planned ≈tok per slice; a slice more than 50 % over budget says why in its
  readout — a signal for the next plan, not a halt.

## Readout — every slice end, and the plan end

At the end of each slice: `token_ledger report --slice Sn` → write the line it prints —
`tokens: Sn admitted ~A; saved ~V (P%); ledger H/N honoured` — on the item (`changelog-conventions.md`
§6). At Stage 7 §4 (and in `/wrap`): `token_ledger report` → the `tokens: plan …` line, which also carries
the planning cost `P`. `metrics.md` reads these as **cost**, beside the outcome metrics, never instead.

## Anti-patterns

- Planning by reading the codebase — the `P` line will show it.
- A pin that is a pointer, not a paste; advice with no hash.
- A `qa` row into the implementation; ledger rows handed to Validation.
- A build plan that re-decides design: a member the structure shard lacks is `[NEEDS-PO:structure]`,
  not a file-map row.

## Exit criteria

- [ ] File map: every structure-shard class → one path; every path → one owner slice.
- [ ] Sequence covers every clause-ID in the manifest; dependencies ordered; lanes split if parallel.
- [ ] Ledger seeded: `P`'s reads, ≥ 1 advice row per later slice per shared file, `aud` + `hash` on every row.
- [ ] Budgets recorded; the planned `tokens:` line on the item.

---
### Gate(s) that close this stage
- `structure_check --plan` — `pwsh gates/structure_check.ps1 -Plan` (Windows) / `sh gates/structure_check.sh --plan`
  (Linux/macOS): every structure shard is member-level.
- `token_ledger verify` + `report` — `pwsh gates/token_ledger.ps1 verify -Plan <file>` /
  `sh gates/token_ledger.sh verify --plan <file>`, then `report`. No human gate.
### Return
Return to PROCESS.md §0 and load the route's next active stage: Stage 5 (QA) for the persona route,
or Stage 7 (gates + ship) for the mechanical route. Read that stage file fully and follow it; this one
is done.
