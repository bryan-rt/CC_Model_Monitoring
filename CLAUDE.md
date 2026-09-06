# CC Model Monitoring

Quarterly monitoring pipeline for a custom credit card application scorecard.
Rebuilds production pipeline (DB2/Databricks) from OCR screenshots, rewired to
Supabase (Postgres) with generic tables.

Primary orchestrator: `orchestration_2.Rmd` (~2,800 lines, ~40 chunks).
Validated frontier: line 300 (`# QC: Validated`) — but "validated" means reviewed,
not run. Code is validated only once it has run (D5).

## Current loop position

Completed: OCR cleanup of pull scripts, `supabase-credentials` (merged 2bbfe03),
prim_score resolution (D8), scorecard grain resolution (D9).
Current: `flatten-apps-query`.

Next sequence: flatten-apps-query -> create-supabase-tables -> round-trip test ->
sample-data-generator -> fix-orchestration-rmd.

## Pull function contracts

| Function | File | Returns |
|---|---|---|
| `get_apps_data(performance_window, write)` | `R/pull_apps.R` | data.frame: application-level, one row per APP_NUM (GROUP BY A.APP_NUM in SQL). Key columns: app_num, user_ref_num, dt_entered, client_product_cd, decision, applied, copied_from, prim_score (NUMERIC, range 100-450, D8). Writes `data/apps/apps_YYYYMM.txt.gz` if `write=T`. |
| `get_cc_scorecard_data(performance_window, write)` | `R/function_cc_scorecard_data.R` | data.frame: one row per user_ref_num (D9). Columns: sq_num, user_ref_num, score, segment, actduty, trans_date_ct, proc_date_ct, priored1. Writes `data/scorecard/scorecard_YYYYMM.txt.gz` if `write=T`. |

## Open questions

- **priored1 vs primedt**: UNRESOLVED, zero uses in 2,802 lines of Rmd. See
  `.claude/docs/decisions.md` and `.claude/passes/clean-ocr-pull-scripts/1-explore.md`.

## Where things live

| What | Where |
|---|---|
| Decisions (D1-D9) | `.claude/docs/decisions.md` |
| Pass artifacts | `.claude/passes/<task-name>/` |
| R script catalog | `R/CATALOG.md` |
| Project catalog | `CATALOG.md` |

## Evidence discipline

- Cite `path:line` for load-bearing claims.
- Distinguish VERIFIED (ran it, output observed) from INFERRED (reasoning).
- `source()` proves a file parses and defines. It does NOT evaluate function bodies.
- Corrections need more verification than original work.
- Reconcile, do not append: if a change makes adjacent text wrong, fix both.
- Confirm the carrying path: a change correct in one file while the path that
  carries the value silently drops it is the recurring failure mode.

## Update rule

This file MUST be updated whenever a connection, table, or frontier changes.
