<!-- Gate Bank manifest. Loadable in isolation. Read at Stage 4–7 and when authoring a project gate. -->

# Gate Bank

Mechanical checks that close stages. **Mechanical-first, human Validation last.** Every gate is
exit-code driven (0 = PASS, nonzero = FAIL), prints `PASS`/`FAIL` + offending paths, reads one config
(`gates/gates.config.json`), and is pure git/text — no stack, seam, or tracker is hardcoded in a
script. Drop any of these into CI or a pre-merge hook unchanged.

## OS selection — run the script that matches the host (read this first)

Every gate ships as a **`.ps1` + `.sh` pair** with identical behaviour. Pick by OS:

- **Windows → run the `.ps1`.** PowerShell has native JSON; the PowerShell gates have **ZERO
  external dependencies** — no Python, no `jq`. (`git` is needed only by the diff-based gates
  `test_edit_ban` and `fold_check`.)
- **Linux / macOS → run the `.sh`.** The POSIX gates need **`git` + `jq`** (`apt install jq` /
  `brew install jq`). A gate that needs `jq` and can't find it prints
  `FAIL <gate>: needs jq (apt/brew install jq)` and exits 2.

> **Agents: detect the host OS and run the matching script — NEVER assume Python.**
> On Windows invoke `pwsh gates/<gate>.ps1 …`; on Linux/macOS invoke `sh gates/<gate>.sh …`.
> Behaviour-identical, so a project's gate results do not depend on which OS ran them.

`run_all.ps1` invokes its `.ps1` siblings; `run_all.sh` invokes its `.sh` siblings — never mix.
The `_common.*` and `_rules.*` files are shared helpers (config/glob/regex; the rule engine) the
gates source; keep them next to the gates. Runs on a fresh clone with no project runtime.

> ### Gates ≠ correctness
>
> **The bank certifies bookkeeping hygiene + traceability, NOT correctness.** It is a
> **drift-catcher, not an oracle.** Every gate proves a cheap structural fact — a clause has
> a test *tag*, a pin *resolves*, a seam *pattern* holds — never that the test is right, the
> code does what the spec means, or the behaviour is correct. **Correctness is the
> human / fresh-Validation layer's job** (Stage 7). **Green is necessary, not sufficient:** a
> fully green bank can still ship a wrong system. The bank exists so the human Validation pass
> spends its attention on diff-vs-spec *intent*, the thing only a fresh reader catches — not on
> link hygiene a script already settled.

## The bank at a glance

| Gate | Files (Win / *nix) | Kind | Proves | Closes stage |
|---|---|---|---|---|
| coverage_check | `coverage_check.ps1` / `.sh` | generic | every behavioural clause-ID → ≥1 test-ID (both directions). **Whole-corpus by default** (ship invariant); **`--manifest` for per-unit** in-loop runs | 4 (`--plan`), 5 |
| test_edit_ban | `test_edit_ban.ps1` / `.sh` | generic | no test file, snapshot, test-runner config, gate script or gate config differs from the **QA-frozen SHA** — working tree incl. untracked, renames not collapsed; base must be an ancestor of HEAD (QA⊥Engineer, structurally) | 6, 7 |
| freeze | `freeze.ps1` / `.sh` | generic (helper) | records the QA-frozen SHA in `gates/.frozen` at Stage 5 exit and prints the `frozen:` line for the item; refuses a dirty tree | 5 |
| link_check | `link_check.ps1` / `.sh` | generic | every spec cross-ref resolves to a real anchor/shard | 3, 7 |
| prose_check | `prose_check.ps1` / `.sh` | generic | spec shards are terse and structured (SDD-PROP-09): paragraph-word share + longest paragraph per shard, **changed shards vs base** by default (`-All` / `--all` for the corpus); `proseCheck.mode` warn / strict / off | 3, 7 |
| fold_check | `fold_check.ps1` / `.sh` | generic | every clause changed this ship carries a resolving provenance pin. CI runs **`--strict`** | 7 |
| suite_green | `suiteCmd` wrapper | generic | the project suite exits 0; **`suiteCmd` is mandatory** (unset = exit 2, never a skip) | 6, 7 |
| constitution_lint | `constitution_lint.template.ps1` / `.sh` | **project** | project principle checks (e.g. no hardcoded UI strings) | 7 |
| seam_conformance | `seam_conformance.template.ps1` / `.sh` | **project** | each Project Details §1 seam holds | 7 |
| qa_import_ban | `qa_import_ban.template.ps1` / `.sh` | **project** | QA tests don't import production internals (structural half of QA⊥impl; **FAILS with no rules**; the plugin hook adds the read-guard while the `qa` persona is set) | 7 |
| run_all | `run_all.ps1` / `.sh` | generic | the whole bank in order, fail-fast | 7 |

