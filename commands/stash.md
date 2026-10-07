<!-- SDD Tier-A session-lifecycle command. Install into <repo>/.claude/commands/. See commands/README.md. -->
# /stash — freeze the current task's working context to a named pack (PM 2026-07-14)

Usage: `/stash [-f] <name>` · `/stash -l` — arguments: $ARGUMENTS

**`-l` (list):** from the project memory directory's `stashes/` folder, print each stash: name, date,
one-line task summary (the pack's first heading line), plus anything in `stashes/archive/` marked
consumed. Do nothing else.

**`<name>` (stash):** freeze the CURRENT task so a `/clear` loses nothing:
1. `stashes/<name>.md` exists and no `-f`: STOP and ask (never silently overwrite).
2. Run the /wrap discipline on the current task only: reconcile its agent lanes to LANDED(hash)/DIED
   (live agent handles do NOT survive a /clear — a lane that must continue becomes a RE-DISPATCH BRIEF
   in the pack, with its persona, pinned facts, and outcome file path); commit-or-park the tree
   (parked = branch/stash noted in the pack); spec/decision debt written.
3. Write `stashes/<name>.md` — the resume pack, richer than HANDOFF:
   - **Task + state**: what was asked, what's done, EXACT next step (file:line grain).
   - **Working set**: the files being edited + why; key signatures/constants pinned (pasted, not
     pointed at).
   - **Rulings taken** this task (with decision numbers if written) + open questions for the PM.
   - **Re-dispatch briefs** for any unfinished agent lanes (see 2).
   - **Verification state**: which suites ran, what's green, what's owed.
4. In HANDOFF.md's in-flight section, replace the task's entry with `STASHED → <name>`.
5. Report ≤5 lines: stash name, what it holds, then **"Stashed — safe to /clear."**
