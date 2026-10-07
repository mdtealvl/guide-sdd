<!-- SDD Tier-A session-lifecycle command. Install into <repo>/.claude/commands/. See commands/README.md. -->
# /wrap — end-of-feature context checkpoint (PM 2026-07-14)

The PM is about to `/clear` this session. Run the full externalization pass so the next session boots
cold from durable artifacts with zero loss. IN ORDER, then report:

1. **Reconcile every agent lane.** Each sub-agent dispatched this session: LANDED (commit hash) or DIED
   (no artifact → re-queue the work in the backlog with failure guidance). Check `git log` for the
   expected artifact — an agent's existence is not evidence its work landed. NO lane left "in flight":
   a `/clear` orphans resumable agent handles.
2. **Land or park the working tree.** Finished work: suites green + committed (stage by path, never
   `git add -A`). Unfinished work: stashed-with-a-backlog-pointer or described precisely in the backlog
   (branch, files, next step).
3. **Backlog to survivable state** (Mode B: the `backlog/` item files, `#CL-1`; Mode A: the tracker): the
   current feature's entry → ✅ SHIPPED (hashes, suite counts, PM-facing verdicts owed) or 🏗️ IN FLIGHT
   (what's decided, what's running, exact resume point). Supersede stale entries.
4. **Bank memories**: any trap that cost >15 minutes and could recur → a memory file + MEMORY.md line.
5. **Spec debt check**: any PM ruling from this session not yet in spec/decisions is written NOW (it
   never survives only in chat).
6. **OVERWRITE the handoff card** (the project memory directory's HANDOFF.md) — the "you are here"
   summary the next boot reads FIRST: in-flight lanes with exact resume points, this session's shipped
   list as commit/decision POINTERS (not prose), PM verdicts owed, parked PM decisions, a
   one-line-per-decision quick index. Replace wholesale; history belongs in the backlog.
7. **MEMORY.md budget check**: over ~200 lines → prune superseded entries (old session_* summaries whose
   content is in backlog/commits) into memory/archive.md.
8. **Report** ≤10 lines: lanes reconciled (with verdicts), commits, the `tokens:` line of each slice
   closed this session (`gates/token_ledger.* report --slice`), what the next session should do first,
   then the literal line: **"Cleared for /clear."** Do not start new work.
