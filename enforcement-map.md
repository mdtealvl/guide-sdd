<!-- Enforcement map. Loadable in isolation. Read when choosing how a new check should be enforced, or to see the whole flow at once. Not a stage file: no stage loads it. -->

# Enforcement map — every check, in order, and why it is the kind it is

GUIDE enforces its rules through five kinds of check. Each point in the flow uses the cheapest kind
that can actually prove (or catch) the thing it guards. This page lists every check from install to
ship, names its kind, and says why that kind was chosen. Commands and flags live in `gates/README.md`;
stage rules live in `stages/`.

## The five kinds

| Kind | Where | What it is | Use it when |
|---|---|---|---|
| **Gate** | `gates/*.ps1` + `*.sh` | Exit-code check over the project tree. One flat config (`gates.config.json`), ps1/sh twins with identical output, closes a stage, runs in the target repo's CI (`ci/target-ci.template.yml`). | The claim is a **structural fact about the project tree** that must hold at a stage boundary, on every box and OS, and be re-runnable by CI. |
| **Gate helper** | `gates/freeze.*`, `gates/token_ledger.*`, `gates/run_all.*` | Same family, but records state or orchestrates other gates instead of returning a verdict on the tree. | A gate needs an input recorded at a known moment (the frozen SHA, a read ledger), or gates must run as one fail-fast bank. |
| **Hook** | `plugin/hooks/persona-guard.sh` (Claude Code plugin) | Write-time tripwire around each agent tool call. Blocks or flags at the moment of action. | Stopping a mistake **as it happens** is worth a lot, but proof can wait for a gate. A hook is never the proof: it only exists on Tier A hosts with the plugin. |
| **Script** | `install.*`, `ci/*`, inline workflow steps | Operates on the **framework or the install**, not on a project's work. | The subject is the spine itself (version stamps, twin parity, installer copies, manifest drift), or the check compares two files / runs the gates against fixtures. A gate cannot test the gates. |
| **Human / Validation** | PM approvals, fresh Validation (Stage 7) | Judgement against spec and intent. | The question is "is this right?", not "is this present?". **Gates certify bookkeeping and traceability, never correctness.** |

