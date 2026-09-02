# Changelog / Ticket Writing Conventions

How to write a **well-formed changelog entry** — the content standard for one work item.
**Identical in Mode A (external tracker) and Mode B (on-disk backlog)**; only *storage/mechanics*
differ, bound in `project-details.md#CL-` (store, id format, states, transitions). This file =
**what-goes-in-the-entry**; project details = **where-it-lives**. Demand-loaded — read at Stage 0
(file/find an item) and Stage 3 (ACs seed the spec). `<ITEM-ID>` = the project's id
(`project-details.md#CL-2`: e.g. `POL-142` Mode A, `BL-20260624-03` Mode B).

---

## 1. Taxonomy — pick exactly one type

| Type | Is | Starts from | Output |
|------|----|-------------|--------|
| **Story** | a user-facing behavioural increment | ACs (EARS) | shipped behaviour + folded spec clauses |
| **Bug** | a failing behaviour vs the spec | **a failing test that reproduces it** | the test goes green; spec clause clarified if it was ambiguous |
| **Task** | mechanical / infra work, **no behaviour change** | a definition-of-done bar | the change; usually no new spec clause |
| **Spike** | a timeboxed investigation | a question + a timebox | a **recorded DECISION** (not shippable code) seeding a follow-up Story/Task |

> A Spike's deliverable is the decision written back to the item, never merged code. A Bug with no
> failing test is not Ready — write the repro first.

---

## 2. Title — imperative + scoped

`<verb> <scoped object>` — e.g. *"Throttle sync retries on 429"*, not *"sync stuff"*. Commit
references the id: **`feat(<ITEM-ID>): …`** / `fix(<ITEM-ID>): …` / `chore(<ITEM-ID>): …`. The id
is the join key for the whole trace (clause-ID → test → ship-SHA); it appears in the title slug,
every commit, and the provenance pin (§4).

---

## 3. Body — five parts, in order

| Part | Holds |
|------|-------|
| **Context / why** | the problem or motivation; one paragraph, no solutioning |
| **The change** | what will be true after, at a high level |
| **Non-goals** | what this item explicitly does **not** do (kills scope creep) |
| **Dependencies & links** | other `<ITEM-ID>`s (blocks/blocked-by) **and** target spec **clause-IDs** |
| **Right-size route** | `mechanical` / `persona` / `parallel` (from the Stage 0 2×2) + points |

The **spec clause-ID** links are load-bearing: they tell the worker which shard(s) the work touches
(`project-details.md#SPEC-`) and are where the ACs fold on Done (§4). For design-bearing work with
no clause yet, write *"spec authored in Stage 3"* — the PO box authors it; a worker box never does
(it surfaces back, §6).

---

## 4. Acceptance Criteria — EARS clauses with stable ids

Every AC is an **EARS clause** (the five forms below; full grammar in `spec-format/README.md#5`),
carrying a stable id **`<ITEM-ID>/AC-n`**:

| Form | Template |
|------|----------|
| Ubiquitous | `The system shall …` |
| Event | `When <trigger> the system shall …` |
| State | `While <state> the system shall …` |
| Unwanted | `If <cond> then the system shall …` |
| Optional | `Where <feature> the system shall …` |

ACs are **implementation-grade**: every constant/threshold named and traceable; no *"should work"*
/ *"handle gracefully"* prose. One AC = one behaviour = one row in the trace; if it needs an "and
also", split it.

```
POL-142/AC-1 — When a sync POST returns 429 the system shall retry after the
               Retry-After header value, capped at 60s.
POL-142/AC-2 — If three consecutive retries return 429 then the system shall
               surface a "sync paused" notice and stop retrying.
```

### The JOIN — AC → spec clause (Stage 7 fold)