Shared (not gates themselves): `_common.ps1` / `_common.sh` (config + glob + regex helpers) and
`_rules.ps1` / `_rules.sh` (the rule engine constitution_lint, seam_conformance, and qa_import_ban
all run).

**Generic** gates ship as working scripts — verified against the INIT smoke fixture. **Project**
gates ship as `.template.ps1` + `.template.sh` + a config schema; copy the template **of the right
OS** to a concrete name (`constitution_lint.ps1` on Windows, `constitution_lint.sh` on *nix) and
author rules in `gates.config.json` (no script edits).

A clause-ID counts as DECLARED only if it carries an inline anchor; bare prose occurrences are
citations that must resolve (see spec-format/README §4).

## Wiring into the flow

The Stage Index (PROCESS.md §0) names which gate closes which stage; this is the other half of
that contract.

Each line below gives the **Windows (`pwsh …`) / Linux–macOS (`sh …`)** invocation. Run one, not both.

- **Per-stage:** `link_check` + `prose_check` after any spec edit (Stage 3); `coverage_check --plan` at Stage 4;
  `coverage_check` then `freeze` at end of Stage 5; `test_edit_ban <frozen-sha>` + `suite_green` at end of Stage 6.

  | Gate | Windows | Linux / macOS |
  |---|---|---|
  | link_check | `pwsh gates/link_check.ps1` | `sh gates/link_check.sh` |
  | prose_check (changed vs base) | `pwsh gates/prose_check.ps1 -Base <baseRef>` | `sh gates/prose_check.sh --base <baseRef>` |
  | prose_check (whole corpus, report) | `pwsh gates/prose_check.ps1 -All -Report` | `sh gates/prose_check.sh --all --report` |
  | prose_check (enforce) | `pwsh gates/prose_check.ps1 -Base <baseRef> -Strict` | `sh gates/prose_check.sh --base <baseRef> --strict` |
  | coverage_check (plan) | `pwsh gates/coverage_check.ps1 -Plan` | `sh gates/coverage_check.sh --plan` |
  | coverage_check (whole-corpus) | `pwsh gates/coverage_check.ps1` | `sh gates/coverage_check.sh` |
  | coverage_check (per-unit) | `pwsh gates/coverage_check.ps1 -Manifest <file>` | `sh gates/coverage_check.sh --manifest <file>` |
  | freeze (Stage 5 exit) | `pwsh gates/freeze.ps1 -Unit <ITEM-ID>` | `sh gates/freeze.sh --unit <ITEM-ID>` |
  | test_edit_ban | `pwsh gates/test_edit_ban.ps1 <frozen-sha>` (no arg: reads `gates/.frozen`) | `sh gates/test_edit_ban.sh <frozen-sha>` (no arg: reads `gates/.frozen`) |
  | fold_check | `pwsh gates/fold_check.ps1 -Base <baseRef>` | `sh gates/fold_check.sh --base <baseRef>` |
  | fold_check (CI, strict) | `pwsh gates/fold_check.ps1 -Base <baseRef> -Strict` | `sh gates/fold_check.sh --base <baseRef> --strict` |
  | constitution_lint | `pwsh gates/constitution_lint.ps1` | `sh gates/constitution_lint.sh` |
  | seam_conformance | `pwsh gates/seam_conformance.ps1` | `sh gates/seam_conformance.sh` |
  | qa_import_ban | `pwsh gates/qa_import_ban.ps1` | `sh gates/qa_import_ban.sh` |

  Every gate accepts a config override: PowerShell `-Config <path>`, POSIX `--config <path>`
  (default `gates/gates.config.json` in both).

  **coverage_check — whole-corpus vs per-unit.** With no flag, coverage_check globs the *entire*
  `paths.spec` and the *entire* test tree and asserts clauses ⊆ tagged — the **whole-corpus**
  invariant, correct **at ship** (Stage 5/7). `-Manifest <file>` / `--manifest <file>` restricts the
  clause set to the clause-IDs named in that file (one clause-ID per line, or any clause-IDs
  `clauseIdRegex` matches in it) — the **per-unit** shard manifest, for fast in-loop feedback while a
  single unit is in flight. Note the asymmetry: the shard manifest the stages hand out is a
  **context-loading** device (which shards a role may read), whereas the gate's *default* clause scope
  is **global** — the per-unit `--manifest` run is a convenience for the inner loop, never a
  replacement for the whole-corpus ship check.

  **test_edit_ban — what it proves, and the trust boundary.** Given the QA-frozen SHA, it proves that no
  path matching `testGlobs` and nothing under the gate directory (config, scripts; `.frozen` may be added)
  differs between that commit and the **working tree** — committed, staged, unstaged and untracked alike,
  with renames reported as delete + add so a test moved out of a test path still shows. The base must
  resolve **and** be an ancestor of HEAD (exit 2 otherwise); a branch name is accepted with a WARN because
  it can be advanced past the frozen point. Be honest about the boundary: anything inside the repo can be
  rewritten by whoever holds git, so the **authoritative SHA is the `frozen:` line on the changelog item**,
  passed by the Orchestrator or CI; `gates/.frozen` and the plugin hook are tripwires for the Engineer
  persona. It does not prove a tagged test ran or passed — that is `suite_green` plus the Stage-7 review
  (a JUnit-based `coverage_ran` gate is a tracked follow-up, SDD-PROP-11).

  **prose_check — spec form, measured.** Per shard: **paragraph share** (words inside paragraph text ÷
  all words; list items, table cells, code, headings and definition lists are *structured*) and the
  **longest paragraph**. HTML shards count `<p>` outside structured elements plus loose text; Markdown
  shards classify lines (list / numbered / lettered / roman items, headings, table rows, fenced code and
  indented continuation lines are structured). Defaults (`proseCheck` in config): share ≤ 35 %, longest
  paragraph ≤ 100 words, share applies only at ≥ 120 words; `excludeGlobs` for generated shards.
  **Scope = shards changed vs base** (committed + working tree + untracked), so a touched shard must meet
  the bar — migrate-on-contact — while untouched legacy shards stay quiet; `-All` / `--all` reports the
  corpus. `proseCheck.mode`: `warn` (default; prints, exit 0), `strict` (violations FAIL), `off`; `-Strict`
  / `--strict` (forwarded by `run_all`) upgrades warn to strict. Calibrated 2026-09-02 on the 4x corpus
  (252 shards, both OS scripts byte-identical): the two terse exemplars measure 15 % / 71w and 23 % / 87w;
  158 legacy shards flag. It measures *form*, not fact density — "one fact per line" stays a review call.

  **fold_check — `--strict` in CI.** When a resolver is configured (`foldCheck.resolveCmd`) but
  **errors or returns non-zero** (e.g. offline CI), default fold_check degrades to "syntactically
  valid pin + NOTE" and PASSES — a fail-open on unit-id resolution, kept for local/offline
  convenience. `-Strict` / `--strict` turns that degrade into a **FAIL** (exit 1). **CI must run
  fold_check with `--strict`** (or `run_all … --strict` / `-Strict`, which forwards it) so a broken
  or unreachable resolver cannot pass open. The "no resolver configured at all" syntactic-only path
  is unchanged either way.

