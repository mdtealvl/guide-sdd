# Intake — from a raw request to a Ready item

> Demand-loaded spine. Load at Stage 0 when the input is not yet a changelog item: a sentence, a
> Slack thread, a bug report, a transcript, a PRD. Output: one item per `changelog-conventions.md`,
> or a recorded reason no item was filed. PO-box work; a worker box hands raw requests to the PO.
> Intake distills; it never invents. A gap is a question, not a guess.

## 1. Classify the input

| Input | Do |
|---|---|
| **Rich** — PRD, design doc, ticket with ACs | Extract. Every load-bearing claim lands in an item field or is listed under "dropped — not load-bearing". Ask nothing unless two claims contradict. |
| **Sparse** — one line, a chat message | Elicit (§3). *Express* (default): draft the item; every gap becomes an open question. *Guided*: walk the fields with the PM one at a time — when the PM asks, or the domain is unfamiliar. |
| **Mixed** — transcript, thread, email chain | Sort claim by claim into the fields, preserving each; then elicit the gaps. |
| **Too thin** — "make it faster", "an app for hikers" | Return it to the PM with the three questions that would make it specific. No item is filed; the exchange goes to the session backlog. |

A claim is **load-bearing** when a worker, QA, or Validation would decide differently without it.
Keep the **verbatim request** (the PM's own words, quoted) in the item — it is the intent-alignment
reference at Stage 7.

## 2. One goal per item

Before writing fields, test scope: does the request hold **two or more deliverables that could be
reviewed and merged independently**? Count deliverables, never verbs or "and"s — a rename plus the
feature it enables is one goal; two unrelated endpoints are two.

- One goal → continue.
- Several → list the goals, recommend which goes first, ask the PM **split or keep**.
  - *Split*: file the first. Each deferred goal becomes a stub item carrying `split-from: <ITEM-ID>`,
    not Ready.
  - *Keep*: record `kept-whole: PM <date>` on the item; Stage 0 still right-sizes it.

## 3. Elicit the gaps — the numbered-question loop

1. List every gap as a **numbered question a PM can answer in one line**, grouped by field (Why ·
   Success signal · Boundaries · Constraints · Non-functional · Dependencies).
2. Send the list. On reply, check **every number** was answered; re-ask **only** the missing ones.
3. Repeat until no question remains that a worker could not settle from existing convention.
4. Never answer your own question to keep moving. An unanswered question stays under **Open
   questions**; the item is not Ready while one remains (`definition-of-done.md`).

**Unknown-finding prompts** — run once the PM says "that's all":

| Prompt | Ask |
|---|---|
| Inversion | What would guarantee this fails, gets reverted, or is never used? |
| Second order | What else changes when this ships — callers, stored data, docs, ops, cost? |
| Seam walk | For each Project Details seam the change touches (`#SEAM-N`): what does it need from that seam, and what does the seam forbid? |
| Fixed-set check | If the change special-cases one member of a set (an enum, a status code, a role, a currency): what happens to every other member? |
| Existing primitive | Which spec section already generalises this? (Conform; never fork a parallel hierarchy — Stage 1.) |

## 4. Domain-implication screen

For each non-functional category the project marks applicable (Project Details, the DoD list:
security · privacy · accessibility · performance · observability · compatibility · migration ·
rollback · compliance) record exactly one of: **an AC covers it** · **`N/A — <reason>`** · **an open
question**. Silence is not an option: healthcare input silent on PHI, payments silent on PCI, a
control loop silent on fail-safe, a data change silent on migration and rollback — each is an open
question, never an assumption.

## 5. Write the item, then judge it

Fill `changelog-conventions.md` §3 in order. Pre-Ready, behaviour may be written as capabilities
(`CAP-n — intent / success`, the *what*); Stage 1/3 turns them into EARS ACs with stable ids (the
testable form). Then the PO records the **readiness verdict** (`definition-of-done.md` DoR):
**PASS** → Ready · **CONCERNS** → each listed; the PM waives or fixes before Ready · **FAIL** → back
to §3 with the findings, each naming what would fix it.

## Anti-patterns

- Filing a one-line ticket and letting Stage 3 discover the questions — every gap found there costs
  a QA pass.
- Resolving a gap "to keep moving" — the worker inherits the guess as fact and the trace records no
  decision.
- Splitting by verb count — "add and update" is one goal when one review covers it.
- Treating a rich PRD as Ready — extraction still ends at §5; a PRD has no readiness verdict.

## Cross-links

- **Stage 0** (`stages/0_triage.md`) — calls intake before right-sizing.
- **`changelog-conventions.md`** — the item the intake produces; `[NEEDS-PO]` reasons.
- **`definition-of-done.md`** — the readiness verdict and the DoR.
- **`greenfield-vs-brownfield.md`** — when the touched area has no spec, the item is brownfield.
