# Box Roles — the deployment-authority layer

> Demand-loaded spine: load to learn what a box may author vs. surface, or when picking up an item
> another box filed. Cross-links: `PROCESS.md` §0, `stages/0_triage.md`, `project-config/INIT.md`,
> `definition-of-done.md` (DoR/DoD), `changelog-conventions.md` (entry + item lines).

- A **box** = a machine/agent session with **standing** authority; a **persona** (PM / PO / QA /
  Engineer / Validation / Orchestrator) = a **per-feature hat** worn inside the loop. They are
  **orthogonal**: the box role says *which personas it may wear*; the persona says *which job it does now*.
- In a distributed setup PO and worker are **different boxes**, and the **changelog item is the async
  channel between them** — the distributed form of "ambiguity = spec bug, Orchestrator-mediated, never
  resolved in conversation."

## The two box roles

| | **PO box** | **Worker box** |
|---|---|---|
| Authority | Full | Execution only |
| Personas it may wear | All (PM-facing, PO, Orchestrator, QA, Engineer, Validation) | Implementation-side only (QA, Engineer, Validation) |
| Stages it may run | `0–7`, including intake and authoring | The route's **execution** stages on a Ready item |
| Files & shapes changelog items | **Yes** (`intake.md`, `changelog-conventions.md`) | No — never edits scope/ACs |
| Decides forks | **Yes** | **No** — surfaces them |
| Authors / patches the canonical spec | **Yes** | **No** (obvious-only exception below) |
| Owns the serialized merge / orchestration | **Yes** | No |

- **PO box — full authority:** intake, Stage 0–3 (triage, design-with-PM, recon, spec authoring).
  **A solo dev is a PO box** and may run the whole loop — the role layer is invisible until you split boxes.
- **Worker box — execution only.** Picks up a DoR-met item the PO marked **Ready** (the work-ready
  state, `project-details.md#CL-6`) and runs the implementation stages to **Ready-for-review**
  (`definition-of-done.md`). It **MUST NOT** decide a fork, author or patch the canonical spec beyond an
  obvious-from-existing-convention detail, or change an item's scope or ACs.

## The surface-back protocol (the core)

When a worker box hits **any decision above "obvious from existing convention"** — an ambiguity, a
spec bug, a missing prerequisite, an AC unreachable through a production API, a fork:

1. **Do NOT guess. Do NOT patch the canonical spec.**
2. **Write the concern to the changelog item** with a **reason from the enum**
   (`changelog-conventions.md` §6):
   - `[NEEDS-PO:<fork|threshold|ac-unreachable|spec-gap|intent-gap|structure>] <question>` — a decision
     the worker may not make (`structure`: a deviation from the PM-approved structure shard).
   - `[BLOCKED:<dor-fail|base-unresolved|suite-red-at-pickup|prereq-missing|fixture-blocking|non-convergence|merge-conflict>] <detail>`
     — work cannot proceed until something lands.
3. **Transition the item to the PO-attention state** (`project-details.md#CL-7`; e.g. a Jira
   "Blocked"/flag in Mode A, a status line in Mode B) and **STOP work on it.** The worker may pick
   up another DoR-met item meanwhile.
4. **The PO box resolves** — patches the spec / decides the fork / updates the AC — and returns the
   item to the work-ready state; only then does execution resume. **Exception — `structure`:** the PM
   approved the diagram, so the PM decides the deviation, never the PO; the PO then replaces the
   structure shard wholesale (own commit) and re-freezes.

This is the QA→Orchestrator escalation (`stages/5_qa.md`, `stages/6_engineer.md`) at box level: the
fix lands **in the artifact**, before code, every time.

## The obvious-only exception

The line between "record inline" and "surface" is the framework's **existing right-sizing line** — the
one the PO uses for an auditable working decision.

