# Stage 6 — Engineer (frozen tests)

**Role:** Engineer sub-agent. **Scoped context:** constitution (verbatim) + this file + the spec
shard(s) from the manifest + QA's frozen tests + the Stage-4 traceability matrix and QA's
fixture/shape-gap notes + named seam rows (`project-details.md#SEAM-N`) and stack
(`project-details.md#STK-N`). **You have NO write access to the tests.** The matrix and shape-gap notes
are **not** the implementation, so they do not break QA⊥Engineer blindness (you already see the frozen
tests); they let you avoid satisfying a test via a fixture stand-in that skips a required production path
/ test layer QA flagged.

Persona route only. Implement against the spec, with QA's tests as the acceptance bar. You are briefed
with **intent + anti-patterns**, never "make these green" alone — a test handed as the *only* success
criterion invites a degenerate implementation (synthetic timers, teleports, deleted code paths) that
passes the test and matches nothing in the spec. The spec is your target; the tests are the floor.

Mechanical guard (Tier A with the GUIDE SDD plugin): the dispatcher runs `/sdd-persona engineer` before this
stage and `/sdd-persona clear` after it; while the marker is set, the plugin's PreToolUse hook denies every edit
to a `testGlobs` path. Tier B: export `SDD_PERSONA=engineer` in the Engineer's session instead. The gate
`test_edit_ban` still runs at Stage 7 — the hook is the early tripwire, not the proof.

## Rules

- **Test-edit ban is absolute.** Never touch a test file. Disputes are **filed** up to the
  Orchestrator, never resolved by editing a test. (`gates/test_edit_ban.ps1` (Windows) /
  `gates/test_edit_ban.sh` (Linux/macOS) proves you didn't — structural enforcement of QA⊥Engineer.)
- **Conform to the spec, not just the tests.** Green is necessary, not sufficient.
- **Use the seams.** No bypassing the project's architecture boundaries (`project-details.md#SEAM-N`),
  even if a bypass would be greener faster. `seam_conformance` checks this at ship.
- Iterate locally until the suite is green (the Orchestrator re-runs to verify — your "tests pass" is
  not taken on narrative).
- Clean your own test droppings before handing back. Stage only the files this task changed, **by
  path** — never a blanket add.

## Disputes

If a test seems wrong, you may be right — but you don't get to decide. File it: the Orchestrator
arbitrates against the spec. If the spec is ambiguous, it goes to PO/PM and the **spec** is fixed; QA
then revises the test. You wait.

## Test-challenge protocol (frozen-but-wrong tests)

A frozen test can be wrong. You **cannot edit it** — but you are not stuck between contorting the code
to satisfy a bad test and stalling forever. You **challenge** it:

1. **Raise the challenge** on the changelog item, **citing the conflict** — the specific clause,
   scenario, or production path the test contradicts. A bare "this test feels wrong" is not a challenge;
   name the authority it violates.
2. **The Orchestrator resolves** exactly one of three ways, **all recorded on the item**:
   - **(a) change the spec** — the spec was wrong/ambiguous; PO/PM fix it, QA revises the test;
   - **(b) change the test** — the test misreads a correct spec; QA fixes it (still QA, never you);
   - **(c) reject the challenge** — the test is right; you conform the code.
3. A challenge **does not unblock local editing** of the test. It **routes through the Orchestrator**;
   you wait on the resolution. The test-edit ban holds throughout.

This closes the "contort the code or stall" failure without ever letting the Engineer edit the tests
that keep QA ⊥ Engineer honest.

## Exit criteria

- [ ] Implementation conforms to the spec (not just passes tests).
- [ ] Seams respected; staged by path; droppings cleaned.

---
### Gate(s) that close this stage
- `test_edit_ban` — run the gate for your OS: `gates/test_edit_ban.ps1` (Windows) /
  `gates/test_edit_ban.sh` (Linux/macOS). See `gates/README.md`. (PASS: no test file touched).
- `suite_green` — Orchestrator re-runs the project suite (`suiteCmd`); exit 0 required.
### Return
Return to PROCESS.md §0 and load Stage 7 (gates + ship). Drop this stage body from context.