The AC is the **transient, point-in-time** form of a behaviour; the canonical **spec clause** is
its **durable** form. On Done, each AC folds into the canonical spec as a current-state clause,
**pinned** `(§X per <ITEM-ID>, YYYY-MM-DD)` (the standard provenance pin —
`project-details.md#CL-5`, `spec-format/README.md#4`). After fold the spec clause is authoritative;
the AC is archived with the item. Same id as the fold-on-ship pin and the commit, so the spec stays
back-derivable from the changelog.

---

## 5. Points & the Ready bar

- **Points:** Fibonacci default (1, 2, 3, 5, 8…); configurable per project.
- **Parallel-dispatch bar:** parallel-dispatchable only when `≤ N` points, single surface, no
  TBDs, no config-shape changes. Threshold `N` and tweaks recorded in `project-details.md#RS-`
  (right-sizing overrides) — not hard-coded here.
- **Ready bar:** an entry must meet **all seven items of the Definition of Ready** before a
  **worker box** picks it up — `definition-of-done.md` (DoR) is the single source: title + type,
  EARS ACs with stable ids, **no open forks / TBDs**, target spec shard(s) identified,
  **prerequisites / viability noted**, points assigned, route recorded. An item failing any DoR
  item is surfaced back (§6), not started.

---

## 6. Worker surfacing templates

When a **worker box** hits anything above *"obvious from existing convention"* — an ambiguity, a
spec bug, a missing prerequisite, an AC unreachable through a production API, or any fork — it does
**not** guess and does **not** patch the canonical spec. It comments on the item using one of these
templates, transitions the item to the **PO-attention** state (`project-details.md#CL-`), then
**stops** on that item (it may pick another DoR-met item). The PO box resolves and re-readies. Full
protocol in `box-roles.md`.

| Template | Use when |
|----------|----------|
| `[NEEDS-PO] <question / ambiguity>` | a spec or design **decision** the worker may not make (a fork, an unspecified threshold, an inadequate AC) |
| `[BLOCKED] <reason / missing prerequisite>` | a prerequisite is missing or the item cannot proceed (broken dep, unavailable seam, failing baseline) |

> The **distributed form** of *"ambiguity is a spec bug, routed through the Orchestrator, never
> resolved in conversation."* The changelog item **is** the async PO ↔ worker channel. The
> **obvious-only exception**: a worker MAY record an obvious-from-convention detail inline (the
> auditable "PO working decision" pattern) and note it on the item; anything non-obvious goes to
> `[NEEDS-PO]`. That line is the framework's existing right-sizing line, nothing wider.

---

## Release state + production feedback

An item carries a **release state** — **Merged** / **Released** / **Enabled** / **RolledBack**.
The canonical spec records intended behaviour at trunk HEAD; the release state (and any flag /
staged-rollout) is **deployment state**, tracked per `project-details.md#CL-` — **not** in the
spec. A revert is a changelog entry that folds a spec delta (Stage 7), not a silent erasure.

**Production lessons re-enter the spec.** A behaviour gap discovered **in production** (incident,
telemetry, support) is not closed in ops — it is filed as a **Bug** (starts from a failing test,
§1) that **folds into the canonical spec**, or as a **spec correction** (Stage-3 update method: replace
wholesale, own commit) where the spec was right but incomplete. The spec stays the single source of intended behaviour; storage bound in
`project-details.md#CL-`.

## Retiring or superseding an item

Use the lifecycle states (`DEPRECATED`/`SUPERSEDED`/`MOVED`/`REMOVED`) with date + reason/pointer —
never a silent delete. See `lifecycle-states.md`.

---

## Cross-links

- **Stage 0** (`stages/0_triage.md`) — file/find the item; right-size route.
- **Stage 3** (`stages/3_spec.md`) — ACs are the **seed clauses** for the canonical spec.
- **`definition-of-done.md`** — the DoR (Ready bar) and DoD this entry is measured against.
- **`box-roles.md`** — PO vs worker authority; the surface-back protocol.
- **`project-details.md#CL-`** — storage, id format, work-ready & PO-attention states, transitions.
