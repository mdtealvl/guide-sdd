# Constitution — amendment log

Append-only. `constitution.md` holds **current-state invariants only**; every change to it is
recorded here with a provenance pin. This dogfoods invariant 7: the changelog is the event log,
kept separate from the materialized current state.

**Rules for changing the constitution.** The ten invariants change only by **Amend**, rarely, and
only when a real project surfaces a gap — never big-bang. Removing an invariant requires an explicit
PM decision recorded here as an **Errata** with a one-line reason. Adding ceremony requires naming
the drift class it catches (invariant 2). Operational detail belongs in a stage file or the Project
Details, not in the constitution. See `README.md` § "Evolving the standard."

---

## v1.1 — worker box surface-back + DoD reference (per SDD-amend-v1.1, 2026-06-24)

Invariant 10 extended: an ambiguity a **worker box** hits is surfaced to the changelog item, never
resolved locally or by patching the spec (`box-roles.md`); "Done" is the Definition of Done
(`definition-of-done.md`). New demand-loaded spine docs: `box-roles.md`, `changelog-conventions.md`,
`definition-of-done.md`. Still ten invariants.

## v1.2 — brownfield gaps + lifecycle states + PowerShell/Bash gates (per SDD-amend-v1.2, 2026-06-24)

Invariant 1 extended: an absent spec for a behaviour you must touch is itself a spec gap —
reconstruct the slice or flag it (`greenfield-vs-brownfield.md`), never infer from code and run
roughshod. Invariant 8 extended: retire anything (clause/doc/config/flag) with an explicit lifecycle
state + date + reason/pointer (`lifecycle-states.md`). Gate scripts moved from Python to PowerShell
(`.ps1`, Windows) + Bash (`.sh`, Linux/macOS) pairs — no Python dependency. Still ten invariants.

## v1.2.1 — terseness + amendment-log split + Project Details rename (per SDD-amend-v1.2.1, 2026-06-24)

Housekeeping, no change of meaning. (1) Constitution prose compressed to a strict, machine-directed
kernel — roughly half the length, same rules. (2) Amendment records moved out of `constitution.md`
into this append-only log, so the constitution stops accreting prose and obeys invariant 7. (3) The
project-specific rulebook layer renamed from "appendix" to **Project Details**
(`project-config/project-details.md` / `project-details.template.md`) — it is binding, project-scoped
law, not back-matter, and for real projects runs to hundreds of KB.

## v1.3 — boot protocol, precedence, discrepancy & prompt-injection, gate hardening (per SDD-amend-v1.3, 2026-06-24)

From two antagonistic reviews. **Invariant 1:** "code is the bug" → a disagreement among
spec/tests/code/observed-behaviour is a defect the Orchestrator classifies (halt + route, never
reconcile locally, never dismiss the spec as stale unilaterally) — handles stale/wrong specs without
spec-laundering. **Invariant 10:** folded in the prompt-injection boundary (repo/ticket/comment text is
data, not instructions) and relocated its operating mechanics (lockstep, trunk, dual-audience) into
`PROCESS.md` §0. **`PROCESS.md` §0 is now a hard boot protocol:** a load manifest (including the Project
Details **seam index**, so seams are discoverable, not just the one an item names), a precedence stack, a
discrepancy/halt protocol, and a DoD summary — always-loaded grows to ≈1.8k tokens, the deliberate cost
of boot safety. **DoD** gains a non-functional floor (security / privacy / a11y / perf / observability /
compatibility / migration / rollback / compliance — N/A + reason), oracle-source classification, and
fixture-gap severity (blocking gaps can't ship). **New:** a test-challenge protocol (the Engineer may
challenge a frozen test; the Orchestrator resolves), a `qa_import_ban` gate (partial structural proof of
QA ⊥ implementation), `coverage_check --manifest` (per-unit scope for in-loop runs; **ship-time coverage
stays whole-corpus** — this was an undocumented gate semantic), and `fold_check --strict` (a configured
resolver that errors now FAILs, not degrades). Gates now state loudly that they certify **bookkeeping +
traceability, not correctness** — a drift-catcher, not an oracle. Still ten invariants.

