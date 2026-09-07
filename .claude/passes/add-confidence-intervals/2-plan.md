# Pass 2: Plan -- add-confidence-intervals

Date: 2026-09-07

## Execution order

1. Create `R/wilson_ci.R`
2. Create `R/bootstrap_ci.R`
3. Wire into `orchestration_2.Rmd` (4 insertion points, bottom-up to preserve
   line numbers during editing: KS decile Wilson -> KS bootstrap -> CSI
   bootstrap -> PSI bootstrap + tier)
4. Update `CLAUDE.md`, `.claude/docs/decisions.md` (D21), `R/CATALOG.md`
5. Run Rmd end-to-end, verify point estimates unchanged, capture wall time
6. Write `3-execute.md`

## Step 1: R/wilson_ci.R

```r
# wilson_ci.R
#
# Wilson score confidence interval for a binomial proportion.
# Used for decile bad-rate intervals where each decile is treated
# independently. These are screening intervals for triage, not
# hypothesis tests -- comparing all nine adjacent pairs is nine
# comparisons and will occasionally show a spurious gap.

wilson_ci <- function(k, n, conf = 0.95) {
  z <- qnorm(1 - (1 - conf) / 2)
  p <- k / n
  d <- 1 + z^2 / n
  center <- (p + z^2 / (2 * n)) / d
  half <- z / d * sqrt(p * (1 - p) / n + z^2 / (4 * n^2))
  lower <- pmax(0, center - half)
  upper <- pmin(1, center + half)
  list(lower = lower, upper = upper)
}
```

~18 lines. Vectorized over k and n via R's natural vectorization (pmax/pmin).

### Required assertions (in Rmd, not in the function)

1. `wilson_ci(0, 1538)` returns ~[0.0000, 0.0025]
2. All 60 decile cells: lower >= 0, upper <= 1

## Step 2: R/bootstrap_ci.R

```r
# bootstrap_ci.R
#
# Stratified percentile bootstrap for stability metrics (PSI, CSI, KS).
# Resamples rows within each group holding group n fixed.
# "All Segments" is just another group with its own n.
#
# stat_fn(resampled_df) must return a tibble/data.frame with columns
# `group` and `value`. One row per group.

bootstrap_ci <- function(data, group_col, stat_fn,
                         B = 500, conf = 0.95, seed = 20260907) {
  set.seed(seed + 3000L)
  alpha <- 1 - conf

  # Split by group
  groups <- split(data, data[[group_col]])

  # Collect B replicates
  reps <- matrix(NA_real_, nrow = B, ncol = length(groups))
  colnames(reps) <- names(groups)

  for (b in seq_len(B)) {
    # Stratified resample: within each group, sample n rows with replacement
    resampled <- do.call(rbind, lapply(groups, function(g) {
      g[sample.int(nrow(g), replace = TRUE), ]
    }))
    result <- stat_fn(resampled)
    reps[b, result$group] <- result$value
  }

  # Percentile CI
  tibble::tibble(
    group    = colnames(reps),
    estimate = apply(reps, 2, median),  # not used for point estimate; stat_fn's original value is authoritative
    ci_lower = apply(reps, 2, quantile, probs = alpha / 2, na.rm = TRUE),
    ci_upper = apply(reps, 2, quantile, probs = 1 - alpha / 2, na.rm = TRUE),
    B        = B
  )
}
```

~35 lines.

Design notes:
- `estimate` in the output is the bootstrap median, NOT the point estimate.
  The Rmd uses the original point estimate from the non-bootstrapped
  computation and only takes `ci_lower`/`ci_upper` from the bootstrap output.
- `stat_fn` returns a tibble with `group` and `value` columns. This is the
  contract that the three call sites must implement.
- The `split` + `lapply` + `rbind` pattern avoids dplyr overhead per
  replicate, which matters at B=500 x 61k rows.

## Step 3: Wire into orchestration_2.Rmd

### 3a. Source calls (after :268, compute_si.R source)

Insert two source() calls at the top of the PSI chunk, after the existing
source lines:

```r
source(here::here("R/wilson_ci.R"))
source(here::here("R/bootstrap_ci.R"))
```

Location: after :269 (source build_dev_population.R), before :270
(build_dev_population() call). These are sourced once and available to all
downstream chunks.

