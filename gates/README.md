<!-- Gate Bank manifest. Loadable in isolation. Read at Stage 4–7 and when authoring a project gate. -->

# Gate Bank

Mechanical checks that close stages. **Mechanical-first, human Validation last.** Every gate is
exit-code driven (0 = PASS, nonzero = FAIL), prints `PASS`/`FAIL` + offending paths, reads one config
(`gates/gates.config.json`), and is pure git/text — no stack, seam, or tracker hardcoded. Drop any into
CI or a pre-merge hook unchanged. Where each gate sits in the whole flow, beside the hook, scripts and
human checks, and why: `../enforcement-map.md`.

## OS selection — run the script that matches the host (read this first)

Every gate ships as a **`.ps1` + `.sh` pair** with identical behaviour:

- **Windows → `.ps1`.** Native JSON; **ZERO external dependencies** — no Python, no `jq` (`git` only for
  the diff-based `test_edit_ban` and `fold_check`).
- **Linux / macOS → `.sh`.** Needs **`git` + `jq`** (`apt install jq` / `brew install jq`); without
  `jq` a gate prints `FAIL <gate>: needs jq (apt/brew install jq)` and exits 2.

> **Agents: detect the host OS and run the matching script — NEVER assume Python.**
> Windows: `pwsh gates/<gate>.ps1 …`; Linux/macOS: `sh gates/<gate>.sh …`. Results do not depend on the OS.

`run_all.ps1` invokes its `.ps1` siblings, `run_all.sh` its `.sh` siblings — never mix. The `_common.*`
and `_rules.*` helpers (config/glob/regex; the rule engine) stay next to the gates. Runs on a fresh
clone with no project runtime.

### Gates ≠ correctness

- **The bank certifies bookkeeping hygiene + traceability, NOT correctness.** It is a
  **drift-catcher, not an oracle.**
- Each gate proves a cheap structural fact — a clause has a test *tag*, a pin *resolves*, a seam
  *pattern* holds — never that the test or code is right.
- **Correctness is the human / fresh-Validation layer's job** (Stage 7).
- **Green is necessary, not sufficient:** a fully green bank can still ship a wrong system.
- The bank lets Validation spend its attention on diff-vs-spec *intent*, not on hygiene a script settled.

## One gate bank per git repository

