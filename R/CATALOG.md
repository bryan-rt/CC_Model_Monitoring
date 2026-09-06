# R/ Catalog

Sourced R scripts. Only `pull_apps.R` and `function_cc_scorecard_data.R` are called before the
validated frontier (line 300). The remaining 8 scripts are sourced but not invoked until later.

| File | Status | Purpose | Key functions | Read by |
|---|---|---|---|---|
| `pull_apps.R` | CLEANED | Pull application data | `get_apps_data()` | `orchestration_2.Rmd:147` |
| `function_cc_scorecard_data.R` | CLEANED | Pull scorecard data | `get_cc_scorecard_data()` | `orchestration_2.Rmd:129` |
| `pull_trended_data.R` | — | Not yet transcribed | — | Sourced at `orchestration_2.Rmd:82` |
| `pull_early_trended_data.R` | — | Not yet transcribed | — | Sourced at `orchestration_2.Rmd:83` |
| `function_join_apps_perf.R` | — | Not yet transcribed | — | Sourced at `orchestration_2.Rmd:84` |
| `pull_score_mapping.R` | — | Not yet transcribed | — | Sourced at `orchestration_2.Rmd:85` |
| `calculate_early_ks.R` | — | Not yet transcribed | — | Sourced at `orchestration_2.Rmd:86` |
| `calculate_true_bad_ks.R` | — | Not yet transcribed | — | Sourced at `orchestration_2.Rmd:87` |
| `build_ks_report_tables.R` | — | Not yet transcribed | — | Sourced at `orchestration_2.Rmd:88` |
| `build_ks_rank_order.R` | — | Not yet transcribed | — | Sourced at `orchestration_2.Rmd:89` |
