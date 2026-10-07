# Changelog / Ticket Writing Conventions

The content standard for one work item's **changelog entry**.
- **Identical in Mode A (external tracker) and Mode B (on-disk backlog)**; storage/mechanics (store, id
  format, states, transitions) bind in `project-details.md#CL-`. This file = **what goes in the entry**.
- Demand-loaded at Stage 0 (file/find an item; `intake.md` produces it from a raw request) and Stage 3
  (ACs seed the spec).
- `<ITEM-ID>` = the project's id (`project-details.md#CL-2`: e.g. `POL-142` Mode A, `BL-20260624-03`
  Mode B).

---

## 1. Taxonomy — pick exactly one type

| Type | Is | Starts from | Output |
|------|----|-------------|--------|
| **Story** | a user-facing behavioural increment | ACs (EARS) | shipped behaviour + folded spec clauses |
| **Bug** | a failing behaviour vs the spec | **a failing test that reproduces it** | the test goes green; spec clause clarified if it was ambiguous |
| **Task** | mechanical / infra work, **no behaviour change** | a definition-of-done bar | the change; usually no new spec clause |
| **Spike** | a timeboxed investigation | a question + a timebox | a **recorded DECISION** (not shippable code) seeding a follow-up Story/Task |

- A Spike delivers the decision written back to the item, never merged code.
- A Bug with no failing test is not Ready — write the repro first.

**Bug intake shape** (before the failing test exists):
- `expected:` the clause-ID and its text — or `no clause → brownfield slice first`
  (`greenfield-vs-brownfield.md`)
- `actual:` what happened · `repro:` input / state / steps · `env:` version, platform, data.
- The PO box writes the failing test from *expected*, never from *actual*.

---

## 2. Title — imperative + scoped

- `<verb> <scoped object>` — e.g. *"Throttle sync retries on 429"*, not *"sync stuff"*.
- Commits reference the id: **`feat(<ITEM-ID>): …`** / `fix(<ITEM-ID>): …` / `chore(<ITEM-ID>): …`.
- The id is the join key for the whole trace (clause-ID → test → ship-SHA): title slug, every commit,
  the provenance pin (§4).

---

## 3. Body — the parts, in order

| Part | Holds |
|------|-------|
| **Verbatim request** | the PM's own words, quoted, unedited — the intent-alignment reference for Stage 7 review |
| **Why** | the force (what is broken or missing), **who** it is for, **why now**; one paragraph, no solutioning |
| **The change** | what will be true after (the *what*, not the *how*) |
| **Success signal** | one measurable line a test or demo can be judged against ("p95 export under 2 s at 10k rows", never "faster"); becomes an AC |
| **Boundaries** | **Always** (invariants the work must keep) · **Ask first** (decisions that HALT the worker and go to the PO: pre-authorised `[NEEDS-PO]` triggers) · **Never** (non-goals + forbidden approaches; kills scope creep) |
| **Open questions / Assumptions** | numbered questions a PM can answer in one line; assumptions the PM must ratify. **Empty questions + ratified assumptions at Ready**; answers written beside the question, never in chat (`intake.md` §3) |
| **Dependencies & links** | other `<ITEM-ID>`s (blocks / blocked-by, `split-from:`), target spec **clause-IDs**, the Project Details seams touched |
| **Right-size route** | `mechanical` / `persona` / `parallel` (from the Stage 0 2×2) + points; brownfield stance |

- The **spec clause-ID** links are load-bearing: they tell the worker which shard(s) the work touches
  (`project-details.md#SPEC-`) and where the ACs fold on Done (§4).
- Design-bearing work with no clause yet: write *"spec authored in Stage 3"* — the PO box authors it,
  never a worker box (it surfaces back, §6).

---

## 4. Acceptance Criteria — EARS clauses with stable ids

Every AC is an **EARS clause** (full grammar: `spec-format/README.md#5`) with a stable id
**`<ITEM-ID>/AC-n`**:

| Form | Template |
|------|----------|
| Ubiquitous | `The system shall …` |
| Event | `When <trigger> the system shall …` |
| State | `While <state> the system shall …` |
| Unwanted | `If <cond> then the system shall …` |
| Optional | `Where <feature> the system shall …` |

- ACs are **implementation-grade**: every constant/threshold named and traceable; no *"should work"*
  / *"handle gracefully"*.
- One AC = one behaviour = one trace row; an "and also" means split it.

```
POL-142/AC-1 — When a sync POST returns 429 the system shall retry after the
               Retry-After header value, capped at 60s.
POL-142/AC-2 — If three consecutive retries return 429 then the system shall
               surface a "sync paused" notice and stop retrying.
```

- **Before Ready** an item may carry **capabilities** instead — `<ITEM-ID>/CAP-n — intent: … /
  success: …` — the *what* before the design fixes the constants (Stage 1). Stage 1/3 converts each
  CAP into one or more ACs; CAP ids are never reused.
- An item is **Ready only with ACs**.

### The JOIN — AC → spec clause (Stage 7 fold)

- The AC is the **transient** form of a behaviour; the canonical **spec clause** is its **durable** form.
- On Done, each AC folds into the canonical spec as a current-state clause, **pinned**
  `(§X per <ITEM-ID>, YYYY-MM-DD)` (`project-details.md#CL-5`, `spec-format/README.md#4`). The clause
  is then authoritative; the AC is archived with the item.
