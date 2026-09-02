---
name: sdd-init
description: Install GUIDE SDD into this repo - vendor the spine to sdd/, place the Claude carriers, seed the gate config, then run INIT from section 1a (box tier/role and the three ASKs stay with the human).
argument-hint: "[--dest sdd] [--version vX.Y.Z|latest] [--carriers claude,codex,copilot,cursor]"
disable-model-invocation: true
allowed-tools: Bash, Read, Edit, Write, AskUserQuestion
---

# /sdd-init — adopt GUIDE SDD here

Run from the repo root. Arguments: $ARGUMENTS (defaults: `--dest sdd --carriers claude`).

1. Say: *"Welcome to GUIDE SDD — I'm setting up a spec-first development process for this project: the spec stays the source of truth, risky work is split across independent agents, and every change is gated. I'll vendor the framework, then ask three quick setup questions, then verify the gates run."*
2. Run the installer that ships with this plugin (it never touches project files and stops before the ASKs):
   - Windows: `pwsh "${CLAUDE_PLUGIN_ROOT}/bin/install.ps1" install $ARGUMENTS`
   - Linux/macOS: `sh "${CLAUDE_PLUGIN_ROOT}/bin/install.sh" install $ARGUMENTS`

   Do **not** pass `--commands`: /wrap, /stash and /unstash come from this plugin. If it says the spine is already installed, stop and offer `/sdd-update` instead.
3. Open `<dest>/project-config/INIT.md` and execute it from **§1a** to the end: set the box tier and role (per-box, uncommitted), ask the three **ASK**s one at a time (changelog mode, greenfield vs brownfield, spec format), instantiate Project Details and the gate config, and run the §6 smoke test **for this OS**.
4. Stop when the smoke test is green and report. Do not build features during setup.
