# Project Init — adopting the SDD framework

Run once when dropping the framework into a project. A guided flow: walk top to bottom, prompt where
marked **ASK**, end with a green gate smoke-test. ~20 minutes.

> **Prerequisite:** No Python needed. **Windows** runs the PowerShell gates (built-in `pwsh`, zero
> extra deps). **Linux/macOS** runs the Bash gates (need `git` + `jq`). Git required; smoke tests
> assume a repo with ≥1 commit.

## Bootstrap (AI agent)

If you are an AI agent asked to set this up: read `sdd/START_HERE.md`, then execute this file top to
bottom. **Open with a welcome before the questions** — tell the user, in your words: *"Welcome to GUIDE SDD —
I'm setting up a spec-first development process for this project: the spec stays the source of truth,
risky work is split across independent agents, and every change is gated, so development is faster and
more accurate. I'll ask three quick setup questions, then verify the gates run."* Give one line of
context before each **ASK**. Stop at the green smoke test; do not build features during setup.

## 0. Copy the spine (verbatim, do not edit)

Copy into the target repo (suggested home: `sdd/` or `docs/sdd/`):
`constitution.md`, `PROCESS.md`, `stages/`, `gates/`, `spec-format/`.
These are the shared spine — **never** edit them per project. Everything project-specific goes in
`project-config/project-details.md` + `gates/gates.config.json` (the gate rules are **inline** arrays
in that one config file — there are no separate `*.rules.json` files). (Spine improvements happen via
the opportunistic-rewrite mechanism in `README.md`, and flow back to all projects — not per-project
forks.)

Or run the installer from the repo root — `pwsh install.ps1 install --carriers … --commands` / `sh install.sh
install …` (README §Install): it does this step, the carrier copies in §1, the command install in §2c, and
seeds `gates.config.json` for §5, then stops. §1a, §1b, and the three ASKs stay yours. `update` and `doctor`
keep the spine current later.

## 1. Wire the always-loaded core into the agent carrier

The always-loaded surface is a ~9-line **stub** that points at the constitution + `PROCESS.md` §0. It is
**agent-neutral** — the same stub, placed in whichever file your agent tool always-loads. `AGENTS.md` is
the canonical carrier; the spine already ships it. See `sdd/host-adapter.md` for the full mechanism map.

**Place the carriers at the repo root** (beside `sdd/`):

- **`AGENTS.md`** (canonical) — copy `sdd/AGENTS.md` to the repo root. Read natively by OpenAI Codex,
  Cursor, and Gemini CLI. This is the single stub of record; edit it here, not per host.
- **`CLAUDE.md`** — for Claude Code, one line `@AGENTS.md` (copy `sdd/CLAUDE.md`); the native `@`-import
  gives physical always-load.
- **`.github/copilot-instructions.md`** — for GitHub Copilot only (it does not read `AGENTS.md`); copy
  `sdd/.github/copilot-instructions.md`. Keep it in sync with `AGENTS.md`.

Copy only the carrier(s) for the agent tool(s) you use. That is the entire always-loaded surface:
constitution (~1-2 pages) + this pointer. Stage files, gates, and spec shards all load on demand. (C1.)

### 1a. Set this box's host tier (per-box, NOT committed)

The persona loop needs contexts that exclude each other; how much your host can deliver is its **tier**
(`sdd/host-adapter.md`): **A** = real scoped sub-agents (Claude Code); **B** = fresh sessions only
(Codex / Cursor / Gemini / Copilot) — the `test_edit_ban` + `qa_import_ban` gates still enforce
QA⊥Engineer structurally; **C** = single context — Mechanical lane only. Stamp it alongside the box role:
`SDD_HOST_TIER=A|B|C` (env, or in `project-config/box-role.local`). Default = `A`.

### 1b. Set this box's role (per-box, NOT committed)

A **box** is a machine/agent session with a standing deployment authority (orthogonal to the
per-feature personas). Declare each box's role **locally and uncommitted**:

