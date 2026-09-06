# Pass 1: Explore — build-csi-calculation

## PSI chunk inventory (lines 245-397)

Inspected the full PSI computation path. Here is the reusability analysis:

### PSI-specific (NOT reusable for CSI)
1. **Binning** (:198-202) — `bucket_scores()` calls `cut()` with score-specific
   breaks and generates "lower to upper" labels. CSI needs two dispatch paths:
   `cut()` for continuous features, `factor()` for categorical.
2. **Aggregation** (:204-226) — groups by `all_bucket_aligned`, counts
   `n_distinct(user_ref_num)`. CSI must iterate over 5 features, not one score.
3. **Label separation** (:229-233) — `tidyr::separate("lower to upper")` into
   Lower_Range/Upper_Range. CSI's continuous bins can reuse this, but categorical
   bins have single-value labels (A, B, C, D), not ranges.
4. **Dev population join** (:266-274) — `full_join` on Scorecard + Lower_Range +
   Upper_Range with `coalesce(counts, 0L)`. CSI joins on Scorecard + bin_label
   (or equivalent), and the dev reference comes from `feature_breaks` (in-memory
   list), not from a file.

### Reusable as-is (identical formula)
5. **PSI formula** (:282-318) — epsilon floor, percent_dev, percent_current,
   Difference (B-A), Proportion (B/A), Log of Proportion, Population Divergence
   (K-L), epsilon_floored, epsilon_only. **This is identical for CSI.** The only
   difference: percent_dev is NOT always 0.05 for CSI (categorical features have
   non-uniform dev proportions).
6. **Split + Total row** (:331-360) — group_split by Scorecard, append totals.
   Reusable if column names match.
7. **Summary** (:362-380) — extract total PSI per segment, epsilon_share.
   Identical logic, different output name (CSI instead of PSI).
8. **xlsx write** (:388-396) — createWorkbook + walk over tabs.

### Helper extraction plan

The shared kernel is steps 5-7: given a joined frame with columns
`{Scorecard, bin_label, counts_dev, counts}`, compute the stability index.
This is ~55 lines in the PSI chunk (:282-380). I propose extracting a helper:

```r
compute_stability_index(joined_df, epsilon = 0.0001)
```

**Input contract**: data.frame with columns `Scorecard`, `counts_dev`, `counts`,
plus any pass-through columns (Lower_Range/Upper_Range for PSI, bin_label for CSI).

**Returns**: list with `$detail` (the per-bin table with all formula columns,
Total rows appended) and `$summary` (one row per Scorecard: total index,
current_count, epsilon_only, epsilon_share).

This helper replaces :282-380 in the PSI chunk and is called identically by CSI.
The PSI chunk becomes: build joined_df → `compute_stability_index()` → xlsx write.
The CSI chunk becomes: build joined_df per feature → `compute_stability_index()`
per feature → xlsx write.

**Key difference from PSI**: the helper must NOT assert `percent_dev == 0.05`.
That assertion is PSI-specific (uniform vigintiles). CSI's categorical features
have non-uniform dev proportions (e.g., 0.45/0.30/0.15/0.10 for feature_4).
The formula itself is the same — only the assertion is removed.

### CSI data flow

1. **Source + pull + cache** — mirror the apps/scorecard pattern at :102-138.
   Source `R/pull_features.R` at :76-78 (where the PENDING TRANSCRIPTION marker
   is). Call `get_features_data()` for 3 months, write to `data/features/`.
   Then fread from cache. Lowercase names.

2. **Source feature_breaks** — `source(here::here("R/feature_breaks.R"))` to
   load the `feature_breaks` list.

3. **Join to PSI population** — `psi_df` already exists from :165-179. Inner
   join features to `psi_df` on `user_ref_num`. This guarantees the CSI
   population is identical to the PSI population (same filters already applied).

4. **Bin + aggregate per feature** — loop over `names(feature_breaks)`:
   - continuous: `cut(value, breaks=fb$breaks, right=TRUE, include.lowest=TRUE)`
   - categorical: `factor(value, levels=fb$levels)`
   Then group_by(Scorecard, bin_label), count. Add "All Segments" group.

5. **Build dev reference per feature** — from `feature_breaks`:
   - continuous: `dev_counts` per bin, bin labels from head/tail of breaks
   - categorical: `dev_counts` per level
   Full_join on Scorecard + bin_label, coalesce counts to 0.

6. **compute_stability_index()** per feature — produces detail + summary.

7. **CSI summary table** — 6 segments x 5 features, one CSI value per cell.
   Pivot from the per-feature summaries.

8. **xlsx output** — one tab per feature (5 tabs), segment as a column within
   each tab. This gives 5 readable tabs instead of 30 unusable ones. The segment
   column already exists (it's called Scorecard). Each tab has
   6 segments x n_bins rows + 6 Total rows.

### Self-test design

Override `cohort_date <- as.Date("2025-10-01")` (Q4 2025, the flat cohort).
Assert all 30 CSI values (5 features x 6 segments) < 1e-6. Feature_2's
remainder residual (1.548e-07) is below this threshold.

### Row count assertion

Per the task brief: 10+8+5+4+3 = 30 bins per segment, 180 across 6 segments.
Assert `nrow(csi_joined) == 180` per feature (after full_join with dev reference).

### Line count impact

The CSI chunk replaces :405-450 (the OCR stub). That's 46 lines of comments.
The new content will be larger (pull + cache + source + loop + compute + xlsx +
summary + assertions). Estimated ~80-100 lines net. Additionally, extracting the
helper removes ~55 lines from the PSI chunk but adds an `R/compute_si.R` file.
Net Rmd delta: roughly +30-50 lines. All live citations must be re-derived.

### Risks

1. **Helper extraction invasiveness**: The PSI chunk's assertions (120 rows,
   5% dev) are interleaved with the formula. Extracting cleanly requires
   moving the formula but keeping PSI-specific assertions in the Rmd. Feasible
   but needs care.

2. **feature source line**: `R/pull_features.R` must be sourced. The natural
   place is :76-78 alongside the other pull scripts, but that's inside the
   validated frontier. Alternative: source it at the top of the CSI chunk,
   which is less clean but doesn't touch validated code.

3. **"All Segments" for CSI**: PSI computes "All Segments" by re-binning all
   scores through a different break vector. CSI uses the SAME breaks for all
   segments (global breaks, D18). So "All Segments" is just the union of all
   rows, binned with the same breaks — simpler than PSI.

### Decision needed

**Source location for pull_features.R**: I recommend sourcing it at :76-78
alongside the other pull functions, inside the validated region. This is a
single `source()` line addition that doesn't change any existing code. The
alternative (sourcing at the top of the CSI chunk) works but creates an
inconsistency with the established pattern.

## Approval requested

Ready for Pass 2 (plan). Key decisions to confirm:

1. Helper name: `compute_stability_index()` in `R/compute_si.R`
2. xlsx layout: 5 tabs (one per feature), segment as column
3. Source `pull_features.R` at :76-78 (one line added to validated region)
