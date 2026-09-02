# Lifecycle States — mark things DEAD or CHANGED, never silently delete

> **v1.2 — 2026-06-24.** Demand-loaded spine. Load when retiring or relocating a clause, doc,
> config key, flag, or behaviour — so history stays traceable and nothing dangles.
> Cross-links: `spec-format/README.md` (retiring a clause), `changelog-conventions.md`
> (retiring an item), `constitution.md` (canonical-vs-transient / archive-not-delete),
> `stages/3_spec.md` (update method), `stages/7_ship.md` (fold + archive).

A thing no longer current carries an **explicit lifecycle state** with required metadata (date +
reason and/or a pointer). **Never** silently delete a clause, doc, config key, or behaviour; **never**
leave a stale one unmarked. Silent deletion breaks back-derivability
(`spec = fold(all shipped work)`); a dangling stale clause causes intent drift.

## The states

| State | Means | Required metadata |
|---|---|---|
| `DEPRECATED` | still present/works, discouraged, slated for removal | date + reason |
| `SUPERSEDED` | replaced by something else | date + **pointer** to the replacement |
| `MOVED` | relocated | date + **pointer** to the new location (leave a stub behind) |
| `REMOVED` | gone | date + reason; a **tombstone** remains in the changelog + a one-line tag stub at the anchor |

## Tag format

A compact **inline marker** at the retired thing:

```
[DEPRECATED 2026-06-24 — superseded by §5x.3]
[SUPERSEDED 2026-06-24 → §5x.3]
[MOVED 2026-06-24 → docs/archive/foo.md]
[REMOVED 2026-06-24 — feature cut per POL-142; tombstone in changelog]
```

## Where it applies

| Thing | How it retires |
|---|---|
| **Spec clause** | retire via a **one-line lifecycle tag at the anchor, body removed** (no struck-through stratum — prior text lives in git + the changelog); the **clause-ID is never reused**; ties to archive-not-delete and the Stage-7 fold/archive. |
| **Doc** | a `MOVED`/`REMOVED` doc leaves a **one-line stub** pointing to the new home or the archive (audit-only — never read it to implement). |
| **Config key / flag / code** | a deprecation marker **+** a changelog entry recording the removal **plan and date**. |

## Why

- **Audit trail.** Silent deletion erases *what was true and when* — the spec must stay
  back-derivable from the folded changelog (`constitution.md` invariant 7).
- **No dangling.** An unmarked stale clause is a live source of intent drift (`constitution.md`
  invariant 2).
- **Stable IDs.** Clause-IDs never renumber and never get reused; retiring is a state change, not a
  deletion (`constitution.md` invariant 5).

## At a glance

- [ ] Never silently delete; never leave a stale thing unmarked.
- [ ] Pick the state: `DEPRECATED` · `SUPERSEDED` · `MOVED` · `REMOVED`.
- [ ] Attach the **required metadata**: date + reason and/or pointer.
- [ ] Spec clause → **one-line tag stub, body removed**; the clause-ID is never reused.
- [ ] Moved/removed doc → leave a **one-line stub** to the new home or archive.
- [ ] Config/flag/code → deprecation marker **+** changelog entry with the removal date.
- [ ] `REMOVED` always leaves a **tombstone** in the changelog and a tag stub at the anchor.
