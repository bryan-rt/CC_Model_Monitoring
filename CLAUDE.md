# CC Model Monitoring

Quarterly monitoring pipeline for a custom credit card application scorecard.
Rebuilds production pipeline (DB2/Databricks) from OCR screenshots, rewired to
Supabase (Postgres) with generic tables.

Primary orchestrator: `orchestration_2.Rmd` (825 lines, 10 chunks).
Validated frontier: line 825 (`# QC: Validated`) — VALIDATED: has run
against live Supabase (D5). psi_df: 30,500 rows (generated cohort), segments
0-4. PSI + CSI + KS + confidence intervals run clean through :821.
CI bootstrap chunks add ~2 minutes to a full run (PSI 28s, CSI 63s, KS 29s).
  (anchor: :825 = `# QC: Validated` marker)
  (anchor: :823 = `# QC: Completed` marker)

cohort_date (orchestration_2.Rmd:65-71): overridable parameter, defaults to
current quarter. Set `cohort_date <- as.Date("YYYY-MM-DD")` before running
the setup chunk to select a different quarter. Available generated quarters:
2025Q4, 2026Q1, 2026Q2, 2026Q3.

## Execution constraint

Do NOT run orchestration_2.Rmd end to end from Claude Code. Full renders stall
in this environment. The user runs the Rmd manually in RStudio. Build and
unit-test R files in isolation with synthetic data frames.

## Current loop position

Completed: OCR cleanup, `supabase-credentials` (2bbfe03), `flatten-apps-query`,
`scrub-rmd-credentials`, `create-supabase-tables`, `make-rmd-run-to-marker`,
`build-psi-calculation`, `sample-data-generator`, `create-features-table`,
`build-feature-breaks`, `build-csi-calculation`, `build-performance-table-and-ks`,
`add-confidence-intervals`, `build-metrics-cache`.
Next sequence: round-trip test -> fix-orchestration-rmd.

CSI (orchestration_2.Rmd:400-617) is fully built: pulls features, joins to PSI
population, computes CSI per feature x segment using the shared
`compute_stability_index()` helper in `R/compute_si.R` (D19). PSI chunk
refactored to use the same helper. Outputs `csi_quarterly.xlsx` (6 tabs: one
per feature + ci tab) and `csi_summary` (6 segments x 5 features).
  (anchor: :400 = CSI chunk opening fence `\`\`\`{r}`)
  (anchor: :273 = `source(here::here("R/compute_si.R"))` in PSI chunk)

KS (orchestration_2.Rmd:619-821) is fully built: pulls 12-month-lagged
performance cohort (Q3 2025), joins to apps+scorecard for score and segment,
computes KS and decile bad rates via `compute_ks_stats()` in `R/compute_ks.R`
(D20). Compares to frozen dev baseline in `R/ks_baseline.R`. Outputs
`ks_quarterly.xlsx` (2 tabs: ks_comparison, decile_rates).
  (anchor: :628 = KS chunk opening fence `\`\`\`{r}`)
  (anchor: :630 = `source(here::here("R/compute_ks.R"))` in KS chunk)

Confidence intervals (D21): PSI, CSI, KS use stratified percentile bootstrap
(B=500, `R/bootstrap_ci.R`). Decile bad rates use Wilson score intervals
(`R/wilson_ci.R`). PSI carries tier (stable/watch/investigate) and
tier_certain (FALSE when CI spans a threshold).
  (anchor: :323 = PSI bootstrap)
  (anchor: :516 = CSI bootstrap)
  (anchor: :747 = KS bootstrap)
  (anchor: :789 = Wilson CI for decile bad rates)

Metrics cache (D22): Per-quarter summary CSVs in
`output_files/quarterly_stats/{PSI,CSI,KS}/`. Named by REPORT quarter (YYYYQn),
with `data_cohort` column recording the actual data period. KS data_cohort is
12 months prior (perf_date at :634). `R/write_metrics_cache.R` writes,
`R/load_metrics_history.R` reads. Schema-validated on both write and read.
Provenance: report_quarter, data_cohort, code_version, run_timestamp.

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
| `wilson_ci(k, n, conf)` | `R/wilson_ci.R` | list: `$lower` (numeric vector), `$upper` (numeric vector). Vectorized Wilson score CI for binomial proportions (D21). |
| `bootstrap_ci(data, group_col, stat_fn, B, conf, seed)` | `R/bootstrap_ci.R` | tibble: group, ci_lower, ci_upper, B. Stratified percentile bootstrap (D21). stat_fn(df) must return tibble with group and value columns. Own RNG stream at seed+3000L. |
| `write_metrics_cache(kpi, data, cohort_date, perf_date)` | `R/write_metrics_cache.R` | invisible(path). Writes summary CSV to `output_files/quarterly_stats/{PSI,CSI,KS}/`. Schema-validated per KPI. Provenance columns prepended. Idempotent (D22). |
| `load_metrics_history(kpi, n_quarters, end_quarter)` | `R/load_metrics_history.R` | tibble: bind_rows'd CSVs sorted by report_quarter. Warns on short window / mixed code_version. Errors on schema mismatch across files (D22). |

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
| Decisions (D1-D22) | `.claude/docs/decisions.md` |
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
