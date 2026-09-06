# data/ Catalog

Data files are gitignored (`data/*.csv`, `data/*.rds`, `data/*.xlsx`). Subdirectories are
created at runtime by the orchestration notebook.

| Path | Status | Purpose | Read by |
|---|---|---|---|
| `data/apps/` | CREATED | Application data files (`.txt.gz`) | `R/pull_apps.R`, `orchestration_2.Rmd:171` |
| `data/scorecard/` | CREATED | Scorecard data files (`.txt.gz`) | `R/function_cc_scorecard_data.R`, `orchestration_2.Rmd:164` |
| `data/performance_24/` | STUB | 24-month performance data | `orchestration_2.Rmd:93` |
| `data/dq_24_mos/` | STUB | Data quality 24-month files | Post-QC code |
| `data/ks_driver_w_perf/` | STUB | KS driver with performance | Post-QC code |
