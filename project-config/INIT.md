# Project Init — adopting the SDD framework

Run once when dropping the framework into a project (~20 minutes): walk top to bottom, prompt where
marked **ASK**, end with a green gate smoke test.

**Prerequisite:** Git, and a repo with ≥1 commit (the smoke tests assume one). No Python. **Windows**
runs the PowerShell gates (built-in `pwsh`); **Linux/macOS** runs the Bash gates (`git` + `jq`).

## Bootstrap (AI agent)

If you are an AI agent asked to set this up:
1. Read `sdd/START_HERE.md`, then execute this file top to bottom.
2. **Open with a welcome before the questions** — tell the user, in your words: *"Welcome to GUIDE SDD —
   I'm setting up a spec-first development process for this project: the spec stays the source of truth,
   risky work is split across independent agents, and every change is gated, so development is faster
   and more accurate. I'll ask three quick setup questions, then verify the gates run."*
3. Give one line of context before each **ASK**.
4. Stop at the green smoke test; do not build features during setup.

## 0. Copy the spine (verbatim, do not edit)

- Copy into the target repo (suggested home: `sdd/` or `docs/sdd/`):
  `constitution.md`, `PROCESS.md`, `stages/`, `gates/`, `spec-format/`.
- **Never** edit the spine per project. Everything project-specific goes in
  `project-config/project-details.md` + `gates/gates.config.json` (gate rules are **inline** arrays
  there — no separate `*.rules.json` files).
- Spine improvements go through the opportunistic-rewrite mechanism in `README.md` and flow back to all
  projects — never per-project forks.

Or run the installer from the repo root — `pwsh install.ps1 install --carriers … --commands` / `sh install.sh
install …` (README §Install):
- It does this step, the carrier copies (§1), the command install (§2c), and seeds `gates.config.json`
  for §5, then stops; §1a, §1b and the three ASKs stay yours.
- Later, `check`, `update` and `doctor` keep the spine current; `update` merges your carriers, project
  details, project gates, commands and gate config with the new templates.

## 1. Wire the always-loaded core into the agent carrier

The always-loaded surface is a short, agent-neutral **stub** pointing at the constitution + `PROCESS.md`
§0, placed in whichever file your agent tool always-loads. `AGENTS.md` is the canonical carrier
(mechanism map: `sdd/host-adapter.md`).

**Place the carriers at the repo root** (beside `sdd/`), only for the tool(s) you use:

- **`AGENTS.md`** (canonical) — copy `sdd/AGENTS.md`. Read natively by OpenAI Codex, Cursor and Gemini
  CLI. The single stub of record; edit it here, not per host.
- **`CLAUDE.md`** — Claude Code: one line `@AGENTS.md` (copy `sdd/CLAUDE.md`); the `@`-import gives
  physical always-load.
- **`.github/copilot-instructions.md`** — GitHub Copilot only (it does not read `AGENTS.md`); copy
  `sdd/.github/copilot-instructions.md` and keep it in sync with `AGENTS.md`.

That is the entire always-loaded surface: constitution + this pointer. Stage files, gates and spec
shards load on demand (C1).

### 1a. Set this box's host tier (per-box, NOT committed)

The persona loop needs contexts that exclude each other; your host's **tier** says how much it can
deliver (`sdd/host-adapter.md`):
- **A** = real scoped sub-agents (Claude Code).
- **B** = fresh sessions only (Codex / Cursor / Gemini / Copilot) — `test_edit_ban` + `qa_import_ban`
  still enforce QA⊥Engineer structurally.
- **C** = single context — Mechanical lane only.
- Stamp `SDD_HOST_TIER=A|B|C` (env, or in `project-config/box-role.local`). Default = `A`.

### 1b. Set this box's role (per-box, NOT committed)

A **box** is a machine/agent session with a standing deployment authority (orthogonal to the
per-feature personas). Declare its role **locally and uncommitted**:

