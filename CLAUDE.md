# CC Model Monitoring

Quarterly monitoring pipeline for a custom credit card application scorecard.
Rebuilds production pipeline (DB2/Databricks) from OCR screenshots, rewired to
Supabase (Postgres) with generic tables.

Primary orchestrator: `orchestration_2.Rmd` (~2,775 lines, ~29 chunks).
Validated frontier: line 292 (`# QC: Validated`) — but "validated" means reviewed,
not run. Code is validated only once it has run (D5).

## Current loop position

Completed: OCR cleanup, `supabase-credentials` (2bbfe03), `flatten-apps-query`,
`scrub-rmd-credentials`, `create-supabase-tables`.
Next sequence: simplify-rmd-psi-region -> round-trip test ->
sample-data-generator -> fix-orchestration-rmd.

CSI (orchestration_2.Rmd:508-583, connection stub at :512-514) is out of scope
for this loop (D13). It is a third data source; D13 stub replaces original
connection block. Gets its own table and iteration once the validated marker
reaches line 508.
  (anchor: :508 = CSI chunk opening fence preceding the D13 stub)
  (anchor: :512-514 = D13 stub comment block)

## Pull function contracts

| Function | File | Returns |
|---|---|---|
| `get_apps_data(performance_window, write)` | `R/pull_apps.R` | data.frame: application-level, one row per app_num. 14 columns: app_num, user_ref_num, dt_entered, client_product_cd, strategy_version, assigned_credit_lim, decision, applied, org_paper_type, lao_credit_lmt, fico_score, bureau_used, acq, prim_score (NUMERIC, D8). Dropped: applid, logic, custom_score/_2/_3 (D11), copied_from (D12). Writes `data/apps/apps_YYYYMM.txt.gz` if `write=T`. |
| `get_cc_scorecard_data(performance_window, write)` | `R/function_cc_scorecard_data.R` | data.frame: one row per user_ref_num (D9). Columns: sq_num, user_ref_num, score, segment, actduty, trans_date_ct, proc_date_ct, primemdt (TEXT, D10). Writes `data/scorecard/scorecard_YYYYMM.txt.gz` if `write=T`. |

## Supabase tables

Both tables exist and are seeded (50 apps, 40 scorecard rows, 2026 Q3).
Schema: `sql/01_create_tables.sql`. Seed: `sql/02_seed_minimal.sql`.
Setup: `R/setup_supabase.R` (idempotent, DROP + CREATE + seed).

| Table | PK | Rows | Source contract |
|---|---|---|---|
| `applications` | `app_num` | 50 | `R/pull_apps.R:9-25` |
| `scorecard` | `user_ref_num` (D9) | 40 | `R/function_cc_scorecard_data.R:7-15` |

## Where things live

| What | Where |
|---|---|
| Decisions (D1-D13) | `.claude/docs/decisions.md` |
| Pass artifacts | `.claude/passes/<task-name>/` |
| R script catalog | `R/CATALOG.md` |
| Project catalog | `CATALOG.md` |
| SQL schema + seed | `sql/` |

## Evidence discipline

- Cite `path:line` for load-bearing claims.
- Distinguish VERIFIED (ran it, output observed) from INFERRED (reasoning).
- `source()` proves a file parses and defines. It does NOT evaluate function bodies.
- Corrections need more verification than original work.
- Reconcile, do not append: if a change makes adjacent text wrong, fix both.
- Confirm the carrying path: a change correct in one file while the path that
  carries the value silently drops it is the recurring failure mode.
- Any task that changes `orchestration_2.Rmd`'s line count must re-derive every
  live line citation in CLAUDE.md, decisions.md, CATALOG.md, and R/CATALOG.md,
  and report a before/after table. Pass artifacts are historical records and
  are NOT updated; add a dated note to the affected pass directory instead.

## Update rule

This file MUST be updated whenever a connection, table, or frontier changes.
