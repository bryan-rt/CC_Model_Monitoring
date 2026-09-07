# Pass 1: Explore — build-metrics-cache

Date: 2026-09-07

## Objective

Add a per-quarter results cache (summary CSVs) and a loader function so
rolling 4-quarter visuals can be built later. No visuals in this task.

## Column schemas (from Rmd source, not from running)

### psi_summary (orchestration_2.Rmd:313-367)

Built at :313 from `psi_result$summary`, then CI-enriched at :352-367.

| Column | Type | Source |
|---|---|---|
| Scorecard | character | compute_si.R:100 — "All Segments", "0"-"4" |
| Population_Stability_Index | numeric | renamed from SI_value at :314 |
| current_count | integer | compute_si.R:102 |
| epsilon_only | logical | compute_si.R:103 |
| epsilon_share | numeric | compute_si.R:104-106 |
| ci_lower | numeric | bootstrap_ci join at :354 |
| ci_upper | numeric | bootstrap_ci join at :354 |
| B | integer | bootstrap_ci join at :354 (always 500) |
| tier | character | case_when at :358-362 |
| tier_certain | logical | threshold-spanning check at :363-366 |

6 rows (All Segments + segments 0-4).

### csi_summary (orchestration_2.Rmd:500-503) — WIDE format

| Column | Type |
|---|---|
| Scorecard | character |
| feature_1 | numeric |
| feature_2 | numeric |
| feature_3 | numeric |
| feature_4 | numeric |
| feature_5 | numeric |

6 rows. This is a DISPLAY table (pivot_wider). Not suitable for cache.

### csi_ci (orchestration_2.Rmd:554-560) — LONG format, CI-enriched

| Column | Type | Source |
|---|---|---|
| Scorecard | character | parsed from compound key at :555 |
| feature | character | parsed from compound key at :555 |
| estimate | numeric | joined from csi_summary_long (SI_value) at :557 |
| ci_lower | numeric | bootstrap_ci |
| ci_upper | numeric | bootstrap_ci |
| B | integer | bootstrap_ci (always 500) |

30 rows (6 segments x 5 features).

### csi_summary_long (orchestration_2.Rmd:499)

| Column | Type | Source |
|---|---|---|
| Scorecard | character | compute_si.R summary |
| SI_value | numeric | compute_si.R summary |
| current_count | integer | compute_si.R summary |
| epsilon_only | logical | compute_si.R summary |
| epsilon_share | numeric | compute_si.R summary |
| feature | character | added at :495 |

30 rows. The LONG source before pivoting.

### ks_comparison (orchestration_2.Rmd:719-765)

Built at :719-724 from inner_join of ks_result$ks_by_segment + ks_baseline$ks.
Then CI-enriched at :761-765.

| Column | Type | Source |
|---|---|---|
| segment | character | compute_ks.R:80 — "All Segments", "0"-"4" |
| ks_value | numeric | compute_ks.R:81 (0-100 scale) |
| n_booked | integer | compute_ks.R:82 |
| n_bads | integer | compute_ks.R:83 |
| dev_ks | numeric | ks_baseline.R:13 |
| dev_br | numeric | ks_baseline.R:14 |
| n_booked (from baseline) | integer | ks_baseline.R:15 — NAME COLLISION |
| ks_delta | numeric | mutate at :724 |
| ci_lower | numeric | bootstrap_ci join at :763 |
| ci_upper | numeric | bootstrap_ci join at :763 |
| B | integer | bootstrap_ci join at :763 |

**NAME COLLISION**: inner_join of ks_result$ks_by_segment (has `n_booked`) with
ks_baseline$ks (has `n_booked`). dplyr produces `n_booked.x` and `n_booked.y`.
This must be handled in the cache write — rename to `n_booked` and
`dev_n_booked` or select out one before the join.

6 rows.

### ks_result$decile_rates (after Wilson CI at :776-777)

| Column | Type | Source |
|---|---|---|
| segment | character | compute_ks.R:73 |
| decile | integer | compute_ks.R:51 (1-10) |
| n | integer | compute_ks.R:56 |
| n_bads | integer | compute_ks.R:57 |
| bad_rate | numeric | compute_ks.R:58 |
| min_score | integer | compute_ks.R:59 |
| max_score | integer | compute_ks.R:60 |
| cum_pct_good | numeric | compute_ks.R:70 |
| cum_pct_bad | numeric | compute_ks.R:71 |
| ks_at_decile | numeric | compute_ks.R:72 (0-100 scale) |
| ci_lower | numeric | wilson_ci at :777 |
| ci_upper | numeric | wilson_ci at :777 |

60 rows (6 segments x 10 deciles).

## CI column status post-merge

All three KPIs already carry CI columns after the `add-confidence-intervals`
merge (4afd2e2):

- **PSI**: ci_lower, ci_upper, B, tier, tier_certain on psi_summary (:352-367)
- **CSI**: ci_lower, ci_upper, B on csi_ci (:554-560); estimate also present
- **KS comparison**: ci_lower, ci_upper, B on ks_comparison (:761-765)
- **KS deciles**: ci_lower, ci_upper on decile_rates (:776-777, Wilson)

No new CI computation needed — just carry existing columns into the cache.

## Key design observations

### 1. data_cohort derivation

- PSI/CSI: `cohort_date` = current quarter (e.g., 2026-07-01 -> "2026Q3").
  `data_cohort` = report_quarter (same period).
