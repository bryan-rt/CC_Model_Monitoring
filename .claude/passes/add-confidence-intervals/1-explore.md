# Pass 1: Explore -- add-confidence-intervals

Date: 2026-09-07

## Runtime object structures

### psi_summary (orchestration_2.Rmd:311)

- Class: `tbl_df/tbl/data.frame`
- Columns: `Scorecard, Population_Stability_Index, current_count, epsilon_only, epsilon_share`
- 6 rows: segments 0, 1, 2, 3, 4, All Segments

Point estimates (full precision, from Rmd run):

| Scorecard | Population_Stability_Index |
|---|---|
| 0 | 0.29996442 |
| 1 | 0.09001510 |
| 2 | 0.25009364 |
| 3 | 0.04013091 |
| 4 | 0.14980100 |
| All Segments | 0.08351459 |

Note: All Segments PSI is 0.08351459, not 0.08472267 (pre-KS-task value).
See item 3 analysis below.

### csi_summary (orchestration_2.Rmd:445)

- Class: `tbl_df/tbl/data.frame`
- Columns: `Scorecard, feature_1, feature_2, feature_3, feature_4, feature_5`
- 6 rows (pivoted wide from `csi_summary_long`)

Underlying `csi_summary_long` has columns:
`Scorecard, SI_value, current_count, epsilon_only, epsilon_share, feature`
(30 rows: 6 segments x 5 features)

csi_summary values (Q3 2026):

| Scorecard | feature_1 | feature_2 | feature_3 | feature_4 | feature_5 |
|---|---|---|---|---|---|
| 0 | 0.2794 | 0.0200 | 0.1897 | 0.0100 | 0.0299 |
| 1 | 0.0402 | 0.0200 | 0.0500 | 0.0100 | 0.0200 |
| 2 | 0.2201 | 0.0300 | 0.0601 | 0.0200 | 0.0400 |
| 3 | 0.0199 | 0.0099 | 0.0200 | 0.0100 | 0.0101 |
| 4 | 0.1098 | 0.0200 | 0.0401 | 0.0200 | 0.0299 |
| All Segments | 0.1008 | 0.0196 | 0.0599 | 0.0134 | 0.0247 |

### ks_result$ks_by_segment (orchestration_2.Rmd:605 via ks_comparison)

- Class: `tbl_df/tbl/data.frame`
- Columns: `segment, ks_value, n_booked, n_bads`
- 6 rows

`ks_comparison` (the object actually printed at :611) adds columns from
`ks_baseline$ks` via inner_join: `dev_ks, dev_br, n_booked.y, ks_delta`.
Full column list: `segment, ks_value, n_booked.x, n_bads, dev_ks, dev_br, n_booked.y, ks_delta`.

| segment | ks_value | n_booked | n_bads | ks_delta |
|---|---|---|---|---|
| All Segments | 28.53 | 61820 | 3463 | -2.87 |
| 0 | 33.22 | 15379 | 343 | -8.58 |
| 1 | 39.09 | 17907 | 828 | -1.01 |
| 2 | 37.22 | 11576 | 746 | -0.88 |
| 3 | 33.88 | 7152 | 884 | -1.32 |
| 4 | 25.17 | 9806 | 662 | -3.03 |

### ks_result$decile_rates (orchestration_2.Rmd:614)

- Class: `tbl_df/tbl/data.frame`
- Columns: `segment, decile, n, n_bads, bad_rate, min_score, max_score, cum_pct_good, cum_pct_bad, ks_at_decile`
- 60 rows (6 segments x 10 deciles)

Segment 0 sample (Wilson CI test cases):

| decile | n | n_bads | bad_rate |
|---|---|---|---|
| 1 | 1538 | 0 | 0.0000 |
| 2 | 1538 | 3 | 0.0020 |
| 5 | 1538 | 43 | 0.0280 |
| 7 | 1538 | 21 | 0.0137 |
| 10 | 1537 | 129 | 0.0839 |

## Verification of expected results

