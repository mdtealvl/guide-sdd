# Metrics — what the method measures about itself

> Demand-loaded spine. Read when reporting on a project, evaluating a process change, or deciding
> whether a route's ceremony earns its cost (invariant 2). Five **outcome** metrics, each computable
> from artifacts the method already produces — the changelog item, git, gate output. Inputs (tokens
> per slice, prose share) are cost, not outcome; report them beside these, never instead.

## The five

| Metric | Definition | Source artifact |
|---|---|---|
| **First-pass acceptance** | shipped items whose first `validated:` line says `accept` ÷ shipped items, per route | `validated: <base>..<head> accept|decline` lines on the item (`stages/7_ship.md`) |
| **Surface-backs per item** | `[NEEDS-PO:<reason>]` + `[BLOCKED:<reason>]` entries per shipped item, grouped by reason | item comments; the reason enum in `changelog-conventions.md` §6 |
| **Test challenges per item** | Stage-6 challenges filed, grouped by resolution (spec / test / rejected) | item comments (`stages/6_engineer.md` challenge protocol) |
| **Post-ship defects** | Bug items filed within 30 days whose failing test tags a clause the item folded (same pin date) | Bug items + the fold pins `(§X per <ITEM-ID>, date)` |
| **Route share + re-triage** | items by route (mechanical / persona / parallel) and how many were re-triaged up or down | the Triage record on the item (`stages/0_triage.md`) |

## Cost, reported beside them — tokens

| Input | Definition | Source artifact |
|---|---|---|
| **Tokens per slice / per plan** | `admitted` = Σ bytes × `tokensPerChar` of every read a slice recorded; `saved` = the whole-file cost the ledger's advice rows let it skip; `P` = what planning itself read (`stages/4b_buildplan.md`) | the `tokens:` lines on the item — recomputable by `gates/token_ledger.* report` from `<ITEM-ID>.buildplan.md` |

An estimate of what a context admitted, never a billed count. Read it per route beside the five: a
route whose saved share rises while first-pass acceptance holds is a cheaper route; a plan whose
`planning (P)` cost exceeds what its ledger saved is over-planning — trim the build plan, not the ledger.

## Reading them

- Compare routes **within one risk class**. If the persona route's post-ship defect rate is not below
  the mechanical route's for comparable work, the split is ceremony there — re-triage the risk bar
  (`project-details.md#RS-N`), do not keep paying.
- A rising **surface-back** count by reason `spec-gap` or `threshold` is an intake problem
  (`intake.md`), not a worker problem.
- **Test challenges** resolved as *spec* are QA finding spec bugs — the blindness working. Resolved
  as *test* more than one in five: the Stage-4 matrix is under-specified.
- **First-pass acceptance** under one in two on the persona route: read the decline classes on the
  items before changing anything.

## Computing them

Per window (a sprint, a month): collect the item ids shipped in the window (Mode B: the `backlog/`
files with a `shipped:` line in range; Mode A: a tracker query), then join to
`git log --grep '<ITEM-ID>'` for commits and ship SHAs and read the item's `validated:`, `[NEEDS-PO`,
`[BLOCKED`, challenge and `lesson:` lines. Ten minutes by hand for a sprint. A script for this join
(`ci/evidence.*`: range in, JSON per item out, measures only) is a tracked follow-up —
`project-config/PROPOSED_CHANGELOG.md` SDD-PROP-11 phase 2.

## What this does not claim

No number here proves the method causes better software; there is no control group. They show
whether a change to the process moved an outcome on this project, which is what a process owner can
act on. The external evidence the method rests on is cited in `README.md` §"Map to the source
practices" and the field survey it links.
