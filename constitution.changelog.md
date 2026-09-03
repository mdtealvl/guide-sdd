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

## v1.12.0 — Enforcement hardening, intake, review loop, autonomy vocabulary (per SDD-amend-v1.12.0, 2026-09-02)

Origin: five adversarial reviews of the spine against BMAD v6.11.0 (enforcement holes, pre-spec zone,
review loop, autonomy + evidence, context economy), triaged per `stages/7_ship.md` §3 and filed as
SDD-PROP-11. No invariant changes; ten remain. Every doc change is demand-loaded; always-loaded text grew
by one sentence (`AGENTS.md`, the unresolved-placeholder note).

- **`test_edit_ban` rewritten (sh + ps1).** Diffs the QA-frozen base against the **working tree** —
  committed, staged, unstaged and untracked, `--no-renames` so a test moved out of a test path shows as a
  delete. FAILs when anything under the gate directory (config, scripts; `.frozen` may be added) differs from
  the base. Base = argument, else `gates/.frozen`, else config `baseRef` with a WARN that a branch name can be
  advanced; the base must resolve **and** be an ancestor of HEAD (exit 2). One glob dialect for the whole bank
  (`**` spans directories, `*` does not, root-anchored) — the old fnmatch translator is no longer used. Trust
  boundary stated in the script header: the authoritative SHA is the item's `frozen:` line; the file and the
  hook are tripwires. Closes the bypasses the enforcement review verified: uncommitted edit, movable base,
  config edit, rename-out, glob drift.
- **`gates/freeze.*` (new helper).** Stage 5 exit: refuses a dirty tree, writes `gates/.frozen`
  (`sha=`, `date=`, `unit=`), prints the `frozen:` line for the item and the commit command.
- **`run_all` (sh + ps1).** Runs from the **project root** (git top-level; `projectRoot` config override) so a
  spine vendored at `sdd/` resolves root-relative globs — the documented layout was broken before. `suiteCmd`
  unset ⇒ **exit 2**, never a skipped-and-passed bank.
- **`coverage_check` (sh + ps1).** `testTagExcludeGlobs` (default `**/*.md`, `**/*.txt`): a tag in a notes file
  under `tests/` no longer counts. WARN line naming any tagged file with skip/only markers.
- **`qa_import_ban` templates.** Empty `qaImportRules` ⇒ exit 2 (a copied-in gate certified nothing).
- **Config template.** `testGlobs` now lists test infrastructure (`**/__tests__/**`, `**/__mocks__/**`,
  `**/*.snap`, `**/jest.config.*`, `**/vitest.config.*`, `**/pytest.ini`, `**/conftest.py`) and nested test
  dirs (`**/tests/**`); `testTagExcludeGlobs`; comments state root-relative paths and the frozen-SHA rule.
- **Plugin hook — three passes** (`plugin/hooks/persona-guard.sh --pre|--post|--stop`, `hooks.json`).
  *pre* (PreToolUse on Edit/Write/MultiEdit/NotebookEdit/Read/Grep/Glob): `engineer` may not edit
  `testGlobs` paths, the gate bank, `.persona` or `.frozen`, and is refused **all** edits when the config is
  unreadable (fail closed); `qa` may not Read/Grep/Glob under `paths.code`. *post* (PostToolUse on
  Bash/Edit/Write/MultiEdit/NotebookEdit) and *stop*: `engineer` gets a working-tree sweep (status + diff vs
  `.frozen`) naming any test/gate path that drifted and the revert command — catches heredocs, `sed -i`,
  `mv`, `git checkout`. `ci/hook_test.sh` grows from 10 to 36 cases in a real git repo.
- **CI negative controls.** `ci/smoke.sh` / `ci/smoke.ps1`: tag-in-notes ignored, skip-marker WARN,
  test_edit_ban FAIL on uncommitted edit / untracked test / rename-out / config tamper / non-ancestor base,
  freeze then PASS via `.frozen` then FAIL on a committed edit, `run_all` exit 2 on unset `suiteCmd`; every
  case twinned on pwsh. A spine prose self-check runs warn-only (the spine fails its own form gate; tracked).
  `ci/target-ci.template.yml`: a PR workflow for target repos so the verdicts are consumed.
- **`intake.md` (new, demand-loaded).** Raw request → Ready item: input classes (rich / sparse / mixed / too
  thin), preservation rule, verbatim request kept, one-goal test with `split-from:` / `kept-whole:`, the
  numbered-question loop (re-ask only the missing), five unknown-finding prompts, the domain-implication
  screen over the non-functional categories, CAP-n before AC-n, and the PO's readiness verdict.
