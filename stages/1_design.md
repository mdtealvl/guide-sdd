# Stage 1 — Design Pass

**Role:** PM (human) + Orchestrator/PO. **Loaded with:** constitution + this file + the spec shards
for the touched area (the Triage record's target shard IDs).

Persona route only: enter when the work touches >1 seam OR there is a non-obvious call.

## The decisive habit: read the spec for what already exists

Before designing anything new, **read the existing spec twice** — the cheapest generalization is the
one already written. **Conform to the existing primitive; don't fork a parallel hierarchy** — the most
common expensive mistake. (Standing rule, not a preference.)

## Do

1. Surface unknowns in prose; don't paper over them. Then run the **unknown-finding pass** — four
   questions, each answered or turned into an open question on the item:
   - *Inversion* — what would guarantee this fails, is reverted, or is never used?
   - *Second order* — what else changes when it ships (callers, stored data, docs, ops, cost)?
   - *Seam walk* — for each touched `#SEAM-N`: what does the design need from it; what does it forbid?
   - *Fixed-set check* — if one member of a set (enum, status code, role) is special-cased, what
     happens to every other member?
2. Decide the forks **explicitly** — recommendations, not exhaustive surveys. Convert the item's
   `CAP-n` capabilities into the constants and thresholds the ACs will name.
3. Name every prerequisite the design assumes exists (feeds Stage 2 recon).
4. Keep it conversational and diagram-first — equally navigable as the human design surface and the
   LLM's primary context.
5. **Brownfield:** if the touched area has no authoritative spec (`greenfield-vs-brownfield.md`), do
   **not** design over behaviour inferred from code — flag the gap to the PM (worker box surfaces
   `[NEEDS-PO]`) and get the intended behaviour decided first.
6. **Structure diagram — the last sub-step.** With the forks decided, draw the **member-level class
   diagram** of what the unit produces: every class / interface / enum it adds or changes, with every
   **public** property and method (name, parameters, return type). A mermaid `classDiagram` in a
   **structure shard** — `<ITEM-ID>.structure.body.md` in the working-spec home
   (`spec-format/README.md` §3) — in **delta form**: `## Added` / `## Changed` (the class, with only
   the changing members) / `## Removed`.
   - Read the area's canonical structure shard first and conform to it (no parallel hierarchy).
   - A member the diagram cannot name is an undecided fork: decide it (step 2) or escalate.
   - Text is the source; the drawing derives.
   - A unit adding no class and no public member records `structure: N/A — <reason>` on the item instead.

## Anti-patterns

- Outlines that defer the hard call ("we'll figure out the formula later") — a spec gap in disguise.
- Designing a new system parallel to one the spec already generalizes.
- Absorbing a conflict silently instead of surfacing it through the Orchestrator.

## Exit criteria

- [ ] Every fork decided explicitly (or escalated to PM and answered).
- [ ] Any brownfield spec gap in the touched area flagged to the PM and resolved — not designed over.
- [ ] Prerequisites enumerated for recon.
- [ ] Structure shard drafted at member level — public surface complete, delta form — or
      `structure: N/A — <reason>` on the item.
- [ ] PM has signed off on the prose plan and the draft diagram.

---
### Gate(s) that close this stage
- PM approves the design prose + the draft structure diagram (human gate). The diagram is approved
  **finally** with the spec at Stage 3 and frozen with the tests at Stage 5; from then on a deviation is
  `[NEEDS-PO:structure]` — a PM decision, never an edit (`stages/6_engineer.md`).
### Return
Return to PROCESS.md §0 and load Stage 2 (recon) if the plan rests on unverified prerequisites, else
Stage 3 (spec). Read that stage file fully and follow it; this one is done.
