# Session Lifecycle — externalizing a volatile context

> Demand-loaded spine. SDD's spine governs the **item** lifecycle (Ready → Done); this governs the
> **session/context** lifecycle — getting durable state out of a volatile agent context before it is
> cleared, so the next boot loses nothing. Load at a session close, a task switch, or an interrupt.
> Tier-A implementation: the bundled slash-commands (`commands/`); Tier-B/C: run the same rituals by
> hand (`host-adapter.md`). Cross-links: `definition-of-done.md` (lane reconciliation is a DoD item),
> `changelog-conventions.md` (backlog entries), `box-roles.md` (HANDOFF is per-box).

## Why
A long agent context accrues state — dispatched agent lanes, PM rulings, spec debt, an edited working
set — that a context-clear destroys unless externalized. The rule mirrors the constitution: **decisions
live in artifacts, not chat** (inv. 1, 10) and **trust artifacts, not narratives** (inv. 10 — *an
agent's existence is not evidence its work landed*). Session lifecycle is that rule applied at the
context boundary.

## The project memory directory
Per-project; path + layout bound in `project-details.md#CL-11`, seeded at INIT
(`project-config/INIT.md`). Standard layout:

- `MEMORY.md` — the index loaded each boot; one line per memory, no content.
- `HANDOFF.md` — the mutable "you are here" card; **overwritten each wrap, never appended** (history
  lives in the backlog). The next boot reads it FIRST.
- `backlog.md` — the durable event log (Mode B) or a tracker pointer (Mode A).
- `stashes/` — named resume packs; `stashes/archive/` holds consumed packs.
- `memory/` — banked trap memories (+ `memory/archive.md` for pruned entries).

## Wrap — the end-of-session externalization pass
Run at an **unambiguous** close, in order (Tier-A: `/wrap`):

1. **Reconcile every agent lane** — each dispatched sub-agent gets a verdict **LANDED(commit-hash)** or
   **DIED(re-queued with failure guidance)**; verify by artifact (`git log`), never by the agent's
   report. No lane may cross the boundary "in flight" — a clear orphans resumable handles. *(This is a
   DoD item — `definition-of-done.md`.)*
2. **Land or park the tree** — finished work committed (stage by path, never blanket-add); unfinished
   work stashed-with-a-pointer or described precisely in the backlog (branch, files, next step).
3. **Backlog to a survivable state** — the current item marked SHIPPED (SHAs, verdicts owed) or
   IN-FLIGHT (what's decided/running, exact resume point); stale entries superseded.
4. **Bank memories** — any trap that cost >15 min and could recur → a memory file + a `MEMORY.md` line.
5. **Spec debt** — any PM ruling not yet in spec/decisions is written NOW (spec-first: it never
   survives only in chat).
6. **Overwrite the HANDOFF card** — in-flight lanes with resume points, the shipped list as
   commit/decision *pointers* (not prose), verdicts owed, parked decisions, a one-line-per-decision
   index. Wholesale replace; history belongs in the backlog.
7. **Report** ≤10 lines and stop; do not start new work.

## Auto-wrap trigger
Wrap fires automatically **only on an unambiguous close signal** (the PM signals end-of-session or an
imminent clear). Ambiguity ⇒ do not auto-wrap — ask. A wrap is cheap to run and expensive to skip, but
a spurious wrap mid-thought costs the thread; gate it on certainty.

## Stash / unstash — task-freezing
Switch tasks without loss (Tier-A: `/stash <name>` / `/unstash <name>`):

- **Stash** = run the wrap discipline on the *current task only*, then write a resume pack
  `stashes/<name>.md`, richer than HANDOFF: task+state (exact next step at file:line grain); working set
  (signatures/constants **pinned — pasted, not pointed at**); rulings taken + open questions;
  re-dispatch briefs for any unfinished lanes; verification state. Never silently overwrite an existing
  pack. Set HANDOFF's in-flight entry to `STASHED → <name>`.
- **Unstash** = wrap any live context first (unstash assumes the current context is disposable — make it
  true), read the pack, reconstruct the working set at the pinned locations (**verify pins still hold**
  against current code; a stale pin is reconciled, never assumed), re-dispatch recorded briefs, restore
  the HANDOFF entry, **pop-with-archive** (move to `stashes/archive/`), continue.

## Interrupt triage
A mid-task interrupt is routed, not absorbed — pick the cheapest that preserves the current task's
resumability:

- **Sidebar** — a quick answer not touching the working set → answer, return; nothing externalized.
- **Sub-agent** — a bounded, dispatchable piece → spawn a scoped lane (reconciled at wrap, step 1).
- **Stash** — a genuine task switch → `/stash` the current task, take the new one, `/unstash` later.

## Host tiers
Tier-A hosts run these as slash-commands (`commands/`, installed to the host's command dir — `.claude/commands/`,
`.github/prompts/`, `.cursor/commands/`). Tier-B/C hosts run the identical rituals **by hand** — the
discipline is the ordered pass, not the slash sugar. See `host-adapter.md`.
