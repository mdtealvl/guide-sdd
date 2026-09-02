<!-- SDD Tier-A session-lifecycle command. Install into <repo>/.claude/commands/. See commands/README.md. -->
# /unstash — resume a stashed task (PM 2026-07-14)

Usage: `/unstash <name>` — arguments: $ARGUMENTS

1. **Safety first**: if the CURRENT session context holds unwrapped work (anything not yet in
   backlog/HANDOFF/a stash), run the /wrap discipline on it before loading — unstash assumes the
   current context is disposable; make that true rather than assuming it.
2. Read the project memory directory's `stashes/<name>.md`.
   Missing ⇒ list available stashes and stop.
3. Reconstruct the working state: re-read the pack's working-set files at the pinned locations
   (verify pins still hold — the tree may have moved since; a stale pin is reconciled against
   current code, never assumed), re-dispatch any recorded agent briefs, restore HANDOFF.md's
   in-flight entry from `STASHED → <name>` back to active.
4. **Pop-with-archive**: move the pack to `stashes/archive/<name>.md` (consumed, kept for
   forensics — the PM deletes archives when they want).
5. Report ≤8 lines: the task, its exact resume point, what was re-dispatched, then continue the
   work — /unstash is a resumption, not a briefing.
