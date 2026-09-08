# bootstrap_ci.R
#
# Stratified percentile bootstrap for stability metrics (PSI, CSI, KS).
# Resamples rows within each group holding group n fixed.
# "All Segments" is constructed inside stat_fn, not as a resampling stratum.
#
# stat_fn(resampled_df) must return a data.frame with columns
# `group` (character) and `value` (numeric). One row per group.

# QUESTION: Do I call this the 95% percentile confidence window because conf = 0.95? When and why would we change the value?

bootstrap_ci <- function(data, group_col, stat_fn,
                         B = 500, conf = 0.95, seed = 20260907) {
  set.seed(seed + 3000L)
  alpha <- 1 - conf

  # Discover group set and point estimates from unresampled data
  baseline <- stat_fn(data)
  group_names <- baseline$group
  n_groups <- length(group_names)

  # Split by resampling group
  groups <- split(data, data[[group_col]])

  # Collect B replicates
  reps <- matrix(NA_real_, nrow = B, ncol = n_groups)
  colnames(reps) <- group_names

  for (b in seq_len(B)) {
    resampled <- dplyr::bind_rows(lapply(groups, function(g) {
      g[sample.int(nrow(g), replace = TRUE), ]
    }))
    result <- stat_fn(resampled)
    reps[b, result$group] <- result$value
  }

  # Percentile CI
  tibble::tibble(
    group    = group_names,
    ci_lower = apply(reps, 2, quantile, probs = alpha / 2, na.rm = TRUE),
    ci_upper = apply(reps, 2, quantile, probs = 1 - alpha / 2, na.rm = TRUE),
    B        = B
  )
}
