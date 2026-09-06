---
name: pass3-execute
description: Pass 3 of the three-pass workflow. Implements exactly the approved Pass 2 spec, tests it, and reports what actually happened.
argument-hint: [task-slug]
disable-model-invocation: true
---

# Pass 3 — Execute

Task slug: `$ARGUMENTS`

## Approved spec

@.claude/passes/$ARGUMENTS/2-plan.md

If missing, stop and tell the user to run `/pass2-plan $ARGUMENTS` first.

## Baseline

- Branch: !`git branch --show-current`
- Clean tree?: !`git status --short`

## Branch

Create a feature branch before making any changes:
```
git checkout -b pass3/$ARGUMENTS
```
All code changes are made on this branch.

## Rules

1. **Implement only what the spec says.** Scope creep here is invisible to the user, who
   approved a different document than the one you are executing.
2. **If the spec is wrong, stop.** Do not repair it in flight. Say what is wrong, what you
   would change, and wait. A spec that survives contact with reality unchanged is rare;
   discovering that is a result, not a failure.
3. **Run the code.** A change that has not executed is not done. Knit the Rmd to the current
   validated marker. Paste real output, real errors, real row counts.
4. **Report what happened, not what should have happened.** If something is untested, say it
   is untested. If a number came from a summary rather than a run, say so. Fabricated
   verification is worse than no verification.
5. **Reconcile, do not append.** When a change makes adjacent text wrong — a comment, a
   header, a docstring, a README line, a table — fix it in the same commit. Superseded
   reasoning surviving next to a correction is a recurring failure in this project.
6. **Do not advance the `# QC: Validated` marker** unless the spec's definition of done says
   to and the Rmd actually knits past it.
7. **Update the `CATALOG.md` of every folder you touched**, in the same commit. Reconcile
   status and descriptions against what actually changed — do not just append new entries.

## Produce

Write to `.claude/passes/$ARGUMENTS/3-execute.md`:

```markdown
# Pass 3 — Execute: <task>
Date: <date>  ·  Commit: <sha>

## What was implemented
Against the spec, per file.

## Deviations from spec
Anything done differently, and why. "None" is a valid answer — but only if true.

## Verification
The actual commands run and their actual output. Knit result. Errors encountered
and how resolved.

## Untested
What was changed but not exercised.

## Adjacent text reconciled
Comments, docs, tables updated to match.

## git diff --stat
<paste>
```

## Then commit and push

Commit all changes (code + `3-execute.md` + catalog/doc updates) to the feature branch
and push for review:

```
git add <changed files>
git commit -m "Pass 3 execute: $ARGUMENTS"
git push -u origin pass3/$ARGUMENTS
```

## Then stop

Print the summary, paste `git diff --stat`, and this line verbatim:

> Pass 3 complete. Changes on branch `pass3/$ARGUMENTS`, committed and pushed.
> Review the diff, then approve to merge to main.

Do not merge to main until the user approves. Do not start the next task.
