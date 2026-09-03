# Stage 5 — QA (spec-only, blind)

**Role:** QA sub-agent. **Scoped context:** constitution (verbatim) + this file + the frozen spec
shard(s) from the manifest + the **PO-authored Stage-4 traceability matrix** (as input — you do not own
it) + the `project-details.md#STK-N` test-home map + named seam rows (`project-details.md#SEAM-N`).
**You do NOT see the implementation, the router, or any sibling working notes. That blindness is the
independence.** With the GUIDE SDD plugin the dispatcher sets `/sdd-persona qa` first: the hook then
denies any Read/Grep/Glob under `paths.code`. Without it, the `qa_import_ban` gate proves the structural
half only; the rest is on you.

Persona route only. Implement tests for the matrix's scenarios, deriving every expected value (the
oracle) from the **spec** — not from the matrix and never from the code. You do not author the coverage
map (the PO did, in Stage 4) and you never see the implementation. If you want to peek at the code to
learn an expected value, stop: that value must come from the spec.

## Rules

- **Oracle rule.** Expected values derive from the spec, never the code under test. A test whose
  expected output was captured from the code under test is a snapshot of a bug protecting the bug.
  Hand-execute the spec's formulas on paper; reimplement naively from spec text for large input spaces;
  use golden corpora and metamorphic relations.
- **Record the oracle source.** Each test names where its expected value comes from — one of: explicit
  clause · example table · formula · external standard · invariant · metamorphic property · approved
  golden data (the Stage-4 matrix planned it; QA confirms it on the test). Non-deterministic / async /
  ranking behaviour uses metamorphic / golden / invariant, never an invented exact value.
- **Shape honesty / production entry points only.** Exercise the real production path. Stubs solely to
  compile. No production-internal bypasses. Where a fixture stands in for production (in-memory DB,
  frozen clock, test JWT, stub HTTP, N=1 cardinality), **write the gap down** next to the test **and
  classify it**:

  | Severity | Meaning |
  |---|---|
  | `harmless` | the stand-in cannot change the behaviour under test (e.g. frozen clock for a non-time clause) |
  | `reviewed` | a stand-in the behaviour touches, judged acceptable and recorded |
  | `blocking` | a fixture that bypasses the real production path for behaviour that depends on it |

  A **`blocking`** gap is **surfaced, not shipped** (it cannot pass DoD — `definition-of-done.md`).
- **Wire-canary for seam-reached behaviour.** Where a clause's behaviour is reachable only through a
  production wiring seam (dispatch table, DI registration, a feature/behaviour-arm selection), write a
  **canary**: a test that exercises the real wired path and **fails if the wiring is bypassed or dead**.
  Watch the **representative-default dead-wire trap** — a convenience overload that *defaults a
  behaviour-arm parameter* leaves every arm dead in production while arm-explicit tests stay green. It is
  grep-able: check the callers of the arm-taking API; if **no** production caller passes the arm
  explicitly, the arm is dead — surface it as a spec/impl defect (the mechanical form is a gate recipe,
  `gates/README.md`). A DoD item (`definition-of-done.md`).
- **No code in test files.** A QA test must not import production internals beyond the contracted
  surface — it tests through the same API a caller has. The `qa_import_ban` gate
  (`gates/qa_import_ban.ps1` (Windows) / `gates/qa_import_ban.sh` (Linux/macOS), `gates/README.md`)
  gives a **partial structural proof** of QA ⊥ implementation.
- **Tag every test with its clause-ID** (`@clause:<id>` per `gates.config.json`) so `coverage_check`
  resolves it.
- Tests must be **red and compiling** at handoff — red because no impl yet; compiling so the Engineer
  has an executable acceptance bar.

## Ambiguity = spec bug (orchestrator-mediated)

You and the Engineer never resolve a spec ambiguity between yourselves. An ambiguity is a **spec bug**:
file it up to the Orchestrator. The PO patches it if the answer is obvious from existing convention; the
PM decides if it isn't; the resolution flows back and the spec is fixed **before code is written.** Your
blindness is what surfaces these — QA doubling as a spec-quality check.

## Behaviour-preservation variant (refactors)

If this is a refactor of a live path, the **existing suite is the oracle**: every prior behaviour must
produce byte-identical results. You migrate any test *calls* a signature change forces, keeping every
*assertion* byte-identical. You still never author an expected value from the new code. The test-edit
ban holds for the Engineer regardless.

## Exit criteria

- [ ] Every planned scenario implemented as a test tagged with its clause-ID + oracle source.
- [ ] Expected values sourced from spec; fixture/shape gaps written down **and** classified
      (`harmless`/`reviewed`/`blocking`); any `blocking` gap surfaced.
- [ ] No production internals imported beyond the contracted surface (`qa_import_ban` passes).
- [ ] Tests red + compiling. No production code read or written.

---
### Gate(s) that close this stage
- `coverage_check` — run the gate for your OS: `gates/coverage_check.ps1` (Windows) /
  `gates/coverage_check.sh` (Linux/macOS). (PASS: every clause-ID → ≥1 test-ID; tags in notes do not
  count; skip/only markers are named.)
- Suite is RED-as-expected and tests compile (Orchestrator re-runs to confirm).
- **Freeze** (Orchestrator): commit QA's tests, then `pwsh gates/freeze.ps1 -Unit <ITEM-ID>` /
  `sh gates/freeze.sh --unit <ITEM-ID>`. It refuses a dirty tree, writes `gates/.frozen`, and prints the
  `frozen: <sha>` line — **record it on the changelog item** (the item's copy is authoritative; the file
  is a mirror), then commit the marker. That SHA is the base every later `test_edit_ban` diffs against.
Tests are now **frozen** — the Engineer cannot edit them, and neither can the gate config.
### Next
Return to PROCESS.md §0 and load Stage 6 (Engineer). Read that stage file fully and follow it; this one
is done.
