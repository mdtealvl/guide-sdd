# Greenfield vs. Brownfield — does an authoritative spec already exist?

> **v1.2 — 2026-06-24.** Demand-loaded spine. Load when triaging a unit whose area may have no
> spec, or when an agent is tempted to infer intent from existing code. Choose the stance **per
> work item** at Stage 0, not once per project.
> Cross-links: `stages/0_triage.md` (the per-unit coverage check), `stages/1_design.md` +
> `stages/3_spec.md` (reconstruct or flag), `box-roles.md` (surface-back),
> `constitution.md` (spec-is-truth), `definition-of-done.md` (Ready bar).

The framework is **spec-first**: behaviour is decided in the spec, then code conforms. That assumes
a spec *exists* for the area you touch. Often it doesn't. This doc is the stance for that fork.

## The two stances

| | **Greenfield** | **Brownfield** |
|---|---|---|
| The area is | nothing yet, or a genuinely new module | an existing codebase, spec absent/partial for the slice you must change |
| The spec is | **authored fresh** in Stage 3 | **reconstructed** for the touched slice — or the gap is flagged |
| Path | pure spec-first; the ideal case | spec-as-you-go; the danger case |
| The danger | none particular | an agent infers intent from the code and "runs roughshod" — unintended knock-on problems |

**It is a per-unit stance, not just a project setting.** A brownfield project is *greenfield* for a
genuinely new module; a greenfield project goes *brownfield* the moment it touches an
under-specified legacy seam. Decide **per work item** in Stage 0 by asking: *does the area this
touches have authoritative spec coverage?*

> **Decision line:** authoritative spec for this area? **yes → greenfield path** (author fresh in
> Stage 3) · **no → reconstruct the slice or surface the gap** (never infer-and-proceed).

## The brownfield discipline (the core rule)

The **absence of a spec for a behaviour you must touch is itself a SPEC GAP** — a kind of spec bug.
You do **not** infer-and-proceed. You **flag** it:

1. **Spec-as-you-go, not spec-the-world.** Do **not** reconstruct the spec for the whole legacy
   codebase up front. Reconstruct only the **slice you are about to touch**, incrementally — the
   same shard-manifest scope every other stage uses.
2. **A discovered gap is surfaced, not guessed.** The discovering agent flags it via the
   **surface-back protocol** (`box-roles.md`): a worker box writes `[NEEDS-PO]` to the changelog
   item. The Orchestrator/PO then either:
   - **ARBITRATES** — if intended behaviour is *obvious from existing code + established
     convention*, the PO records the reconstructed clause as an auditable **PO working decision**
     (the framework's right-sizing line — `box-roles.md`), **or**
   - **ESCALATES to the PM** — if it is a genuine product decision.

   Never resolve a real ambiguity silently. When in doubt, it is non-obvious → escalate.
3. **The unspecified-surface register.** Track known spec-gap areas as a **spec-debt list** so gaps
   stay *visible*, not rediscovered. Register per the project's choice — the project details
   pointer-doc map, or a `docs/UNSPECIFIED_SURFACES` list (bind its location in
   `project-details.md`; do not invent a pointer id here).

## The escalation chain, explicitly

```
discovering agent  →  PO  (ARBITRATE if obvious-from-code-and-convention)
                          (else ESCALATE)  →  PM  (decides)
```

The reconstructed/decided behaviour is **written into the spec in the same exchange** (Stage 3 — a
decision never lives only in chat), then implementation proceeds against the now-specified slice.
The fix lands in the artifact, before code.

## Incremental (brownfield) adoption — scope the coverage corpus

`coverage_check` is **whole-corpus at ship**: every clause in `paths.spec` needs a test. Pointed at
a whole legacy repo with no clause-ID'd spec, it can never go green — blocking every ship. The
lever, **not a workaround:**

- Scope `paths.spec` to **SDD-authored shards only** when retrofitting an existing repo. The legacy
  spec is **left as-is** (it isn't in `paths.spec`); new features are **SDD-native** from shard one.
- The clause-ID'd corpus **grows** as you reconstruct-the-slice (above) for each touched area —
  spec-as-you-go, never spec-the-world.
- This is the **deliberate adoption path**: SDD lands feature-by-feature, the coverage gate stays
  honest over what SDD authored, and spec debt is visible in the unspecified-surface register rather
  than faked green.

**Up-front alternative — Discover Spec.** To bring a whole area (or the repo) under SDD in one
deliberate pass rather than feature-by-feature, run `discover-spec.md`: reconstruct *provisional* spec
for the area, baseline test coverage + quality (mutation score, not just line coverage), and produce a
prioritized test plan to the targets. It scales this per-unit rule up; the reconstructed spec stays
**provisional** until the PM ratifies it.

## When to use which

- **Greenfield project or new module** → greenfield (author fresh in Stage 3).
- **Existing area, no/partial spec** → brownfield (reconstruct-the-slice-or-flag).
- **Mixed projects are normal** — the stance is chosen **per unit at triage**, never assumed for the
  whole repo.

## At a glance

- [ ] Ask at Stage 0: **authoritative spec for this slice — yes or no?**
- [ ] Yes → greenfield: author the spec fresh in Stage 3, pure spec-first.
- [ ] No → brownfield: **do not infer-and-proceed.** The gap is a spec bug.
- [ ] Reconstruct only the **slice you touch**, incrementally — never spec the whole legacy world.
- [ ] Surface the gap (`[NEEDS-PO]`) → PO **arbitrates** (obvious) or **escalates** to PM.
- [ ] Record the area in the **unspecified-surface register** so it isn't rediscovered.
- [ ] A brownfield unit is **not Ready** until its touched slice is specified (`definition-of-done.md`).
