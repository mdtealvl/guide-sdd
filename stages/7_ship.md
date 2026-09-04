# Stage 7 — Gates + Ship & Fold

**Role:** Orchestrator runs gates + owns the merge; Validation sub-agent (fresh context) reviews.
**Loaded with:** constitution + this file + `project-details.md#CL-N` (changelog binding) +
`project-details.md#SPEC-N` (build command) + the changelog item + the build plan (for the fold of the
structure shard and the plan readout, §4). Validation is spawned **fresh** with
the brief in §2 — it did not build the thing.

Closing stage in **every** route. Green is necessary, not sufficient. Mechanical gates run first
(cheap, deterministic); fresh Validation runs last (judgement against spec + intent).

This stage is the consolidated exit bar: the **Definition of Done** (`definition-of-done.md`) is the
literal checklist Validation enforces. The changelog item transitions **Done** (step 5 below,
`project-details.md#CL-4`) **only when the DoD fully holds** — every item unchecked keeps the unit open.

## Order of operations

### 1. Pre-fold mechanical gates — `run_all --pre-fold` (must be green)

Run the gate runner for your OS from anywhere inside the repo: `pwsh gates/run_all.ps1 <base> -PreFold`
/ `sh gates/run_all.sh <base> --pre-fold` (persona route) or add `-Mechanical` / `--mechanical`
(mechanical route). It runs `link_check` + `prose_check` + `coverage_check` + (`test_edit_ban` +
`structure_check --frozen`, persona only) + `structure_check` + `suite_green`, but **SKIPS** `fold_check` —
the provenance pins do not exist yet (step 3).

`<base>` is the **QA-frozen SHA** from the item's `frozen:` line (persona route; written by
`gates/freeze.*` at Stage 5 exit and mirrored in `gates/.frozen`) or the pre-work base (mechanical).
Pass the SHA, not a branch name: `test_edit_ban` diffs that commit against the **working tree** and also
proves the gate config and scripts are the ones QA froze. `suiteCmd` must be set — an unset suite is
exit 2, never a skip.

| Gate | Proves | Type |
|---|---|---|
| `coverage_check` | every clause-ID → ≥1 test-ID (both directions); tags in notes do not count; skip/only markers are named | generic script |
| `test_edit_ban` | no test file, test-runner config, gate script or gate config differs from the frozen SHA (working tree incl. untracked; renames not collapsed) — persona route only | generic script |
| `structure_check` | pre-fold, persona only: no structure shard differs from the frozen SHA (the PM-approved diagram did not move); every pass: every class and member in every structure shard resolves to an identifier under `paths.code`, and a class under `Removed` is absent | generic script |
| `link_check` | every spec cross-ref resolves to a real anchor/shard | generic script |
| `constitution_lint` | project principle checks hold | template + config |
| `seam_conformance` | architecture seams (`#SEAM-N`) not bypassed | template + config |
| `qa_import_ban` | QA tests import nothing production-internal (fails with no rules) | template + config |
| `suite_green` | the project suite exits 0, **re-run by the Orchestrator** | runner (project details) |

Trust artifacts, not narratives: the Orchestrator re-runs the suite; an agent's "tests pass" is not
accepted. (Project-specific gates run only if their concrete script + rules exist.)

### 2. Fresh Validation — four lenses, one verdict

**The brief** (what the Validation context is handed — and not):

| HANDED | NOT HANDED |
|---|---|
| `git diff <frozen-sha>..HEAD` (the full diff, not a summary) | the Orchestrator's transcript or notes, the build plan and its ledger |
| the shard manifest's spec clauses + the approved structure shard + the constitution | the Engineer's or QA's reports ("tests pass", "done") |
| the changelog item: verbatim request, ACs, Boundaries, Stage-4 matrix, QA's fixture-gap notes | `HANDOFF.md`, memory, prior verdicts |
| the suite output, filtered to verdict lines + failure names | anything the diff does not touch |
| Project Details rows for the touched seams + applicable non-functional categories | |

**Output schema** — one line per finding, no prose around it:
`<class> | <severity> | <file:line or clause-ID> | <claim> | <evidence: what was read>` —
class ∈ `spec` · `code` · `test` · `migration` · `intentional-legacy` · `out-of-range`; severity is
left **blank** (the Orchestrator sets it, §3). Then one verdict line: `accept` or `decline`.

**Lenses** — run **2a** and **2b** as two separate fresh contexts (Tier A) or two fresh sessions
(Tier B); 2c and 2d are questions 2a answers explicitly:

- **2a Conformance** (the DoD as a checklist): full suites green (re-run) · every changed behaviour
  traces to a clause-ID **and** every behaviour-affecting diff has a linked clause (reverse trace) ·
  constitution invariants + the feature's coverage matrix satisfied · each acceptance test declares an
  oracle source; fixture gaps classified, **no `blocking` gap** · non-functional floor: each applicable
  category met or `N/A — <reason>` · **structure**: every public member added, changed or removed in the
  diff is in the approved structure shard, and every diagram member is in the diff or pre-existed
  (`structure_check` proves the forward half; read the diff for the reverse — a public member the
  diagram lacks is a finding: class `spec` if the design needed it, `code` if it did not).
