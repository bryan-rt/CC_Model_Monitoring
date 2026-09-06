# CC Model Monitoring

Quarterly monitoring pipeline for a custom credit card application scorecard.
Rebuilds production pipeline (DB2/Databricks) from OCR screenshots, rewired to
Supabase (Postgres) with generic tables.

Primary orchestrator: `orchestration_2.Rmd` (~2,661 lines, ~28 chunks).
Validated frontier: line 487 (`# QC: Validated`) — VALIDATED: has run
against live Supabase (D5). psi_df: 30,500 rows (generated cohort), segments
0-4. PSI + CSI run clean through :485.
  (anchor: :487 = `# QC: Validated` marker)
  (anchor: :327 = `# QC: Completed` marker)

cohort_date (orchestration_2.Rmd:66-69): overridable parameter, defaults to
current quarter. Set `cohort_date <- as.Date("YYYY-MM-DD")` before running
the setup chunk to select a different quarter.

## Current loop position

Completed: OCR cleanup, `supabase-credentials` (2bbfe03), `flatten-apps-query`,
`scrub-rmd-credentials`, `create-supabase-tables`, `make-rmd-run-to-marker`,
`build-psi-calculation`, `sample-data-generator`, `create-features-table`,
`build-feature-breaks`, `build-csi-calculation`.
Next sequence: round-trip test -> fix-orchestration-rmd.

CSI (orchestration_2.Rmd:329-485) is fully built: pulls features, joins to PSI
population, computes CSI per feature x segment using the shared
`compute_stability_index()` helper in `R/compute_si.R` (D19). PSI chunk
refactored to use the same helper. Outputs `csi_quarterly.xlsx` (5 tabs, one
per feature) and `csi_summary` (6 segments x 5 features).
  (anchor: :335 = CSI chunk opening fence `\`\`\`{r}`)
  (anchor: :267 = `source(here::here("R/compute_si.R"))` in PSI chunk)

## Pull function contracts

| Function | File | Returns |
|---|---|---|
| `get_apps_data(performance_window, write)` | `R/pull_apps.R` | data.frame: application-level, one row per app_num. 14 columns: app_num, user_ref_num, dt_entered, client_product_cd, strategy_version, assigned_credit_lim, decision, applied, org_paper_type, lao_credit_lmt, fico_score, bureau_used, acq, prim_score (NUMERIC, D8). Dropped: applid, logic, custom_score/_2/_3 (D11), copied_from (D12). Writes `data/apps/apps_YYYYMM.txt.gz` if `write=T`. |
| `get_cc_scorecard_data(performance_window, write)` | `R/function_cc_scorecard_data.R` | data.frame: one row per user_ref_num (D9). Columns: sq_num, user_ref_num, score, segment, actduty, trans_date_ct, proc_date_ct, primemdt (TEXT, D10). Writes `data/scorecard/scorecard_YYYYMM.txt.gz` if `write=T`. |
| `generate_cohort(quarters, feature_targets, seed)` | `R/generate_cohort.R` | list: `$apps` (data.frame, ~141k rows), `$scorecard` (data.frame, ~137k rows), `$features` (data.frame, ~141k rows), `$meta` (per-quarter stats). Per-segment alpha solved from target_psi via bisection (D16). Features generated in Phase 2 with independent RNG stream (D17). Generalized solver accepts dev_weights for categorical features. Bin counts deterministic. |
| `get_features_data(performance_window, write)` | `R/pull_features.R` | data.frame: one row per user_ref_num (D9). 7 columns: user_ref_num, feature_date, feature_1 (NUMERIC), feature_2 (NUMERIC), feature_3 (NUMERIC), feature_4 (TEXT), feature_5 (TEXT). Writes `data/features/features_YYYYMM.txt.gz` if `write=T`. |
| `build_feature_breaks(seed)` | `R/build_feature_breaks.R` | Bootstraps `R/feature_breaks.R` if absent; validates against feature_defs and generated data if present (D18). Fails loudly on drift. |
| `compute_stability_index(joined_df, epsilon)` | `R/compute_si.R` | list: `$detail` (named list of tibbles per Scorecard, each with Total row), `$summary` (tibble: Scorecard, SI_value, current_count, epsilon_only, epsilon_share). Shared kernel for PSI and CSI (D19). Asserts sum(percent_dev)==1 per group. |

## Supabase tables

All three tables exist. Two load modes via `setup_supabase(mode)`:
- `"minimal"`: 50 apps, 40 scorecard, 40 features (sql/02_seed_minimal.sql, fast debugging)
- `"generated"`: ~141k apps, ~137k scorecard, ~141k features across 4 quarters (D16, D17)

Schema: `sql/01_create_tables.sql`, `sql/03_create_features_table.sql`. Setup: `R/setup_supabase.R`.

| Table | PK | Rows (generated) | Source contract |
|---|---|---|---|
| `applications` | `app_num` | 141,720 | `R/pull_apps.R:9-25` |
| `scorecard` | `user_ref_num` (D9) | 136,840 | `R/function_cc_scorecard_data.R:7-15` |
| `features` | `user_ref_num` (D9, D17) | 141,720 | `R/pull_features.R:7-15` |

## Where things live

| What | Where |
|---|---|
| Decisions (D1-D19) | `.claude/docs/decisions.md` |
| Pass artifacts | `.claude/passes/<task-name>/` |
| R script catalog | `R/CATALOG.md` |
| Project catalog | `CATALOG.md` |
| SQL schema + seed | `sql/` |

## Serialization contract

The binding contract between Postgres and R is the gzipped CSV, not the
Postgres schema. Types that arrive in R are what `fread` infers, not what
Postgres declares:

- `user_ref_num` (VARCHAR(14)) → `integer64` (bit64). Nobody chose this;
  fread inferred it from 14-digit values. `as.numeric()` is exact at 1e13
  (within 2^53). The join works because `scipen = 999` in fwrite
  (`pull_apps.R:57`, `function_cc_scorecard_data.R:42`) prevents scientific
  notation on write — without it, "1e+13" round-trips as character and the
  join silently breaks.
- `dt_entered` (DATE) → `IDate` (data.table's Date subclass). Inherits from
  Date, so `zoo::as.yearqtr()` works.
- `prim_score` (NUMERIC) → `integer` when all values are whole numbers.
  `is.numeric(integer)` is TRUE in R.

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