- env `SDD_BOX_ROLE=po|worker` (+ `SDD_BOX_ID=<short id>`, e.g. the hostname — required on a worker; it
  stamps claims), **or** a `project-config/box-role.local` file holding both. Git-ignore that file, plus
  `sdd/.persona` + `sdd/.persona-state/` (the plugin's persona marker and its per-session/per-agent
  state; `install.sh`/`install.ps1` add both) — all per-box, **never committed**.
- Default = **po** (an unset/solo box does everything: triage, design, spec authoring, fork decisions,
  merge). A **worker** box only executes Ready (DoR-met) items and surfaces concerns back — it never
  authors the spec or decides forks. See `sdd/box-roles.md`.

## 2. ASK: changelog mode (C4)

> **"Do you want an external tracker (Jira / Linear / etc.) or a lighter on-disk
> backlog?"**

- **Solo / light:** on-disk backlog. Cheap, no tooling.
- **Multi-dev / real PO-PM tracking:** external tracker.

- The fold-on-ship invariant (constitution §8) holds **identically** either way; only the changelog's
  *storage* differs.
- Record the choice in Project Details §4 (Changelog binding), which wires both modes.
- Mode-independent: how to write a well-formed item (taxonomy, EARS ACs, surfacing templates) is
  `sdd/changelog-conventions.md`; the DoR/DoD gates (when an item may be picked up, when a unit is Done)
  are `sdd/definition-of-done.md`.

## 2b. ASK: greenfield vs brownfield

> **"Is this greenfield (building new) or brownfield (existing code with little/no
> spec)?"** — see `sdd/greenfield-vs-brownfield.md`.

- The stance is chosen **per work item** at triage; record the project's default here.
- **Brownfield:** set up the **unspecified-surface register** (a `docs/UNSPECIFIED_SURFACES.md`
  spec-debt list, or a pointer-doc-map row) so spec gaps are tracked, not rediscovered; adopt
  spec-as-you-go (reconstruct only the slice you touch, surface gaps via `[NEEDS-PO]`, never
  infer-and-proceed).
- **To bring a whole area under SDD up front, consider `sdd/discover-spec.md`** — a characterization
  pass (enough spec to understand the system, a test coverage + quality baseline, a prioritized test
  plan) before building features.

## 2c. Seed the project memory directory + install session-lifecycle commands

The session-lifecycle ritual (`sdd/session-lifecycle.md` — wrap-at-close, the overwrite-only HANDOFF
card, stash/unstash) needs a per-project **memory directory**. Create it (path recorded in Project
Details `#CL-11`) and seed the skeleton:

```sh
MEM=docs/memory          # or your chosen path — record it as CL-11
mkdir -p "$MEM/stashes/archive" "$MEM/memory"
printf '# Memory index\n\n_one line per memory; no content here_\n' > "$MEM/MEMORY.md"
printf '# HANDOFF — you are here\n\n_overwritten each wrap, never appended_\n' > "$MEM/HANDOFF.md"
# Mode B only — the on-disk backlog is one file per item at the repo root (#CL-1; fold_check reads it):
mkdir -p backlog                            # SKIP in Mode A (the tracker is the backlog)
```

- **Install the Tier-A commands** (`/wrap`, `/stash`, `/unstash`): copy `sdd/commands/*.md` into the
  host's command dir — Claude Code `.claude/commands/`, Copilot `.github/prompts/`, Cursor
  `.cursor/commands/`.
- Tier-B/C host with no slash-commands: skip the copy and run the rituals by hand from
  `session-lifecycle.md`. See `sdd/commands/README.md`.

## 3. ASK: spec format (C5)

> **"Author the spec directly in HTML, or in Markdown and compile to HTML?"**

- Either way, **each subsection is its own content-only shard** (no page formatting / scripts /
  styling) and a build step assembles the navigable HTML index.
- Default: Markdown content-only fragments named `<section>.body.md` (HTML permitted by config).
  Markdown→HTML is preferred for a current human-readable whole-corpus view.
- Record the choice + build command in Project Details §5. See `spec-format/README.md`.

## 4. Instantiate the project details