### 3b. PSI bootstrap + tier (after :314, psi_summary print)

Insert after `psi_summary` (currently :311-314). The `stat_fn` for PSI:

1. Takes resampled `psi_df` rows
2. Re-runs the binning pipeline (bucket_scores -> aggregate -> join dev_pop ->
   compute_stability_index)
3. Returns tibble(group = summary$Scorecard, value = summary$SI_value)

The dev side (`dev_pop`) and `segment_breaks` are fixed -- only the current
side varies.

```r
# --- PSI Bootstrap CI ---
psi_boot <- bootstrap_ci(
  data      = psi_df |> dplyr::mutate(segment = as.character(as.numeric(segment))),
  group_col = "segment",
  stat_fn   = function(df) {
    # "All Segments" row
    boot_all <- df |>
      dplyr::mutate(all_bucket_aligned = bucket_scores(prim_score, segment_breaks[["All Segments"]])) |>
      dplyr::group_by(all_bucket_aligned) |>
      dplyr::summarise(counts = dplyr::n_distinct(user_ref_num), .groups = "drop") |>
      dplyr::mutate(Scorecard = "All Segments")
    # Per-segment rows
    boot_seg <- df |>
      dplyr::group_by(segment) |>
      dplyr::group_modify(~ {
        brks <- segment_breaks[[.y$segment]]
        .x |>
          dplyr::mutate(all_bucket_aligned = bucket_scores(prim_score, brks)) |>
          dplyr::group_by(all_bucket_aligned) |>
          dplyr::summarise(counts = dplyr::n_distinct(user_ref_num), .groups = "drop")
      }) |>
      dplyr::ungroup() |>
      dplyr::rename(Scorecard = segment)
    boot_psi <- dplyr::bind_rows(boot_all, boot_seg) |>
      tidyr::separate(all_bucket_aligned, c("Lower_Range", "Upper_Range"), sep = " to ") |>
      dplyr::mutate(Lower_Range = as.numeric(Lower_Range), Upper_Range = as.numeric(Upper_Range))
    boot_joined <- dplyr::full_join(dev_pop, boot_psi,
                                     by = c("Scorecard", "Lower_Range", "Upper_Range")) |>
      dplyr::mutate(counts = dplyr::coalesce(counts, 0L))
    boot_result <- compute_stability_index(boot_joined, epsilon = psi_epsilon)
    tibble::tibble(group = boot_result$summary$Scorecard,
                   value = boot_result$summary$SI_value)
  },
  B = 500
)

# Add CI and tier to psi_summary
psi_summary <- psi_summary |>
  dplyr::left_join(
    psi_boot |> dplyr::select(group, ci_lower, ci_upper, B),
    by = c("Scorecard" = "group")
  ) |>
  dplyr::mutate(
    tier = dplyr::case_when(
      Population_Stability_Index < 0.10 ~ "stable",
      Population_Stability_Index <= 0.25 ~ "watch",
      TRUE ~ "investigate"
    ),
    tier_certain = !(
      (ci_lower < 0.10 & ci_upper >= 0.10) |
      (ci_lower < 0.25 & ci_upper >= 0.25)
    )
  )

psi_summary
```

IMPORTANT: the `stat_fn` resamples within groups via `bootstrap_ci`'s
stratification, but for PSI, the group_col is `segment` (the per-segment
column in psi_df). The "All Segments" aggregation happens INSIDE stat_fn
by rebinding all rows with Scorecard = "All Segments". This means All
Segments is resampled as the union of per-segment resamples -- which is
correct: the total population size is fixed, and each segment's n is fixed.

### 3c. CSI bootstrap (after csi_summary print, currently :449)

