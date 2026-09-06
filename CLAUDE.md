# CC Model Monitoring

Quarterly monitoring pipeline for a custom credit card application scorecard.
Rebuilds production pipeline (DB2/Databricks) from OCR screenshots, rewired to
Supabase (Postgres) with generic tables.

Primary orchestrator: `orchestration_2.Rmd` (~2,800 lines, ~40 chunks).
Validated frontier: line 300 (`# QC: Validated`) — but "validated" means reviewed,
not run. Code is validated only once it has run (D5).

## Current loop position

Completed: OCR cleanup of `R/pull_apps.R` and `R/function_cc_scorecard_data.R`.
Current: `supabase-credentials` — wiring `db_connect()` to Supabase, installing
RPostgres, live connection test.

Next sequence: prim_score/grain resolution (user) -> flatten-apps-query ->
create-supabase-tables -> round-trip test -> sample-data-generator ->
fix-orchestration-rmd.

## Pull function contracts

| Function | File | Returns |
|---|---|---|
| `get_apps_data(performance_window, write)` | `R/pull_apps.R` | data.frame: application-level, one row per APP_NUM (GROUP BY A.APP_NUM in SQL). Key columns: app_num, user_ref_num, dt_entered, client_product_cd, decision, applied, copied_from, prim_score. Writes `data/apps/apps_YYYYMM.txt.gz` if `write=T`. |
| `get_cc_scorecard_data(performance_window, write)` | `R/function_cc_scorecard_data.R` | data.frame: grain UNRESOLVED — no GROUP BY in the query; source table grain unknown. Columns: sq_num, user_ref_num, score, segment, actduty, trans_date_ct, proc_date_ct, priored1. Writes `data/scorecard/scorecard_YYYYMM.txt.gz` if `write=T`. |

## Open questions

- **prim_score**: score value or scorecard identifier? Derived from element
  `PRIM_SCORE_CARD` via `ALPHA_VALUE` (text, `R/pull_apps.R:77-79`) but compared
  numerically (100-450 range) in the Rmd. Gates the schema task — do not type the
  column until resolved.
- **priored1 vs primedt**: UNRESOLVED, zero uses in 2,802 lines of Rmd. See
  `.claude/docs/decisions.md` JC4 and `.claude/passes/clean-ocr-pull-scripts/1-explore.md`.
- **scorecard grain**: the scorecard query has no GROUP BY; the source table's grain
  is unknown. Determines whether the Rmd's bare `left_join()` fans out apps rows,
  which changes what PSI counts (`n_distinct(app_num)` vs `n_distinct(user_ref_num)`).

## Where things live

| What | Where |
|---|---|
| Decisions (D1-D7) | `.claude/docs/decisions.md` |
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