- `cp project-config/project-details.template.md project-config/project-details.md` and fill every
  section. Each (seams, stack, toolchain, changelog binding, pointer-doc map) is its own growable,
  indexed section (C3a).
- At minimum, register the **architecture seams** (§1) — what Stage 6 and `seam_conformance` enforce.

## 5. Instantiate the gate config + project-specific gates

1. `cp gates/gates.config.template.json gates/gates.config.json` and fill the
   flat, inline keys (these are the EXACT keys the gate scripts read):
   - `clauseIdRegex` — the clause-ID regex (mirror from project-details `#SPEC-6`).
   - `testClauseTag` — the `@clause:` tag the tests carry.
   - `paths.spec` — the recursive shard glob, e.g. `spec/**/*.body.md`. **Every path/glob is relative
     to the project root** (the git top-level), not to `sdd/`; `run_all` resolves that root itself.
   - `testGlobs` — the test files **plus** snapshots and test-runner config (`jest.config.*`,
     `pytest.ini`, `conftest.py`): an Engineer who can edit those can silence a test without touching it.
     One dialect everywhere: `**` spans directories, `*` does not, anchored at the root.
   - `structureGlobs` — the PM-approved structure shards (default `**/*.structure.body.md`): frozen with
     the tests (`structure_check --frozen`, the plugin hook) and forward-traced into `paths.code` at ship.
   - `buildPlan.glob` / `buildPlan.tokensPerChar` — where the Stage-4b build plan lives
     (`**/*.buildplan.md`) and the estimate `token_ledger` reports (`0.25` ≈ 4 chars per token).
   - `baseRef` — fallback only. `test_edit_ban` diffs the **QA-frozen SHA** (the item's `frozen:` line,
     mirrored in `gates/.frozen` by `gates/freeze.*`); a branch name is warned as weak.
   - `suiteCmd` — the suite-green command (mirror from project-details `#TOOL-3`). **Mandatory:**
     `run_all` exits 2 while it is unset — a bank that skips the suite proves nothing.
   - `unitIdRegex` — the changelog unit-id regex (from project-details `#CL-2`).
   - `foldCheck.backlogRoot` / `foldCheck.resolveCmd` — how `fold_check` resolves a pin's
     `<unit-id>`. The fold step is otherwise changelog-mode-blind, so switching modes later touches
     `foldCheck` + Project Details §4 only.
2. For each project-specific gate you want enforced, copy the concrete script **for your OS** (so
   `run_all` can invoke it):
   - Windows: `cp gates/constitution_lint.template.ps1 gates/constitution_lint.ps1` (and
     `seam_conformance`).
   - Linux/macOS: `cp gates/constitution_lint.template.sh gates/constitution_lint.sh` (and
     `seam_conformance`).
   - Add the rules as inline `constitutionRules[]` and `seamRules[]` entries in
     `gates.config.json` — one per principle/seam, using the recipe in `gates/README.md`.
     Each seam registered in Project Details §1 maps to one `seamRules[]` entry, its `id` keyed to a
     `#SEAM-N`.

## 6. Smoke test the gates (must pass before you trust the framework)

Requires a repo with ≥1 commit; **jq on Linux/macOS only** (Windows uses built-in `pwsh`). First seed a
trivial Markdown spec shard with one ANCHORED clause, and a test that tags it (OS-agnostic):

```sh
mkdir -p spec
printf '## DEMO.1 smoke {#DEMO.1}\nWhen init runs, the system shall pass the smoke test.\n' > spec/demo.body.md
mkdir -p tests
printf '// @clause:DEMO.1\nok();\n' > tests/demo.smoke.test
```

Then run the four generic gates — **Windows:**

```powershell
pwsh gates/coverage_check.ps1 --config gates/gates.config.json   # expect PASS
pwsh gates/link_check.ps1     --config gates/gates.config.json   # expect PASS
pwsh gates/prose_check.ps1    --config gates/gates.config.json -All   # expect PASS (heading + one clause line)
pwsh gates/test_edit_ban.ps1  HEAD gates/gates.config.json       # expect PASS (clean tree, base resolves)
```

