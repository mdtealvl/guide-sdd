# Stage 2 — Recon / Viability

- **Role:** Orchestrator/PO.
- **Loaded with:** constitution + this file + the design's prerequisite list from Stage 1 + the relevant
  seam rows (`project-details.md#SEAM-N`) and stack (`project-details.md#STK-N`).
- Persona route only. Enter when the plan depends on an unverified prerequisite.
- Verifying the ground is cheap; an integration failure is not.

## Do

For each prerequisite the design assumes, run a **viability check** — a concrete yes/no probe against
the real system (Grep/Read/Bash on the real code and data), not a guess:

- "Does the server actually expose the lifetime counters the achievement reads?"
- "Do the reward-bag defs exist server-side?"
- "Does the contract field we're keying off already serialize?"

Record each as ✓ (exists) or ✗ (missing).

## Routing the ✗'s

- A missing prerequisite becomes its **own work item**, filed on the changelog
  (`project-details.md#CL-N`) and sequenced **before** the dependent work.
- Never paper over it or assume it will appear.

## Exit criteria

- [ ] Every prerequisite probed against the real system — none left as an assumption.
- [ ] All ✓, or each ✗ converted into a tracked, sequenced prerequisite work item.

---
### Gate(s) that close this stage
- Viability checklist recorded — all ✓ (or each ✗ tracked and sequenced first).
  Human/Orchestrator gate (no script).
### Return
Return to PROCESS.md §0 and load Stage 3 (spec). Read that stage file fully and follow it; this one is done.
