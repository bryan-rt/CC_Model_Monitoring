# R/ Catalog

Sourced R scripts. Only `pull_apps.R` and `function_cc_scorecard_data.R` are called before the
validated frontier (line 236; anchor: `# QC: Validated`). The remaining 8 scripts are
commented out at `orchestration_2.Rmd:74` (PENDING TRANSCRIPTION marker).

| File | Status | Purpose | Key functions | Read by |
|---|---|---|---|---|
| `db.R` | FLATTENED | Shared `db_connect()` helper | `db_connect()` | Sourced by `pull_apps.R`, `function_cc_scorecard_data.R`, `setup_supabase.R` |
| `setup_supabase.R` | CREATED | Idempotent table setup (DROP + CREATE + seed) | `setup_supabase()` | Manual setup |
| `pull_apps.R` | FLATTENED | Pull application data (14 cols from flat `applications` table) | `get_apps_data()` | `orchestration_2.Rmd:130` (anchor: `get_apps_data` call in cache-miss branch) |
| `function_cc_scorecard_data.R` | FLATTENED | Pull scorecard data (8 cols from flat `scorecard` table) | `get_cc_scorecard_data()` | `orchestration_2.Rmd:112` (anchor: `get_cc_scorecard_data` call in cache-miss branch) |
| `pull_trended_data.R` | — | Not yet transcribed | — | Commented at `orchestration_2.Rmd:74` (PENDING TRANSCRIPTION marker) |
| `pull_early_trended_data.R` | — | Not yet transcribed | — | Commented at `orchestration_2.Rmd:74` |
| `function_join_apps_perf.R` | — | Not yet transcribed | — | Commented at `orchestration_2.Rmd:74` |
| `pull_score_mapping.R` | — | Not yet transcribed | — | Commented at `orchestration_2.Rmd:74` |
| `calculate_early_ks.R` | — | Not yet transcribed | — | Commented at `orchestration_2.Rmd:74` |
| `calculate_true_bad_ks.R` | — | Not yet transcribed | — | Commented at `orchestration_2.Rmd:74` |
| `build_ks_report_tables.R` | — | Not yet transcribed | — | Commented at `orchestration_2.Rmd:74` |
| `build_ks_rank_order.R` | — | Not yet transcribed | — | Commented at `orchestration_2.Rmd:74` |
