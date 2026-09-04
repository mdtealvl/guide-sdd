# Definition of Ready & Definition of Done

> Demand-loaded spine. The two lifecycle gates, as literal checklists.
> **DoR** = the Stage 0 / worker-pickup **entry** bar, closed by the PO's **readiness verdict**.
> **DoD** = the Stage 7 consolidated **exit** bar (fresh Validation checks the unit against it).
> They consolidate existing triage and ship criteria — no new ceremony.

A **PO box** files & readies items; a **worker box** picks up only DoR-met items and runs them to
DoD. A worker that hits a gate it may not clear **surfaces back** — never guesses or patches the
spec. See `box-roles.md`.

---

## Definition of Ready (DoR)

A changelog item may be **picked up for work** only when **all** hold. A worker box verifies DoR
*before* loading any route stage; a "ready" item that fails DoR is **surfaced back**
(`[BLOCKED:dor-fail]`, `box-roles.md`), not fixed by the worker.

- [ ] **Clear title + type** — Story / Bug / Task / Spike (per `changelog-conventions.md`).
- [ ] **Verbatim request recorded** — the PM's words, quoted (the Stage-7 intent reference).
- [ ] **ACs written as EARS clauses**, each carrying a stable id `<ITEM-ID>/AC-n`,
      implementation-grade (every constant/threshold traceable; no "should work" prose). A pre-Ready
      `CAP-n` has been converted; none remain.
- [ ] **Success signal is measurable** — a line a test or demo can be judged against.
- [ ] **Open questions empty; assumptions ratified** — each question answered beside itself by the
      PM; each assumption marked ratified. Those are PO/PM decisions, made *before* an item is Ready
      (`intake.md` §3).
- [ ] **Boundaries set** — Always / Ask-first / Never filled; at least one Never.
- [ ] **Non-functional screen done** — for each applicable category (Project Details): an AC, an
      `N/A — <reason>`, or an open question (which then blocks Ready). None silently unaddressed.
- [ ] **Target spec shard(s) / clause-ID ranges identified** — or explicitly
      "spec authored in Stage 3" for design-bearing work.
- [ ] **Structure shard approved with the spec** — the member-level class diagram (delta form,
      `stages/1_design.md` step 6) PM-approved at Stage 3; or `structure: N/A — <reason>` on the item;
      or "authored in Stage 3" alongside the spec.
- [ ] **Prerequisites / viability noted** — dependencies & blockers known, not latent.
- [ ] **Points assigned** (Fibonacci default; see `changelog-conventions.md`).
- [ ] **Right-size route recorded** — mechanical / persona / parallel (the Stage 0 2×2 cell).
- [ ] **Readiness verdict recorded by the PO** — one question: *could a worker implement this
      without inventing a decision nothing records?* **PASS** → Ready · **CONCERNS** → each listed
      with what fixes it; the PM waives or fixes before Ready · **FAIL** → not Ready; findings ordered
      by severity, each naming the fixing stage or doc.

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
- [ ] **(Persona route) `frozen: <sha>` on the item**, and the authoritative `test_edit_ban` ran
      against **that SHA** (not a branch name) over the working tree — the proof that no test, gate
      script or gate config differs from what QA froze.
- [ ] **Public surface = the approved structure shard** — `structure_check` green: the shard unchanged
      vs the frozen SHA before the fold, every diagram class/member resolving in the code after it, no
      `Removed` class present; Validation's reverse trace found no public member the diagram lacks;
      every `[NEEDS-PO:structure]` answered by the **PM** and re-frozen. Never an Engineer edit.
- [ ] **Token readout recorded** — a `tokens:` line per slice and one for the plan on the item
      (`gates/token_ledger.* report`; estimates from bytes admitted, never billed), read as cost beside
      `metrics.md`.
- [ ] **Authoritative `run_all` gate bank green** (full bank incl. `fold_check`; `suiteCmd` set) over the
      folded + pinned + recompiled corpus.
- [ ] **Fresh Validation accepts** — a context that did not build the thing, per the brief in
      `stages/7_ship.md` §2 (conformance + hunt + verification-gap + intent alignment), verdict written
      as `validated: <base>..<head> accept` on the item. Validation reads **diffs + clauses + test
      output** — never a summary of them.
- [ ] **Out-of-range findings deferred, not fixed** — each `[DEFER]` line carries evidence; nothing
      outside the unit's clause range changed.
- [ ] **Docs updated in lockstep** — diagram-first where applicable, per slice, never batched.
- [ ] **`spec/index.html` recompiled** (whole-corpus view never stale).
- [ ] **Transient working-spec and build plan archived** (`git mv` to `spec/archive/`) — never deleted;
      the structure delta folded into the area's canonical structure shard.
- [ ] **Changelog item carries the ship-SHA and is transitioned Done** (per `project-details.md#CL-N`).

Traceability is then closed: `clause-ID → scenario → test-ID → code → ship-SHA`.

---

### Cross-links
- **`intake.md`** — produces the fields the DoR checks.
- **Stage 0** (`stages/0_triage.md`) — produces the records the DoR checks; worker verifies DoR here.
- **Stage 7** (`stages/7_ship.md`) — the DoD is its exit criteria; Validation enforces it.
- **`box-roles.md`** — who may clear each gate; the surface-back protocol for a worker that can't.
- **`changelog-conventions.md`** — how a Ready item is written; the item lines (`[DEFER]`, `validated:`, `lesson:`).
