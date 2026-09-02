# Stage 7 — Gates + Ship & Fold

**Role:** Orchestrator runs gates + owns the merge; Validation sub-agent (fresh context) reviews.
**Loaded with:** constitution + this file + `project-details.md#CL-N` (changelog binding) +
`project-details.md#SPEC-N` (build command). Validation is spawned **fresh** with the spec shards + the
diff only — it did not build the thing.

Closing stage in **every** route. Green is necessary, not sufficient. Mechanical gates run first
(cheap, deterministic); fresh human Validation runs last (judgement against spec).

This stage is the consolidated exit bar: the **Definition of Done** (`definition-of-done.md`) is the
literal checklist Validation enforces. The changelog item transitions **Done** (step 4 below,
`project-details.md#CL-4`) **only when the DoD fully holds** — every item unchecked keeps the unit open.

## Order of operations

### 1. Pre-fold mechanical gates — `run_all --pre-fold` (must be green)

Run the gate runner for your OS: `gates/run_all.ps1 <base> -PreFold` / `gates/run_all.sh <base>
--pre-fold` (persona route) or `gates/run_all.ps1 <base> -PreFold -Mechanical` / `gates/run_all.sh
<base> --pre-fold --mechanical` (mechanical route). See `gates/README.md`. This runs `link_check` +
`coverage_check` + (`test_edit_ban`, persona only) + `suite_green`, but **SKIPS** `fold_check` — the
provenance pins do not exist yet (created in step 3). `<base>` is the QA-frozen commit (persona) or the
pre-work base (mechanical); it must resolve.

| Gate | Proves | Type |
|---|---|---|
| `coverage_check` | every clause-ID → ≥1 test-ID (both directions) | generic script |
| `test_edit_ban` | Engineer touched no test files (persona route only) | generic script |
| `link_check` | every spec cross-ref resolves to a real anchor/shard | generic script |
| `constitution_lint` | project principle checks hold | template + config |
| `seam_conformance` | architecture seams (`#SEAM-N`) not bypassed | template + config |
| `suite_green` | the project suite exits 0, **re-run by the Orchestrator** | runner (project details) |

Trust artifacts, not narratives: the Orchestrator re-runs the suite; an agent's "tests pass" is not
accepted. (Project-specific gates run only if their concrete script + rules exist.)

### 2. Fresh Validation (sub-agent, fresh context)

A literal checklist (reads **diffs + clauses + test output**, never a summary):
- Full suites green (re-run).
- Diff reviewed **against the spec** — every changed behaviour traces to a clause-ID, **and** every
  behaviour-affecting diff has a linked clause (reverse trace; an unlinked changed path is a defect).
- Constitution invariants + the feature's coverage matrix satisfied.
- Each acceptance test declares an oracle source; fixture/shape gaps written down **and classified**
  where stand-ins are used — **no `blocking` gap ships**.
- **Non-functional floor:** for every category that applies (set in Project Details), it is **met or
  `N/A — <reason>`** — security · privacy · accessibility · performance · observability · compatibility
  · migration · rollback · compliance. Behaviour-correct but (say) a11y-violating work is **declined**.
- Output: **accept** or **decline-with-findings** (findings are filed, not fixed here).

### 3. Ship-time fold (mode-agnostic, the back-derivability invariant)

The changelog is the append-only log; the spec is the materialized current state. `spec = fold(all
shipped units)` is enforced **here, at ship time** — not queried later. **Mode-agnostic** (identical in
changelog Mode A and Mode B):
1. Fold the transient working spec's resolved decisions into the canonical spec fragment(s) — **preserving
   the draft's form**: list/table/code clauses stay list/table/code, never re-narrated into paragraphs;
   decisions only, no rationale or history (`stages/3_spec.md` §"Spec form"); replaced text goes wholesale.
2. Pin provenance on each folded clause: `(§X per <unit-id>, YYYY-MM-DD)` — `<unit-id>` is a Jira key
   (Mode A) or backlog id (Mode B); identical syntax in both.
3. **Archive, don't delete** the transient working spec (`git mv` to `spec/archive/`).
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

### 4. Authoritative gate bank — `run_all` (full bank, must be green)

Run the gate runner for your OS: `gates/run_all.ps1 <base>` (Windows) / `gates/run_all.sh <base>`
(Linux/macOS) (FULL bank). See `gates/README.md`. Re-runs the mechanical gates **plus** `fold_check`
over the folded + pinned + recompiled corpus — confirming every clause changed this ship carries a
provenance pin whose `<unit-id>` resolves — plus a suite re-run and `link_check` over the recompiled
index. This is the **binding** gate; it must be green.

In CI, `fold_check` runs **`--strict`** (`gates/fold_check.ps1 -Strict` (Windows) / `gates/fold_check.sh
--strict` (Linux/macOS), `gates/README.md`): a configured resolver that errors **FAILs**, it does not
degrade. (Offline-degrade-to-file-exists is for local runs only.)

### 5. Merge

**Split deployment:** a worker box does **not** merge — it stops at `Ready-for-review` (gates green, branch
pushed) and the **PO box** runs the fresh Validation + the merge (`box-roles.md` §"Box loops"). Solo box: continue.

Orchestrator owns the single serialized merge to the one published branch (trunk-based; `--no-ff` then
delete the local branch, per project details). Traceability is now closed: clause-ID → scenario →
test-ID → code → ship-SHA.

## Exit criteria

- [ ] Pre-fold `run_all --pre-fold` green (re-run by Orchestrator, not reported).
- [ ] Validation accepts (fresh context, vs spec + constitution) — incl. the non-functional floor
      (applicable categories met or `N/A — reason`) and no `blocking` fixture gap.
- [ ] Transient spec folded + pinned + archived; `spec/index.html` recompiled.
- [ ] Authoritative `run_all` (full bank incl. `fold_check --strict` in CI) green over the folded corpus.
- [ ] Merged to published branch; ship-SHA recorded + release state set on the changelog item.

---
### Gate(s) that close this stage
- pre-fold `run_all --pre-fold` green → Validation accepts → fold+pin+recompile → authoritative
  `run_all` (incl. `fold_check`) green → merge.
### Return
**Work item is DONE.** Return to PROCESS.md §0 for the next unit. Drop this stage body from context.