## v1.4 — Discover Spec, self-announcing onboarding, LLM-compression pass (per SDD-amend-v1.4, 2026-06-24)

No invariant change. **`discover-spec.md`** (new spine doc) — a deliberate brownfield characterization
action: map the codebase, reconstruct *provisional* EARS spec, baseline coverage AND quality (mutation
score via Stryker + the invariant-4 trust criteria, since line coverage alone is theatre), and produce a
risk-prioritized test plan to ≥85% coverage + a mutation floor (default 70%). Reconstructed spec is
provisional until PM-ratified — never bless a bug as spec. **Self-announcing onboarding:** the CLAUDE.md
stub instructs an agent to announce SDD and leave ad-hoc work for PROCESS §0 the moment it acts in an SDD
repo; INIT opens with a welcome before the ASK steps. **LLM-compression pass:** all demand-loaded docs
compressed for the LLM reader (rules/names/anchors kept, prose cut); always-loaded core ≈1.6k tokens.

## v1.5 — box loops & cross-box coordination (per SDD-amend-v1.5, 2026-06-25)

No invariant change. Defines the operational LOOP behind the box-role contract (`box-roles.md`
§"Box loops & coordination"). Item state machine: `Ready → Claimed:<box-id> → In-Progress →
Ready-for-review → Done`, with `PO-attention` as the surface-back exit. **Claim:** a worker stamps
`claimed-by:<SDD_BOX_ID>` (Jira comment / backlog tag) before starting, only on an unclaimed Ready
item; first claim wins. **Worker loop** (~15–30 min): poll for the oldest unclaimed Ready item →
claim → run to gates-green → flag `Ready-for-review` (never merge); idle = do nothing. **PO loop**
(~30 min): resolve `PO-attention` surface-backs, review + serialized-merge `Ready-for-review` items,
intake new work. **Cross-box merge serialization:** workers never merge — the PO box owns the merge +
the (cross-box-fresh) Validation; solo deployment runs both inline at Stage 7. New per-box identity
`SDD_BOX_ID` stamps claims. New states bound in Project Details §4: CL-9 (Claim), CL-10 (Ready-for-review).

## v1.6 — cross-agent host-adapter layer + AGENTS.md carrier (per SDD-amend-v1.6, 2026-07-09)

