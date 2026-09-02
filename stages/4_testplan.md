# Stage 4 — Test Plan + Traceability

**Role:** PO/Orchestrator authors the traceability matrix in **every** route. The matrix is an
independent artifact — in the persona route it is reviewed against the spec (PM/PO) **before** QA
enters Stage 5, so the planner is never the implementer.
**Loaded with:** constitution + this file + the frozen spec shard(s) from the Stage-3 shard manifest +
`project-details.md#STK-N` (layer → test-home map). **Not** the implementation.

Active in **every** route. The plan lives in the spec (or a linked shard). Every behavioural clause
maps to ≥1 numbered scenario across the test layers — coverage becomes auditable *before* anyone writes
a test.

## The four test layers (each required, or "N/A — reason")

| Layer | What it exercises |
|---|---|
| **Pure-logic unit** | The function in isolation: math, parsers, predicates, config defaults. |
| **Integration** | Services through public interfaces; the chain in isolation. Test seams (`*ForTests`) ok; production-internal bypasses are not. |
| **Functional / lifecycle** | The full flow in a real loop; every state transition in sequence; assert observable side effects, not internal flags. |
| **Visual regression** (UI) | PNG baselines at every form factor, with a content canary. |

Exact layer names/tools per project are in `project-details.md#STK-N`; the *shape* (pure → integration
→ lifecycle → visual) is universal.

## Build the traceability matrix

For each behavioural clause-ID in the slice:

```
clause-ID → scenario# → (planned test-ID) → layer       → oracle source
CB.07     → S3        → T.CB.07.a         → integration → explicit clause
```

Every clause must appear ≥1 time. A clause with no scenario is either dead spec (delete it) or missing
coverage (add a scenario). This matrix is the input `coverage_check --plan` verifies mechanically to
close this stage.

## Declare an oracle source per planned test

Each planned test names **where its expected value comes from** — one of:

| Oracle source | The expected value is fixed by |
|---|---|
| **explicit clause** | a literal value/threshold stated in the spec clause |
| **example table** | a worked example/decision table in the spec |
| **formula** | a spec formula, hand-executed on paper |
| **external standard** | a cited standard (RFC, codec, currency rounding rule) |
| **invariant** | a property that must always hold (no exact value) |
| **metamorphic property** | a relation between inputs/outputs (f(2x)=2·f(x), reorder-stable) |
| **approved golden data** | a reviewed, signed-off golden corpus |

For **non-deterministic / async / ranking** behaviour the oracle is **metamorphic / golden /
invariant**, never an invented exact value — there is no single correct number to assert. Recorded in
the matrix; QA implements to it (Stage 5).

## The reachability gate (PO runs it here)

For each planned test: **"can a test literally reach this through the contracted, production API?"** If
not, the seam is wrong — fix it in the spec/design before any test is written. Catches un-testable spec
before it costs a QA pass.

## Exit criteria

- [ ] Every clause-ID → ≥1 numbered scenario across the four layers (or "N/A — reason").
- [ ] Each scenario reachable through a production entry point.
- [ ] Matrix recorded in the spec/linked shard with stable IDs.
- [ ] (Persona route) The matrix is reviewed vs the spec by the PO/PM and recorded before QA enters
  Stage 5 — QA receives it as input, it does not author it.

---
### Gate(s) that close this stage
- `coverage_check --plan` — run the gate for your OS: `gates/coverage_check.ps1 -Plan` (Windows) /
  `gates/coverage_check.sh --plan` (Linux/macOS). See `gates/README.md`.
  (PASS: every clause-ID in the manifest → ≥1 planned scenario).
- **Coverage scope:** `coverage_check` is **whole-corpus at ship** — every clause in `paths.spec` needs
  a test. For fast per-unit feedback in-loop, use `coverage_check --manifest <file>` / `-Manifest
  <file>` (Windows) to scope to this unit's shards; the ship-time pass stays whole-corpus.
### Return
Return to PROCESS.md §0 and load the route's next active stage: Stage 5 (QA) for the persona route, or
Stage 7 (gates + ship) for the mechanical route. Drop this stage body from context.