```r
# --- CSI Bootstrap CI ---
# Resample application rows ONCE per replicate; recompute all 5 features
# from the same draw to preserve correlation structure.
csi_boot_data <- csi_df |>
  dplyr::mutate(Scorecard = as.character(as.numeric(segment)))

csi_ci <- bootstrap_ci(
  data      = csi_boot_data,
  group_col = "Scorecard",
  stat_fn   = function(df) {
    all_results <- list()
    for (fname in names(feature_breaks)) {
      fb <- feature_breaks[[fname]]
      vals <- df[[fname]]
      if (fb$type == "continuous") {
        bin_idx <- as.integer(cut(vals, breaks = fb$breaks, right = TRUE, include.lowest = TRUE))
        n_bins <- length(fb$dev_counts)
      } else {
        bin_idx <- as.integer(factor(vals, levels = fb$levels))
        n_bins <- length(fb$levels)
      }
      binned <- dplyr::tibble(Scorecard = df$Scorecard, bin_index = bin_idx)
      agg <- dplyr::bind_rows(
        binned |> dplyr::group_by(Scorecard, bin_index) |> dplyr::summarise(counts = dplyr::n(), .groups = "drop"),
        binned |> dplyr::mutate(Scorecard = "All Segments") |> dplyr::group_by(Scorecard, bin_index) |>
          dplyr::summarise(counts = dplyr::n(), .groups = "drop")
      )
      dev_ref <- dplyr::bind_rows(lapply(c("All Segments", as.character(0:4)), function(seg) {
        dplyr::tibble(Scorecard = seg, bin_index = seq_len(n_bins), counts_dev = fb$dev_counts)
      }))
      joined <- dplyr::full_join(dev_ref, agg, by = c("Scorecard", "bin_index")) |>
        dplyr::mutate(counts = dplyr::coalesce(counts, 0L))
      result <- compute_stability_index(joined, epsilon = psi_epsilon)
      for (i in seq_len(nrow(result$summary))) {
        all_results[[length(all_results) + 1]] <- list(
          group = paste0(result$summary$Scorecard[i], "::", fname),
          value = result$summary$SI_value[i]
        )
      }
    }
    dplyr::bind_rows(all_results)
  },
  B = 500
)

# Parse compound group key back to Scorecard + feature
csi_ci <- csi_ci |>
  tidyr::separate(group, into = c("Scorecard", "feature"), sep = "::") |>
  dplyr::left_join(
    csi_summary_long |> dplyr::select(Scorecard, feature, estimate = SI_value),
    by = c("Scorecard", "feature")
  ) |>
  dplyr::select(Scorecard, feature, estimate, ci_lower, ci_upper, B)

csi_ci
```

Key design decision: the `group` key is a compound `"Scorecard::feature"`
string. This is because `bootstrap_ci` returns one row per group, and CSI
has 30 groups (6 segments x 5 features). The compound key is split back
after the bootstrap returns.

The `estimate` column is overwritten with the original point estimate from
`csi_summary_long` to ensure exact match.

### 3d. KS bootstrap (after ks_comparison, currently :611)

```r
# --- KS Bootstrap CI ---
ks_boot <- bootstrap_ci(
  data      = ks_df |> dplyr::mutate(segment = as.character(segment)),
  group_col = "segment",
  stat_fn   = function(df) {
    # Append "All Segments" copy
    all_df <- dplyr::bind_rows(df, df |> dplyr::mutate(segment = "All Segments"))
    # ntile() runs INSIDE stat_fn -- decile boundaries are re-derived
    ks <- all_df |>
      dplyr::group_by(segment) |>
      dplyr::group_modify(~ {
        .x <- .x |> dplyr::arrange(dplyr::desc(prim_score)) |>
          dplyr::mutate(decile = dplyr::ntile(dplyr::desc(prim_score), 10))
        dec <- .x |> dplyr::group_by(decile) |>
          dplyr::summarise(n = dplyr::n(), n_bads = sum(dq90), .groups = "drop") |>
          dplyr::arrange(decile)
        total_goods <- sum(dec$n - dec$n_bads)
        total_bads <- sum(dec$n_bads)
        if (total_bads == 0) return(tibble::tibble(ks_value = 0))
        dec <- dec |>
          dplyr::mutate(
            cum_pct_good = cumsum(n - n_bads) / total_goods,
            cum_pct_bad  = cumsum(n_bads) / total_bads,
            ks_at_decile = abs(cum_pct_bad - cum_pct_good) * 100
          )
        tibble::tibble(ks_value = max(dec$ks_at_decile))
      }) |>
      dplyr::ungroup()
    tibble::tibble(group = ks$segment, value = ks$ks_value)
  },
  B = 500
)

ks_comparison <- ks_comparison |>
  dplyr::left_join(
    ks_boot |> dplyr::select(group, ci_lower, ci_upper, B),
    by = c("segment" = "group")
  )

ks_comparison
```

