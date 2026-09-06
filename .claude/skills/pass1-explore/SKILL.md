---
name: pass1-explore
description: Pass 1 of the three-pass workflow. Read-only exploration of the live repo to establish what is actually true before any planning. Produces a cited findings document.
argument-hint: [task-slug]
disable-model-invocation: true
disallowed-tools: Edit Write NotebookEdit
---

# Pass 1 — Explore

Task slug: `$ARGUMENTS`

You are establishing ground truth. You are **not** planning and **not** writing code.

## Repo state

- Branch: !`git branch --show-current`
- Uncommitted: !`git status --short`
- Validated marker: !`grep -n "QC: Validated" orchestration_2.Rmd || echo "marker not found"`

## Rules

1. **Read the actual files.** Never describe code from memory, from a filename, from a
   previous session, or from what the Task Brief said. The Task Brief is a hypothesis about
   the repo; your job is to test it.
2. **Every claim carries a citation** in `path:line` form. A claim you cannot cite is an
   assumption, and assumptions go in the Assumptions section, not the Findings section.
3. **Report contradictions with the Task Brief loudly.** The brief was written without
   reading the repo. Where it is wrong, that is the single most valuable thing you produce.
4. **Do not fix anything.** Not typos, not obvious bugs, not formatting. Record them.
5. **Do not propose a solution.** If an approach occurs to you, note it in one line under
   Open Questions and move on. Designing is Pass 2's job.
6. State when you did not look at something. Silence reads as "checked and clean."
7. **A catalog is a navigation hint, never authority.** You may use `CATALOG.md` files to
   choose what to read. You may not cite them as evidence. Every finding needs a `path:line`
   citation from the actual file. A stale catalog that gets trusted is worse than no catalog.

## Child-checkpoint behavior

When `$ARGUMENTS` matches `<parent>-cp<N>`:

1. Read `.claude/passes/<parent>/1-explore.md` and `0-checkpoints.md` first.
2. Explore only the delta this checkpoint needs, plus anything the previous checkpoint changed.
3. Carry forward relevant parent findings by ID rather than re-deriving them (cite as
   `parent:F7`). Re-verify any parent finding a prior checkpoint may have invalidated.
4. Always classify as SINGLE. A checkpoint that assesses as CHECKPOINTED means the parent
   split was wrong. Say so and stop rather than nesting further.

## Produce

Write findings to `.claude/passes/$ARGUMENTS/1-explore.md` using this structure. Use the
`create_file`/`Write` tool only for this one path — it is the sole exception to the read-only
rule. If the tool is unavailable, print the document in full and ask the user to save it.

```markdown
# Pass 1 — Explore: <task>
Date: <date>  ·  Commit: <sha>

## Scope
What the Task Brief asked me to establish.

## Findings
Numbered. Each with a `path:line` citation.
F1. <claim> — `R/pull_apps.R:42`

## Contradictions with the Task Brief
What the brief assumed that the repo does not support. Cited.

## Existing contracts touched
Function signatures, return column names, file paths, schema fields that anything
downstream depends on. Cite where each is consumed, not just where it is defined.

## Defects observed (not fixed)
Cited. Mark each: OCR artifact / real bug / unknown.

## Not examined
What I did not look at, and why.

## Open questions for Pass 2
Things that must be decided before a plan can be written.

## Assumptions
Anything I believe but could not cite. Pass 2 must treat these as unverified.

## Scope assessment
- Files edited: <count>
- Contract changes: <yes/no — list if yes>
- New Supabase tables or migrations: <yes/no>
- Single verification run sufficient: <yes/no>
- Spec fits on one page: <yes/no>
- **Verdict: SINGLE / CHECKPOINTED** — <one-line rationale>
```

## Scope branch

After writing findings, assess scope before stopping.

**Classify as SINGLE** only if ALL of these hold:
- Three or fewer files edited
- No change to a contract consumed outside those files (function signature, return column
  names, table schema, file path other code reads)
- No new Supabase table or migration
- One verification run can prove the whole thing works
- The Pass 2 spec would fit on roughly one page

Otherwise classify as **CHECKPOINTED**. When uncertain, choose CHECKPOINTED — an unnecessary
split costs a little ceremony, an oversized cycle costs a rollback.

### If SINGLE

Commit and push:
```
git add .claude/passes/$ARGUMENTS/1-explore.md
git commit -m "Pass 1 explore: $ARGUMENTS"
git push
```

Stop with:

> Pass 1 complete. Findings at `.claude/passes/$ARGUMENTS/1-explore.md`.
> Committed and pushed to `main`.
> Verdict: SINGLE. Review, then run `/pass2-plan $ARGUMENTS` when you approve.

### If CHECKPOINTED

Write `.claude/passes/$ARGUMENTS/0-checkpoints.md`:

```markdown
# Checkpoint plan: <task>
Date: <date>  ·  Grounded in: 1-explore.md
Verdict: CHECKPOINTED — <one line on why it exceeded the SINGLE thresholds>

## Checkpoints
### CP1 — <slug-suffix>: <title>
- Objective:
- Files touched:
- Depends on: (none / CP<n>)
- Definition of done:
- Verification: how CP1 alone is proven to work

### CP2 — ...
```

Checkpoints must be **independently verifiable and ordered by dependency**. Each one leaves
the repo in a working state — the Rmd must still knit to the current validated marker at the
end of every checkpoint. A checkpoint that only makes sense once a later one lands is drawn
wrong; merge them or re-cut the boundary.

Commit and push:
```
git add .claude/passes/$ARGUMENTS/1-explore.md .claude/passes/$ARGUMENTS/0-checkpoints.md
git commit -m "Pass 1 explore (checkpointed): $ARGUMENTS"
git push
```

Stop with:

> Pass 1 complete. Findings at `.claude/passes/$ARGUMENTS/1-explore.md`.
> Verdict: CHECKPOINTED — <n> checkpoints at `.claude/passes/$ARGUMENTS/0-checkpoints.md`.
> Committed and pushed to `main`.
> Review both, then run `/pass1-explore $ARGUMENTS-cp1` when you approve.

Do not begin planning. Do not continue in this turn. Wait for the user.