**Linux/macOS:**

```sh
sh gates/coverage_check.sh --config gates/gates.config.json   # expect PASS
sh gates/link_check.sh     --config gates/gates.config.json   # expect PASS
sh gates/prose_check.sh    --config gates/gates.config.json --all   # expect PASS (heading + one clause line)
sh gates/test_edit_ban.sh  HEAD gates/gates.config.json       # expect PASS (clean tree, base resolves)
```

- All four PASS → the generic gates are wired correctly.
- The gates take config via the `--config` FLAG; `test_edit_ban` takes positional
  `[baseRef] [config]` — pass `HEAD` so the base resolves.

**Negative control (proves the predicate, not just the plumbing).** A gate that only ever passes is
worthless. Append a clause with NO test (OS-agnostic):

```sh
printf '\n## DEMO.2 unfollowed {#DEMO.2}\nThe system shall have no test, on purpose.\n' >> spec/demo.body.md
```

1. Re-run coverage — **Windows:** `pwsh gates/coverage_check.ps1 --config gates/gates.config.json`
   / **Linux/macOS:** `sh gates/coverage_check.sh --config gates/gates.config.json`. It must FAIL
   naming `DEMO.2`.
2. Revert: remove the DEMO.2 lines and confirm it PASSes.
3. Second negative control — the edit ban: append a line to `tests/demo.smoke.test` without
   committing and run `test_edit_ban` with `HEAD`; it must FAIL naming the file (the working tree is
   diffed, not just commits). Revert.
4. Set `suiteCmd` for the demo (`"exit 0"` is enough here; the real command follows in §5) and run
   the whole bank — **Windows:**

```powershell
pwsh gates/run_all.ps1 HEAD   # generic gates in order; pass a RESOLVING base (real CI passes the QA-frozen commit)
```

**Linux/macOS:**

```sh
sh gates/run_all.sh HEAD   # generic gates in order; pass a RESOLVING base (real CI passes the QA-frozen commit)
```

- `run_all` skips absent project gates, and skips `fold_check` only under `-PreFold` / `--pre-fold`;
  here the full bank runs, and the demo has no pins, so expect it clean over the demo corpus.
- It exits 0 on the clean demo tree, nonzero if any gate fails. Remove the demo files when done.
- If a gate errors on paths/regex (not a real PASS/FAIL), fix `gates.config.json` — never edit a
  generic gate body; they are spine and must stay stack-agnostic.

## Init checklist

- [ ] Spine copied verbatim; not edited.
- [ ] Agent carrier wired (`AGENTS.md`; `CLAUDE.md` routes to it; Copilot shim if used); `$SDD_HOST_TIER` set (`host-adapter.md`).
- [ ] Box role set per box (`SDD_BOX_ROLE` or `box-role.local`); `box-role.local` git-ignored.
- [ ] Changelog mode chosen + recorded in Project Details §4 (incl. CL-6 work-ready / CL-7 PO-attention states).
- [ ] Project memory directory seeded (MEMORY.md, HANDOFF.md, stashes/, memory/) + path recorded as CL-11; `backlog/` created in Mode B (CL-1); session-lifecycle commands installed if Tier-A (`sdd/commands/`).
- [ ] Box default greenfield/brownfield recorded; brownfield → unspecified-surface register created.
- [ ] Spec format chosen (default `.body.md` content-only shards) + build command in Project Details §5.
- [ ] `project-details.md` instantiated; seams registered in §1.
- [ ] `gates.config.json` filled with the flat keys (`clauseIdRegex`, `testClauseTag`,
  `paths.spec`, `testGlobs`, `baseRef`, `suiteCmd`, `unitIdRegex`, `foldCheck.*`) and inline
  `constitutionRules[]` / `seamRules[]`; concrete project gate scripts copied.
- [ ] Gate smoke test green for this OS (PowerShell or Bash gates; `.body.md` demo, `--config`
  flag, `HEAD` base, DEMO.2 negative control, uncommitted-test-edit negative control, `suiteCmd` set);
  demo files removed.
