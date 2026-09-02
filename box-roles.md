# Box Roles — the deployment-authority layer

> **v1.1 — 2026-06-24.** Demand-loaded spine. Load when a box needs to know what it may
> author vs. surface, or when picking up a changelog item filed by another box.
> Cross-links: `PROCESS.md` §0 (the role branch), `stages/0_triage.md`, `project-config/INIT.md`,
> `definition-of-done.md` (DoR/DoD), `changelog-conventions.md` (entry + surfacing templates).

A **box** = a machine/agent session with **standing** authority. A **persona** (PM / PO / QA /
Engineer / Validation / Orchestrator) = a **per-feature hat** worn inside the loop. The two are
**orthogonal**: the box role says *which personas it may wear at all*; the persona says *which job
it does right now*. In a distributed setup PO and worker are **different boxes**, and the
**changelog item is the async channel between them** — the distributed form of "ambiguity = spec
bug, Orchestrator-mediated, never resolved in conversation."

## The two box roles

| | **PO box** | **Worker box** |
|---|---|---|
| Authority | Full | Execution only |
| Personas it may wear | All (PM-facing, PO, Orchestrator, QA, Engineer, Validation) | Implementation-side only (QA, Engineer, Validation) |
| Stages it may run | `0–7`, including authoring | The route's **execution** stages on a Ready item |
| Files & shapes changelog items | **Yes** (per `changelog-conventions.md`) | No — never edits scope/ACs |
| Decides forks | **Yes** | **No** — surfaces them |
| Authors / patches the canonical spec | **Yes** | **No** (obvious-only exception below) |
| Owns the serialized merge / orchestration | **Yes** | No |

- **PO box — full authority.** Stage 0 triage + routing; Stage 1 design-with-PM; Stage 2 recon;
  Stage 3 spec authoring. Files/shapes changelog items, decides forks, patches the canonical spec,
  owns the single serialized merge. **A solo dev is a PO box** and may run the whole loop solo —
  the role layer is invisible until you split boxes.
- **Worker box — execution authority only.** Picks up a DoR-met item the PO marked **Ready** (the
  work-ready state, `project-details.md#CL-6`) and runs the implementation stages to **Done**
  (`definition-of-done.md`). It **MUST NOT**: decide a fork; author or patch the canonical spec
  beyond an obvious-from-existing-convention detail; change an item's scope or its ACs.

## The surface-back protocol (the core)

When a worker box hits **any decision above "obvious from existing convention"** — an ambiguity, a
spec bug, a missing prerequisite, an AC unreachable through a production API, a fork:

1. **Do NOT guess. Do NOT patch the canonical spec.** Stop resolving it locally.
2. **Write the concern to the changelog item** using the templates in `changelog-conventions.md`:
   - `[NEEDS-PO] <question / ambiguity>` — a spec or design decision the worker may not make.
   - `[BLOCKED] <reason / missing prerequisite>` — work cannot proceed until something lands.
3. **Transition the item to the PO-attention state** (`project-details.md#CL-7`; e.g. a Jira
   "Blocked"/flag in Mode A, a status line in Mode B) and **STOP work on it.** The worker may pick
   up another DoR-met item meanwhile.
4. **The PO box resolves** — patches the spec / decides the fork / updates the AC / re-readies —
   and returns the item to the work-ready state. Only then does execution resume.

This is the QA→Orchestrator escalation (`stages/5_qa.md`, `stages/6_engineer.md`) cast at box
level: a worker box never settles an ambiguity with the spec. The fix lands **in the artifact**,
before code, every time.

## The obvious-only exception

The line between "record it inline" and "surface it" is the framework's **existing right-sizing
line** — the same one the PO uses for an auditable working decision.

- **Obvious from existing convention** → a worker MAY record it inline (the auditable "PO working
  decision" pattern) **and** note it on the item, so the trail stays in the changelog.
- **Anything non-obvious** → `[NEEDS-PO]`. When in doubt, it is non-obvious — surface it.

Authoring a spec clause, choosing between two viable designs, or setting a constant the spec does
not already imply are all **non-obvious by definition**. A worker never widens this exception to
dodge a surface-back.

## Assignment — local, per-box, uncommitted

Each box declares its own role; the role is **never committed** (a property of the deployment, not
the repo).

- Env var: `SDD_BOX_ROLE=po|worker` plus `SDD_BOX_ID=<short personal id>` (e.g. the hostname), **or**
- A git-ignored `project-config/box-role.local` file holding both.
- **Default = `po`.** An unset / solo box does everything. A worker box **must** set `SDD_BOX_ID` — it stamps claims (see Box loops below).

The agent carrier's stub (`AGENTS.md`; `CLAUDE.md` routes to it — `host-adapter.md`) surfaces the active role at the top of every context (wired in
`project-config/INIT.md`).

## Box loops & coordination

Separate boxes coordinate **only through the changelog item**. Each runs a poll loop on its own
schedule (defaults below; tune in Project Details). Item state machine in a split deployment:
`Ready → Claimed:<box-id> → In-Progress → Ready-for-review → Done`, with `PO-attention` as the
surface-back exit from any worker step.

**Claim (worker, before starting).** Work an item only after claiming it: comment (Mode A) / status
tag (Mode B) `claimed-by:<SDD_BOX_ID>` + timestamp. **Only claim an unclaimed Ready item;** if it
already carries another box's claim, leave it and take the next. First claim wins; a rare double-claim
is a PO-resolved conflict (the trail shows both).

**Worker loop (~15–30 min):**
1. Poll for the oldest **unclaimed Ready** item. None ⇒ **do nothing**; wait for the next cycle.
2. Claim it; verify DoR. DoR fails ⇒ surface back (`PO-attention`) and loop.
3. Run the route's implementation stages to **all gates green** (`run_all`). **Do not merge.**
4. Push the branch, flag the item **`Ready-for-review`**, loop.
5. Any non-obvious decision en route ⇒ surface back (`[NEEDS-PO]`/`[BLOCKED]` → `PO-attention`), drop the item, loop.

**PO loop (~30 min):**
1. **`PO-attention`** items: resolve — arbitrate if obvious, else escalate to the PM — write the decision into the spec/item, **re-ready** it.
2. **`Ready-for-review`** items: run the **fresh Validation** (diff vs spec + constitution — genuinely cross-box-fresh) and the **serialized merge**; transition `Done` + ship-SHA.
3. Intake new work: triage → design → spec/test-plan → mark `Ready`.

**Cross-box merge serialization.** Workers never merge to the published branch — they stop at
`Ready-for-review`; the **PO box owns the serialized merge** (it already owns the branch) and runs the
final Validation + merge-train. That single owner is the cross-machine serialization point. **Solo
deployment** (one PO box): invisible — the same box runs Validation + merge inline at Stage 7.

## At a glance

- Know your box role **before** you touch a Ready item.
- Worker box: verify DoR (`definition-of-done.md`) on pickup; if it fails, surface back — do not
  start.
- Worker box: spec authoring and fork decisions are **PO-box only**. Surface, never author.
- The changelog item is the channel. The fix lands in the artifact, not the conversation.