CRITICAL: `ntile()` runs inside `stat_fn`. Decile boundaries are re-derived
from each resampled cohort, so decile-boundary variability is part of the
uncertainty. Binning outside the replicate loop would understate the interval.

Note: `bootstrap_ci` stratifies by `segment` (the 5 per-segment groups in
ks_df). "All Segments" is constructed INSIDE stat_fn by appending a copy --
same pattern as `compute_ks_stats`. This means All Segments resamples are
the union of the per-segment resamples, which correctly holds segment sizes
fixed.

### 3e. Decile Wilson CI (after decile_rates print, currently :614)

```r
# --- Decile bad-rate Wilson CI ---
# Wilson intervals per decile INDEPENDENTLY. These describe each decile
# alone, not the ten jointly. Comparing all nine adjacent pairs is nine
# comparisons and will occasionally show a spurious gap. These are
# screening intervals for triage, not hypothesis tests.
source(here::here("R/wilson_ci.R"))
decile_wilson <- wilson_ci(ks_result$decile_rates$n_bads, ks_result$decile_rates$n)
ks_result$decile_rates <- ks_result$decile_rates |>
  dplyr::mutate(ci_lower = decile_wilson$lower, ci_upper = decile_wilson$upper)

# Assertions
stopifnot("Wilson CI lower bound negative" = all(ks_result$decile_rates$ci_lower >= 0))
stopifnot("Wilson CI upper bound > 1" = all(ks_result$decile_rates$ci_upper <= 1))

# Test case: segment 0 decile 1 (0 bads in 1538)
seg0_d1 <- ks_result$decile_rates |>
  dplyr::filter(segment == "0", decile == 1)
stopifnot("Wilson CI for 0/1538 should have lower ~0" =
            seg0_d1$ci_lower < 0.001)
stopifnot("Wilson CI for 0/1538 should have upper ~0.0025" =
            abs(seg0_d1$ci_upper - 0.0024) < 0.001)

ks_result$decile_rates
```

Wait -- I need to reconsider the source() placement. The task brief says
`source(here::here("R/wilson_ci.R"))` should be at the top with the other
sources. Let me move it:

Actually, the source calls for both wilson_ci.R and bootstrap_ci.R should
go at the top of the PSI chunk (after :269), so they're available to all
downstream code. The Wilson CI is only used in the KS chunk, but sourcing
it early is cleaner than sourcing it mid-chunk.

Revised placement:
- After :269 (`source(here::here("R/build_dev_population.R"))`):
  ```r
  source(here::here("R/wilson_ci.R"))
  source(here::here("R/bootstrap_ci.R"))
  ```

### 3f. Update xlsx cache (after :616, openxlsx::write.xlsx call)

The `ks_result$decile_rates` now has `ci_lower` and `ci_upper` columns.
The existing `write.xlsx` at :617-621 already writes `ks_result$decile_rates`
to the `decile_rates` tab, so the new columns will flow through automatically.

Similarly, `ks_comparison` now has `ci_lower`, `ci_upper`, `B` columns, and
the xlsx write at :618 already includes it.

`psi_summary` gains `ci_lower`, `ci_upper`, `B`, `tier`, `tier_certain`.
The PSI xlsx write at :317-325 writes per-segment detail tabs, not the
summary. The summary is printed to console only. No xlsx change needed.

`csi_ci` is a new object. Add it to the CSI xlsx output:
```r
openxlsx::addWorksheet(wb_csi, "ci")
openxlsx::writeDataTable(wb_csi, "ci", csi_ci)
```
Insert before the saveWorkbook call at :481.

## Step 4: Documentation updates

### D21 in decisions.md

Two-method rationale:

| Metric | Method | Why |
|---|---|---|
| PSI, CSI, KS | Bootstrap (B=500, percentile) | Nonlinear functions of whole distributions; no closed form. KS adds decile re-derivation per replicate. |
| Decile bad rates | Wilson binomial | Single proportion; closed form; survives zero counts (Wald returns [0,0] at k=0). |

