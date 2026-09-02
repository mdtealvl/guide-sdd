# Proposed changelog — SDD self-evolution (staging)

> **Status: RATIFIED & IMPLEMENTED in v1.7 (SDD-amend-v1.7, 2026-07-14).** All five were PM-approved and
> folded into canon; this doc is retained as the origin record (per `lifecycle-states.md` — retire with a
> state + pointer, never silent-delete). Where each landed:
> - **PROP-01** → `session-lifecycle.md` (new spine doc) + `host-adapter.md` capability + `PROCESS.md` §0
>   demand-loaded list + `commands/` (Tier-A impl).
> - **PROP-02** → `PROCESS.md` §0 standing rule "Admit tool output frugally" (placement fork resolved: §0,
>   one terse line).
> - **PROP-03** → `definition-of-done.md` (lane-reconciliation item) + `PROCESS.md` §0 DoD summary.
> - **PROP-04** → `definition-of-done.md` (wire-canary) + `stages/5_qa.md` (QA rule) + `gates/README.md`
>   (dead-wire recipe). *Deferred:* the `any_match` callers-count gate kind — smoke-tested follow-up.
> - **PROP-05** → `project-config/INIT.md` §2c + Project Details `#CL-11`.
> - **PROP-07** → v1.8 (`PROCESS.md` §0 "Dispatch frugally"). **PROP-08 / PROP-09** → v1.9 (`stages/3_spec.md`
>   update method + spec form, and the docs each names). **PROP-06** remains OPEN. **PROP-10** (installer
> & distribution) OPEN, phase 0 done 2026-09-02.
>
> Full record: `constitution.changelog.md` v1.7. Original proposal bodies preserved below.

---

## SDD-PROP-01 — Story — Add a session/context-lifecycle module

- **Context / why.** SDD governs the *item* lifecycle (Ready → Done) but has nothing for the *session*
  lifecycle. A long agent context accumulates state (agent lanes, rulings, spec debt) that a `/clear`
  destroys unless externalized. The 4x project converged on: a wrap-at-close ritual, a single
  **overwrite-only** HANDOFF "you are here" card, stash/unstash task-freezing, an **auto-wrap trigger**
  gated on *unambiguous* close, and **interrupt triage** (sidebar / sub-agent / stash).
- **The change.** A demand-loaded spine doc (e.g. `session-lifecycle.md`) defining the ritual in
  agent-neutral load-verbs, registered in `host-adapter.md` as a **Tier-A capability** whose Claude-native
  implementation is the already-bundled `commands/` (`/wrap`, `/stash`, `/unstash`), with a Tier-B/C
  manually-run fallback.
- **Non-goals.** Does not replace the item lifecycle; does not hard-code a memory-dir path (→ PROP-05);
  does not add a script gate.
- **Dependencies & links.** Consumes `sdd/commands/` (shipped); edits `host-adapter.md` (register
  capability); pairs with PROP-03 (lane reconciliation is wrap step 1) and PROP-05 (memory dir). Spec
  authored in Stage 3.
- **Right-size route.** `persona` (spine + host-adapter, design-bearing) — PM approves Stage 1/3. **5 pts.**

ACs:
```
SDD-PROP-01/AC-1 — When a session reaches an unambiguous close, the system shall externalize all
                   durable state (lane verdicts, working tree, backlog, memories, spec debt, HANDOFF)
                   before the context is cleared.
SDD-PROP-01/AC-2 — The HANDOFF card shall be overwritten wholesale on each wrap, never appended;
                   session history lives in the backlog, not the card.
SDD-PROP-01/AC-3 — Where the host lacks slash-commands, the system shall provide the identical ritual
                   as a manually-run procedure (Tier-B/C fallback).
```

---

## SDD-PROP-02 — Task — Add a token-admission standing rule

- **Context / why.** Demand-loading governs what *spec* enters context; nothing governs what *tool
  output* enters. Unfiltered reads / verbose command output flood context and degrade the session — the
  complement to demand-loading.
- **The change.** One paragraph of standing rule: **filter at source** (never dump raw output you can
  scope), a **>~5-call quarantine threshold** (repeated exploratory calls get summarized, not accreted),
  and **compute-don't-deliberate** (derive the answer, don't re-reason over dumped text).
