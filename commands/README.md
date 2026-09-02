# SDD session / context-lifecycle commands

> Bundled capability, **not spine**. SDD's spine governs the **item** lifecycle (Ready → Done); these
> govern the **session/context** lifecycle — the ritual that gets durable state out of a volatile agent
> context before it is cleared, so the next boot loses nothing. Origin: the 4x project's session
> practice (2026-07-14). Deeper integration (a spine module, DoD gate, INIT auto-install + memory
> seeding) is **proposed, not yet ratified** — see `project-config/PROPOSED_CHANGELOG.md`
> (`SDD-PROP-01/03/05`). Until then these ship as a usable drop-in.

## The three commands

| Command | Does |
|---|---|
| `/wrap` | End-of-session externalization pass: reconcile every agent lane (LANDED(hash)/DIED), land-or-park the tree, update the backlog, bank memories, write spec debt, **overwrite** the HANDOFF card, report — then "Cleared for /clear." |
| `/stash [-f] <name>` · `/stash -l` | Freeze the **current task** to a named resume pack (richer than HANDOFF) so a `/clear` loses nothing; list with `-l`. |
| `/unstash <name>` | Resume a stashed task: wrap any live context first, reconstruct the working set at pinned locations, re-dispatch recorded agent briefs, pop-with-archive, continue. |

## Capability tier (`host-adapter.md`)

- **Tier A — Claude Code (and any host with native slash-commands).** These are the **native
  implementation.** Install: copy `commands/*.md` into the target repo's `.claude/commands/`. Then
  `/wrap`, `/stash <name>`, `/unstash <name>` are live. (For a Copilot/Cursor host, place the same
  bodies under that host's prompt/command dir — `.github/prompts/` / `.cursor/commands/`.)
- **Tier B / C — no slash-commands.** The commands are just a **named, ordered ritual.** Run the same
  steps by hand: at an unambiguous session close, execute the `/wrap` list in order; to switch tasks
  mid-flight, perform the `/stash` freeze into a pack file; to resume, perform `/unstash`. The
  discipline is what matters, not the slash sugar — the bodies here are the procedure.

## The project memory directory (convention these assume)

The commands read/write a per-project **memory directory** (path bound in `project-details.md#CL-`,
Mode-A/B aware). Expected layout:

```
<memory-dir>/
  MEMORY.md         # the index loaded each boot — one line per memory, no content
  HANDOFF.md        # the mutable "you are here" card — OVERWRITTEN each wrap, never appended
  backlog.md        # the durable event log (Mode B) or a pointer to the tracker (Mode A)
  stashes/          # named resume packs; stashes/archive/ holds consumed packs
  memory/           # banked trap memories (+ memory/archive.md for pruned entries)
```

**Seeding this at bootstrap** is proposed as an INIT step (`SDD-PROP-05`) so each project stops
rediscovering the convention. Per-project **contents** stay local by design — the *practice* of banking
traps ports; the specific traps do not.

## Why these belong with SDD

`/wrap` step 1 (**agent-lane reconciliation** — every dispatched lane gets a LANDED(hash)-or-DIED
verdict before a boundary) is the session-level form of SDD's "trust artifacts, not narratives": *an
agent's existence is not evidence its work landed.* That rule cost the origin project two lost fixes
before it was learned, and is proposed as a DoD item (`SDD-PROP-03`). The HANDOFF-overwrite rule and
stash/unstash semantics are the session-lifecycle counterpart to the spec's canonical-vs-transient
split.