Deterministic-generator caveat: The bootstrap CI measures SAMPLING variability
of the metric given the observed cohort. It does NOT predict regeneration
variance. generate_cohort.R uses deterministic_allocate(), so regenerating the
cohort produces identical per-segment numbers -- zero variability by
construction. Someone testing this by regenerating would get identical numbers
and a zero-width interval, which is correct behavior (the generator is
deterministic) but must not be confused with "no uncertainty." The CI answers:
"if a real quarter with this shape had rolled differently, how much would this
number move?"

### CLAUDE.md updates

Add to function contracts table:

| Function | File | Returns |
|---|---|---|
| `wilson_ci(k, n, conf)` | `R/wilson_ci.R` | list: `$lower` (numeric vector), `$upper` (numeric vector). Vectorized Wilson score CI. |
| `bootstrap_ci(data, group_col, stat_fn, B, conf, seed)` | `R/bootstrap_ci.R` | tibble: group, estimate, ci_lower, ci_upper, B. Stratified percentile bootstrap. |

Update validated frontier line number (will shift by ~62 lines).
Add `add-confidence-intervals` to completed list.
Update anchors for all shifted lines.

### R/CATALOG.md updates

Add two new entries for wilson_ci.R and bootstrap_ci.R.
Update frontier line number.

## Step 5: Verification protocol

1. Run Rmd :1 through marker
2. Paste PSI before/after (must be identical point estimates)
3. Paste CSI before/after (must be identical point estimates)
4. Paste KS before/after (must be identical point estimates)
5. Report wall time
6. Assert wilson_ci(0, 1538) ~[0.0000, 0.0025]
7. Assert all 60 Wilson CIs have 0 <= lower, upper <= 1
8. Assert all bootstrap CIs contain their point estimates
9. Report any segment where tier_certain is FALSE
10. Report segment 0 decile 5/6/7 overlap finding

## Step 6: Expected outcomes

### PSI tier assignments (predicted from Pass 1 point estimates)

| Scorecard | PSI | Predicted tier | tier_certain? |
|---|---|---|---|
| 0 | 0.300 | investigate | likely TRUE (CI ~[0.275, 0.335], stays above 0.25) |
| 1 | 0.090 | stable | likely FALSE (CI ~[0.08, 0.11], spans 0.10) |
| 2 | 0.250 | watch | likely FALSE (CI may span 0.25) |
| 3 | 0.040 | stable | TRUE |
| 4 | 0.150 | watch | likely TRUE (CI ~[0.13, 0.17]) |
| All Segments | 0.084 | stable | likely TRUE |

Segments 1 and 2 are the interesting cases -- their point estimates sit near
thresholds and the CI likely spans the boundary.

### Wilson CI substantive finding

Segment 0 current deciles 5 and 6 (bad rates 0.028 and 0.023):
- Wilson CI for decile 5 (43/1538): ~[0.021, 0.037]
- Wilson CI for decile 6 (36/1538): ~[0.017, 0.032]
These overlap heavily -- the step is noise.

Segment 0 deciles 5 and 7 (bad rates 0.028 and 0.014):
- Wilson CI for decile 5 (43/1538): ~[0.021, 0.037]
- Wilson CI for decile 7 (21/1538): ~[0.009, 0.021]
These barely touch -- that drop is real (the Gaussian bump, D20).

## Risk assessment

### Performance risk
KS bootstrap is the bottleneck: 61,820 rows x 500 replicates, each with
ntile() + group_by + summarise. Budget: 30-60s. If > 60s, reduce to B=200
(defensible; state B in output).

### Correctness risk
The PSI stat_fn is the most complex (full binning pipeline). Must produce
exactly the same computation as the non-bootstrapped path. Verified by
checking that the bootstrap median is close to the point estimate.

### Breaking-change risk
None if point estimates are unchanged. The only modification to existing
objects is adding columns (left_join). No existing columns are removed or
renamed.

## Estimated line counts

| Location | Lines added |
|---|---|
| Source calls (after :269) | +2 |
| PSI bootstrap + tier (after :314) | +35 |
| CSI bootstrap (after :449) | +35 |
| CSI xlsx ci tab (before :481) | +2 |
| KS bootstrap (after :611) | +25 |
| Wilson CI (after :614) | +15 |
| Total | ~114 |

Revised estimate from Pass 1's ~62: the stat_fn closures are larger than
initially estimated because they reproduce the full computation pipeline.

New Rmd total: ~627 + 114 = ~741 lines. All anchors shift.