Decision rule for a new check: if it is about the project tree and must hold at a stage boundary,
make it a gate (a generic gate if every project needs it, a `constitutionRules` / `seamRules` /
`qaImportRules` row if it is one project's rule). If it must fire during the edit, add a hook pass
**and** keep the gate. If its subject is the framework or the install, it is a script. If it needs
judgement, it is Validation.

## The flow

```mermaid
flowchart LR
  I[Install + INIT] --> S0[0 Triage] --> S1[1 Design] --> S2[2 Recon] --> S3[3 Spec]
  S3 --> S4[4 Test plan] --> S4b[4b Build plan] --> S5[5 QA] --> S6[6 Engineer] --> S7[7 Ship + fold]
  S7 --> CI[Target CI]
  classDef human fill:#f6e7c8,stroke:#b8862b
  classDef gate fill:#d7ecd9,stroke:#3f8a4a
  class S0,S1,S2 human
  class S3,S4,S4b,S5,S6,S7,CI gate
```

Green boxes close on a gate; amber boxes close on a recorded human decision.

### Setup — install and INIT

| Check | Kind | Why this kind |
|---|---|---|
| `install.* install` / `update` — copies the spine, writes `sdd/.sdd-manifest.json`, refuses a dirty tree or a locally edited spine file | Script | Its subject is the install, not project work. Runs once per install or update. |
| Nested-repo `WARN` (gitlink or subdirectory with its own `.git`) | Script | The gate bank cannot see inside a nested repo, so the installer has to flag it. The fix is a second bank (`--gates-only`). |
| `install.* doctor` / `/sdd-doctor` — spine files vs the manifest | Script | Manifest drift is about the install. Run it before trusting the gates. |
| INIT §6 smoke test — a demo clause, a tagged test, `run_all` green, then two negative controls (a clause with no test must fail `coverage_check`; an uncommitted test edit must fail `test_edit_ban`) | Gate | Proves the bank works **on this box and OS** before any real work trusts it. Uses the real gates on a throwaway fixture. |

### Stages 0–2 — no script gate

| Stage | Closes on | Why no gate |
|---|---|---|
| 0 Triage | Routing decision + shard manifest recorded on the item | Right-sizing is a judgement call; the record is what later gates read. |
| 1 Design (persona route) | PM approves design prose + draft structure diagram | The diagram's *content* is a design decision. Its *form* is gated at Stage 3. |
| 2 Recon (persona route) | Viability recorded | Whether a prerequisite is viable needs a person or the Orchestrator. |

### Stage 3 — Spec

| Check | Kind | Why this kind |
|---|---|---|
| `link_check` — every cross-ref resolves to a real anchor or shard | Gate | A broken reference is a structural fact. Cheap, deterministic, the same on every box. |
| `prose_check` — paragraph share and longest paragraph per shard (warn, strict or off) | Gate | Spec form (SDD-PROP-09) is measurable. Mode is set per project, because the heuristic can misfire (e.g. on HTML-heavy shards). |
| `structure_check --plan` — every structure shard is member-level | Gate | Member-level form is countable; the PM's approval covers the content. |
| PM approves the spec diff and the structure shard | Human | Whether the spec says the right thing is judgement. Last gate before any test or code. |

### Stage 4 / 4b — Test plan and build plan

| Check | Kind | Why this kind |
|---|---|---|
| `coverage_check --plan` — every clause has a planned scenario | Gate | Traceability is set membership over the spec and the plan. |
| `structure_check --plan` | Gate | Re-checked because the build plan reads the structure shard. |
| `token_ledger add` / `verify` / `report` — hash-stamped read ledger | Gate helper | Records what each later context may read and flags STALE rows. A ledger, not a verdict on the tree. |

### Stage 5 — QA (persona route)

| Check | Kind | Why this kind |
|---|---|---|
| `qa` persona read guard — no Read/Grep/Glob or Bash path under `paths.code`, except QA's own `testGlobs` files | Hook | Blindness to the implementation has to hold *while* QA works. Afterwards nothing can prove what QA read. Tier A with the plugin only. |
| `qa_import_ban` — QA tests import no production internals | Gate (project rules) | The structural half of QA blindness, provable from the test files on any host. Fails with no rules, so it cannot pass silently. |
| `coverage_check` — every clause has at least one tagged test | Gate | Tags are text; coverage is set membership. |
| Suite runs red as expected; tests compile | Human (Orchestrator) | "Red for the right reason" needs reading the failures. |
| `freeze` — records the QA-frozen SHA in `gates/.frozen` and prints the `frozen:` line | Gate helper | Every later edit-ban check needs a fixed base, recorded at this exact moment. The `frozen:` line on the item is authoritative; the file is a mirror. |

### Stage 6 — Engineer (persona route)

| Check | Kind | Why this kind |
|---|---|---|
| `engineer` persona edit guard — no edits to tests, the structure diagram, the gate bank or markers; tree swept after each Bash call and edit tool, and at turn end | Hook | Catches the edit as it happens, so the Engineer reverts at once instead of building on it. Only a tripwire: Tier B/C hosts have no hook. |
| `test_edit_ban <frozen-sha>` — no test, runner config, gate script or gate config differs from the frozen SHA (working tree, untracked, renames) | Gate | **The proof** of QA ⊥ Engineer. Works on every tier because it reads git, not the agent. |
| `structure_check --frozen` — the approved diagram did not move | Gate | Same reasoning as the edit ban, for the structure shard. A deviation is `[NEEDS-PO:structure]`, never an edit. |
| `suite_green` — `suiteCmd` exits 0 | Gate | The suite is the project's own oracle. An unset `suiteCmd` is exit 2, never a skip. |

### Stage 7 — Ship and fold

| Check | Kind | Why this kind |
|---|---|---|
| `run_all --pre-fold` — link → prose → coverage → test_edit_ban\* → structure → suite → constitution_lint† → seam_conformance† → qa_import_ban† (fold_check skipped) | Gate helper running gates | One fail-fast bank, so nothing is forgotten. \*Persona route only. †Only when the project copied the template and wrote rules. |
| `constitution_lint` / `seam_conformance` — the project's own principles and seams | Gate (project rules) | Project rules written as regex rows over the tree. One engine, no script edits per project. |
| Fresh Validation — four lenses, one verdict, against the full diff, spec, structure shard and constitution | Human / Validation | **Green is necessary, not sufficient.** A context that did not build the thing checks intent. |
| Classify and route Validation's findings (spec / code / test / ...), decline cap 3 | Human (Orchestrator) | Which layer is wrong is a judgement; the routing table makes it repeatable. |
| Fold, then authoritative `run_all` (post-fold) — adds `fold_check`: every changed clause carries a resolving provenance pin; suite re-run | Gate | Pins are text that must resolve. They exist only after the fold, hence the two passes. |
| Merge | Human (Orchestrator) | One serialized merge to trunk, owned by a person or the Orchestrator. |

### After ship — target CI

| Check | Kind | Why this kind |
|---|---|---|
| `ci/target-ci.template.yml` — `run_all --strict` on every PR (`--mechanical` with no `.frozen`) | Gate | Nothing consumes gate verdicts unless something runs them. Branch protection should require this job. Reviewers compare `gates/.frozen` with the item's `frozen:` line. |

## The framework repo's own checks

These guard GUIDE itself, not a project. They are scripts because their subject is the spine, or
because they test the gates. `ci/` is never installed into a target repo.

| Check | Runs in | Kind | Why this kind |
|---|---|---|---|
| `ci/version_check.sh` — VERSION = README header = changelog tail = plugin.json (= tag on release) | ci, release | Script | Release metadata of the framework. No project gate has this subject. |
| `ci/smoke.sh --compare` — the INIT §6 smoke plus a negative control per known bypass, sh gates with ps1 output compared | ci (ubuntu), release | Script | Tests the gates. A gate cannot test itself. |
| `ci/smoke.ps1` — the same on the ps1 gates | ci (windows) | Script | Proves the Windows family on a Windows runner. |
| `ci/hook_test.sh` — persona guard cases (PG.1–PG.9) | ci (ubuntu) | Script | Tests the hook against synthetic tool calls. |
| `prose_check` over the spine (warn only) | ci (ubuntu) | Gate | The spine is held to its own spec form. Warn only: it does not yet pass (SDD-PROP-11). |
| `cmp install.* plugin/bin/install.*` | ci (ubuntu) | Script | Compares two files. The rule engine checks one file at a time. |
| `claude plugin validate --strict` (plugin + marketplace) | ci (ubuntu) | External tool | The schema belongs to Claude Code. |
| Pages build: `.md` links rewritten, none left relative | pages | Script | Checks the published site's build output, not the spine. |
| Release zip: rsync excludes framework-only files, sha256, notes from the changelog | release | Script | Packaging. |

Not run on the spine, by decision: `link_check` (the spine cites files as backticked paths, not
links, so the gate has almost nothing to check) and the stage gates (`coverage_check`,
`test_edit_ban`, `fold_check`, `structure_check`), which need a spec, tests and code the framework
repo does not have.

## Known gaps

- **Rule-engine twin parity.** `_rules.ps1` matches a rule's regex against the whole file;
  `_rules.sh` uses `grep -E`, one line at a time. A rule using `^`, `$` or a negated class can pass
  on one OS and fail on the other. Affects `constitution_lint`, `seam_conformance` and
  `qa_import_ban`. Until it is fixed, write rules without line anchors.
- **Framework conventions are not yet gated.** No bashisms in `.sh` (Ubuntu `sh` is dash), ASCII-only
  gate output, a builtins-only hook — today these hold by review and by smoke coverage of executed
  paths only. They belong in a `constitution_lint` run over the spine, after the parity fix.
- **The spine prose self-check config lives inline in `ci.yml`**, so it cannot be re-run locally as is.
- **Persona guard normalization gaps** on the qa side — GitHub issue #5.