- **`changelog-conventions.md`.** Body gains Verbatim request, Why (force + who + why-now), Success signal,
  Boundaries (Always / Ask-first / Never), Open questions / Assumptions; Bug intake shape; `CAP-n` pre-Ready;
  §6 becomes the **item lines** with a fixed reason enum: `[NEEDS-PO:<reason>]`, `[BLOCKED:<reason>]`,
  `[DEFER] … — evidence:`, `frozen:`, `validated: <base>..<head> accept|decline`, `lesson:`.
- **`definition-of-done.md`.** DoR adds verbatim request, measurable success signal, open questions empty +
  assumptions ratified, boundaries, the non-functional screen, and the **readiness verdict** (PASS /
  CONCERNS / FAIL — "could a worker implement this without inventing a decision nothing records?"). DoD adds
  the `frozen:` SHA + working-tree ban, the four-lens `validated:` line, and deferred-not-fixed.
- **`stages/7_ship.md` rewritten.** Validation brief (HANDED / NOT HANDED / output schema); four lenses —
  conformance, **hunt** (second fresh context, ≥10 findings, "what is missing", no persona framing),
  verification gap ("if this broke, which test fails — read it"), intent alignment against the verbatim
  request; the Orchestrator judges findings independently, assigns severity by consequence, scores (any
  high ⇒ decline; `3×medium + low ≥ 5` ⇒ one more fresh pass); **class routing table** — `spec` writes
  `KEEP:`/`AVOID:` and **resets to the frozen SHA** before Stage 3/5/6 re-derive, `test` → 5, `code` → 6,
  `migration` → 2, `intentional-legacy` → 3, `out-of-range` → `[DEFER]`; `validation-pass:` cap of three then
  `[BLOCKED:non-convergence]`; one `lesson:` per decline; merge policy table.
- **`box-roles.md`.** Item state machine drawn with `Rework:<class>`; terminal states a worker may leave
  (`Ready-for-review`, `PO-attention`, `Died:<gate>`); claim **lease** (default 2× cadence, renewed per loop,
  expired claims reclaimable); gate-fix loop capped at three; PO loop reads open `lesson:` and `[DEFER]` lines
  at intake; Ask-first boundaries are pre-declared `[NEEDS-PO:fork]` triggers.
- **`metrics.md` (new).** Five outcome metrics (first-pass acceptance, surface-backs by reason, test
  challenges by resolution, post-ship defects in 30 days, route share + re-triage), each from an artifact the
  method already writes; how to read them; what they do not claim.
- **Stages 0, 1, 5, 6.** Stage 0: "is it an item yet?" → `intake.md`; **Q0 one goal** before Q1/Q2. Stage 1:
  the unknown-finding pass; CAP → constants. Stage 5: QA read-guard note; **freeze** as a closing step with
  the `frozen:` line. Stage 6: the three-pass hook, test infrastructure in the ban, gate reads `.frozen`.
  Every stage tail now says "read the next stage file fully and follow it" instead of "drop this body from
  context" (an instruction no LLM can execute); inline gate commands no longer point at `gates/README.md`.
- **Context fixes.** `CLAUDE.md` `@`-imports `sdd/constitution.md` — the constitution was pointed at, not
  injected. `AGENTS.md` says what to do when the `$SDD_…` placeholders are still literal. `PROCESS.md`: the
  whole file is §0 (the old "read §0 then stop" sent the reader past §0 for the stage index); the
  maintainer-only section is two lines; demand-loaded list gains `intake.md` and `metrics.md`; the undefined
  "adversarial verify" persona is now the Stage-7 hunt pass; defects route per §3. **Backlog layout
  contradiction resolved:** Mode B is one file per item under `backlog/` at the repo root (`#CL-1`, what
  `fold_check` resolves); `session-lifecycle.md`, `commands/wrap.md` (+ the wrap skill), `commands/README.md`,
  INIT and `#CL-11` no longer describe a single `backlog.md` in the memory dir. `commands/README.md` no longer
  calls v1.7 content "proposed". `gates/README.md` documents the frozen-SHA trust boundary, the root cwd, the
  mandatory suite, the new keys, and the negative-control rule for gate authors.
- **Deferred (SDD-PROP-11 phase 2), listed so no one mistakes them for done:** a JUnit/TRX-based
  `coverage_ran` gate; a machine-readable item-status script and event hooks for an unattended
  orchestrator; `ci/evidence.*` to compute `metrics.md`; the spine meeting its own `prose_check` bar; a
  rendered single-file mechanical lane and persona briefs; a Bash read-guard for the `qa` persona; recording
  the route on a committed artifact so `--mechanical` is not the agent's say-so; PROP-06 `any_match`.