- **Ship (Stage 7):** run the whole bank, fail-fast, in order:
  ```
  link_check → prose_check → coverage_check → test_edit_ban → suite_green
             → constitution_lint* → seam_conformance* → qa_import_ban* → fold_check
             → suite_green (re-run)
  ```
  - **Windows:** `pwsh gates/run_all.ps1 [baseRef] [-PreFold] [-Mechanical] [-Strict]`
  - **Linux / macOS:** `sh gates/run_all.sh [baseRef] [--pre-fold] [--mechanical] [--strict]`

  `run_all` changes to the **project root** before running anything — the git top-level of the tree the
  gates live in (so a spine vendored at `sdd/` still resolves `spec/**` and `tests/**` from the repo root),
  or `projectRoot` from the config (relative to the spine dir) for a non-git layout. Every config path is
  root-relative; run the individual gates from the root too. `[baseRef]` is the QA-frozen SHA; omitted,
  `test_edit_ban` reads `gates/.frozen`. **`suiteCmd` unset ⇒ exit 2** — the bank never reports ALL GATES
  PASSED without running the suite.

  `*` project gates run **only if** their concrete same-OS script + rules exist; absent, they are
  skipped with a notice (a fresh repo is green before you author them).
  - `-Mechanical` / `--mechanical` skips `test_edit_ban` (the mechanical route has no QA/Engineer
    split, so a single author legitimately writes tests + code together).
  - `-Strict` / `--strict` forwards `--strict` to `fold_check` (a configured resolver that
    errors/returns non-zero FAILS instead of degrading) and to `prose_check` (spec-form violations FAIL
    instead of WARN). **CI should pass it.**
  - `-PreFold` / `--pre-fold` skips `fold_check` and its post-fold suite re-run (the provenance pins
    it checks do not exist until the fold happens). **Stage-7 two-pass pattern:** run a pre-fold pass
    (`run_all.ps1 -PreFold` / `run_all.sh --pre-fold`), perform the fold, then run a full
    authoritative pass (no flag) so `fold_check` sees the pins and the suite re-runs against the
    recompiled spec index.
