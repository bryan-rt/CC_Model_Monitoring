# CC Model Monitoring

Quarterly monitoring pipeline for a custom credit card application scorecard.
Rebuilds production pipeline (DB2/Databricks) from OCR screenshots, rewired to
Supabase (Postgres) with generic tables.

Primary orchestrator: `orchestration_2.Rmd` (635 lines, 10 chunks).
Validated frontier: line 635 (`# QC: Validated`) — VALIDATED: has run
against live Supabase (D5). psi_df: 30,500 rows (generated cohort), segments
0-4. PSI + CSI + KS run clean through :631.
  (anchor: :635 = `# QC: Validated` marker)
  (anchor: :633 = `# QC: Completed` marker)

cohort_date (orchestration_2.Rmd:66-69): overridable parameter, defaults to
current quarter. Set `cohort_date <- as.Date("YYYY-MM-DD")` before running
the setup chunk to select a different quarter.

## Current loop position

Completed: OCR cleanup, `supabase-credentials` (2bbfe03), `flatten-apps-query`,
`scrub-rmd-credentials`, `create-supabase-tables`, `make-rmd-run-to-marker`,
`build-psi-calculation`, `sample-data-generator`, `create-features-table`,
`build-feature-breaks`, `build-csi-calculation`, `build-performance-table-and-ks`.
Next sequence: round-trip test -> fix-orchestration-rmd.

CSI (orchestration_2.Rmd:329-485) is fully built: pulls features, joins to PSI
population, computes CSI per feature x segment using the shared
`compute_stability_index()` helper in `R/compute_si.R` (D19). PSI chunk
refactored to use the same helper. Outputs `csi_quarterly.xlsx` (5 tabs, one
per feature) and `csi_summary` (6 segments x 5 features).
  (anchor: :335 = CSI chunk opening fence `\`\`\`{r}`)
  (anchor: :268 = `source(here::here("R/compute_si.R"))` in PSI chunk)

KS (orchestration_2.Rmd:495-631) is fully built: pulls 12-month-lagged
performance cohort (Q3 2025), joins to apps+scorecard for score and segment,
computes KS and decile bad rates via `compute_ks_stats()` in `R/compute_ks.R`
(D20). Compares to frozen dev baseline in `R/ks_baseline.R`. Outputs
`ks_quarterly.xlsx` (2 tabs: ks_comparison, decile_rates).
  (anchor: :495 = KS chunk opening fence `\`\`\`{r}`)
  (anchor: :497 = `source(here::here("R/compute_ks.R"))` in KS chunk)

## Pull function contracts

| Function | File | Returns |
|---|---|---|
| `get_apps_data(performance_window, write)` | `R/pull_apps.R` | data.frame: application-level, one row per app_num. 14 columns: app_num, user_ref_num, dt_entered, client_product_cd, strategy_version, assigned_credit_lim, decision, applied, org_paper_type, lao_credit_lmt, fico_score, bureau_used, acq, prim_score (NUMERIC, D8). Dropped: applid, logic, custom_score/_2/_3 (D11), copied_from (D12). Writes `data/apps/apps_YYYYMM.txt.gz` if `write=T`. |
| `get_cc_scorecard_data(performance_window, write)` | `R/function_cc_scorecard_data.R` | data.frame: one row per user_ref_num (D9). Columns: sq_num, user_ref_num, score, segment, actduty, trans_date_ct, proc_date_ct, primemdt (TEXT, D10). Writes `data/scorecard/scorecard_YYYYMM.txt.gz` if `write=T`. |
| `generate_cohort(quarters, feature_targets, seed)` | `R/generate_cohort.R` | list: `$apps` (data.frame, ~141k rows), `$scorecard` (data.frame, ~137k rows), `$features` (data.frame, ~141k rows), `$performance` (data.frame, mature quarter approved apps with dq90), `$dev_cohort` (data.frame, dev cohort with user_ref_num/prim_score/segment/dq90), `$meta` (per-quarter stats). Per-segment alpha solved from target_psi via bisection (D16). Features generated in Phase 2 with independent RNG stream (D17). Mature quarter + dev cohort use seed+2000L and seed+3000L respectively (D20). Generalized solver accepts dev_weights for categorical features. Bin counts deterministic. |
| `get_features_data(performance_window, write)` | `R/pull_features.R` | data.frame: one row per user_ref_num (D9). 7 columns: user_ref_num, feature_date, feature_1 (NUMERIC), feature_2 (NUMERIC), feature_3 (NUMERIC), feature_4 (TEXT), feature_5 (TEXT). Writes `data/features/features_YYYYMM.txt.gz` if `write=T`. |
| `build_feature_breaks(seed)` | `R/build_feature_breaks.R` | Bootstraps `R/feature_breaks.R` if absent; validates against feature_defs and generated data if present (D18). Fails loudly on drift. |
| `compute_stability_index(joined_df, epsilon)` | `R/compute_si.R` | list: `$detail` (named list of tibbles per Scorecard, each with Total row), `$summary` (tibble: Scorecard, SI_value, current_count, epsilon_only, epsilon_share). Shared kernel for PSI and CSI (D19). Asserts sum(percent_dev)==1 per group. |
| `get_performance_data(performance_window, write)` | `R/pull_performance.R` | data.frame: one row per user_ref_num. 3 columns: user_ref_num, origination_date, dq90 (INTEGER 0/1). Approved apps only. Writes `data/dq_12_mos/dq_12_mos_YYYYMM.txt.gz` if `write=T`. |
| `compute_ks_stats(df, score_col, outcome_col, segment_col)` | `R/compute_ks.R` | list: `$ks_by_segment` (tibble: segment, ks_value 0-100, n_booked, n_bads), `$decile_rates` (tibble: segment, decile, n, n_bads, bad_rate, min_score, max_score, cum_pct_good, cum_pct_bad, ks_at_decile), `$min_bads_per_decile` (integer). Shared helper for KS computation (D20). Deciles re-derived per cohort (not frozen). |
| `build_ks_baseline(seed)` | `R/build_ks_baseline.R` | Generates `R/ks_baseline.R` from dev cohort; validates monotonicity, KS targets (±1.5), min bads/decile (≥28) (D20). |

## Supabase tables

All four tables exist. Two load modes via `setup_supabase(mode)`:
- `"minimal"`: 50 apps, 40 scorecard, 40 features (sql/02_seed_minimal.sql, fast debugging)
- `"generated"`: ~141k apps, ~137k scorecard, ~141k features across 4 quarters + ~61k performance from mature quarter (D16, D17, D20)

Schema: `sql/01_create_tables.sql`, `sql/03_create_features_table.sql`, `sql/04_create_performance_table.sql`. Setup: `R/setup_supabase.R`.

| Table | PK | Rows (generated) | Source contract |
|---|---|---|---|
| `applications` | `app_num` | 141,720 | `R/pull_apps.R:9-25` |
| `scorecard` | `user_ref_num` (D9) | 136,840 | `R/function_cc_scorecard_data.R:7-15` |
| `features` | `user_ref_num` (D9, D17) | 141,720 | `R/pull_features.R:7-15` |
| `performance` | `user_ref_num` (D20) | ~61,820 | `R/pull_performance.R:7-11` |

## Where things live

| What | Where |
|---|---|
| Decisions (D1-D20) | `.claude/docs/decisions.md` |
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