- **Non-goals.** No new gate; no change to spec-shard demand-loading.
- **Dependencies & links.** `PROCESS.md` standing rules. **Open fork for PM:** the blurb says "standing
  rules" (always-loaded §0), but §0 is deliberately ~1.2k tokens — placing it there grows the always-loaded
  core. Alternative: a one-line §0 pointer + the paragraph in a demand-loaded doc. PM picks.
- **Right-size route.** `mechanical` (one doc, no behaviour change), but a §0 edit → PM sanity-check. **1 pt.**

---

## SDD-PROP-03 — Task — Add agent-lane reconciliation to the Definition of Done

- **Context / why.** Dispatched sub-agent lanes get orphaned at a session/context boundary — *"an agent
  was working on it" is not evidence the work landed.* This cost the origin project **two lost fixes**
  before the rule was learned. It is the session-level form of invariant 10 (artifacts over narratives).
- **The change.** DoD gains an item: before a unit is Done (and before any session close), **every**
  dispatched lane carries a verdict **LANDED(commit-hash)** or **DIED(re-queued with failure guidance)** —
  no lane left "in flight" across a boundary.
- **Non-goals.** Does not prescribe dispatch mechanics; ships as a checklist item (a mechanical gate could
  follow if the lane ledger is machine-readable).
- **Dependencies & links.** `definition-of-done.md`; overlaps PROP-01 wrap step 1.
- **Right-size route.** `persona` (DoD is load-bearing) — PM approves. **2 pts.**

ACs:
```
SDD-PROP-03/AC-1 — Before a unit is marked Done, the system shall record for each dispatched agent lane
                   a verdict of LANDED with its commit hash, or DIED with re-queue guidance.
```

---

## SDD-PROP-04 — Task — Add the representative-default dead-wire gate + wire-canary policy

- **Context / why.** Two gate-worthy traps from the arc. (a) **Representative-default dead-wire:** a
  convenience overload that *defaults a behaviour-arm parameter* makes every arm dead in production while
  arm-explicit tests stay green — silent, and **grep-able** (grep the callers for the defaulted arm). (b)
  **Wire-canary:** a test asserting the production wiring path is actually exercised prevents the class;
  confirm SDD carries it, else add it.
- **The change.** A project-gate template (grep-the-callers rule catching behaviour-arm params defaulted
  at all call sites — `must_not_match` / `pair_requires` shape per `gates/README.md`) + a wire-canary line
  in QA/DoD guidance.
- **Non-goals.** Does not replace human review; the gate certifies **bookkeeping, not correctness**
  (`gates/README.md`).
- **Dependencies & links.** `gates/` (+ config schema); `gates/README.md`; `stages/5_qa.md` /
  `definition-of-done.md` (wire-canary). May split into 04a (gate) / 04b (canary) at triage.
- **Right-size route.** `mechanical` for the gate template; `persona` for the QA/DoD wording. **3 pts.**

---

## SDD-PROP-05 — Task — Seed the project memory directory at INIT

- **Context / why.** The session-lifecycle commands (PROP-01) assume a per-project memory directory
  (`MEMORY.md` index, `HANDOFF.md`, `backlog.md`, `stashes/`). Each project currently rediscovers the
  convention; bootstrapping it makes it standard.
- **The change.** `project-config/INIT.md` gains a step that seeds the memory dir — `MEMORY.md` (index
  header), empty `HANDOFF.md`, `backlog.md` (Mode B) or tracker pointer (Mode A), `stashes/` +
  `stashes/archive/`. Path bound in `project-details.md#CL-`.
- **Non-goals.** Does **not** prescribe memory *contents* (per-project by design — trap memories stay
  local); does not change the changelog-mode choice.
- **Dependencies & links.** `project-config/INIT.md`; `project-details.md#CL-`; PROP-01 (consumer).
- **Right-size route.** `mechanical` (INIT doc + template files). **2 pts.**

---

## SDD-PROP-07 — Task — Dispatch frugality: sub-agent token-budget discipline — **RATIFIED & IMPLEMENTED in v1.8 (PO-directed 2026-09-01)**