- env `SDD_BOX_ROLE=po|worker` (+ `SDD_BOX_ID=<short id>`, e.g. the hostname — required on a worker; it
  stamps claims), **or** a `project-config/box-role.local` file holding both. If you use the file, add it
  to the repo `.gitignore` (and `sdd/.persona`, the plugin's persona marker) — these are per-box and **never committed**.
- Default = **po** (an unset/solo box does everything: triage, design, spec authoring, fork
  decisions, merge). A **worker** box only executes Ready (DoR-met) items and surfaces concerns back
  — it never authors the spec or decides forks. See `sdd/box-roles.md`.

## 2. ASK: changelog mode (C4)

> **"Do you want an external tracker (Jira / Linear / etc.) or a lighter on-disk
> backlog?"**

- **Solo / light:** on-disk backlog. Cheap, no tooling.
- **Multi-dev / real PO-PM tracking:** external tracker.

The fold-on-ship invariant (constitution §8) holds **identically** either way — only the *storage* of
the changelog differs. Record the choice in Project Details §4 (Changelog binding); see that section
for both modes' wiring. The **entry-writing standard** is mode-independent: how to write a well-formed
item (taxonomy, EARS ACs, surfacing templates) is in `sdd/changelog-conventions.md`; the **DoR/DoD**
lifecycle gates (when an item may be picked up, and when a unit is Done) are in
`sdd/definition-of-done.md`.

## 2b. ASK: greenfield vs brownfield

> **"Is this greenfield (building new) or brownfield (existing code with little/no
> spec)?"** — see `sdd/greenfield-vs-brownfield.md`. The stance is actually chosen
> **per work item** at triage, but record the project's default here. **Brownfield:** set
> up the **unspecified-surface register** (a `docs/UNSPECIFIED_SURFACES.md` spec-debt list,
> or a pointer-doc-map row) so spec gaps are tracked, not rediscovered; adopt spec-as-you-go
> (reconstruct only the slice you touch, surface gaps via `[NEEDS-PO]`, never
> infer-and-proceed). **To bring a whole area under SDD up front, consider `sdd/discover-spec.md`** —
> a deliberate characterization pass (reconstruct enough spec to understand the system, baseline test
> coverage + quality, produce a prioritized test plan) before building features.

## 2c. Seed the project memory directory + install session-lifecycle commands

The session-lifecycle ritual (`sdd/session-lifecycle.md`) — wrap-at-close, the overwrite-only HANDOFF
card, stash/unstash — needs a per-project **memory directory**. Create it (path recorded in Project
Details `#CL-11`) and seed the skeleton:

```sh
MEM=docs/memory          # or your chosen path — record it as CL-11
mkdir -p "$MEM/stashes/archive" "$MEM/memory"
printf '# Memory index\n\n_one line per memory; no content here_\n' > "$MEM/MEMORY.md"
printf '# HANDOFF — you are here\n\n_overwritten each wrap, never appended_\n' > "$MEM/HANDOFF.md"
# Mode B only — the on-disk backlog is one file per item at the repo root (#CL-1; fold_check reads it):
mkdir -p backlog                            # SKIP in Mode A (the tracker is the backlog)
```

**Install the Tier-A commands** so `/wrap`, `/stash`, `/unstash` are live: copy `sdd/commands/*.md` into
the host's command dir — Claude Code `.claude/commands/`, Copilot `.github/prompts/`, Cursor
`.cursor/commands/`. On a Tier-B/C host with no slash-commands, skip the copy — the rituals are run by
hand from `session-lifecycle.md`. See `sdd/commands/README.md`.

## 3. ASK: spec format (C5)

> **"Author the spec directly in HTML, or in Markdown and compile to HTML?"**

Either way the rule is the same: **each subsection is its own content-only shard** (no page
formatting / scripts / styling) + a build step assembles the navigable HTML index. Default is Markdown
content-only fragments named `<section>.body.md` (HTML permitted by config); Markdown→HTML is
preferred for keeping a current human-readable whole-corpus view. Record the choice + the build
command in Project Details §5. See `spec-format/README.md`.

## 4. Instantiate the project details

`cp project-config/project-details.template.md project-config/project-details.md` and fill every
section. It is structured + indexed so it grows addressably (C3a) — seams, stack, toolchain, changelog
binding, pointer-doc map are each their own growable section. At minimum, register the project's
**architecture seams** (§1) — these are what Stage 6 and `seam_conformance` enforce.

## 5. Instantiate the gate config + project-specific gates

