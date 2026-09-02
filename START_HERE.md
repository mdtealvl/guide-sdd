# START HERE

You just unzipped **GUIDE SDD** — Gated, Unified, Intent-Driven Engineering, a spec-driven development framework (short name `sdd`). This is the front door.

## If you are an AI agent (e.g. told "unzip `sdd.zip` and follow the instructions")

Do exactly this, nothing else, until setup is green:

1. Read `project-config/INIT.md` — the setup runbook. Execute it top to bottom. If `sdd/.sdd-manifest.json`
   exists, the installer already did the copying (INIT §0, §1 carriers, §2c commands, §5 config seed) — start at §1a.
2. At each **ASK**, ask the human and wait: changelog mode, greenfield vs brownfield, spec format.
3. Wire the always-loaded core into the agent carrier (`AGENTS.md`; `CLAUDE.md` routes to it, Copilot via a shim — `host-adapter.md`), set this box's role, instantiate project details + gate config.
4. Run the gate smoke test **for this OS** — PowerShell (`.ps1`) on Windows, Bash (`.sh`) on Linux/macOS. See `gates/README.md`. No Python.
5. Stop and report when the smoke test is green. **Do not build features during setup.**

After setup, every unit of work flows through `PROCESS.md` §0 (the stage router): load only your
current stage, never the whole framework. Before touching code in an existing repo, check
`greenfield-vs-brownfield.md` — if the area has no spec, flag the gap, do not guess.

## If you are a human

- **What it is:** a reusable, token-efficient, spec-first method for projects worked by humans *and* AI agents. The spec is the source of truth; code conforms; a 2×2 right-sizes each task; risky work is split across independent agents so a misread can't ship.
- **5-minute tour:** open `welcome.html` in a browser.
- **Adopt it:** walk `project-config/INIT.md` (≈20 min).

## Map

| You want… | Open |
|---|---|
| To set it up | `project-config/INIT.md` |
| The non-negotiables (always loaded) | `constitution.md` |
| How work flows | `PROCESS.md` + `stages/` |
| New code vs existing code | `greenfield-vs-brownfield.md` |
| Who-does-what across machines | `box-roles.md` |
| Which agent tool / going cross-agent | `host-adapter.md` |
| To write a ticket | `changelog-conventions.md` |
| When work is Ready / Done | `definition-of-done.md` |
| To retire something safely | `lifecycle-states.md` |
| The gates (PowerShell + Bash) | `gates/README.md` |
| The spec format | `spec-format/README.md` |
| A pretty tour | `welcome.html` |
| The full picture | `README.md` |