- **2b Hunt** (a second fresh context, the diff only): *list at least ten concrete findings; look for
  what is missing, not only what is wrong; no severity, no ranking.* Fewer than ten ⇒ re-check before
  stopping. Same-model, no persona framing — the floor and the "what is missing" question are what
  move the hit-rate, the cynical-reviewer voice does not.
- **2c Verification gap** — for each changed behaviour: name the smallest regression (invert the branch,
  drop the default, omit the field, return the old error) and the test that would fail; **read that
  test**. Snapshot-only, no-throw, mock-call and "it exists but is skipped or filtered" checks do not
  count. No such test ⇒ finding, class `test`.
- **2d Intent alignment** — against the **verbatim request** on the item: enumerate the plausible
  readings; which one does the diff implement; where does it diverge from the request in scope or
  meaning. Diff-vs-spec passes when Stages 1–3 misread the PM; this is the check that catches it. A
  divergence rooted in the spec ⇒ class `spec` with `[NEEDS-PO:intent-gap]`.

Write the verdict on the item: `validated: <frozen-sha>..<head-sha> accept` or `… decline <classes>`.

### 3. Classify and route — the Orchestrator, not Validation

1. **Judge each finding independently.** Deduplicate only two findings with the same claim **and** the
   same required action; never drop a finding because a related one was rejected.
2. **Assign severity by consequence for the user** — `high` (intolerable) · `medium` (tolerable) ·
   `low` (cosmetic/none). Reviewers' own severities, if any, are disregarded: they judged under designed
   information asymmetry.
3. **Score.** Any `high` ⇒ **decline**. Otherwise `3 × medium + low ≥ 5` ⇒ fix, then **one more fresh
   2a pass** before accept. Below that ⇒ accept with the fixes applied and re-verified (step 1 re-run).
4. **Route each finding by class** — the fix lands in the layer that caused it, never patched over:

| Class | Root cause | Route |
|---|---|---|
| `spec` | the clause was wrong, ambiguous or missing — or the approved structure shard lacks a member the design needed | write `KEEP: <what must survive>` and `AVOID: <the known-bad state>` on the item → **reset the branch to `<frozen-sha>`** (the tests are the floor; the code re-derives) → Stage 3 (PO patches the spec: negotiate → replace wholesale → commit solo; a structure change is the **PM's** decision) → Stage 5 (QA revises the affected tests; freeze again) → Stage 6 re-run with the KEEP/AVOID lines in the brief |
| `test` | a test misreads a correct spec, or verification is missing/weak | Stage 5 (QA fixes or adds; freeze again) → Stage 6 re-run for the affected tests |
| `code` | implementation diverges from a correct spec + correct test | Stage 6: the Engineer patches; the Orchestrator re-runs step 1 |
| `migration` | data / config / dependency shape changed without its migration or rollback | Stage 2 (viability of the migration) → Stage 3 if it needs a clause → Stage 6 |
| `intentional-legacy` | the spec is right but describes a future state the item was not meant to reach | Stage 3 correction (a lifecycle tag or an explicit deferral clause) → §2 re-validation only |
| `out-of-range` | pre-existing, not caused by this unit | `[DEFER] <summary> — evidence: <file:line>` on the item; **never fixed here** |

5. **Cap.** Each decline increments `validation-pass:` on the item. A **third decline** transitions the
   item to PO-attention with `[BLOCKED:non-convergence]` and the finding history; the PM decides.
6. **Lesson.** Every decline gets one line on the item: `lesson: <the upstream rule or stage that would
   have caught it> — source: <file:line|sha>`. The PO reads open lessons at intake (`box-roles.md`).

In a split deployment the worker box stops at `Ready-for-review`; the PO box runs §2–§3 and, on
decline, returns the item as `Rework:<class>` (`box-roles.md`).

### 4. Ship-time fold (mode-agnostic, the back-derivability invariant)

The changelog is the append-only log; the spec is the materialized current state. `spec = fold(all
shipped units)` is enforced **here, at ship time** — not queried later. **Mode-agnostic** (identical in
changelog Mode A and Mode B):
1. Fold the transient working spec's resolved decisions into the canonical spec fragment(s) — **preserving
   the draft's form**: list/table/code clauses stay list/table/code, never re-narrated into paragraphs;
   decisions only, no rationale or history (`stages/3_spec.md` §"Spec form"); replaced text goes wholesale.
2. Pin provenance on each folded clause: `(§X per <unit-id>, YYYY-MM-DD)` — `<unit-id>` is a Jira key
   (Mode A) or backlog id (Mode B); identical syntax in both.
2b. **Fold the structure shard.** The transient delta (`<ITEM-ID>.structure.body.md`) folds into the
   area's canonical structure shard (`<section>.structure.body.md`, current state): `Added` classes
   appended, a `Changed` class's members replaced wholesale, `Removed` ones retired with a lifecycle tag
   (`lifecycle-states.md`); pin each touched class with a `%% (§X per <unit-id>, YYYY-MM-DD)` comment
   line inside the block. The next unit's Stage 1 reads this shard first.
2c. **Plan readout.** `token_ledger report` (`gates/token_ledger.*`) → write the `tokens: plan …` line on
   the item beside the per-slice lines. Cost, read beside `metrics.md`, never instead of it.
3. **Archive, don't delete** the transient working spec **and the build plan** (`git mv` to
   `spec/archive/`).