- The pin, the commit and the item share one id, so the spec stays back-derivable from the changelog.

---

## 5. Points & the Ready bar

- **Points:** Fibonacci default (1, 2, 3, 5, 8…); configurable per project.
- **Parallel-dispatch bar:** only when `≤ N` points, single surface, no TBDs, no config-shape changes.
  `N` and tweaks live in `project-details.md#RS-` (right-sizing overrides), not here.
- **Ready bar:** a **worker box** picks up an entry only when it meets **every item of the Definition
  of Ready** — `definition-of-done.md` (DoR) is the single source, closed by the PO's **readiness
  verdict** (PASS / CONCERNS / FAIL). An item failing any DoR item is surfaced back (§6), not started.

---

## 6. Item lines — surfacing, deferring, verdicts

- A worker box, QA, the Engineer, or Validation writes these lines on the item; they are the async
  channel and the metric source (`metrics.md`).
- Reasons are a **fixed enum** so a PO loop or a script can triage without reading prose.

| Line | Use when | Transition |
|------|----------|------------|
| `[NEEDS-PO:<reason>] <question>` — reason ∈ `fork` · `threshold` · `ac-unreachable` · `spec-gap` · `intent-gap` · `structure` | a spec or design **decision** the worker may not make. `structure` = a deviation from the PM-approved structure shard (a public member the diagram lacks, a changed signature): **PM-only**, never PO-arbitrated; approved ⇒ the PO replaces the shard wholesale and re-freezes | → PO-attention; stop on the member (other members may continue) |
| `[BLOCKED:<reason>] <detail>` — reason ∈ `dor-fail` · `base-unresolved` · `suite-red-at-pickup` · `prereq-missing` · `fixture-blocking` · `non-convergence` · `merge-conflict` | the item cannot proceed until something lands | → PO-attention; stop on the item |
| `[DEFER] <summary> — evidence: <file:line>` | a finding **outside this unit's clause range** (pre-existing, incidental). Never fixed in this unit — that would break reverse trace | no transition; the PO loop converts each to a Bug/Task at intake |
| `frozen: <sha>` | Stage 5 exit: the QA-frozen commit `test_edit_ban` and `structure_check --frozen` diff against (mirrored in `gates/.frozen`) | — |
| `structure: N/A — <reason>` | a unit that adds no class and no public member, so no structure shard (Stage 1 / Stage 3) | — |
| `tokens: <slice\|plan> admitted ~A; saved ~V (P%); ledger H/N honoured` | every slice end (`token_ledger report --slice`) and the plan end at Stage 7 (`report`); an estimate from bytes admitted, never a billed count (`stages/4b_buildplan.md`) | — |
| `validated: <base>..<head> accept\|decline [class]` | every Stage 7 Validation pass, with the SHA range it read | decline → Rework:<class> (`box-roles.md`) |
| `lesson: <rule or stage that would have caught it> — source: <file:line\|sha>` | one per decline, written by the Orchestrator; the PO reads open lessons at intake | — |
| `split-from: <ITEM-ID>` · `kept-whole: PM <date>` | intake scope decisions (`intake.md` §2) | — |

- This is the **distributed form** of *"ambiguity is a spec bug, routed through the Orchestrator, never
  resolved in conversation"*: the changelog item **is** the async PO ↔ worker channel.
- **Obvious-only exception:** a worker MAY record an obvious-from-convention detail inline (the
  auditable "PO working decision") and note it on the item; anything non-obvious goes to `[NEEDS-PO]`.
- A worker that surfaces moves the item to **PO-attention** (`project-details.md#CL-7`) and **stops**
  on it (it may pick another DoR-met item). Full protocol: `box-roles.md`.

---

## Release state + production feedback

- An item carries a **release state** — **Merged** / **Released** / **Enabled** / **RolledBack**.
- The canonical spec records intended behaviour at trunk HEAD; release state (and any flag / staged
  rollout) is **deployment state**, tracked per `project-details.md#CL-` — **not** in the spec.
- A revert is a changelog entry that folds a spec delta (Stage 7), not a silent erasure.

**Production lessons re-enter the spec.** A behaviour gap found **in production** (incident,
telemetry, support) is not closed in ops: file a **Bug** (starts from a failing test, §1) that **folds
into the canonical spec**, or a **spec correction** (Stage-3 update method: replace wholesale, own
commit) where the spec was right but incomplete.

## Retiring or superseding an item

Use the lifecycle states (`DEPRECATED`/`SUPERSEDED`/`MOVED`/`REMOVED`) with date + reason/pointer —
never a silent delete. See `lifecycle-states.md`.

---

## Cross-links

- **`intake.md`** — a raw request becomes this entry.
- **Stage 0** (`stages/0_triage.md`) — file/find the item; right-size route.
- **Stage 3** (`stages/3_spec.md`) — ACs seed the canonical spec; the structure shard is approved with it.
- **Stage 4b** (`stages/4b_buildplan.md`) — the build-plan ledger the `tokens:` lines summarize.
- **Stage 7** (`stages/7_ship.md`) — the `validated:` / `[DEFER]` / `lesson:` lines.
- **`definition-of-done.md`** — the DoR (Ready bar + readiness verdict) and DoD.
- **`box-roles.md`** — PO vs worker authority; the surface-back protocol; item state machine.
- **`metrics.md`** — what these lines are counted into.
- **`project-details.md#CL-`** — storage, id format, work-ready & PO-attention states, transitions.
