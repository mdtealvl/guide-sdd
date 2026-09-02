# SDD — Spec-Driven Development Framework

> **v1.9 — 2026-09-02.** A reusable, token-efficient, spec-first / persona-split development
> method that drops into large, multi-developer projects worked by humans **and** AI agents. It
> merges two mature in-house practices (Mistwright's *How We Work*, Polars' *How To Develop*) with
> the published SOTA into one copyable **spine** + a small, indexed **per-project surface**.

## The core idea (in four lines)

1. **Spec is the source of truth.** Code conforms; when they disagree the code is the bug.
2. **Intent drift is the adversary.** Every rule is an anti-drift mechanism.
3. **One mind writing spec+tests+code transcribes its misread into all three** — so for risky
   work, split the jobs across independently-scoped agents (the **persona loop**).
4. **Match ceremony to risk.** A 2×2 routes each unit to the cheapest sufficient process.

The full non-negotiables are the **ten invariants** in `constitution.md` (tiny, always loaded).

## The artifact stack

| Layer | File(s) | Loaded |
|-------|---------|--------|
| Entry point | `START_HERE.md` | first read / bootstrap |
| Agent carrier — per-host always-load stub | `AGENTS.md` (canonical) · `CLAUDE.md` (routes to it) · `.github/copilot-instructions.md` (shim) | **Always** (the host's rules file) |
| Spine: host adapter — load-verbs → each agent tool | `host-adapter.md` | On demand |
| Constitution — the 10 invariants | `constitution.md` | **Always** (via the agent carrier — `host-adapter.md`) |
| Constitution amendment log | `constitution.changelog.md` | On demand (audit) |
| Process spine — stage router/index | `PROCESS.md` | **§0 always**; stage bodies on demand |
| Stage playbooks | `stages/0_triage.md` … `stages/7_ship.md` | One at a time |
| Spine: box roles + surface-back | `box-roles.md` | On demand |
| Spine: changelog/ticket conventions | `changelog-conventions.md` | On demand |
| Spine: DoR + DoD lifecycle gates | `definition-of-done.md` | On demand |
| Spine: greenfield vs brownfield | `greenfield-vs-brownfield.md` | On demand |
| Spine: discover spec (brownfield characterization) | `discover-spec.md` | On demand |
| Spine: lifecycle states (retiring things) | `lifecycle-states.md` | On demand |
| Spine: session/context lifecycle (wrap, stash/unstash) | `session-lifecycle.md` | On demand |
| Session-lifecycle commands (Tier-A impl) | `commands/` (`wrap` · `stash` · `unstash` + README) | Installed to host command dir |
| Gate bank | `gates/` (generic + project gates as `.ps1`+`.sh` pairs, runner, config template) | Run, not loaded |
| Spec format standard | `spec-format/` (`README.md` + `build.ps1` / `build.sh`) | On demand |
| Project details (7 indexed sections) | `project-config/project-details.md` | The cited section only |
| Init / onboarding | `project-config/INIT.md` | Once, at adoption |

**The spine** (`constitution.md`, `PROCESS.md`, `stages/`, `host-adapter.md`, generic `gates/`,
`spec-format/`) is copied verbatim into every project and never edited per project — it names no stack,
seam, tracker, **or agent tool** (the spine speaks in load-verbs; `host-adapter.md` is the one place
tools are named). **The project-specific surface** is `project-config/project-details.md` +
`gates/gates.config.json` (paths, `clauseIdRegex`, and the inline `constitutionRules[]` /
`seamRules[]`). **The per-host surface** is the carrier file (`AGENTS.md` / `CLAUDE.md` /
`.github/copilot-instructions.md`) + the `$SDD_HOST_TIER` stamp — all small, indexed, addressable.

## The 2×2 right-sizing summary

Decided once in Stage 0 (Triage) and recorded; everything downstream reads that decision.

| | **Misread cheap / obvious** | **Misread expensive / non-obvious** |
|---|---|---|
| **Not decomposable** | **Mechanical** — single-context: stages 0 → 3 → 4 → 7 | **Coupled + risky** — full persona loop: stages 0–7 |
| **Decomposable into slices** | **Independent + simple** — parallel dispatch of worktree workers; mechanical lane per worker | **Independent + risky** — parallel dispatch; persona loop per worker |

Routes **compose** (e.g. contract-first FE/BE split, then a persona loop per lane). Conservative
default: **touches >1 project-details seam → at least the persona bar.** Project-specific escalations
(e.g. "money path → always persona") live in Project Details §7. Never silently up/downgrade — re-triage
explicitly and record it.

## How staged loading keeps it cheap (the headline feature)

The framework never loads itself wholesale. The always-loaded surface is **≈1.6k tokens**:
`constitution.md` (tiny) + `PROCESS.md` §0 — the **boot protocol**: router, a load manifest (with the
Project Details *seam index*, so seams are discoverable), a precedence stack, a discrepancy/halt
protocol, and a DoD summary — carried by a ~9-line stub (`AGENTS.md`; `CLAUDE.md` routes to it, Copilot
via a shim — `host-adapter.md`). §0 is deliberately fatter than
the constitution: that's the bounded cost of making seams discoverable and "Done" knowable in every
context. Everything that scales with project size — the 8 stage bodies, gate
scripts, spec shards, the 7-section project details, the changelog — is **demand-loaded** at shard
granularity.

`PROCESS.md` §0's first instruction is literally: *read this, then stop; load only your current
stage; return here for the next.* Sub-agents (QA / Engineer / Validation) are spawned with a
**hand-assembled scoped context** — constitution + their single stage file + named spec shards +
named project-details seams — and never the router, sibling notes, or transcript. That physical exclusion
is what enforces the two independences. Standing cost is therefore ~constant regardless of project
size. Mapped onto each host's mechanics (`host-adapter.md`): the agent carrier (always), stage files as
on-demand reads / slash-commands, and personas as scoped sub-agent contexts (Tier A) or fresh sessions
(Tier B).

## Adopt it on a new project (7 steps)

Walk `project-config/INIT.md`. In short:

1. Copy the spine into the repo (`sdd/`).
2. Wire the agent carrier — `AGENTS.md` holds the ~9-line stub (constitution + `PROCESS.md` §0);
   `CLAUDE.md` routes to it, Copilot via `.github/copilot-instructions.md` (`host-adapter.md`). The
   stub also surfaces this box's role (`$SDD_BOX_ROLE`, default `po`) — see `box-roles.md`.
3. **Choose changelog mode** — prompted at init: external tracker (Jira/Linear/…) vs lighter
   on-disk backlog. The fold-on-ship invariant is identical in both modes.
4. **Choose spec format** — prompted at init: Markdown→HTML (default) vs raw HTML. Either way,
   each subsection is a **content-only** shard compiled into one navigable index.
5. Instantiate `project-details.md` from the template; register your architecture seams (§1).
6. Fill `gates.config.json` (paths + `clauseIdRegex` + suite command); add your project-specific
   gate rules as inline `constitutionRules[]` / `seamRules[]` entries in that same config.
7. Run the gate smoke test; confirm the generic gates pass/fail correctly. Green = adopted.

## Evolving the standard — opportunistic rewrites (C3c)

**This framework improves the same way a spec does: Patch / Amend, opportunistically,
never big-bang.** The SDD package is a dogfooded spec governed by its own constitution. When
running a project teaches you something about the *process*, the project that hit the gap fixes
the process file **in the same exchange** — never a conversational artifact, never a scheduled
"rewrite the method" project (mirrors "doc updates land in-flight per slice").

- **Patch** — in-place edit to a stage/gate/spec-format file (typo, clarification, tightened wording).
- **Amend** — a versioned entry (`## vN Amendment — <topic>` here + `constitution.changelog.md`) for a
  substantive new step or gate.
- Either way the doc text is **replaced wholesale** — no struck-through, bracketed, or dated strata; a wrong
  rule is corrected in place and the correction recorded in the changelog + git (v1.9). Product specs use
  the one update method in `stages/3_spec.md`.

Discipline:
- **Scope.** The constitution's invariants change **only by Amend** and **only** the ten
  invariants; operational detail flows down to a stage file or the project details. If a proposed change
  would grow the always-loaded core, it belongs elsewhere.
- **Provenance.** A changed standard clause is pinned `(per <unit-id>, date)` exactly like a
  product spec clause, so the process's own evolution is back-derivable.
- **Promulgation.** New projects adopt the *current* spine; this is the standard going forward.
  Improvements propagate by **re-pulling the package**. A project's local `project-details.md` /
  `gates.config.json` is **never overwritten** by a standard update — the spine/project-details split
  guarantees it. A project that needs different behaviour expresses it in its project-details/config,
  never by forking the spine.

### v1.1 Amendment — box roles, changelog conventions, DoR/DoD (2026-06-24)

Three interlocking, stack-agnostic spine docs (demand-loaded), plus cross-reference edits to
the constitution, `PROCESS.md` §0, INIT, Project Details §4, and stages 0/3/7:

- **`box-roles.md`** — the deployment-role layer (orthogonal to per-feature personas). A **PO
  box** has full authority (triage, design, spec authoring, fork decisions, merge); a **worker
  box** has execution authority only and runs the **surface-back protocol** — on any ambiguity,
  spec-bug, or above-convention decision it writes the concern to the changelog item and stops,
  never guessing or patching the spec. This is the distributed form of "ambiguity = spec bug,
  orchestrator-mediated, never resolved in conversation." Role is set per-box, uncommitted
  (`SDD_BOX_ROLE`, default `po`).
- **`changelog-conventions.md`** — the well-formed-entry standard (Story/Bug/Task/Spike;
  imperative scoped title; ACs as EARS clauses `<ITEM-ID>/AC-n` that fold into the spec on
  Done; surfacing templates). Identical content standard in changelog Mode A and Mode B;
  Project Details §4 binds only the storage/state mechanics.
- **`definition-of-done.md`** — the two lifecycle gates as literal checklists: **DoR** (the
  Stage-0 / worker-pickup entry bar) and **DoD** (the Stage-7 consolidated exit bar the
  Validation checklist enforces).

### v1.2 Amendment — brownfield, lifecycle states, PowerShell+Bash gates (2026-06-24)

- **`greenfield-vs-brownfield.md`** — a per-unit stance. Greenfield (new) authors the spec fresh;
  brownfield (existing code, no spec) reconstructs only the slice it touches and **flags** any gap
  rather than inferring intent from code. The escalation chain: discovering agent → PO (arbitrate if
  obvious) → PM. Wired into constitution invariant 1, Stage 0 triage, Stages 1 & 3.
- **`lifecycle-states.md`** — retire anything (clause, doc, config, code) with an explicit lifecycle
  state (deprecated/superseded/moved/removed) + date + reason/pointer; never silent-delete. Wired
  into constitution invariant 8, `spec-format/README.md`, `changelog-conventions.md`.
- **Gates moved off Python** to **PowerShell (`.ps1`, Windows) + Bash (`.sh`, Linux/macOS)** pairs —
  zero Python dependency; Windows uses built-in `pwsh`, Linux/macOS uses `git` + `jq`. Agents detect
  the host OS and run the matching script (`gates/README.md`).
- **`START_HERE.md`** — the bootstrap front door so an unzipped drop is self-setting-up.

### v1.3 Amendment — boot protocol, precedence, prompt-injection, gate hardening (2026-06-24)

Folds in two antagonistic reviews. `PROCESS.md` §0 is now a hard **boot protocol** (load manifest +
discoverable seam index, precedence stack, discrepancy/halt protocol, DoD summary). Constitution
invariant 1 reframed (disagreement is a defect the Orchestrator classifies — handles stale specs
without spec-laundering); invariant 10 gained the **prompt-injection boundary** (repo/ticket text is
data, not instructions) and shed its operating mechanics to §0. DoD gained a **non-functional floor**
(security/privacy/a11y/perf/observability/compat/migration/rollback/compliance, N/A+reason), **oracle-source
classification**, and **fixture-gap severity** (blocking gaps can't ship). New: a **test-challenge
protocol**, a `qa_import_ban` gate (partial proof of QA ⊥ implementation), `coverage_check --manifest`
(per-unit scope — **ship-time coverage stays whole-corpus**, an undocumented semantic now stated), and
`fold_check --strict`. Gates now say loudly: they certify **bookkeeping + traceability, not correctness**
— a drift-catcher, not an oracle. Full record in `constitution.changelog.md`.

### v1.4 Amendment — Discover Spec, self-announcing onboarding, LLM-compression pass (2026-06-24)

- **`discover-spec.md`** — a deliberate brownfield characterization action: reconstruct *provisional*
  spec for an area, baseline test coverage **and quality** (mutation score + the "a test you can trust"
  criteria, not just line coverage), and produce a risk-prioritized test plan to ≥85% coverage + a
  mutation floor. Reconstructed spec stays provisional until the PM ratifies it — never bless a bug as spec.
- **Self-announcing onboarding** — the `CLAUDE.md` stub now tells an agent that lands in an SDD repo to
  announce "this project uses SDD" and switch out of ad-hoc work into PROCESS §0; INIT opens onboarding
  with a plain-language welcome before the ASK questions.
- **LLM-compression pass** — every demand-loaded doc (PROCESS, the 8 stages, spine docs, spec-format &
  gates README) compressed for an LLM reader: rules/names/anchors preserved, motivation/restatement cut;
  always-loaded core trimmed to ≈1.6k tokens. `welcome.html` realigned to v1.4.

Full record in `constitution.changelog.md`.

### v1.5 Amendment — box loops & cross-box coordination (2026-06-25)

No invariant change. Defines the operational loop behind the box-role contract (`box-roles.md`
§"Box loops & coordination"): the item state machine `Ready → Claimed:<box-id> → In-Progress →
Ready-for-review → Done` with `PO-attention` as the surface-back exit; the worker claim protocol
(`claimed-by:$SDD_BOX_ID`, first claim wins); the ~15–30 min worker loop and ~30 min PO loop; and
cross-box merge serialization (workers never merge — the PO box owns the merge + fresh Validation). New
per-box identity `SDD_BOX_ID`; new states bound in Project Details §4 (CL-9 Claim, CL-10 Ready-for-review).

Full record in `constitution.changelog.md`.

### v1.6 Amendment — cross-agent host-adapter layer + AGENTS.md carrier (2026-07-09)

Makes SDD **agent-neutral** without changing the method or the install pattern (no package manager, no
build step). The always-loaded core was already a **pointer stub**, not a Claude-specific mechanism — so
generalizing it is an extraction, not a rewrite.

- **`host-adapter.md`** — a new demand-loaded spine doc, the **third axis** beside the spine and
  `project-details.md`. The spine now speaks in three **load-verbs** (always-load · demand-load · scoped
  sub-agent); this doc is the single place agent tools are named, and it binds each verb to a host
  mechanism. Only *scoped sub-agent* varies across hosts — that variance is the **capability tier**.
- **`AGENTS.md`** — the canonical agent-neutral carrier holding the ~9-line always-load stub. Read
  natively by Codex / Cursor / Gemini. `CLAUDE.md` is now a one-line router (`@AGENTS.md`) giving Claude
  physical injection; `.github/copilot-instructions.md` is a shim for Copilot (which does not read
  `AGENTS.md`). One core, many carriers — no content duplication.
- **Capability tiers A/B/C** wired into `PROCESS.md` §0's persona route: Tier A runs the persona loop as
  scoped sub-agents; Tier B as fresh sessions (the `test_edit_ban` + `qa_import_ban` gates still enforce
  QA⊥Engineer **structurally** — why SDD degrades more gracefully across agents than a pure-prompt
  method); Tier C is Mechanical-lane-only. Stamped per box as `$SDD_HOST_TIER`.
- **Host-neutralized** the ~17 Claude-specific references across the spine (constitution note, `PROCESS.md`
  §0, `README.md`, `INIT.md`, `START_HERE.md`, `box-roles.md`, `gates/README.md`, `welcome.html`) to the
  load-verbs, pointing at `host-adapter.md`. Gates unchanged — already host-agnostic. Still ten invariants.

Full record in `constitution.changelog.md`.

### v1.7 Amendment — session/context lifecycle, token-admission, lane reconciliation (2026-07-14)

No invariant change; still ten. Folds in five ratified proposals from the Mistwright/4x `d224` arc
(originally staged in `project-config/PROPOSED_CHANGELOG.md`) — session lifecycle to complement item
lifecycle:

- **`session-lifecycle.md`** (new demand-loaded spine doc) — the ritual for externalizing a volatile
  context before it clears: the wrap-at-close pass, the **overwrite-only** HANDOFF "you are here" card,
  stash/unstash task-freezing, the auto-wrap trigger (gated on unambiguous close), and interrupt triage.
  Tier-A implementation is the bundled `commands/` (`/wrap`, `/stash`, `/unstash`), registered in
  `host-adapter.md`; Tier-B/C run the rituals by hand.
- **Token-admission standing rule** (`PROCESS.md` §0) — the complement to demand-loading: filter tool
  output at source, quarantine after ~5 exploratory calls, compute-don't-deliberate. Kept to one terse
  standing-rule line (not a paragraph) to bound always-loaded growth.
- **Agent-lane reconciliation** — a DoD item + §0 DoD-summary line: every dispatched sub-agent lane
  carries a **LANDED(hash)/DIED** verdict before a unit is Done or a session closes. *An agent's
  existence is not evidence its work landed* — cost the origin project two lost fixes.
- **Wire-canary + dead-wire recipe** — a DoD item + Stage-5 QA rule + a `gates/README.md` recipe for the
  representative-default dead-wire trap (a defaulted behaviour-arm parameter leaving every arm dead while
  arm-explicit tests stay green). The full callers-count gate needs an `any_match` engine kind — left as
  a smoke-tested follow-up, not shipped untested.
- **Memory-directory seeding at INIT** — a new INIT step + Project Details `#CL-11` bind the per-project
  memory dir (`MEMORY.md`, `HANDOFF.md`, `stashes/`, `memory/`, Mode-B `backlog.md`) so projects stop
  rediscovering the convention. Memory *contents* stay per-project by design.

Full record in `constitution.changelog.md`.

### v1.8 Amendment — dispatch frugality: sub-agent token-budget discipline (2026-09-01)

No invariant change; still ten. Ratifies SDD-PROP-07 from the Mistwright/4x MW-234/S35 arc, after
measurement showed sub-agents routinely consuming 300–450k tokens per dispatch — dominated by unfiltered
build/test output re-sent as context on every later turn (tool-call count is the multiplier), off-brief
full-suite runs, whole-file reads, and unbriefed gate reruns.

- **`PROCESS.md` §0 standing rule "Dispatch frugally"** — the token-admission rule binds dispatched
  contexts too, and the DISPATCHER enforces it in the brief: output-filtered gate commands (summary +
  failure names, never raw logs), exact run counts (the deciding suite is the Orchestrator's alone),
  pinned read RANGES, no background processes/waits the turn won't outlive; resume a live agent over
  re-dispatching fresh (measured ~81k/wave resumed vs ~350k fresh) — unless the persona needs a fresh or
  blind context (invariant 3).
- Project-side bindings (quiet gate idioms, repo-level build-noise suppression) live in each project's
  `project-details.md` TOOL- section (template row `TOOL-6`), not the spine.

### v1.9 Amendment — one spec-edit method + terse factual spec form (2026-09-02)

No invariant change; still ten. Ratifies SDD-PROP-08 and SDD-PROP-09 (staged in
`project-config/PROPOSED_CHANGELOG.md`) — both aimed at **spec bloat**: history strata that hide the
current law, and narrative prose that costs tokens on every demand-load.

- **One update method** (`stages/3_spec.md`; replaces Patch/Amend/Errata for canonical spec text) —
  negotiate the exact text with the PO → replace wholesale (no Errata blocks, in-page addenda,
  DECISION brackets, strike-throughs, SUPERSEDED chains, dated deltas) → commit the spec edit by itself
  with what + why, before the slice's code. The provenance pin stays as the sole in-text annotation
  (invariant 7, `fold_check`); a retired clause-ID keeps a one-line lifecycle tag stub, body removed
  (invariant 5, `lifecycle-states.md`). Origin: 4x PO law 2026-08-20. Framework docs keep Patch/Amend;
  their Errata mode retires too.
- **Spec form — terse and factual** (`stages/3_spec.md`, `spec-format/README.md` §5, Stage-7 fold,
  DoD): decisions only (rationale/history → changelog item, build contract, commit message);
  structured, not narrative; one fact per line naming the concrete construct; EARS in its shortest form
  (`When X: Y.`, `the system shall` optional where the subject is obvious); no framing prose; the fold
  preserves the draft's form. Measured origin: the 4x Inventory 2.0 draft was 19 % paragraph-words, its
  canonical fold 58 % — the fold re-narrated. Exemplars bound per project (`project-details.md#SPEC-7`).
- **`prose_check` gate** (new, generic, `.ps1` + `.sh`) — measures paragraph-word share and longest
  paragraph per shard; scope = shards changed vs base (`-All` / `--all` for the corpus); warn by default,
  strict on contact via `proseCheck.mode`. Smoke-tested on the 4x corpus (252 shards, both OS scripts
  byte-identical; exemplars pass, 158 legacy shards flag). Closes Stage 3 beside `link_check`; runs
  second in `run_all`; in the INIT smoke test and the config template.

Full record in `constitution.changelog.md`.

## Map to the source practices

| Concept | Mistwright dialect | Polars dialect |
|---------|--------------------|----------------|
| Spec is canon | `spec/section*.html` | `docs/SPECIFICATION.md` |
| Changelog (Mode B / Mode A) | backlog + memory | Jira project POL |
| Persona loop | §8.2 persona protocol | `PERSONA_PROTOCOL.md` + `persona_gate.sh` |
| Traceability | `CB.##` acceptance clauses | AC blocks + ship SHA |
| Parallel dispatch | worktree workers | `PARALLEL_DISPATCH.md` |
| Spec shards (content-only) | `.body.md` fragments (compiled to HTML) | per-section spec docs |

Same method, two dialects. This framework is the merged, reusable form.
