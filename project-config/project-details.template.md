# Project Details — <PROJECT NAME>

> Instantiated from `project-details.template.md` at init. This is the **only** project-
> specific prose document. It is **structured and indexed** so it grows addressably:
> every entry has a stable key (`SEAM-N`, `PTR-N`, …) so stages, gates, and other
> docs can reference a single section without loading the whole file. Add rows;
> don't rewrite. Not loaded by default — stages load the specific section they need.

## Index

| § | Section | Stable-key prefix | Load when |
|---|---------|-------------------|-----------|
| 1 | Architecture seams | `SEAM-` | Stage 1 design, Stage 6 engineer, seam_conformance |
| 2 | Stack & layout | `STK-` | Any stage needing build/run/test |
| 3 | Toolchain & gate wiring | `TOOL-` | Stage 7, CI setup |
| 4 | Changelog binding | `CL-` | Stage 0 (file work), worker pickup/surface-back (CL-6/CL-7), Stage 7 (record SHA) |
| 5 | Spec format & home | `SPEC-` | Stage 3 spec, Stage 7 fold |
| 6 | Pointer-doc map | `PTR-` | On trigger, per row |
| 7 | Right-sizing overrides | `RS-` | Stage 0 triage |

---

## 1. Architecture seams (`SEAM-`)

The boundaries no work may bypass. Each becomes a `seam_conformance` rule (C2).
Add a row per seam; keep the stable key forever.

| Key | Seam | Rule (what must hold) | Gate rule id |
|-----|------|-----------------------|--------------|
| SEAM-1 | _e.g. dispatch registry_ | _new write-side work files a handler class; no manual DI in Program.cs_ | _seam_conformance:DISPATCH-1_ |
| SEAM-2 | _e.g. audit invariant_ | _every state-changing handler writes ≥1 AuditEntry before returning_ | _seam_conformance:AUDIT-1_ |
| SEAM-3 | | | |

> "Touches >1 of {…}" list for the Stage 0 right-size bar: _list the project's
> high-blast-radius surfaces here, e.g. {domain model, workflow config, public API,
> UI flow}._

## 2. Stack & layout (`STK-`)

| Key | Item | Value |
|-----|------|-------|
| STK-1 | Backend | _e.g. .NET 8, Domain/Application/Infrastructure/Api_ |
| STK-2 | Frontend | _e.g. React 18 + Vite + TS_ |
| STK-3 | Test layers → tools | _pure→xunit; integration→EF InMemory; functional→WAF; visual→…_ |
| STK-4 | Repo dirs | _backend/ frontend/ docs/ config/_ |

## 3. Toolchain & gate wiring (`TOOL-`)

| Key | Item | Value |
|-----|------|-------|
| TOOL-1 | Build | _cmd_ |
| TOOL-2 | Run | _cmd_ |
| TOOL-3 | Test suite (suite-green) | _cmd — mirror into gates.config.json `suiteCmd`_ |
| TOOL-4 | Gate runner | `gates/run_all.ps1` (Windows) / `gates/run_all.sh` (Linux/macOS) — local + CI |
| TOOL-5 | Published branch / merge | _e.g. `main`; local `dev`; `--no-ff`_ |
| TOOL-6 | Quiet gate idioms for dispatched briefs (§0 "Dispatch frugally") | _build/test commands filtered at source to a summary line + failure names, never raw logs; repo-level build-noise suppression; cite this row in every sub-agent brief_ |

## 4. Changelog binding (`CL-`) — C4

**Mode chosen at init:** ☐ External tracker ☐ On-disk backlog

Both modes satisfy constitution §8 identically; only storage differs.