No invariant change; still ten. Makes SDD **agent-neutral** without touching the method or the install
pattern (no package manager, no build step). The always-loaded core was already a **pointer stub**, not a
Claude-specific mechanism, so this is an extraction, not a rewrite. **New spine doc `host-adapter.md`** —
the third axis beside the spine and `project-details.md`. The spine now speaks in three **load-verbs**
(always-load · demand-load · scoped sub-agent); `host-adapter.md` is the one place agent tools are named
and binds each verb to a host mechanism. Only *scoped sub-agent* varies — that variance is the
**capability tier** (A real sub-agents / B fresh sessions / C single context). **New carrier `AGENTS.md`**
(canonical stub, read natively by Codex / Cursor / Gemini); `CLAUDE.md` becomes a one-line router
(`@AGENTS.md`, physical injection = Tier A); `.github/copilot-instructions.md` is a shim for Copilot
(which doesn't read `AGENTS.md`). **`PROCESS.md` §0 persona route** now reads `$SDD_HOST_TIER`: Tier A runs
the loop as scoped sub-agents, Tier B as fresh sessions (the `test_edit_ban` + `qa_import_ban` gates still
enforce QA⊥Engineer **structurally** — the reason SDD degrades more gracefully across agents than a
pure-prompt method), Tier C is Mechanical-lane-only. **Host-neutralized** the ~17 Claude-specific
references across the spine (constitution note, `PROCESS.md` §0, `README.md`, `INIT.md`, `START_HERE.md`,
`box-roles.md`, `gates/README.md`, `welcome.html`) to the load-verbs. Gates unchanged — already
host-agnostic. INIT §1 rewritten to wire the carrier(s) + stamp the tier.

## v1.7 — session/context lifecycle, token-admission, lane reconciliation (per SDD-amend-v1.7, 2026-07-14)

No invariant change; still ten. Ratifies five proposals from the Mistwright/4x `d224` arc (staged in
`project-config/PROPOSED_CHANGELOG.md`, SDD-PROP-01..05) — a **session** lifecycle complementing the
**item** lifecycle. **New spine doc `session-lifecycle.md`** (demand-loaded): externalize a volatile
context before it clears — the wrap-at-close pass, the overwrite-only HANDOFF card, stash/unstash, the
unambiguous-close auto-wrap trigger, interrupt triage; Tier-A impl = bundled `commands/`
(`/wrap`,`/stash`,`/unstash`), registered in `host-adapter.md`, Tier-B/C run by hand. **Token-admission
standing rule** in `PROCESS.md` §0 (one terse line — filter at source · ~5-call quarantine ·
compute-don't-deliberate; the tool-output complement to spec demand-loading; placement fork resolved to
§0 to keep it always-in-force, kept to one line to bound core growth). **Agent-lane reconciliation**: a
new DoD item + §0 DoD-summary line — every dispatched lane carries LANDED(hash)/DIED before Done or a
session boundary (*existence ≠ landed*; cost the origin two lost fixes). **Wire-canary**: a DoD item +
Stage-5 QA rule + a `gates/README.md` recipe for the representative-default dead-wire trap; the full
callers-count check needs an `any_match` engine kind — deferred as a smoke-tested follow-up, not shipped
untested (an unrun gate isn't trustworthy). **Memory-dir seeding**: new INIT step (`INIT.md` §2c) +
Project Details `#CL-11` bind the per-project memory directory; contents stay per-project by design.

## v1.8 — dispatch frugality: sub-agent token-budget discipline (per SDD-amend-v1.8, 2026-09-01)

No invariant change; still ten. Ratifies SDD-PROP-07 from the Mistwright/4x MW-234/S35 arc (staged in
`project-config/PROPOSED_CHANGELOG.md`), PO-directed 2026-08-31 after measurement showed sub-agents
routinely consuming 300-450k+ tokens per dispatch. Root causes (measured): unfiltered build/test output
re-sent as context on every subsequent sub-agent turn (the dominant cost — tool-call COUNT is the
multiplier); off-brief full-suite runs; whole-file reads where a range was pinned; unbriefed gate
reruns. **New §0 standing rule "Dispatch frugally"**: the v1.7 token-admission rule binds dispatched
contexts too, and the DISPATCHER enforces it in the brief — output-filtered gate commands (summary +
failure names, never raw logs), exact run counts (deciding suite = Orchestrator's alone), pinned read
RANGES (grep beyond them), no background processes/waits a turn won't outlive, resume-over-redispatch
(origin measurement: ~81k/wave resumed vs ~350k fresh — a resumed agent's cumulative counter LOOKS
expensive but its marginals are the cheapest waves in the system). Project-side bindings (gate-command
idioms, build-noise suppression at the repo level) live in each project's `project-details.md` TOOL-
section, not the spine.

## v1.9 — one spec-edit method + terse factual spec form (per SDD-amend-v1.9, 2026-09-02)

No invariant change; still ten. Ratifies SDD-PROP-08 and SDD-PROP-09 (staged in
`project-config/PROPOSED_CHANGELOG.md`), PO-directed 2026-09-02; both target **spec bloat** — history
strata that hide the current law, and narrative prose paid for on every demand-load. **One update
method** (`stages/3_spec.md`, replacing the Patch/Amend/Errata modes for canonical spec text; origin
4x PO law 2026-08-20): negotiate the exact text with the PO → replace wholesale (no Errata blocks,
in-page addenda, DECISION/ruling brackets, strike-throughs, SUPERSEDED/CORRECTED chains, dated deltas;
the shard always reads as current ground truth) → commit the spec edit by itself with what + why,
before the slice's code commits. Reconciled with the spine: the provenance pin `(§X per <unit-id>,
date)` remains the sole in-text annotation, overwritten never chained (invariant 7, `fold_check`); a
retired clause-ID keeps a one-line lifecycle tag at its anchor with the body removed (invariant 5;
`lifecycle-states.md`, `spec-format/README.md` §4 updated); "own commit" precedes the code within the
same slice (spec-first + lockstep). Framework self-evolution keeps Patch/Amend (README amendment blocks
+ this log are its history); its Errata mode retires (`README.md` C3c, `PROCESS.md` §"Improving",
`changelog-conventions.md` production-lessons line). **Spec form — terse and factual** (rule block in
`stages/3_spec.md` §"Writing the clauses" + exit criterion; `spec-format/README.md` §1/§5/§9;
`stages/7_ship.md` fold step 1; `definition-of-done.md` fold item): decisions only — rationale,
alternatives, measurements, history go to the changelog item / build contract / commit message;
structured, not narrative (lists, tables, code blocks; a paragraph only where a rule cannot be a line);
one fact per line naming the concrete construct; EARS semantics in the shortest form (`When X: Y.`;
`the system shall` optional where the subject is obvious — PO fork resolved 2026-09-02); no framing
prose; **the fold preserves form**. Measured origin (4x, words in list/table/code vs paragraph
elements): `Inventory_Spec_2.0.md` 19 % paragraph-words vs its canonical fold `section5x` 58 % — the
fold re-narrated; legacy shards 40–60 %. Exemplars bound per project via new Project Details `SPEC-7`;
new `TOOL-6` template row binds the v1.8 quiet-gate idioms. v1.8 housekeeping folded here: `PROCESS.md`
§0 "Dispatch frugally" shortened and given its freshness caveat (resume never overrides invariant 3),
header token count re-measured, README v1.8 + v1.9 amendment blocks added. **New generic gate
`prose_check`** (`gates/prose_check.ps1` + `.sh`, behaviour-identical; PO-directed same day, 4x as the
test bed): per shard, paragraph-word share and longest paragraph (HTML: `<p>` vs list / table / code /
heading elements; Markdown: line classes with list-continuation); scope = shards changed vs base like
`fold_check`, `-All` / `--all` for the corpus; `proseCheck.mode` warn (default) | strict | off, `-Strict`
forwarded by `run_all`; defaults share ≤ 35 %, paragraph ≤ 100 words, share applies at ≥ 120 words.
Smoke-tested 2026-09-02 on a synthetic fixture (prose / structured / nested / BOM / excluded / strict /
bad-base / off) and read-only on the 4x corpus (252 shards; both scripts byte-identical): exemplars
15 % / 71w and 23 % / 87w pass; 158 legacy shards flag; the Combat 2.0 canonical fold measures 26–94 %
share with paragraphs to 381 words against the draft's 23 % / 87w — the fold re-narration, now caught
mechanically. Runs second in `run_all`, closes Stage 3 beside `link_check`, added to the INIT smoke test
and the config template.

## v1.10.0 — GUIDE SDD rebrand + distribution phase 1: repo, CI, release automation (per SDD-amend-v1.10.0, 2026-09-02)

- **Name.** Framework renamed **GUIDE SDD** — Gated, Unified, Intent-Driven Engineering, a spec-driven
  development method. Display `GUIDE`; slug `guide-sdd`; internal short name `sdd` unchanged (spine dir,
  `SDD_*` env vars, `SDD-PROP` / `SDD-amend` IDs), so adopting repos rename nothing. Why: "SDD" is the
  field's generic term (field survey 2026-09-02). Touched: README (§Name), START_HERE, the three carriers,
  INIT welcome line, welcome.html title/hero.
- **Versioning.** Three-part `vX.Y.Z` from here. `VERSION` at the repo root is the stamp of record;
  `ci/version_check.sh` requires README header, changelog tail heading, `VERSION`, the plugin manifest
  (when present) and the release tag to agree.
- **Repo.** `github.com/mdtealvl/guide-sdd` (private until the PO flips it). `.gitignore`: box-role.local,
  settings.local.json, `*.zip`, `dist/`. `.gitattributes`: LF everywhere (bash gates on Windows checkouts).
- **CI** (`.github/workflows/ci.yml`). `ci/smoke.sh` and `ci/smoke.ps1` reproduce INIT §6 on a throwaway
  copy of the spine: four generic gates PASS, negative control FAILs naming `DEMO.2`, revert, `run_all HEAD`
  clean. Ubuntu runs the sh gates with every ps1 twin compared (same exit code required, output diff
  reported); Windows runs the ps1 gates.
- **Release** (`.github/workflows/release.yml`). Tag `vX.Y.Z` → version check → smoke → `guide-sdd-X.Y.Z.zip`
  (`sdd/` prefix; excludes workflows, `ci/`, `plugin/`, `PROPOSED_CHANGELOG.md`) + sha256 → GitHub Release
  with this changelog section as notes. Retires the hand-built `sdd.zip`.
- **Gate fix.** `test_edit_ban.ps1` now takes the config positionally (`HEAD gates/gates.config.json`) as
  INIT §6 documents and as the `.sh` twin already did. Found by the first parity run.
- **Installer pair** (`install.sh` / `install.ps1`; SDD-PROP-10 phase 2). Verbs `install | update | doctor`;
  flags `--version`, `--dest`, `--carriers`, `--commands`, `--source`, `--repo`, `--force`. Writes
  `sdd/.sdd-manifest.json` (version + per-file sha256, CR-stripped so a CRLF checkout is not drift). Never
  touches the project surface, never deletes, stops before INIT's ASKs; `update` refuses on a dirty tree or
  locally edited spine files; a pre-manifest mirror is adopted with `install --force`. Twins verified
  byte-identical over a 14-step scenario including a copy of the 4x mirror (project files untouched).
- **POSIX fix.** `coverage_check.sh` and `fold_check.sh` used bash process substitution; `sh` is dash on
  Debian/Ubuntu, so INIT §6's `sh gates/…` failed there. Rewritten with awk. Found by the new ubuntu job.
- **Proposal.** SDD-PROP-10 phases 0–2 done; 3 (Claude Code plugin) and 4 (docs, license, public) open.

## v1.11.0 — Claude Code plugin + marketplace; persona edit-guard (per SDD-amend-v1.11.0, 2026-09-02)

- **Plugin** `plugin/` (name `guide-sdd`, version = `VERSION`); marketplace `.claude-plugin/marketplace.json`
  at the repo root (source `./plugin`). Install: `/plugin marketplace add mdtealvl/guide-sdd` →
  `/plugin install guide-sdd@guide-sdd`. Host affordances only: the vendored spine stays canonical and
  works without the plugin (SDD-PROP-10 phase 3).
- **Skills.** `sdd-init` (bundled installer, then INIT from §1a — the ASKs stay human), `sdd-update`,
  `sdd-doctor`, `sdd-gates` (run_all, verdict lines only — dispatch frugality), `sdd-persona` (marker
  `sdd/.persona`), and `wrap` / `stash` / `unstash` generated from `commands/*.md`, which remain the source
  for non-plugin hosts.
- **Hook** `plugin/hooks/persona-guard.sh` — PreToolUse on Edit|Write|MultiEdit. Persona `engineer` (env
  `SDD_PERSONA`, else `sdd/.persona`) → any edit to a path matching `gates.config.json` `testGlobs` is
  denied (exit 2) with the reason: test_edit_ban at edit time, not only at gate time (invariant 3). Runs
  under `sh` (Git Bash on Windows). Unit-tested by `ci/hook_test.sh` (10 cases, incl. Windows-escaped paths).
- **CI.** Hook unit test; `claude plugin validate --strict` on plugin and marketplace; `plugin/bin/install.*`
  must be byte-identical to the root installers.
- **Proposal.** SDD-PROP-10 phases 0–3 done. Phase 4 open: docs refresh (`welcome.html` still at v1.5,
  `host-adapter.md` plugin row, Stage 6 persona-marker note), `LICENSE`, visibility — the last two are PO
  decisions D1/D2.

## v1.11.1 — MIT license (per SDD-amend-v1.11.1, 2026-09-02)

- **License.** `LICENSE` added: MIT, © 2026 Voyager Labs (PO decision D2). Same license as 11 of the 12
  comparable frameworks surveyed 2026-09-02. `plugin.json` gains `"license": "MIT"`; README §Name and
  `plugin/README.md` state it. A README note asks forks to use a different name.
- **Proposal.** SDD-PROP-10: only D1 (visibility) remains open.
