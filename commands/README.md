# SDD session / context-lifecycle commands

> Bundled capability, **not spine**.
> - These are the Tier-A implementation of the spine module `session-lifecycle.md` (the **session/context**
>   lifecycle, beside the spine's **item** lifecycle); the plugin ships them as skills.
> - Origin: the 4x project's session practice (2026-07-14); the module, the DoD lane-reconciliation item
>   and INIT memory seeding were ratified in v1.7 (`SDD-PROP-01/03/05`).

## The three commands

| Command | Does |
|---|---|
| `/wrap` | End-of-session externalization pass: reconcile every agent lane (LANDED(hash)/DIED), land-or-park the tree, update the backlog, bank memories, write spec debt, **overwrite** the HANDOFF card, report — then "Cleared for /clear." |
| `/stash [-f] <name>` · `/stash -l` | Freeze the **current task** to a named resume pack (richer than HANDOFF) so a `/clear` loses nothing; list with `-l`. |
| `/unstash <name>` | Resume a stashed task: wrap any live context first, reconstruct the working set at pinned locations, re-dispatch recorded agent briefs, pop-with-archive, continue. |

## Capability tier (`host-adapter.md`)

- **Tier A — Claude Code (and any host with native slash-commands).** Copy `commands/*.md` into the
  target repo's `.claude/commands/`; `/wrap`, `/stash <name>`, `/unstash <name>` are then live. (Copilot /
  Cursor: the same bodies under `.github/prompts/` / `.cursor/commands/`.)
- **Tier B / C — no slash-commands.** Run the same ordered steps by hand: the `/wrap` list at an
  unambiguous session close, the `/stash` freeze to switch tasks, `/unstash` to resume. The bodies here
  are the procedure.

## The project memory directory (convention these assume)

- The commands read/write a per-project **memory directory** (path bound in `project-details.md#CL-`,
  Mode-A/B aware; seeded at INIT). Expected layout:

```
<memory-dir>/
  MEMORY.md         # the index loaded each boot — one line per memory, no content
  HANDOFF.md        # the mutable "you are here" card — OVERWRITTEN each wrap, never appended
  (the backlog itself lives at #CL-1: backlog/ item files in Mode B, the tracker in Mode A)
  stashes/          # named resume packs; stashes/archive/ holds consumed packs
  memory/           # banked trap memories (+ memory/archive.md for pruned entries)
```

- Per-project **contents** stay local by design — the *practice* of banking traps ports; the specific
  traps do not.

## Why these belong with SDD

- `/wrap` step 1 (**agent-lane reconciliation** — every dispatched lane gets a LANDED(hash)-or-DIED
  verdict before a boundary) is the session-level form of "trust artifacts, not narratives":
  *an agent's existence is not evidence its work landed.* It cost the origin project two lost fixes
  before it was learned; it is now a DoD item.
- The HANDOFF-overwrite rule and stash/unstash semantics are the session-lifecycle counterpart to the
  spec's canonical-vs-transient split.
