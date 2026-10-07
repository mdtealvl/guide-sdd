# Discover Spec — brownfield characterization

> Demand-loaded spine. A deliberate, scoped action on an existing codebase with little/no spec:
> - Reconstruct enough spec to understand it; baseline test **coverage + quality**; produce a prioritized
>   test plan to the targets.
> - Scope: an AREA (or the repo) — distinct from the per-unit brownfield rule (reconstruct only the
>   slice you touch, `greenfield-vs-brownfield.md`).
> - Expensive; run on purpose. PO-box work. Output is a backlog; normal per-item flow then resumes.

## The hard rule: reconstructed spec is PROVISIONAL

Spec reconstructed from code describes **current** behaviour — which may encode bugs. So:
- Every reconstructed clause is marked **provisional** (`status: provisional, reconstructed <date>, per code@<sha>`) — it states *what the code does*, not *what the system shall do*.
- The PM **ratifies** a provisional clause when a unit touches it (the `greenfield-vs-brownfield.md` escalation). Until then it is a characterization, not a requirement.
- Anything suspicious or non-obvious ⇒ the unspecified-surface register + `[NEEDS-PO]`. **Never silently bless a bug as spec.**

## Phase 1 — Map

- **Survey:** entry points (controllers / handlers / CLI / jobs / consumers), public contracts
  (API / message / schema), data models, the dependency graph.
- **Seams** (boundaries that must not be bypassed) — these become Project Details §1.
- **Output:** an architecture map + the behavioural surfaces, **ranked by blast radius**
  (money / auth / data-integrity / the seams first).

## Phase 2 — Reconstruct (draft spec)

- Per surface, **EARS clauses** for current observable behaviour, from code + existing tests + docs.
- Stable IDs, content-only shards under the SDD spec root (`spec/sdd/`), each marked provisional.
- Enough to understand the system — not a finished spec.

## Phase 3 — Characterize (golden-master safety net)

- Where behaviour is understood but untested, write **characterization tests** pinning current
  behaviour, so nothing changes silently before ratification.
- Tag them `@characterization` — they assert *what is*, not *what should be*.

## Phase 4 — Measure (coverage AND quality — they differ)

Baseline both, per layer (unit / functional / integration) and per surface:

- **Coverage (quantity):** line + branch via the project's tool (.NET: `dotnet test --collect:"XPlat Code Coverage"` → coverlet/cobertura; JS: `vitest --coverage`); tool + command in Project Details. Target **≥85% line/branch** on the prioritized surfaces.
- **Quality (do the tests catch bugs?):** a suite can execute 90% of lines and assert nothing. Measure:
  1. **Mutation score** — a mutation tester (.NET: Stryker.NET; JS: StrykerJS) injects faults; the score is the fraction the suite **kills**. Target a **mutation floor** (start **≥70%** on prioritized surfaces, rising).
  2. **"A test you can trust"** (invariant 4): each test declares an **oracle source** (from spec, not code) and has **no blocking fixture gap**. A characterization test that only snapshots code output is coverage, not trust — flag it for spec-derived replacement.
- Report a **matrix: surface × {line %, branch %, mutation %}** — showing the seams and money paths are well-tested, not just the easy getters.

## Phase 5 — Plan (to the targets, risk-first)

A **prioritized test backlog** (changelog items) closing the gaps to ≥85% coverage + the mutation floor.
- Ordered by **risk**: seams, money/auth/data-integrity, high-blast-radius-low-coverage first — never
  blanket 85% on trivial code.
- Each item maps to reconstructed clause-ID(s), names its test layer(s), declares its oracle source,
  carries points + route (most are mechanical/parallel test-adds).

## Output — the Discovery Report

1. Architecture map + ranked surfaces.
2. Provisional spec shards (`spec/sdd/`).
3. Coverage + mutation baseline matrix.
4. The populated unspecified-surface register.
5. The prioritized test backlog (Stage-0-ready).

Then normal SDD: each item flows through the stage loop, the PM ratifies provisional clauses as
they're touched, and coverage + mutation climb as the backlog burns down.

## Config (Project Details)

- Coverage tool + command; mutation tool + command.
- Coverage target (default **85%** line/branch) and mutation floor (default **70%**).
- The prioritized-surface list.
- A `coverage_floor` project-gate can enforce the targets at ship once past baseline.

## Cross-links

- `greenfield-vs-brownfield.md` (the per-unit rule this scales up)
- `definition-of-done.md` (oracle + fixture-gap + trust)
- `changelog-conventions.md` (the backlog items)
- `project-details.md` (tools, targets, seams)
- constitution invariant 4 (a test you can trust)