- KS: `perf_date <- cohort_date %m-% months(12)` (orchestration_2.Rmd:616).
  `data_cohort` = quarter of perf_date. For report_quarter "2026Q3",
  data_cohort = "2025Q3".

### 2. Existing folder init

Line 92: `fs::dir_create(c('output_files', 'output_files/quarterly_stats'))`
— `quarterly_stats` exists but is unused. We extend to create subdirs.

### 3. gitignore coverage

`.gitignore:31`: `output_files/` — covers everything under it. No change needed.

### 4. Quarter key format

`paste0(lubridate::year(cohort_date), "Q", lubridate::quarter(cohort_date))`
yields "2026Q3" for cohort_date = 2026-07-01. Consistent with the brief.

### 5. xlsx writes to preserve

| KPI | Current write location | Line |
|---|---|---|
| PSI | output_files/psi_quarterly.xlsx | :378-380 |
| CSI | output_files/csi_quarterly.xlsx | :596-598 |
| KS | output_files/ks_quarterly.xlsx | :793-795 |

These continue to overwrite in place (single latest quarter). The NEW cache
writes go to the dated subdirectories.

### 6. CSI summary CSV schema decision

The brief specifies: `Scorecard, feature, CSI, ci_lower, ci_upper` (30 rows).
This is exactly `csi_ci` with `estimate` renamed to `CSI`, minus the `B` column.
We can derive this from `csi_ci` plus `csi_summary_long` for epsilon_share if
desired. But the brief's schema doesn't mention epsilon_share for CSI — only
for PSI. I'll carry it anyway since it's already computed and valuable.

### 7. n_booked collision in ks_comparison

The inner_join at :719-722 joins `ks_by_segment` (columns: segment, ks_value,
n_booked, n_bads) with `ks_baseline$ks` (columns: segment, dev_ks, dev_br,
n_booked). dplyr's default suffix produces `n_booked.x` and `n_booked.y`.
The cache write must select/rename to produce clean column names.

## Proposed cache CSV schemas (with provenance)

### PSI/psi_summary_YYYYQN.csv (6 rows)

```
report_quarter, data_cohort, code_version, run_timestamp,
Scorecard, Population_Stability_Index, ci_lower, ci_upper,
tier, tier_certain, current_count, epsilon_share
```

### CSI/csi_summary_YYYYQN.csv (30 rows)

```
report_quarter, data_cohort, code_version, run_timestamp,
Scorecard, feature, CSI, ci_lower, ci_upper
```

### KS/ks_summary_YYYYQN.csv (6 rows)

```
report_quarter, data_cohort, code_version, run_timestamp,
segment, ks_value, dev_ks, ks_delta, ci_lower, ci_upper, n_booked, n_bads
```

Note: `dev_br` and `dev_n_booked` from baseline intentionally excluded —
they're constant across quarters and would be noise in trend data.

### KS/ks_deciles_YYYYQN.csv (60 rows)

```
report_quarter, data_cohort, code_version, run_timestamp,
segment, decile, n, n_bads, bad_rate, ci_lower, ci_upper, min_score, max_score
```

Note: cum_pct_good, cum_pct_bad, ks_at_decile excluded — they're intermediate
KS computation artifacts, not trend-worthy metrics. Bad_rate + CI is the
meaningful quantity.

## Files to create

| File | Purpose |
|---|---|
| `R/write_metrics_cache.R` | `write_metrics_cache()` — writes 6 files per quarter |
| `R/load_metrics_history.R` | `load_metrics_history(kpi, n_quarters, end_quarter)` |

## Files to modify

| File | Change |
|---|---|
| `orchestration_2.Rmd:92` | Add subdirectory creation |
| `orchestration_2.Rmd` (after :380) | Call write_metrics_cache for PSI |
| `orchestration_2.Rmd` (after :598) | Call write_metrics_cache for CSI |
| `orchestration_2.Rmd` (after :795) | Call write_metrics_cache for KS |
| `orchestration_2.Rmd:66` | Make cohort_date override more prominent |
| `CLAUDE.md` | D22 ref, no-end-to-end-runs constraint, new file refs |
| `.claude/docs/decisions.md` | D22: cache layout decision |
| `R/CATALOG.md` | New files |
| `CATALOG.md` | Update if needed |

## Estimated line-count impact

- :92 — one line expands to ~2 lines (+1)
- After :380 — ~4 lines for PSI cache write call
- After :598 — ~4 lines for CSI cache write call
- After :795 — ~6 lines for KS cache write calls (summary + deciles)
- :66 area — ~2-3 lines for comment enhancement

Total: ~+18 lines. All anchors after :92 shift by ~1; anchors after :380 shift
by ~5; anchors after :598 shift by ~9; anchors after :795 shift by ~15.
Every live citation must be re-derived.

## Open questions

1. **B column**: Include in summary CSVs? It's always 500 currently but could
   change. Mild preference to include for provenance. The brief's PSI schema
   doesn't list it; KS schema doesn't either. I'll exclude it to match the
   brief exactly.

2. **ks_comparison n_booked collision**: Resolve by selecting only current-
   quarter n_booked into the summary CSV. Dev n_booked is in the baseline
   and doesn't change.

3. **cum_pct fields in deciles**: Brief doesn't include them. Exclude.

## Risks

- Line-count changes require re-deriving all live anchors. This is mechanical
  but error-prone. Will use grep-based verification.
- Cannot verify computed values without running. Will state this explicitly
  in the handoff.
