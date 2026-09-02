# Definition of Ready & Definition of Done

> Demand-loaded spine. The two lifecycle gates, as literal checklists.
> **DoR** = the Stage 0 / worker-pickup **entry** bar. **DoD** = the Stage 7 consolidated **exit**
> bar (fresh Validation checks the unit against it). They consolidate existing triage and ship
> criteria — no new ceremony.

A **PO box** files & readies items; a **worker box** picks up only DoR-met items and runs them to
DoD. A worker that hits a gate it may not clear **surfaces back** — never guesses or patches the
spec. See `box-roles.md`.

---

## Definition of Ready (DoR)

A changelog item may be **picked up for work** only when **all** hold. A worker box verifies DoR
*before* loading any route stage; a "ready" item that fails DoR is **surfaced back**
(`box-roles.md`), not fixed by the worker.

- [ ] **Clear title + type** — Story / Bug / Task / Spike (per `changelog-conventions.md`).
- [ ] **ACs written as EARS clauses**, each carrying a stable id `<ITEM-ID>/AC-n`,
      implementation-grade (every constant/threshold traceable; no "should work" prose).
- [ ] **No open forks / TBDs** — those are PO decisions, made *before* an item is Ready.
- [ ] **Target spec shard(s) / clause-ID ranges identified** — or explicitly
      "spec authored in Stage 3" for design-bearing work.
- [ ] **Prerequisites / viability noted** — dependencies & blockers known, not latent.
- [ ] **Points assigned** (Fibonacci default; see `changelog-conventions.md`).
- [ ] **Right-size route recorded** — mechanical / persona / parallel (the Stage 0 2×2 cell).

A Bug additionally starts from a **failing test**; a Spike's "done" is a recorded **decision**, not
shippable code (`changelog-conventions.md`).

---

## Definition of Done (DoD)

A unit is **DONE** only when **all** hold. This **is** the Stage 7 exit bar consolidated; fresh
Validation accepts/declines the unit against it (the Orchestrator re-runs, never reports).

- [ ] **Working-spec folded** into the canonical spec in spec form (structure preserved, decisions only), with provenance pins
      `(§X per <ITEM-ID>, YYYY-MM-DD)` on every clause changed this ship.
- [ ] **Every behavioural clause → ≥1 test** across the four layers, or `N/A — <reason>`
      (coverage traces both directions: clause-ID ↔ test-ID).
- [ ] **Reverse traceability holds** — every behaviour-affecting diff links to a clause/scenario.
      A changed code path with **no** linked clause is a **defect**, not just an unfolded extra:
      the trace runs clause→test **and** changed-code→clause.
- [ ] **Each acceptance test declares its oracle source** — one of: explicit clause · example
      table · formula · external standard · invariant · metamorphic property · approved golden
      data. Non-deterministic / async / ranking behaviour uses metamorphic / golden / invariant,
      **never** an invented exact value (an oracle captured from the code is a snapshot of a bug).
- [ ] **Every fixture gap is classified** — `harmless` / `reviewed` / `blocking`. A **blocking**
      gap (a fixture that bypasses the real production path for behaviour that depends on it)
      **cannot ship** — surfaced, not shipped. Writing the gap down is necessary, not sufficient.
- [ ] **Non-functional floor met** — for each category that applies (set in Project Details), it
      is **met or `N/A — <reason>`**. Behaviour-correct work that violates an applicable category
      is **NOT Done**:
  - [ ] security · [ ] privacy · [ ] accessibility · [ ] performance · [ ] observability
  - [ ] compatibility · [ ] migration · [ ] rollback · [ ] compliance
- [ ] **Every dispatched agent lane reconciled** — each sub-agent lane opened for this unit carries a
      verdict **LANDED (commit-hash)** or **DIED (re-queued with failure guidance)**, verified by
      artifact (`git log`), never by the agent's report. No lane may cross a session/context boundary
      "in flight" — *an agent's existence is not evidence its work landed* (`session-lifecycle.md`).
- [ ] **Wired-path behaviour has a canary** — behaviour reachable only through a production wiring seam
      (dispatch table, DI registration, feature-arm selection) carries a test that **fails if the wiring
      is bypassed or dead**. Guards the representative-default dead-wire trap (`gates/README.md`,
      `stages/5_qa.md`): a convenience default on a behaviour-arm parameter leaves every arm dead in
      production while arm-explicit tests stay green.
- [ ] **Full suite green**, re-run by the Orchestrator — an agent's "tests pass" is not accepted.
- [ ] **Authoritative `run_all` gate bank green** (full bank incl. `fold_check`) over the
      folded + pinned + recompiled corpus.
- [ ] **Fresh Validation accepts** (a context that did not build the thing; vs spec + constitution).
      Validation reads **diffs + clauses + test output** — never a summary of them.
- [ ] **Docs updated in lockstep** — diagram-first where applicable, per slice, never batched.
- [ ] **`spec/index.html` recompiled** (whole-corpus view never stale).
- [ ] **Transient working-spec archived** (`git mv` to `spec/archive/`) — never deleted.
- [ ] **Changelog item carries the ship-SHA and is transitioned Done** (per `project-details.md#CL-N`).

Traceability is then closed: `clause-ID → scenario → test-ID → code → ship-SHA`.

---

### Cross-links
- **Stage 0** (`stages/0_triage.md`) — produces the records the DoR checks; worker verifies DoR here.
- **Stage 7** (`stages/7_ship.md`) — the DoD is its exit criteria; Validation enforces it.
- **`box-roles.md`** — who may clear each gate; the surface-back protocol for a worker that can't.
- **`changelog-conventions.md`** — how a Ready item is written; surfacing templates.