- **Context / why.** v1.7's token-admission rule (PROP-02) governs what tool output enters *your own*
  context; nothing governed what a DISPATCHED context admits. Measured on the origin project's MW-234/S35
  slice: sub-agents routinely consumed 300–450k+ tokens per dispatch (~4M/slice). Dominant costs, in
  order: unfiltered `dotnet build`/`test` output re-sent as input on every later sub-agent turn (tool-call
  COUNT is the multiplier — 100–165 calls per engineer); off-brief full-suite runs (~6.5k-test listings);
  whole-file reads of 2–4k-line files where a range was known; unbriefed gate reruns (one fact run 9×).
  Counter-signal: a RESUMED agent averaged ~81k/wave over 8 waves vs ~350k for an equivalent fresh
  dispatch — resume is the cheapest pattern and cumulative counters make it LOOK the most expensive.
- **The change.** A §0 standing rule ("Dispatch frugally"): the dispatcher's brief pins output-filtered
  gate commands, exact gate run counts (deciding suite = Orchestrator's alone), read RANGES (grep beyond),
  and bans background processes/waits the agent's turn won't outlive; prefer resume over re-dispatch.
  Project bindings (concrete filter idioms, repo-level build-noise suppression) go to `project-details.md`
  TOOL-.
- **Non-goals.** No new gate; does not change the persona loop's shape (blind QA / adversarial verify /
  fresh Validation earn their cost — the waste was plumbing, not process).