4. Record the ship-SHA back onto the changelog item per `project-details.md#CL-N` (transition Done + SHA
   comment in Mode A; appended `SHIPPED <sha> <date>` line in Mode B).
5. Recompile `spec/index.html` via the `project-details.md#SPEC-3` build command so the whole-corpus
   view never goes stale.

**Release states — fold reflects trunk HEAD, not rollout.** An item carries a release state:

| State | Means |
|---|---|
| **Merged** | on the published branch |
| **Released** | built/deployed artifact exists |
| **Enabled** | live to users (flag on / rollout complete) |
| **RolledBack** | disabled after release |

The fold writes the **intended behaviour at trunk HEAD** into the canonical spec. Flags and
staged-rollout state live in **Project Details**, **not** the canonical spec. A **revert** is not an
erasure — it is a **changelog entry that folds a spec delta** (the new intended behaviour). *"Committing
is shipping"* holds **only because every commit on the published branch is deployable** — the state
machine above tracks *where it actually is*, the spec tracks *what trunk says it should do*.

### 5. Authoritative gate bank — `run_all` (full bank, must be green)

Run the gate runner for your OS: `pwsh gates/run_all.ps1 <frozen-sha>` (Windows) / `sh
gates/run_all.sh <frozen-sha>` (Linux/macOS) — the FULL bank. Re-runs the mechanical gates **plus**
`fold_check` over the folded + pinned + recompiled corpus — confirming every clause changed this ship
carries a provenance pin whose `<unit-id>` resolves — plus a suite re-run and `link_check` over the
recompiled index. This is the **binding** gate; it must be green.

In CI, run with **`--strict`** / `-Strict`: `fold_check` then FAILS on a resolver error instead of
degrading, and `prose_check` FAILS instead of warning. (Offline-degrade-to-file-exists is for local runs
only.) A CI template for target repos ships as `ci/target-ci.template.yml` in the framework repo.

### 6. Merge

**Split deployment:** a worker box does **not** merge — it stops at `Ready-for-review` (gates green, branch
pushed) and the **PO box** runs §2–§3 + the merge (`box-roles.md` §"Box loops"). Solo box: continue.

| Rule | Policy |
|---|---|
| Worker commits | on the item branch, small, `<type>(<ITEM-ID>): …`; never squashed by the worker, never pushed to the published branch |
| Merge order | `Ready-for-review` items in the order they were flagged; one at a time |
| Merge form | Orchestrator merges `--no-ff` to the one published branch, then deletes the local branch (trunk-based; per project details) |
| Conflict | rebase onto the published branch **fails** ⇒ `[BLOCKED:merge-conflict]` back to the worker; the PO never resolves a conflict inside a unit it did not build |
| After merge | ship-SHA + release state on the item; traceability closed: clause-ID → scenario → test-ID → code → ship-SHA |

## Exit criteria

- [ ] Pre-fold `run_all --pre-fold <frozen-sha>` green (re-run by Orchestrator, not reported).
- [ ] Validation `accept` written as `validated: <base>..<head> accept` on the item — all four lenses,
      findings routed by class, out-of-range findings deferred, no `blocking` fixture gap, non-functional
      floor met or `N/A — reason`.
- [ ] Transient spec + structure delta folded + pinned; working spec and build plan archived;
      `spec/index.html` recompiled.
- [ ] `structure_check` green — frozen half pre-fold, forward trace post-fold; Validation found no
      unapproved public member. `tokens: plan` line on the item.
- [ ] Authoritative `run_all` (full bank incl. `fold_check --strict` in CI) green over the folded corpus.
- [ ] Merged to published branch; ship-SHA recorded + release state set on the changelog item.

---
### Gate(s) that close this stage
- pre-fold `run_all --pre-fold` green → Validation accepts (or declines and routes per §3) →
  fold+pin+recompile → authoritative `run_all` (incl. `fold_check`) green → merge.
### Next
**Work item is DONE.** Return to `PROCESS.md` §0 for the next unit. On a decline, read the stage the
class routes to (§3) and follow it.
