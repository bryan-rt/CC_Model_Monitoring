# R/ Catalog

Sourced R scripts. `pull_apps.R`, `function_cc_scorecard_data.R`, and
`build_dev_population.R` are called before the validated frontier (line 453;
anchor: `# QC: Validated`). The remaining 8 scripts are commented out at
`orchestration_2.Rmd:78` (PENDING TRANSCRIPTION marker).

| File | Status | Purpose | Key functions | Read by |
|---|---|---|---|---|
| `db.R` | FLATTENED | Shared `db_connect()` helper | `db_connect()` | Sourced by `pull_apps.R`, `function_cc_scorecard_data.R`, `setup_supabase.R` |
| `setup_supabase.R` | CREATED | Idempotent table setup (DROP + CREATE + seed or generated) | `setup_supabase(mode)` | Manual setup |
| `generate_cohort.R` | CREATED | Parameterized cohort generator (4 quarters, drift via tilt weights, D6/D16) | `generate_cohort(quarters, seed)` | `R/setup_supabase.R` (mode="generated") |
| `pull_apps.R` | FLATTENED | Pull application data (14 cols from flat `applications` table) | `get_apps_data()` | `orchestration_2.Rmd:132` (anchor: `get_apps_data` call in cache-miss branch) |
| `function_cc_scorecard_data.R` | FLATTENED | Pull scorecard data (8 cols from flat `scorecard` table) | `get_cc_scorecard_data()` | `orchestration_2.Rmd:114` (anchor: `get_cc_scorecard_data` call in cache-miss branch) |
| `build_dev_population.R` | CREATED | Generate development population reference (120 rows, frozen vigintile bins, D15) | `build_dev_population(output_path)` | `orchestration_2.Rmd:266` (anchor: `source` + `build_dev_population` call in PSI chunk) |
| `pull_trended_data.R` | — | Not yet transcribed | — | Commented at `orchestration_2.Rmd:74` (PENDING TRANSCRIPTION marker) |
| `pull_early_trended_data.R` | — | Not yet transcribed | — | Commented at `orchestration_2.Rmd:74` |
| `function_join_apps_perf.R` | — | Not yet transcribed | — | Commented at `orchestration_2.Rmd:74` |
| `pull_score_mapping.R` | — | Not yet transcribed | — | Commented at `orchestration_2.Rmd:74` |
| `calculate_early_ks.R` | — | Not yet transcribed | — | Commented at `orchestration_2.Rmd:74` |
| `calculate_true_bad_ks.R` | — | Not yet transcribed | — | Commented at `orchestration_2.Rmd:74` |
| `build_ks_report_tables.R` | — | Not yet transcribed | — | Commented at `orchestration_2.Rmd:74` |
| `build_ks_rank_order.R` | — | Not yet transcribed | — | Commented at `orchestration_2.Rmd:74` |