| Key | Item | If EXTERNAL tracker | If ON-DISK backlog |
|-----|------|---------------------|--------------------|
| CL-1 | Store | _Jira project KEY / Linear team; access via `scripts/<tracker>.sh`_ | _`backlog/` append-only md files, one per item_ |
| CL-2 | Item id format | _e.g. `POL-###`_ | _e.g. `BL-YYYYMMDD-NN`_ |
| CL-3 | Start work | _create/find issue; transition In Progress; ref key in commits_ | _append a backlog entry: what/why/acceptance bar/who_ |
| CL-4 | Record ship | _transition Done; comment ship-SHA_ | _append `shipped: <SHA> <date>` to the entry_ |
| CL-5 | Provenance pin | `(§X per <id>, YYYY-MM-DD)` on each folded clause | _same pin syntax_ |
| CL-6 | **Work-ready state** (PO marks an item ready for a worker to pick up). Keep **distinct** from CL-3 start-work when boxes are split — else a worker must claim/assign the item on pickup so two boxes can't grab it. | _e.g. Jira `Selected for Dev` / `Ready`_ | _e.g. a `status: ready` line on the entry_ |
| CL-7 | **PO-attention state** (worker transitions here when surfacing `[NEEDS-PO]`/`[BLOCKED]`) | _e.g. Jira `Blocked` / a flag_ | _e.g. a `status: blocked` line on the entry_ |
| CL-8 | Entry-writing standard / DoR-DoD | `sdd/changelog-conventions.md` (well-formed entry); `sdd/definition-of-done.md` (DoR/DoD gates) — mode-independent | _same two docs_ |
| CL-9 | **Claim** (worker stamps before starting; only an unclaimed Ready item) | _a comment `claimed-by:<SDD_BOX_ID>` + timestamp_ | _a `claimed-by: <SDD_BOX_ID>` line on the entry_ |
| CL-10 | **Ready-for-review state** (worker flags; PO box reviews + merges) | _e.g. Jira `Ready for Review` / a label_ | _a `status: review` line on the entry_ |
| CL-11 | **Project memory directory** — session-lifecycle home (`session-lifecycle.md`), seeded at INIT: `MEMORY.md` index, `HANDOFF.md` (overwrite-only card), `stashes/` (+ `archive/`), `memory/`. Session state only — the backlog itself lives at CL-1 (`backlog/` item files in Mode B; the tracker in Mode A). | _e.g. `docs/memory/`_ | _e.g. `docs/memory/`_ |

> **Box loops:** worker poll ~15–30 min, PO poll ~30 min; `SDD_BOX_ID` + cadence are per-box (`box-role.local`). Workers never merge — they flag CL-10 and the PO box owns the serialized merge. See `box-roles.md` §"Box loops & coordination".

## 5. Spec format & home (`SPEC-`) — C5

**Format chosen at init:** ☐ HTML direct ☐ Markdown→HTML compile

| Key | Item | Value |
|-----|------|-------|
| SPEC-1 | Canonical spec home | _e.g. `spec/` (shards) + `spec/index.html` (compiled)_ |
| SPEC-2 | Shard naming | _`<section>.body.md` (content-only fragment; Markdown default, HTML permitted by config)_ |
| SPEC-3 | Compile command | _`spec-format/build.ps1` (Windows) / `spec-format/build.sh` (Linux/macOS) (see spec-format/README.md)_ |
| SPEC-4 | Transient working-spec home | _e.g. `spec/working/<id>.body.md` — a standalone draft file, never an in-page addendum_ |
| SPEC-5 | Archive | _e.g. `spec/archive/` (audit-only; never read to implement)_ |
| SPEC-6 | Clause-ID convention | _e.g. `SECTION.NN` like `CB.07`; mirror regex into gates.config.json `clauseIdRegex`_ |
| SPEC-7 | Spec-form exemplars | _1–2 shards showing the terse factual form (`stages/3_spec.md` §"Spec form"); e.g. 4x `spec/Inventory_Spec_2.0.md`, `spec/Combat_Spec_2.0.md`_ |
| SPEC-8 | Structure shards | _canonical `<section>/<subsection>.structure.body.md` (member-level mermaid `classDiagram`, current state); transient `<ITEM-ID>.structure.body.md` beside SPEC-4 (delta: Added / Changed / Removed). Mirror the glob into gates.config.json `structureGlobs`; add mermaid.js to `_layout.html` if the compiled view should render them_ |
| SPEC-9 | Build plan home | _`<ITEM-ID>.buildplan.md` beside SPEC-4 (`stages/4b_buildplan.md`); gates.config.json `buildPlan.glob` + `tokensPerChar` (default 0.25)_ |

## 6. Pointer-doc map (`PTR-`) — read on trigger

Growable. Add a row per pointer doc; agents load it only on its trigger.

| Key | Doc | Read it when |
|-----|-----|--------------|
| PTR-1 | _docs/ONBOARDING.md_ | _fresh machine setup_ |
| PTR-2 | _docs/TESTING_SHAPES.md_ | _a fixture stands in for production_ |
| PTR-3 | docs/UNSPECIFIED_SURFACES.md | a brownfield spec-gap is found (spec-debt list) |
| PTR-4 | | |

## 7. Right-sizing overrides (`RS-`)

Project-specific tweaks to the Stage 0 2×2 (defaults live in `stages/0_triage.md`).

| Key | Override |
|-----|----------|
| RS-1 | _e.g. "anything touching money/economy math is always persona-loop, regardless of size"_ |
| RS-2 | _e.g. "parallel-dispatch triage bar: ≤3 SP, single surface, no config-shape changes, cap 4 workers"_ |