- Segment 0 PSI: 0.2997 -- matches expected ~0.30
- Segment 1 PSI: 0.0900 -- matches expected ~0.09
- Segment 0 decile 1: 0/1538 -- Wilson test case confirmed
- Segment 0 decile 5: 43/1538 -- Wilson ~[0.0208, 0.0374] test case confirmed
- Segment 0 decile 7: 21/1538 -- Wilson ~[0.0089, 0.0208] test case confirmed

## Key sizes for bootstrap budget

| Object | Rows | Use |
|---|---|---|
| `psi_df` | 30,500 | PSI bootstrap resampling |
| `csi_df` | 30,500 | CSI bootstrap (same population) |
| `ks_df` | 61,820 | KS bootstrap (expensive -- ntile() per replicate) |
| `psi_joined` | 120 | 6 segments x 20 bins (intermediate, not resampled) |

## Wiring plan

### PSI (psi_summary at :311)

Method: `bootstrap_ci`. Resample `psi_df` rows stratified by Scorecard (=
segment). Each replicate re-bins with frozen `segment_breaks`, rebuilds
`psi_joined` against fixed `dev_pop`, calls `compute_stability_index()`,
extracts `$summary$SI_value`.

New columns on `psi_summary`: `ci_lower, ci_upper, B, tier, tier_certain`.

Tier logic: `< 0.10` = stable, `0.10-0.25` = watch, `> 0.25` = investigate.
`tier_certain = FALSE` when `[ci_lower, ci_upper]` spans 0.10 or 0.25.

### CSI (csi_summary at :445)

Method: `bootstrap_ci`. Resample `csi_df` rows (application-level) ONCE per
replicate, recompute ALL 5 features from the same draw. This preserves the
correlation structure -- resampling features independently would destroy it
and produce five unrelated intervals.

Add companion `csi_ci` tibble (long form: Scorecard, feature, estimate,
ci_lower, ci_upper, B). Do NOT restructure `csi_summary` (pivoted wide).

### KS (ks_comparison at :605)

Method: `bootstrap_ci`. Resample `ks_df` rows stratified by segment. CRITICAL:
`ntile(desc(score), 10)` must run INSIDE `stat_fn` -- decile boundaries are
part of the uncertainty. "All Segments" is just another group with its own n.

New columns on `ks_comparison`: `ci_lower, ci_upper, B`.

### Decile bad rates (ks_result$decile_rates at :614)

Method: `wilson_ci` (closed-form, not bootstrap). Vectorized
`wilson_ci(n_bads, n)` per row.

New columns: `ci_lower, ci_upper`. Per decile INDEPENDENTLY -- not joint.
Comment the multiple-comparison caveat.

## Files to create

1. `R/wilson_ci.R` (~15 lines) -- vectorized Wilson score interval
2. `R/bootstrap_ci.R` (~40 lines) -- stratified bootstrap with percentile CI

## Files to modify

1. `orchestration_2.Rmd` -- wire CIs at 4 insertion points:
   - After :312 (psi_summary): ~25 lines (bootstrap + tier)
   - After :449 (csi_summary): ~20 lines (bootstrap)
   - After :611 (ks_comparison): ~10 lines (bootstrap)
   - After :614 (decile_rates): ~5 lines (Wilson)
   - Two new `source()` calls
2. `CLAUDE.md` -- new function contracts, updated line anchors
3. `.claude/docs/decisions.md` -- D21
4. `R/CATALOG.md` -- two new entries

## Line-count estimate

Current Rmd: 627 lines (content through :627, markers at :625/:627).
Estimated insertions: ~62 lines. New total: ~689 lines.
All downstream anchors shift accordingly.

## Constraints checklist

- [ ] Do not modify compute_si.R, compute_ks.R, feature_breaks.R, ks_baseline.R, generate_cohort.R
- [ ] Point estimates unchanged (before/after paste required)
- [ ] CI code must not reference the generator
- [ ] Wilson intervals per decile independently (not joint)
- [ ] Document deterministic-generator caveat (CI does not predict regeneration variance)