- **Dependencies & links.** `PROCESS.md` §0 (extends PROP-02's rule); origin record: 4x memory
  `feedback_subagent_token_budget_discipline.md` + `feedback_subagent_orphaned_test_runs.md` (the
  background-run death loop this also fences).
- **Right-size route.** `persona` (a §0 edit) — PO approved verbally 2026-08-31/09-01. **1 pt.**

ACs:
```
SDD-PROP-07/AC-1 — Every sub-agent brief shall pin gate commands whose output is filtered at source to
                   a summary line plus failure names, and the exact number of times each gate runs.
SDD-PROP-07/AC-2 — A sub-agent shall not launch background processes or waits that do not complete
                   within its own turn; the deciding full suite runs only in the Orchestrator's context.
SDD-PROP-07/AC-3 — When follow-up work targets an agent whose context is still live, the dispatcher
                   shall resume that agent rather than dispatch a fresh one, absent a blindness/freshness
                   requirement to the contrary.
```

---

## SDD-PROP-06 — Task — Add an `any_match` rule kind for the callers-count dead-wire gate — **OPEN (deferred from v1.7)**

- **Context / why.** PROP-04 shipped the dead-wire trap as a wire-canary (DoD/QA) + a `must_not_match`
  guard + a documented recipe. The *precise* mechanical predicate — "≥1 caller in `<glob>` passes the
  behaviour-arm explicitly" — is an **`any_match`** semantic the rule engine's four kinds
  (`must_match`/`must_not_match`/`file_exists`/`pair_requires`) do not express. It was **not** shipped in
  v1.7 because adding it means editing the shared `_rules.ps1`/`_rules.sh` engine, which **cannot be
  smoke-tested in this framework dir** (no working shell/git here) — and an unrun gate is not trustworthy.
- **The change.** Add `any_match` (passes when ≥1 file in `paths` matches `pattern`) to `_rules.*`, both
  OS scripts behaviour-identical; document it in `gates/README.md`'s kind table; add the dead-wire
  callers-check as a worked example.
- **Non-goals.** Does not replace the wire-canary (a suite test proves behaviour; a gate proves text).
- **Dependencies & links.** `gates/_rules.ps1` + `_rules.sh`; `gates/README.md`. **Must be authored and
  INIT-smoke-tested in a live repo**, not statically.
- **Right-size route.** `mechanical`, but engine code → smoke test mandatory. **2 pts.**

---

## SDD-PROP-08 — Task — One spec-edit method: negotiate → replace wholesale → commit solo — **RATIFIED & IMPLEMENTED in v1.9 (PO-directed 2026-09-02)**

- **Context / why.** Origin: 4x commit `6a7944db` (spec §0 §5.1 / §5.3 / §9; project-details SPEC-4/5),
  PO law 2026-08-20. Layered Errata blocks, in-page addenda, DECISION/ruling brackets, strike-throughs and
  SUPERSEDED chains compound until an implementer cannot tell what the current law is — **spec bloat
  becomes spec collapse**. Every demand-load of such a shard also pays tokens for dead text. The spine's
  own Errata mode (`~~old~~ → new` inside the shard) keeps history inside the current-state projection,
  which invariant 7 says belongs in the changelog. Field-tested in 4x since 2026-08-20 (S37–S39 shipped).
- **The change.** Replace Stage 3's "three update modes" with ONE method for canonical spec text:
  **(1) negotiate** the exact inserted / removed / updated text and its location with the PO;
  **(2) replace wholesale** — no Errata blocks, in-page addenda, DECISION/ruling brackets,
  strike-throughs, SUPERSEDED/CORRECTED chains, or dated deltas; the shard always reads as current
  ground truth; **(3) commit the spec edit by itself**, message = what + why; history lives in git and
  the changelog item. Three reconciliations with the spine as written: **(a)** the provenance pin
  `(§X per <unit-id>, YYYY-MM-DD)` stays as the SOLE in-text annotation — overwritten on each change,
  never chained (invariant 7, `fold_check`); **(b)** a retired clause-ID keeps a one-line lifecycle
  tag stub at its anchor (`[REMOVED 2026-… — reason → pointer]`) with the body removed — a tag is a
  state, a chain is history (invariant 5, `lifecycle-states.md`); **(c)** "own commit" = the Stage-3
  spec commit precedes the code commits *within the same slice* (spec-first + docs-in-lockstep), not a
  separate slice. Framework self-evolution keeps Patch/Amend (the README `vN Amendment` blocks are its
  changelog); only its Errata mode retires.
- **Non-goals.** No invariant change (still ten). No new gate. The changelog / event log keeps full
  history — nothing is erased, it is relocated.
- **Dependencies & links.** `stages/3_spec.md` (update modes), `lifecycle-states.md` (Spec-clause row +
  checklist), `spec-format/README.md` §4 ("struck (Errata)"), `changelog-conventions.md` ("or as an
  Errata"), `PROCESS.md` §"Evolving" line, `README.md` C3c. Origin record: 4x memory
  `feedback_spec_wholesale_edit_no_strata.md`.
- **Right-size route.** `persona` (six spine docs, PO ratification). **2 pts.**

ACs:
```
SDD-PROP-08/AC-1 — When a canonical spec clause changes, the shard shall contain only the current text
                   plus its provenance pin; no struck, bracketed, or dated prior text shall remain.
SDD-PROP-08/AC-2 — When a clause-ID is retired, the shard shall carry a one-line lifecycle tag at the
                   anchor and the clause body shall be removed; the ID shall never be reused.
SDD-PROP-08/AC-3 — Every canonical spec change shall land as its own commit whose message states what
                   changed and why, before the code commits of the same slice.
```

---

## SDD-PROP-09 — Task — Terse, factual spec form: decision-only, structured, one fact per line — **RATIFIED & IMPLEMENTED in v1.9 (PO-directed 2026-09-02)**

- **Context / why.** Specs were being generated as blocks of narrative prose — framing, rationale and
  reconciliation history wrapped around a few facts — and prose is paid for on every demand-load. Measured
  on 4x (words in list/table/code vs paragraph elements): the PO's exemplar `Inventory_Spec_2.0.md` is
  **19 %** paragraph-words; its canonical fold `section5x_intro.body.html` is **58 %** — the fold
  re-narrated lists into paragraphs (same content, +7 % words, ×3 paragraph share). `Combat_Spec_2.0.md`
  29 %; legacy shards 40–60 % (`section5d.5_fatigue`: the first two paragraphs ≈150 words carry ~4 facts
  plus a reconciliation-history block). Prose also defeats range-pinning + grep, which the v1.8 "Dispatch
  frugally" rule depends on. Companion PO directives already standing in 4x: "spec states WHAT we use,
  not the argument for it" (2026-08-26); implementation-grade detail (every constant / formula /
  threshold, traceable).
- **The change.** A **Spec form** rule block in `stages/3_spec.md` §"Writing the clauses" and
  `spec-format/README.md` §5, binding authoring AND the Stage-7 fold:
  1. **Decision, not argument.** Rationale, alternatives, measurements, history → changelog item /
     build contract / commit message. Never the shard.
  2. **Structured, not narrative.** Numbered/lettered clauses, bullets, tables for value catalogs, code
     blocks for formulas and signatures. A paragraph only where a rule cannot be a line.
  3. **One fact per line**, atomic + testable. EARS *semantics* (trigger / state / condition →
     response) in the shortest form — `When X: Y.` — **fork resolved 2026-09-02:** `the system shall` is optional where the subject is obvious.
  4. **Name the concrete thing** — class, method signature, config key, constant, file. No outlines
     (implementation-grade stays in force).
  5. **No framing prose** — no preambles, "background", "note that", or restatement of another
     section; cross-ref by anchor.
  6. **Fold preserves form.** Stage 7 folds the draft's structure verbatim; never re-narrates into
     paragraphs.
  Exemplars bound per project in Project Details `SPEC-` (4x: `spec/Inventory_Spec_2.0.md`,
  `spec/Combat_Spec_2.0.md`).
- **Non-goals.** Not a licence for vagueness. No change to EARS atomicity / testability / stable IDs.
  *Shipped with it (PO-directed 2026-09-02):* the `prose_check` gate — smoke-tested on a synthetic fixture
  and read-only on the 4x corpus (252 shards, both OS scripts byte-identical).
- **Dependencies & links.** `stages/3_spec.md`, `spec-format/README.md` §5 + §9 checklist,
  `stages/7_ship.md` §3 (fold step), `definition-of-done.md` (docs item), `project-details.template.md`
  (new SPEC-7 exemplar row). Origin: 4x memories `feedback_spec_names_decision_not_rationale.md`,
  `feedback_spec_implementation_grade_detail.md`. Pairs with PROP-08 (no strata) — together: the shard is
  current truth, stated once, tersely.
- **Right-size route.** `persona` (PO ratification). **2 pts.**

ACs:
```
SDD-PROP-09/AC-1 — A canonical spec shard shall carry decisions only; rationale, alternatives, and
                   reconciliation history shall not appear in the shard.
SDD-PROP-09/AC-2 — Every behavioural clause shall be one atomic line (list item, table row, or code
                   line) naming the concrete construct; a paragraph is permitted only where the rule
                   cannot be expressed as a line.
SDD-PROP-09/AC-3 — When a transient spec folds at Stage 7, the folded clauses shall keep the draft's
                   structural form; the fold shall not convert list or table clauses into paragraphs.
```

---

## SDD-PROP-10 — Story — Installer & distribution: GitHub repo, release automation, installer pair, Claude Code plugin — **OPEN (PO-directed 2026-09-02; phases 0–4 shipped in v1.10.0–v1.11.0 except LICENSE + visibility = PO decisions D1/D2)**

- **Context / why.** Distribution today is a hand-built `../sdd.zip` plus "unzip and follow INIT"; the
  spine reaches a project by copying. Measured 2026-09-02: the 4x mirror (vendored 2026-07-20) is 12
  spine files behind and never received 17 framework files (carriers, commands, INIT, templates,
  `prose_check`). The field survey of the same date rates SDD behind rivals on distribution alone.
  Claude Code's plugin model (skills + hooks + marketplace, Sept 2026) can carry the session commands
  and a mechanical persona edit-guard without touching the vendored spine.
- **The change.** One repo, three channels, four phases.
  (0) **Repo** `github.com/mdtealvl/guide-sdd` — private, `main`, tag `v1.9`, `.gitignore` (box-role.local,
  settings.local.json, *.zip), `.gitattributes` (LF) — **done 2026-09-02**.
  (1) **Release automation** — `VERSION` file; `ci.yml` runs the INIT smoke test on windows + ubuntu and
  a ps1/sh parity check on fixtures; `release.yml` on tag `vX.Y.Z` builds `guide-sdd-X.Y.Z.zip` (`sdd/` prefix)
  + sha256 and publishes a GitHub Release with the matching `constitution.changelog.md` section.
  (2) **Installer pair** `install.ps1` / `install.sh` (behaviour-identical, no toolchain): verbs
  `install | update | doctor`; flags `--version`, `--dest` (default `sdd`), `--carriers claude,codex,
  copilot,cursor`, `--commands`, `--force`. Copies spine + carriers + commands, writes
  `sdd/.sdd-manifest.json` (version + per-file sha256). **Never** touches the project surface:
  `project-config/project-details.md`, `gates/gates.config.json`, concrete project gates,
  `box-role.local`. **Never** answers INIT's three ASKs — it stops at them.
  (3) **Claude Code plugin** at `plugin/` + `.claude-plugin/marketplace.json` at root (a repo cannot be
  marketplace and plugin at once; relative-path source). Skills: `sdd-init`, `sdd-update`, `sdd-doctor`,
  `sdd-gates`, `wrap`, `stash`, `unstash`. Hook: `PreToolUse` on `Edit|Write` denies paths matching
  `testGlobs` when `SDD_PERSONA=engineer` (test_edit_ban at edit time, not just at gate time).
  `claude plugin validate plugin/` in CI. Install: `/plugin marketplace add mdtealvl/guide-sdd`,
  `/plugin install guide-sdd@guide-sdd`.
  (4) **Docs + public** — `LICENSE`; README "Install" (three routes); START_HERE routes; INIT §0/§1/§2c
  "run the installer, or by hand"; `host-adapter.md` plugin row; `welcome.html` brought to current;
  a `version_check` gate (README header = changelog head = VERSION = plugin.json); flip visibility.
- **Non-goals.** No Node/Python at install time. The vendored spine stays canonical in the target repo;
  the plugin adds host affordances only (the Agent OS lesson: never make the process depend on a host
  feature). No per-host command bundles beyond the Claude / Copilot / Cursor dirs INIT already names.
  Installer makes no triage, spec, or fork decisions.
- **Dependencies & links.** `project-config/INIT.md` §0–§2c, §5; `host-adapter.md`; `commands/README.md`;
  `gates/README.md`. Claude Code docs: plugins, plugin-marketplaces, skills, hooks-guide. Origin: field
  survey 2026-09-02 (§6 "Worse", §7 roadmap).
- **Right-size route.** Phases 1–2 **mechanical** (scripts + CI + fixtures). Phase 3 **persona** (the hook
  encodes invariant 3; QA writes the hook fixtures blind). Phase 4 mechanical. Points: 2 / 5 / 5 / 3.
- **PO decisions.** D1 when to go public (recommend: end of phase 3 — a private marketplace works only
  where the box's git auth reaches the repo). D2 license (recommend MIT). D3 names: marketplace `guide-sdd`, plugin `guide-sdd`. D4 versions: `vX.Y.Z` releases; plugin tag `guide-sdd--vX.Y.Z` via `claude plugin tag --push`.

ACs:
```
SDD-PROP-10/AC-1 — When a tag vX.Y.Z is pushed and both-OS smoke tests pass, CI shall publish a GitHub
                   Release carrying guide-sdd-X.Y.Z.zip (sdd/ prefix) and its sha256.
SDD-PROP-10/AC-2 — install.ps1 and install.sh shall produce byte-identical file sets in a fresh repo.
SDD-PROP-10/AC-3 — update shall replace only spine files listed in the manifest and shall leave
                   project-details.md, gates.config.json, concrete project gates, and box-role.local
                   unchanged; on a dirty git tree it shall refuse unless --force.
SDD-PROP-10/AC-4 — doctor shall list every spine file whose sha256 differs from the manifest, and the
                   installed version, and exit non-zero when any differs.
SDD-PROP-10/AC-5 — With the plugin installed and SDD_PERSONA=engineer, a PreToolUse hook shall deny
                   Edit/Write to any path matching gates.config.json testGlobs.
SDD-PROP-10/AC-6 — /plugin install guide-sdd@guide-sdd on a second box shall make /wrap, /stash, /unstash and
                   /sdd-init available without copying commands/.
SDD-PROP-10/AC-7 — The installer shall stop before INIT's three ASKs; they remain human-answered.
```
