# R/ Catalog

Sourced R scripts. Only `pull_apps.R` and `function_cc_scorecard_data.R` are called before the
validated frontier (line 292). The remaining 8 scripts are sourced but not invoked until later.

| File | Status | Purpose | Key functions | Read by |
|---|---|---|---|---|
| `db.R` | FLATTENED | Shared `db_connect()` helper | `db_connect()` | Sourced by `pull_apps.R`, `function_cc_scorecard_data.R`, `setup_supabase.R` |
| `setup_supabase.R` | CREATED | Idempotent table setup (DROP + CREATE + seed) | `setup_supabase()` | Manual setup |
| `pull_apps.R` | FLATTENED | Pull application data (14 cols from flat `applications` table) | `get_apps_data()` | `orchestration_2.Rmd:139` |
| `function_cc_scorecard_data.R` | FLATTENED | Pull scorecard data (8 cols from flat `scorecard` table) | `get_cc_scorecard_data()` | `orchestration_2.Rmd:121` |
| `pull_trended_data.R` | — | Not yet transcribed | — | Sourced at `orchestration_2.Rmd:74` |
| `pull_early_trended_data.R` | — | Not yet transcribed | — | Sourced at `orchestration_2.Rmd:75` |
| `function_join_apps_perf.R` | — | Not yet transcribed | — | Sourced at `orchestration_2.Rmd:76` |
| `pull_score_mapping.R` | — | Not yet transcribed | — | Sourced at `orchestration_2.Rmd:77` |
| `calculate_early_ks.R` | — | Not yet transcribed | — | Sourced at `orchestration_2.Rmd:78` |
| `calculate_true_bad_ks.R` | — | Not yet transcribed | — | Sourced at `orchestration_2.Rmd:79` |
| `build_ks_report_tables.R` | — | Not yet transcribed | — | Sourced at `orchestration_2.Rmd:80` |
| `build_ks_rank_order.R` | — | Not yet transcribed | — | Sourced at `orchestration_2.Rmd:81` |