1. `cp gates/gates.config.template.json gates/gates.config.json` and fill the
   flat, inline keys (these are the EXACT keys the gate scripts read):
   - `clauseIdRegex` — the clause-ID regex (mirror from project-details `#SPEC-6`).
   - `testClauseTag` — the `@clause:` tag the tests carry.
   - `paths.spec` — the recursive shard glob, e.g. `spec/**/*.body.md`. **Every path/glob is relative
     to the project root** (the git top-level), not to `sdd/`; `run_all` resolves that root itself.
   - `testGlobs` — where the test files live, **plus** snapshots and test-runner config (`jest.config.*`,
     `pytest.ini`, `conftest.py`): an Engineer who can edit those can silence a test without touching it.
     One dialect everywhere: `**` spans directories, `*` does not, anchored at the root.
   - `baseRef` — fallback only. `test_edit_ban` diffs the **QA-frozen SHA** (the item's `frozen:` line,
     mirrored in `gates/.frozen` by `gates/freeze.*`); a branch name is warned as weak.
   - `suiteCmd` — the suite-green command (mirror from project-details `#TOOL-3`). **Mandatory:**
     `run_all` exits 2 while it is unset — a bank that skips the suite proves nothing.
   - `unitIdRegex` — the changelog unit-id regex (from project-details `#CL-2`).
   - `foldCheck.backlogRoot` / `foldCheck.resolveCmd` — how `fold_check` resolves a pin's
     `<unit-id>`. The fold step (Stage 7) is otherwise changelog-mode-blind, so switching
     modes later touches `foldCheck` + Project Details §4 only — no spine or generic-gate change.
2. For each project-specific gate you want enforced, copy the concrete script **for your OS**
   (so `run_all` can invoke it) and add its rules **inline** to `gates.config.json`. Rules
   still live inline in `gates.config.json` — there are no separate `*.rules.json` files.
   - Windows: `cp gates/constitution_lint.template.ps1 gates/constitution_lint.ps1` (and
     `seam_conformance`).
   - Linux/macOS: `cp gates/constitution_lint.template.sh gates/constitution_lint.sh` (and
     `seam_conformance`).
   - Add the rules as inline `constitutionRules[]` and `seamRules[]` entries in
     `gates.config.json` — one per principle/seam, using the recipe in `gates/README.md`.
     Each seam you registered in Project Details §1 maps to one `seamRules[]` entry, its `id`
     keyed to a Project Details `#SEAM-N`. (There are no separate `*.rules.json` files.)

## 6. Smoke test the gates (must pass before you trust the framework)

Requires a repo with ≥1 commit (see the Prerequisite note above). No Python. **jq is needed on
Linux/macOS only**; Windows uses built-in `pwsh`.

First seed a trivial Markdown spec shard with one ANCHORED clause, and a test that tags it
(OS-agnostic):

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

All four PASS → the generic gates are wired correctly. (The gates take config via the `--config`
FLAG; `test_edit_ban` takes positional args `[baseRef] [config]` — pass `HEAD` so the base resolves.)

**Negative control (proves the predicate, not just the plumbing).** A gate that only ever passes is
worthless. Add a second clause with NO test and confirm coverage fails:

Append the unfollowed clause (OS-agnostic):

```sh
printf '\n## DEMO.2 unfollowed {#DEMO.2}\nThe system shall have no test, on purpose.\n' >> spec/demo.body.md
```

Then re-run coverage — **Windows:** `pwsh gates/coverage_check.ps1 --config gates/gates.config.json`
/ **Linux/macOS:** `sh gates/coverage_check.sh --config gates/gates.config.json`. It must FAIL
naming `DEMO.2`. Then revert: remove the DEMO.2 lines so the tree is clean again, and confirm it
PASSes. Second negative control — the edit ban: append a line to `tests/demo.smoke.test` without
committing and run `test_edit_ban` with `HEAD`; it must FAIL naming the file (the working tree is
diffed, not just commits). Revert. Now set `suiteCmd` for the demo (`"exit 0"` is enough here; the real
command follows in step 5) and run the whole bank — **Windows:**

```powershell
pwsh gates/run_all.ps1 HEAD   # generic gates in order; pass a RESOLVING base (real CI passes the QA-frozen commit)
```

**Linux/macOS:**

```sh
sh gates/run_all.sh HEAD   # generic gates in order; pass a RESOLVING base (real CI passes the QA-frozen commit)
```

`run_all` skips absent project gates and skips `fold_check` unless run without `-PreFold` /
`--pre-fold` (here the full bank runs — but the demo has no pins, so use `HEAD` and expect the bank to
be clean over the demo corpus). It exits 0 on the clean demo tree, nonzero if any gate fails. Remove
the demo files when done.

> If a gate errors on paths/regex (not a real PASS/FAIL), fix `gates.config.json` — never edit a
> generic gate body; they are spine and must stay stack-agnostic.

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