- **CI:** call the same per-OS scripts with `--strict` / `-Strict`; they are CI-agnostic (exit codes only).

## Config — one file, every gate reads it

`gates/gates.config.json` (flat, instantiated at INIT from the project details). Set once; never hardcode
in a script.

| Key | Meaning |
|---|---|
| `clauseIdRegex` | what a behavioural clause-ID looks like. Default `\b[A-Z]{2,}\.\d+\b` (matches `CB.12`, `POL.5`). Mirrors Project Details §5. |
| `testClauseTag` | the literal prefix a test uses to claim a clause, e.g. `@clause:`. A test tagged `@clause:CB.12` covers `CB.12`. |
| `paths.spec` | glob for content-only spec shards (`spec/**/*.body.md`). |
| `paths.tests` / `testGlobs` | globs identifying test files **and test infrastructure** — snapshots, `jest.config.*`, `pytest.ini`, `conftest.py` (coverage_check scans tags; test_edit_ban forbids edits; the plugin hook denies them at edit time). One dialect everywhere: `**` spans directories, `*` does not, anchored at the project root. |
| `testTagExcludeGlobs` | files under `testGlobs` whose `@clause:` tags do **not** count as coverage (default `**/*.md`, `**/*.txt`). |
| `paths.code` | the implementation glob (`src/**`); the plugin hook denies the `qa` persona reads under it. |
| `baseRef` | fallback base for diffs (`main`). `test_edit_ban` uses the QA-frozen SHA (argument, else `gates/.frozen`) and warns when it falls back to a branch name. |
| `projectRoot` | optional; the project root relative to the spine directory, for a non-git layout. Default: the git top-level. |
| `suiteCmd` | the project's full-suite command, from Project Details §3 `#TOOL-3`. |
| `unitIdRegex` | what a changelog unit-id looks like — Jira key (Mode A) or backlog id (Mode B). Read by fold_check; otherwise mode-blind. |
| `proseCheck` | `prose_check` tunables: `mode` (warn / strict / off), `maxParaShare`, `maxParaWords`, `minWords`, `excludeGlobs[]`. See "prose_check — spec form, measured" above. |
| `constitutionRules[]` / `seamRules[]` | project-gate rule arrays (see schema). |
| `qaImportRules[]` | project-gate rule array for `qa_import_ban` — same rule shape as the other two. Typically `must_not_match` an import of a production-internal namespace/path over the QA test glob. **Why:** the QA-blind independence (QA tests the contract, never reads the impl) is otherwise honor-system; this catches the structural half mechanically. |