- **Obvious from existing convention** → a worker MAY record it inline (the auditable "PO working
  decision") **and** note it on the item, so the trail stays in the changelog.
- **Anything non-obvious** → `[NEEDS-PO:…]`. When in doubt, it is non-obvious.
- **Non-obvious by definition:** authoring a spec clause, choosing between two viable designs, setting
  a constant the spec does not already imply, or adding a public member the approved structure shard
  lacks. A worker never widens this exception to dodge a surface-back.
- An item's **Ask-first** boundary (`changelog-conventions.md` §3) pre-declares decisions that halt
  the worker; hitting one is a `[NEEDS-PO:fork]`, not a judgement call.

## Assignment — local, per-box, uncommitted

Each box declares its own role; it is **never committed** (a property of the deployment, not the repo).

- Env var: `SDD_BOX_ROLE=po|worker` plus `SDD_BOX_ID=<short personal id>` (e.g. the hostname), **or**
- A git-ignored `project-config/box-role.local` file holding both.
- **Default = `po`.** An unset / solo box does everything. A worker box **must** set `SDD_BOX_ID` — it
  stamps claims (Box loops below).

The agent carrier's stub (`AGENTS.md`; `CLAUDE.md` routes to it — `host-adapter.md`) surfaces the
active role in every context (wired in `project-config/INIT.md`). If it still shows the literal
`$SDD_BOX_ROLE`, INIT §1a was not completed: read the env var or `box-role.local`.

## Item state machine (split deployment)

```
Ready ──claim──▶ Claimed:<box-id> ──▶ In-Progress ──▶ Ready-for-review ──accept──▶ Done
   ▲                    │                  │                  │
   │                    └──── surface-back ┴──▶ PO-attention  │ decline
   └────────── re-ready ◀───────────────────────┘             ▼
                                              Rework:<spec|test|code|migration>
                                                     (PO routes per stages/7_ship.md §3;
                                                      the worker resumes at that stage)
```

- State names are literal strings on the item (`project-details.md#CL-6/7` bind where they live).
- **Terminal states a worker may leave an item in:** `Ready-for-review` · `PO-attention` (with the
  reason line) · `Died:<gate>` (the gate-fix loop hit its cap). Nothing else; an item abandoned
  without one of these is a process defect.

## Box loops & coordination

Boxes coordinate **only through the changelog item**, each polling on its own schedule (defaults
below; tune in Project Details).

**Claim (worker, before starting).**
- Claim first: comment (Mode A) / status tag (Mode B) `claimed-by:<SDD_BOX_ID> <timestamp>
  lease:<minutes>` (default lease = 2 × the worker cadence).
- **Only claim an unclaimed Ready item** — or one whose lease has **expired**; then add
  `reclaimed-from:<box-id>` so the trail shows both.
- A live worker **renews** its lease each cycle. First valid claim wins; a rare double-claim inside one
  lease is a PO-resolved conflict.

**Worker loop (~15–30 min):**
1. Poll for the oldest **unclaimed (or lease-expired) Ready** item. None ⇒ **do nothing** until the next cycle.
2. Claim it; verify DoR. DoR fails ⇒ `[BLOCKED:dor-fail]` → PO-attention and loop.
3. Run the route's implementation stages to **all gates green** (`run_all <frozen-sha>`). **Do not merge.**
   A gate-fix loop gets **three** attempts; the fourth failure writes `Died:<gate>` with the gate output
   and `[BLOCKED:non-convergence]`, then loops.
4. Push the branch, flag the item **`Ready-for-review`**, stop renewing, loop.
5. Any non-obvious decision en route ⇒ surface back (`[NEEDS-PO:…]` / `[BLOCKED:…]` → `PO-attention`), drop the item, loop.
6. A `Rework:<class>` item carrying this box's claim resumes at the stage `stages/7_ship.md` §3 names,
   with the item's `KEEP:` / `AVOID:` lines in the brief.

**PO loop (~30 min):**
1. **`PO-attention`** items: resolve by reason — arbitrate if obvious, else escalate to the PM (`structure` always goes to the PM) — write the decision into the spec/item, **re-ready** it.
2. **`Ready-for-review`** items: run the **fresh Validation** (`stages/7_ship.md` §2, genuinely cross-box-fresh), classify + score (§3), then either the **serialized merge** (→ `Done` + ship-SHA) or `Rework:<class>` with the routing, `KEEP:`/`AVOID:` and `lesson:` lines written.
3. Intake: open `lesson:` and `[DEFER]` lines from finished items become Bugs/Tasks or process changes; new requests go through `intake.md` → triage → design → spec/test-plan → **Ready**.

**Cross-box merge serialization.** Workers never merge to the published branch — they stop at
`Ready-for-review`. The **PO box owns the serialized merge** and runs the final Validation +
merge-train (`stages/7_ship.md` §6): that single owner is the cross-machine serialization point. In a
**solo deployment** the same box runs Validation + merge inline at Stage 7.

## At a glance

- Know your box role **before** you touch a Ready item.
- Worker box: verify DoR on pickup; if it fails, surface back — do not start. Never author spec or
  decide forks.
- Every line you leave on an item carries its enum reason; every item you leave is in a terminal state.
