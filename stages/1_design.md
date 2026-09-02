# Stage 1 — Design Pass

**Role:** PM (human) + Orchestrator/PO. **Loaded with:** constitution + this file + the spec shards
for the touched area (from the Triage record's target shard IDs).

Persona route only. Enter when the work touches >1 seam OR there is a non-obvious call. Skip for
mechanical work.

## The decisive habit: read the spec for what already exists

Before designing anything new, **read the existing spec twice.** The cheapest generalization is the
one already written. **Conform to the existing primitive; don't fork a parallel hierarchy** — the most
common expensive mistake. (Standing rule, not a preference.)

## Do

1. Surface unknowns in prose. Don't paper over them; follow the train of thought.
2. Decide the forks **explicitly** — recommendations, not exhaustive surveys.
3. Name every prerequisite the design assumes exists (feeds Stage 2 recon).
4. Keep it conversational and diagram-first — the human design surface and the LLM primary context at
   once; equally navigable to both.
5. **Brownfield:** if the touched area has no authoritative spec (`greenfield-vs-brownfield.md`), do
   **not** design over behaviour inferred from code — flag the gap to the PM (worker box surfaces
   `[NEEDS-PO]`) and get the intended behaviour decided before designing on top of it.

## Anti-patterns

- Outlines that defer the hard call ("we'll figure out the formula later") — a spec gap in disguise.
- Designing a new system parallel to one the spec already generalizes.
- Absorbing a conflict silently instead of surfacing it through the Orchestrator.

## Exit criteria

- [ ] Every fork decided explicitly (or escalated to PM and answered).
- [ ] Any brownfield spec gap in the touched area flagged to the PM and resolved — not designed over.
- [ ] Prerequisites enumerated for recon.
- [ ] PM has signed off on the prose plan.

---
### Gate(s) that close this stage
- PM approves the design prose (human gate).
### Return
Return to PROCESS.md §0 and load Stage 2 (recon) if the plan rests on unverified prerequisites, else
Stage 3 (spec). Drop this stage body from context.