## Generic vs project-specific — the split (C2)

- **Generic gates** are pure git/text ops parameterized by config. They ship as **working scripts**
  and run unmodified across projects: only `gates.config.json` changes.
- **Project-specific gates** encode *this project's* principles and seams, which differ per project.
  They ship as **template + config schema**: copy the template, author rules in config — no code.

## Rule schema (project gates)

All three project gates — `constitution_lint` (`constitutionRules`), `seam_conformance` (`seamRules`),
and `qa_import_ban` (`qaImportRules`) — run the **same engine** (the shared `_rules.ps1` / `_rules.sh`
runner they all source) over a rule array, each reading its own key. Each rule:

```jsonc
{
  "id": "SEAM-2-audit",                // stable; for seamRules MUST key to an Project Details SEAM-N
  "kind": "pair_requires",             // one of the four kinds below
  "paths": "src/**/Handlers/**/*.cs",  // glob the rule applies to
  "pattern": "ICommandHandler",        // the trigger regex
  "expect": "IAuditSink",              // (pair_requires only) regex that must ALSO be present
  "message": "handler must write an AuditEntry"  // shown on failure
}
```

| `kind` | Passes when | Use for |
|---|---|---|
| `must_match` | every file in `paths` matches `pattern` | "every migration carries `ON CONFLICT`" |
| `must_not_match` | no file in `paths` matches `pattern` | "no hardcoded UI string", "no manual DI in `Program.cs`", "no QA test imports a production-internal namespace" |
| `file_exists` | a file matching `paths` exists | "a workflow diagram accompanies a config change" |
| `pair_requires` | every file matching `pattern` ALSO matches `expect` | audit invariant, dispatch registration, `[OnEnter]` pairing |

`pair_requires` is the workhorse: most architecture seams reduce to "if a file does X it must also do
Y." Polars' audit invariant ("every `ICommandHandler` writes via `IAuditSink`") and dispatch registry
("every handler carries `[Command(...)]`") are each one such rule.

> **Regex portability:** the `.ps1` engine uses .NET regex; the `.sh` engine uses POSIX ERE via
> `grep -E`. Keep `pattern`/`expect` in the portable subset (character classes, `+ * ? { } | ( )`,
> anchors). `\b` works in both (.NET and `grep -E`); avoid PCRE-only constructs like lookaround.
> `\d`/`\s` are accepted (the `.sh` engine rewrites them to `[0-9]`/`[[:space:]]`).

## Recipe — making a project-specific gate scriptable

1. State the principle as a **mechanical predicate** over file text: *X must/must-not appear*, or
   *files doing X must also do Y*.
2. Pick the `kind`. Write `pattern` (and `expect`) as a regex. Scope with a `paths` glob.
3. Add the rule to `constitutionRules[]` (principles), `seamRules[]` (seams, keyed to a `SEAM-N`
   in Project Details §1), or `qaImportRules[]` (QA must not import production internals).