- Every gate resolves its root with `git -C <its own location> rev-parse --show-toplevel`, so it cannot
  see inside a **nested git repo** (a submodule/gitlink, or a subdirectory with its own `.git`; GitHub
  issue #2).
- `install.sh` / `install.ps1` detect these after install/update (a gitlink, or a first-level
  subdirectory holding `.git`) and print `WARN nested git repo '<path>': ...` naming the fix.
- The fix: a **second** bank there via `install.sh --gates-only <path>` (or `install.ps1 --gates-only
  <path>`) — copies only `gates/`, seeds `gates.config.json` from the template if absent, never touches
  an existing config.
- One bank per repository boundary, always.

## The bank at a glance

| Gate | Files (Win / *nix) | Kind | Proves | Closes stage |
|---|---|---|---|---|
| coverage_check | `coverage_check.ps1` / `.sh` | generic | every behavioural clause-ID → ≥1 test-ID (both directions). **Whole-corpus by default** (ship invariant); **`--manifest` for per-unit** in-loop runs | 4 (`--plan`), 5 |
| test_edit_ban | `test_edit_ban.ps1` / `.sh` | generic | no test file, snapshot, test-runner config, gate script or gate config differs from the **QA-frozen SHA** — working tree incl. untracked, renames not collapsed; base must be an ancestor of HEAD (QA⊥Engineer, structurally) | 6, 7 |
| freeze | `freeze.ps1` / `.sh` | generic (helper) | records the QA-frozen SHA in `gates/.frozen` at Stage 5 exit and prints the `frozen:` line for the item; refuses a dirty tree | 5 |
| structure_check | `structure_check.ps1` / `.sh` | generic | the PM-approved **member-level structure diagram** holds: `--plan` every structure shard is member-level; `--frozen` no structure shard differs from the **QA-frozen SHA** (deviation guard; persona pre-fold pass); default every diagram class/member resolves under `paths.code` and a `Removed` class is absent (forward trace, every pass) | 3 / 4b (`--plan`), 6 (`--frozen`), 7 |
| token_ledger | `token_ledger.ps1` / `.sh` | generic (helper) | the Stage-4b read ledger: `add` appends a hash-stamped row with its token estimate, `verify` names STALE rows (exit 1), `report` prints the `tokens:` lines | 4b, every slice end, 7 |
| link_check | `link_check.ps1` / `.sh` | generic | every spec cross-ref resolves to a real anchor/shard | 3, 7 |
| prose_check | `prose_check.ps1` / `.sh` | generic | spec shards are terse and structured (SDD-PROP-09): paragraph-word share + longest paragraph, **changed shards vs base** by default (`-All` / `--all` for the corpus); `proseCheck.mode` warn / strict / off | 3, 7 |
| fold_check | `fold_check.ps1` / `.sh` | generic | every clause changed this ship carries a resolving provenance pin. CI runs **`--strict`** | 7 |
| suite_green | `suiteCmd` wrapper | generic | the project suite exits 0; **`suiteCmd` is mandatory** (unset = exit 2, never a skip) | 6, 7 |
| constitution_lint | `constitution_lint.template.ps1` / `.sh` | **project** | project principle checks (e.g. no hardcoded UI strings) | 7 |
| seam_conformance | `seam_conformance.template.ps1` / `.sh` | **project** | each Project Details §1 seam holds | 7 |
| qa_import_ban | `qa_import_ban.template.ps1` / `.sh` | **project** | QA tests don't import production internals (structural half of QA⊥impl; **FAILS with no rules**; the plugin hook adds the read-guard while the `qa` persona is set) | 7 |
| run_all | `run_all.ps1` / `.sh` | generic | the whole bank in order, fail-fast | 7 |

Shared helpers, not gates: `_common.ps1` / `.sh` (config + glob + regex) and `_rules.ps1` / `.sh` (the
rule engine of the three project gates).

A clause-ID counts as DECLARED only if it carries an inline anchor; bare prose occurrences are
citations that must resolve (spec-format/README §4).

## Wiring into the flow

The Stage Index (PROCESS.md §0) names which gate closes which stage; this is the other half of that
contract. Run the Windows (`pwsh …`) **or** the Linux–macOS (`sh …`) form, not both.

- **Per-stage:** `link_check` + `prose_check` + `structure_check --plan` after any spec edit (Stage 3);
  `coverage_check --plan` at Stage 4; `structure_check --plan` + `token_ledger verify` / `report` at Stage 4b
  and `token_ledger report --slice` at every slice end; `coverage_check` then `freeze` at end of Stage 5;
  `test_edit_ban <frozen-sha>` + `structure_check --frozen <frozen-sha>` + `suite_green` at end of Stage 6.

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
  | structure_check (plan) | `pwsh gates/structure_check.ps1 -Plan` | `sh gates/structure_check.sh --plan` |
  | structure_check (frozen diagram) | `pwsh gates/structure_check.ps1 -Frozen <frozen-sha>` (no sha: reads `gates/.frozen`) | `sh gates/structure_check.sh --frozen <frozen-sha>` (no sha: reads `gates/.frozen`) |
  | structure_check (forward trace) | `pwsh gates/structure_check.ps1` (`-Changed <base>` to scope) | `sh gates/structure_check.sh` (`--changed <base>` to scope) |
  | token_ledger (add a row) | `pwsh gates/token_ledger.ps1 add -Plan <file> -Kind <read\|range\|grep\|pin\|skip> -By <S> [-For <S\|*>] [-Aud any\|qa\|eng] -Path <p> [-Range <r>] [-Note <t>]` | `sh gates/token_ledger.sh add --plan <file> --kind … --by … [--for …] [--aud …] --path … [--range …] [--note …]` |
  | token_ledger (verify / report) | `pwsh gates/token_ledger.ps1 verify -Plan <file> [-For <S>]` · `… report -Plan <file> [-Slice <S>]` | `sh gates/token_ledger.sh verify --plan <file> [--for <S>]` · `… report --plan <file> [--slice <S>]` |
  | fold_check | `pwsh gates/fold_check.ps1 -Base <baseRef>` | `sh gates/fold_check.sh --base <baseRef>` |
  | fold_check (CI, strict) | `pwsh gates/fold_check.ps1 -Base <baseRef> -Strict` | `sh gates/fold_check.sh --base <baseRef> --strict` |
  | constitution_lint | `pwsh gates/constitution_lint.ps1` | `sh gates/constitution_lint.sh` |
  | seam_conformance | `pwsh gates/seam_conformance.ps1` | `sh gates/seam_conformance.sh` |
  | qa_import_ban | `pwsh gates/qa_import_ban.ps1` | `sh gates/qa_import_ban.sh` |

  Every gate takes a config override: `-Config <path>` / `--config <path>` (default
  `gates/gates.config.json`).

  **coverage_check — whole-corpus vs per-unit.**
  - No flag: globs the *entire* `paths.spec` and test tree and asserts clauses ⊆ tagged — the
    **whole-corpus** invariant, correct **at ship** (Stage 5/7).
  - `-Manifest <file>` / `--manifest <file>` restricts the clause set to the clause-IDs in that file (one
    per line, or any `clauseIdRegex` matches) — the **per-unit** shard manifest, for fast in-loop feedback.
  - Asymmetry: the stages' shard manifest is a **context-loading** device (which shards a role may read);
    the gate's *default* clause scope is **global**.
  - The per-unit run is an inner-loop convenience, never a replacement for the whole-corpus ship check.

  **test_edit_ban — what it proves, and the trust boundary.**
  - Given the QA-frozen SHA, no path matching `testGlobs` and nothing under the gate directory (config,
    scripts; `.frozen` may be added) differs between that commit and the **working tree** — committed,
    staged, unstaged and untracked alike.
  - Renames show as delete + add, so a test moved out of a test path still shows.
  - The base must resolve **and** be an ancestor of HEAD (exit 2 otherwise); a branch name gets a WARN,
    since it can advance past the frozen point.
  - Boundary: whoever holds git can rewrite anything in the repo, so the **authoritative SHA is the
    `frozen:` line on the changelog item**, passed by the Orchestrator or CI; `gates/.frozen` and the
    plugin hook are tripwires for the Engineer persona.
  - It does not prove a tagged test ran or passed — that is `suite_green` plus the Stage-7 review (a
    JUnit-based `coverage_ran` gate is a tracked follow-up, SDD-PROP-11).

  **structure_check — what it proves, and what it leaves to Validation.**
  - A structure shard (`structureGlobs`, default `**/*.structure.body.md`) holds fenced `mermaid`
    `classDiagram` blocks at member level; a transient shard is a delta under `## Added` / `## Changed` /
    `## Removed`, a canonical one the area's current state.
  - `--plan` proves shape (≥ 1 class with ≥ 1 member; a memberless class is WARNed).
  - `--frozen [sha]` is the **deviation guard**: `test_edit_ban`'s working-tree diff over the structure
    globs, fail-closed on a base that does not resolve or is not an ancestor of HEAD.
  - `run_all` runs `--frozen` on the persona route's `--pre-fold` pass only — the Stage-7 fold
    legitimately rewrites the canonical shard.
  - The default **forward trace**: every class and member under Added / Changed / an unlabelled block
    resolves to an identifier under `paths.code` (`git grep -w`, tracked + untracked, structure shards
    excluded), and a class under Removed is absent (a removed *member* still present is a WARN — the name
    may live on elsewhere).
  - Matching is by **name**, stack-agnostic: the planned member exists somewhere, not necessarily on the
    planned class.
  - The **reverse trace** — no public member in the diff that the diagram lacks — is Stage-7 Validation
    lens 2a, read from the diff; a language-aware extractor is a tracked follow-up (SDD-PROP-12).

  **token_ledger — what it measures.**
  - The Stage-4b build plan (`buildPlan.glob`, default `**/*.buildplan.md`) ends in a `## Ledger` table:
    `| kind | by | for | aud | path | range | hash | full | est | note |`.
  - `add` computes `hash` (`git hash-object`, 7 chars), `full` (whole-file tokens) and `est` (tokens of
    the range / grep window / pasted note; `0` for `skip`; the admitted tokens for `read`), with tokens =
    `ceil(chars × buildPlan.tokensPerChar)` (default `0.25`). It refuses a `qa`-audience row pointing into
    `paths.code`.
  - `verify` prints `STALE` (exit 1) for any row whose hash no longer matches the file — reconcile, never
    assume.
  - `report` sums, per slice, `admitted` (its `read` rows) and `saved` (per advice row aimed at it: the
    whole-file cost if it never opened the file, the difference if it read a range, nothing if it read
    the whole file — "not honoured"), printing `tokens: <slice> admitted ~A; saved ~V (P%); ledger H/N
    honoured` plus a plan line with the planning cost `P`.
  - ASCII on both twins, recomputable from the table, **an estimate from bytes admitted — never a billed
    count**.

  **prose_check — spec form, measured.**
  - Per shard: **paragraph share** (paragraph-text words ÷ all words; list items, table cells, code,
    headings and definition lists are *structured*) and the **longest paragraph**.
  - HTML shards count `<p>` outside structured elements plus loose text; Markdown shards classify lines
    (list / numbered / lettered / roman items, headings, table rows, fenced code and indented
    continuation lines are structured).
  - Defaults (`proseCheck`): share ≤ 35 %, longest paragraph ≤ 100 words, share only at ≥ 120 words;
    `excludeGlobs` for generated shards.
  - **Scope = shards changed vs base** (committed + working tree + untracked): a touched shard must meet
    the bar — migrate-on-contact — while untouched legacy shards stay quiet; `-All` / `--all` reports the
    corpus.
  - `proseCheck.mode`: `warn` (default; prints, exit 0), `strict` (violations FAIL), `off`; `-Strict` /
    `--strict` (forwarded by `run_all`) upgrades warn to strict.
  - Calibrated 2026-09-02 on a 252-shard corpus (both twins byte-identical): the two terse exemplars
    measure 15 % / 71w and 23 % / 87w; 158 legacy shards flag.
  - It measures *form*, not fact density — "one fact per line" stays a review call.

  **fold_check — `--strict` in CI.**
  - When a configured resolver (`foldCheck.resolveCmd`) **errors or returns non-zero** (e.g. offline CI),
    default fold_check degrades to "syntactically valid pin + NOTE" and PASSES — fail-open on unit-id
    resolution, for local/offline convenience.
  - `-Strict` / `--strict` turns that degrade into a **FAIL** (exit 1). **CI must run it** (directly or
    via `run_all … --strict` / `-Strict`), so a broken or unreachable resolver cannot pass open.
  - With no resolver configured, the syntactic-only path is unchanged either way.

- **Ship (Stage 7):** run the whole bank, fail-fast, in order:
  ```
  link_check → prose_check → coverage_check → test_edit_ban → structure_check → suite_green
             → constitution_lint* → seam_conformance* → qa_import_ban* → fold_check
             → suite_green (re-run)
  ```
  (`structure_check --frozen` precedes the trace on the persona route's `--pre-fold` pass only.)
  - **Windows:** `pwsh gates/run_all.ps1 [baseRef] [-PreFold] [-Mechanical] [-Strict]`
  - **Linux / macOS:** `sh gates/run_all.sh [baseRef] [--pre-fold] [--mechanical] [--strict]`

  `run_all` first changes to the **project root** — the git top-level of the tree the gates live in (so a
  spine vendored at `sdd/` still resolves `spec/**` and `tests/**` from the repo root), or `projectRoot`
  from the config (relative to the spine dir) for a non-git layout. Config paths are root-relative; run
  individual gates from the root too. `[baseRef]` is the QA-frozen SHA; omitted, `test_edit_ban` reads
  `gates/.frozen`. **`suiteCmd` unset ⇒ exit 2** — never ALL GATES PASSED without running the suite.

  `*` project gates run **only if** their concrete same-OS script + rules exist; else skipped with a
  notice (a fresh repo is green before you author them).
  - `-Mechanical` / `--mechanical` skips `test_edit_ban` (no QA/Engineer split: a single author writes
    tests + code).
  - `-Strict` / `--strict` forwards to `fold_check` and `prose_check` (above). **CI should pass it.**
  - `-PreFold` / `--pre-fold` skips `fold_check` and its post-fold suite re-run (the pins do not exist
    until the fold). **Stage-7 two-pass pattern:** a pre-fold pass, the fold, then a full authoritative
    pass (no flag) so `fold_check` sees the pins and the suite re-runs against the recompiled spec index.
- **CI:** the same per-OS scripts with `--strict` / `-Strict`; CI-agnostic (exit codes only).

## Config — one file, every gate reads it

`gates/gates.config.json` (flat, instantiated at INIT from the project details). Set once; never hardcode
in a script.

| Key | Meaning |
|---|---|
| `clauseIdRegex` | what a behavioural clause-ID looks like. Default `\b[A-Z]{2,}\.\d+\b` (matches `CB.12`, `POL.5`). Mirrors Project Details §5. |
| `testClauseTag` | the literal prefix a test uses to claim a clause, e.g. `@clause:` — `@clause:CB.12` covers `CB.12`. |
| `paths.spec` | glob for content-only spec shards (`spec/**/*.body.md`). |
| `paths.tests` / `testGlobs` | test files **and test infrastructure** — snapshots, `jest.config.*`, `pytest.ini`, `conftest.py` (coverage_check scans tags; test_edit_ban forbids edits; the plugin hook denies them at edit time). One dialect everywhere: `**` spans directories, `*` does not, anchored at the project root. |
| `testTagExcludeGlobs` | files under `testGlobs` whose `@clause:` tags do **not** count as coverage (default `**/*.md`, `**/*.txt`). |
| `structureGlobs` | the PM-approved structure shards (default `**/*.structure.body.md`): `structure_check --frozen` forbids edits vs the frozen SHA, the plugin hook denies the `engineer` persona, the forward trace resolves their members under `paths.code`. |
| `buildPlan` | `glob` for the Stage-4b build plan (default `**/*.buildplan.md`) and `tokensPerChar` (default `0.25`) for every `token_ledger` estimate. |
| `paths.code` | the implementation glob (`src/**`), or an array; the plugin hook denies the `qa` persona reads and Bash path tokens under it, except paths matching `testGlobs`. |
| `baseRef` | fallback base for diffs (`main`). `test_edit_ban` uses the QA-frozen SHA (argument, else `gates/.frozen`) and warns when it falls back to a branch name. |
| `projectRoot` | optional; the project root relative to the spine directory, for a non-git layout. Default: the git top-level. |
| `suiteCmd` | the project's full-suite command, from Project Details §3 `#TOOL-3`. |
| `unitIdRegex` | what a changelog unit-id looks like — Jira key (Mode A) or backlog id (Mode B). Read by fold_check; otherwise mode-blind. |
| `proseCheck` | `prose_check` tunables: `mode` (warn / strict / off), `maxParaShare`, `maxParaWords`, `minWords`, `excludeGlobs[]` (see above). |
| `constitutionRules[]` / `seamRules[]` | project-gate rule arrays (see schema). |
| `qaImportRules[]` | `qa_import_ban`'s rule array, same shape — typically `must_not_match` an import of a production-internal namespace/path over the QA test glob. **Why:** QA-blind independence is otherwise honor-system; this catches its structural half. |

## Generic vs project-specific — the split (C2)

- **Generic gates** are pure git/text ops parameterized by config. They ship as **working scripts**
  (verified against the INIT smoke fixture) and run unmodified across projects: only
  `gates.config.json` changes.
- **Project-specific gates** encode *this project's* principles and seams. They ship as
  **`.template.ps1` + `.template.sh` + config schema**: copy the template **of your OS** to a concrete
  name (Recipe below) and author rules in config — no code.

## Rule schema (project gates)

`constitution_lint` (`constitutionRules`), `seam_conformance` (`seamRules`) and `qa_import_ban`
(`qaImportRules`) run the **same engine** (`_rules.ps1` / `_rules.sh`) over their own rule array. Each rule:

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

`pair_requires` is the workhorse: most seams reduce to "if a file does X it must also do Y" — e.g. Polars'
"every `ICommandHandler` writes via `IAuditSink`" and "every handler carries `[Command(...)]`".

- **Regex portability:** `.ps1` uses .NET regex; `.sh` uses POSIX ERE via `grep -E`.
  - Stay in the portable subset (character classes, `+ * ? { } | ( )`, anchors). `\b` works in both;
    avoid PCRE-only constructs like lookaround.
  - Both match **line by line** (since v1.15.0): `^` and `$` anchor each line; no match spans a newline.
  - Inside `[...]`, write a tab as the JSON escape `"\t"` (a real tab), never the regex escape `\\t` —
    `grep -E` reads that as a backslash and a `t`.
  - `\d`/`\s` are accepted (the `.sh` engine rewrites them to `[0-9]`/`[[:space:]]`).

## Recipe — making a project-specific gate scriptable

1. State the principle as a **mechanical predicate** over file text: *X must/must-not appear*, or
   *files doing X must also do Y*.
2. Pick the `kind`; write `pattern` (and `expect`) as a regex; scope with a `paths` glob.
3. Add the rule to `constitutionRules[]` (principles), `seamRules[]` (seams, keyed to a `SEAM-N`
   in Project Details §1), or `qaImportRules[]` (QA must not import production internals).
4. Copy the template **for your OS** to a concrete name, unedited (it reads its rule array by name):
   - Windows: `cp gates/constitution_lint.template.ps1 gates/constitution_lint.ps1` (or `seam_conformance`, `qa_import_ban`)
   - Linux/macOS: `cp gates/constitution_lint.template.sh gates/constitution_lint.sh` (or `seam_conformance`, `qa_import_ban`)
5. `run_all` auto-detects and runs the concrete script; no `run_all.*` edit needed.

> **If a principle cannot be reduced to a mechanical predicate, it is NOT a gate** — it is a line on
> the human Validation checklist (Stage 7). Don't fake judgement with a brittle regex.

### Recipe — the representative-default dead-wire trap

**The trap:** a convenience overload that **defaults a behaviour-arm parameter** makes every other arm
dead in production while arm-explicit tests stay green. **The tell:** if **no** production caller of
the arm-taking API passes the arm explicitly, the default is the only live path.

Catch it, cheapest-first:

1. **Wire-canary test (preferred, most reliable).** A suite test that exercises the real wired path and
   fails if the arm is defaulted/bypassed — a DoD item (`definition-of-done.md`) and a Stage-5 QA rule
   (`stages/5_qa.md`). It proves behaviour, not just text.
2. **`must_not_match` guard (partial, gateable now).** If the convenience overload should never exist,
   forbid its *definition* (e.g. a default value on the arm parameter) with a `must_not_match` rule over
   the defining file — caught at the source, not the call sites.
3. **Callers-count check (full form — engine follow-up).** "≥1 caller in `<glob>` passes the arm
   explicitly" is an **`any_match`** semantic the four-kind engine does **not** express; do **not**
   approximate it with a regex. An `any_match` kind is a tracked follow-up, to be **smoke-tested in a
   live repo** before trusted (a gate that has never run is not trustworthy); until then, rely on (1) + (2).

## Author conventions (binding on anyone adding a gate)

- Ship a **`.ps1` + `.sh` pair** with identical behaviour and the dependencies of "OS selection" above
  (`.sh`: `command -v jq` first). No other third-party deps; runs on a fresh clone.
- Print `PASS`/`FAIL` and the offending paths; exit 0 PASS, 1 FAIL, 2 config/usage.
- Read all tunables from `gates.config.json` (PowerShell `Get-Content | ConvertFrom-Json`; POSIX
  `jq -r`). Never name a stack, seam, path, or tracker in a script. Share helpers via `_common.*` /
  `_rules.*`.
- A gate is a pure function of working tree + git history + config. No network unless a mode needs it
  (fold_check Mode A may resolve a tracker key; offline it degrades to file-exists and says so).
- A gate must FAIL CLOSED: `test_edit_ban` and `fold_check` exit 2 (never a silent PASS) when their
  base does not resolve or is not an ancestor of HEAD; `run_all` exits 2 when `suiteCmd` is unset; a
  copied-in project gate with an empty rule array exits 2. A needed skip is said in a FAIL line, never
  a PASS line.
- A gate must ship with a **negative control** in `ci/smoke.sh` + `ci/smoke.ps1`: a violating case where
  the gate FAILs naming the path. A gate that has only ever passed is not trustworthy.
