---
name: pass2-plan
description: Pass 2 of the three-pass workflow. Turns approved Pass 1 findings into an exact change specification. No code is written.
argument-hint: [task-slug]
disable-model-invocation: true
disallowed-tools: Edit NotebookEdit
---

# Pass 2 — Plan

Task slug: `$ARGUMENTS`

## Pass 1 findings

@.claude/passes/$ARGUMENTS/1-explore.md

If that file is missing or empty, stop. Say so and tell the user to run
`/pass1-explore $ARGUMENTS` first. Do not explore the repo yourself to fill the gap — that
skips the gate.

## Rules

1. **Ground every design decision in a numbered Pass 1 finding.** Write the finding ID next
   to the decision: "Rename to `app_num` (F7)."
2. **A decision you cannot ground is an assumption.** Put it under Unresolved and say what
   would settle it. Do not quietly proceed on it.
3. **You may re-read files to confirm a specific detail**, but new information discovered
   here is a Pass 1 gap. Record it under "Discovered during planning" and flag whether it
   invalidates anything.
4. **Write no code.** Signatures, schemas, column lists, and pseudocode are in scope; working
   implementations are not.
5. **Name what could break.** Every change has a blast radius. If you cannot name what
   consumes the thing you are changing, you have not finished planning.
6. **Verify the carrying path.** For any value being renamed, rewired, or passed through:
   state where it is produced, every hop it takes, and where it is finally read. A change
   that is correct at the source and dropped in transit is this project's characteristic
   failure.
7. **A catalog is a navigation hint, never authority.** You may use `CATALOG.md` files to
   choose what to read. You may not cite them as evidence. Every finding needs a `path:line`
   citation from the actual file.

## Produce

Write to `.claude/passes/$ARGUMENTS/2-plan.md`:

```markdown
# Pass 2 — Plan: <task>
Date: <date>  ·  Grounded in: 1-explore.md

## Objective
One paragraph. What is true after this change that is not true now.

## Changes
Per file. Exact paths.
### `path/to/file.R`
- What changes, and the finding it rests on (F#)
- Signature / schema before → after
- Pseudocode only where the logic is non-obvious

## Carrying paths verified
| Value | Produced at | Hops | Consumed at |
|---|---|---|---|

## Blast radius
What else reads the things being changed. Cited.

## Edge cases and how each is handled

## Discovered during planning
New facts not in Pass 1. Note whether any invalidate a Pass 1 finding.

## Unresolved
Assumptions I could not ground, and what would settle each.

## Definition of done
- [ ] Concrete, checkable outcomes
- [ ] Rmd knits clean to the current validated marker against live data
- [ ] `git diff --stat` in the Pass 3 summary
```

## Then commit and push

```
git add .claude/passes/$ARGUMENTS/2-plan.md
git commit -m "Pass 2 plan: $ARGUMENTS"
git push
```

## Then stop

Print the plan summary and this line verbatim:

> Pass 2 complete. Spec at `.claude/passes/$ARGUMENTS/2-plan.md`.
> Committed and pushed to `main`.
> Review, then run `/pass3-execute $ARGUMENTS` when you approve.

Do not implement. Do not continue in this turn. If the Unresolved section is non-empty, say
so explicitly — the user may want to answer those before approving.