4. Copy the template **for your OS** to a concrete name — no edits; the template reads its rule
   array by name (`constitution_lint` / `seam_conformance` / `qa_import_ban`):
   - Windows: `cp gates/constitution_lint.template.ps1 gates/constitution_lint.ps1` (or `seam_conformance`, `qa_import_ban`)
   - Linux/macOS: `cp gates/constitution_lint.template.sh gates/constitution_lint.sh` (or `seam_conformance`, `qa_import_ban`)
5. `run_all` auto-detects the concrete script and runs it; no edit to `run_all.*` is needed.

> **If a principle cannot be reduced to a mechanical predicate, it is NOT a gate** — it is a line on
> the human Validation checklist (Stage 7). Don't fake a gate with a brittle regex that approximates
> judgement; write it down for the fresh reader instead.

### Recipe — the representative-default dead-wire trap

**The trap:** a convenience overload that **defaults a behaviour-arm parameter** makes every arm dead in
production while arm-explicit tests stay green — a silent, whole-feature dead-wire. **The mechanical
tell:** grep the callers of the arm-taking API; if **no** production caller passes the arm explicitly,
the default is the only live path and the other arms are dead.

Catch it, cheapest-first:

1. **Wire-canary test (preferred, most reliable).** A suite test that exercises the real wired path and
   fails if the arm is defaulted/bypassed — a DoD item (`definition-of-done.md`) and a Stage-5 QA rule
   (`stages/5_qa.md`). Lives in the project's own test framework, so it proves behaviour, not just text.
2. **`must_not_match` guard (partial, gateable now).** If the convenience overload should never exist
   for a given behaviour-arm API, forbid its *definition* with a `must_not_match` rule over the defining
   file (e.g. a default value on the arm parameter's signature). Catches the trap at the source, not the
   call sites.
3. **Callers-count check (full form — engine follow-up).** The precise predicate — "≥1 caller in
   `<glob>` passes the arm explicitly" — is an **`any_match`** semantic the current rule engine (four
   kinds) does **not** express. Do **not** approximate it with a brittle regex. Adding an `any_match`
   kind to `_rules.*` is a tracked follow-up to be authored **and smoke-tested in a live repo** (a gate
   that has never run is not trustworthy); until then, rely on (1) + (2).

## Author conventions (binding on anyone adding a gate)

- Ship a **`.ps1` + `.sh` pair** with identical behaviour. Windows runs the PowerShell (native JSON,
  no deps); Linux/macOS runs the POSIX script (`git` + `jq` only — `command -v jq` first, else
  `FAIL <gate>: needs jq (apt/brew install jq)` exit 2). No other third-party deps. Runs on a fresh clone.
- Print `PASS`/`FAIL` and the offending paths; exit nonzero on any failure (0 PASS, 1 FAIL, 2
  config/usage).
- Read all tunables from `gates.config.json` (PowerShell `Get-Content | ConvertFrom-Json`; POSIX
  `jq -r`). Never name a stack, seam, path, or tracker in a script. Share helpers via `_common.*`
  / `_rules.*`.
- A gate is a pure function of the working tree + git history + config. No network except where a
  mode explicitly needs it (fold_check Mode A may resolve a tracker key; it degrades to file-exists
  offline and says so).
- A gate must FAIL CLOSED: `test_edit_ban` and `fold_check` exit 2 (never silently PASS) when their
  base does not resolve or is not an ancestor of HEAD; `run_all` exits 2 when `suiteCmd` is unset; a
  copied-in project gate with an empty rule array exits 2. A gate that would need to skip must say so
  in a FAIL line, never in a PASS line.
- A gate must ship with a **negative control** in `ci/smoke.sh` + `ci/smoke.ps1`: one case where the
  predicate is violated and the gate FAILs naming the path. A gate that has only ever passed is not
  trustworthy.
