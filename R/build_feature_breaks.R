# build_feature_breaks.R
#
# Bootstrap and freeze-check for R/feature_breaks.R (D18).
#
# If R/feature_breaks.R does not exist: GENERATE it from feature_defs.
# If it exists: VALIDATE it against feature_defs and fail loudly on drift.
#
# Also validates against the actual generated data (Q4 2025 flat cohort):
#   - Continuous: binned counts must be EXACTLY uniform
#   - Categorical: level proportions must match dev_counts exactly
#   - Every feature value must appear in the declared level/range set
#   - All bin/level counts >= 50

build_feature_breaks <- function(seed = 42L) {
  output_path <- here::here("R/feature_breaks.R")
  source(here::here("R/generate_cohort.R"))

  if (!file.exists(output_path)) {
    # --- Bootstrap: generate R/feature_breaks.R from feature_defs ---
    message("R/feature_breaks.R not found — generating from feature_defs.")
    emit_feature_breaks(feature_defs, output_path)
    message("Wrote ", output_path)
  }

  # --- Freeze-check: validate committed file against feature_defs ---
  env <- new.env(parent = baseenv())
  source(output_path, local = env)
  fb <- env$feature_breaks

  for (fname in names(feature_defs)) {
    fdef <- feature_defs[[fname]]
    fbrk <- fb[[fname]]
    if (is.null(fbrk)) stop(fname, " missing from feature_breaks", call. = FALSE)
    if (fbrk$type != fdef$type) stop(fname, " type mismatch: ", fbrk$type, " vs ", fdef$type, call. = FALSE)

    n_bins <- length(fbrk$dev_counts)

    if (fdef$type == "continuous") {
      expected_breaks <- seq(fdef$range[1], fdef$range[2],
                             length.out = fdef$n_bins + 1L)
      if (length(fbrk$breaks) - 1L != n_bins)
        stop(fname, ": length(breaks)-1 != length(dev_counts)", call. = FALSE)
      if (!identical(fbrk$breaks, expected_breaks))
        stop(fname, ": breaks drift — expected seq(",
             fdef$range[1], ", ", fdef$range[2], ", length.out=", fdef$n_bins + 1L, ")",
             call. = FALSE)
      if (n_bins != fdef$n_bins)
        stop(fname, ": n_bins mismatch: ", n_bins, " vs ", fdef$n_bins, call. = FALSE)
    } else {
      if (!identical(fbrk$levels, fdef$levels))
        stop(fname, ": levels drift", call. = FALSE)
      expected_props <- fdef$dev_weights
      actual_props <- fbrk$dev_counts / sum(fbrk$dev_counts)
      if (!isTRUE(all.equal(actual_props, expected_props, tolerance = 1e-10)))
        stop(fname, ": dev_counts proportions drift from dev_weights", call. = FALSE)
    }
  }

  # Check all dev_counts totals are equal
  totals <- sapply(fb, function(x) sum(x$dev_counts))
  if (length(unique(totals)) != 1L)
    stop("dev_counts totals differ across features: ",
         paste(names(totals), totals, sep = "=", collapse = ", "), call. = FALSE)

  message("Freeze-check passed: feature_breaks.R matches feature_defs.")

  # --- Data validation against Q4 2025 flat cohort ---
  message("Generating cohort for data validation (seed=", seed, ")...")
  result <- generate_cohort(seed = seed)

  apps <- result$apps
  scorecard <- result$scorecard
  features <- result$features

  dev_apps <- apps[zoo::as.yearqtr(apps$dt_entered) ==
                   zoo::as.yearqtr(as.Date("2025-10-01")), ]
  merged <- merge(dev_apps, scorecard, by = "user_ref_num", all.x = TRUE)
  core <- merged[merged$client_product_cd %in% c("CC", "PLAT", "GOLD") &
                 !is.na(merged$prim_score) & !is.na(merged$segment), ]
  dev_feat <- features[features$user_ref_num %in% core$user_ref_num, ]

  N <- nrow(dev_feat)
  message("Dev core population: ", N, " rows")
  min_count <- Inf

  for (fname in names(fb)) {
    fbrk <- fb[[fname]]
    vals <- dev_feat[[fname]]

    if (fbrk$type == "continuous") {
      binned <- cut(vals, breaks = fbrk$breaks, include.lowest = TRUE, right = TRUE)
      counts <- tabulate(binned, nbins = length(fbrk$dev_counts))
      n_bins <- length(fbrk$dev_counts)

      # Expected counts: pool per-segment deterministic_allocate results.
      # Not N/n_bins because per-segment remainders accumulate when n_bins
      # does not divide evenly into every segment volume.
      expected_counts <- rep(0L, n_bins)
      for (seg in names(segment_volumes)) {
        N_seg <- segment_volumes[seg]
        expected_counts <- expected_counts +
          deterministic_allocate(N_seg, rep(1 / n_bins, n_bins))
      }
      if (!all(counts == expected_counts))
        stop(fname, ": flat cohort counts != expected — actual: ",
             paste(counts, collapse = ", "), " expected: ",
             paste(expected_counts, collapse = ", "), call. = FALSE)

      if (min(counts) == max(counts)) {
        message(sprintf("  %s: %d bins, all counts = %d (exact uniform)",
                        fname, n_bins, counts[1]))
      } else {
        message(sprintf("  %s: %d bins, counts [%d, %d] (per-segment remainder, max delta = %d)",
                        fname, n_bins, min(counts), max(counts),
                        max(counts) - min(counts)))
      }
      min_count <- min(min_count, min(counts))

    } else {
      obs <- table(factor(vals, levels = fbrk$levels))
      obs_props <- as.numeric(obs / sum(obs))
      dev_props <- fbrk$dev_counts / sum(fbrk$dev_counts)
      if (!isTRUE(all.equal(obs_props, dev_props, tolerance = 1e-10)))
        stop(fname, ": flat cohort proportions != dev_props — observed: ",
             paste(sprintf("%.4f", obs_props), collapse = ", "), call. = FALSE)
      # Check for undeclared levels
      all_vals <- unique(features[[fname]])
      undeclared <- setdiff(all_vals, fbrk$levels)
      if (length(undeclared) > 0)
        stop(fname, ": undeclared levels in features table: ",
             paste(undeclared, collapse = ", "), call. = FALSE)
      message(sprintf("  %s: %d levels, proportions exact — %s",
                      fname, length(fbrk$levels),
                      paste(sprintf("%s=%.4f", fbrk$levels, obs_props), collapse = ", ")))
      min_count <- min(min_count, min(as.integer(obs)))
    }
  }

  message("Min bin/level count: ", min_count)
  if (min_count < 50) stop("Min count below 50: ", min_count, call. = FALSE)
  message("All checks passed.")
  invisible(fb)
}

# --- Helper: emit R/feature_breaks.R from feature_defs ---
emit_feature_breaks <- function(feature_defs, output_path) {
  lines <- c(
    "# feature_breaks.R",
    "#",
    "# Frozen feature binning reference for CSI calculation (D18).",
    "# Analogous to segment_breaks for PSI — computed once from the development",
    "# population and held fixed. If re-derived from each cohort, CSI would always",
    "# be ~0 (the same trap as PSI with re-derived vigintiles).",
    "#",
    "# Continuous breaks are the generator's evenly-spaced bin boundaries — the",
    "# development population's deciles by construction. Categorical dev_counts",
    "# are the declared level proportions scaled to a common total.",
    "#",
    "# Global (not per-segment): the generator draws features from identical",
    "# distributions for all segments. Per-segment breaks would be identical.",
    "# Known simplification: in production, segments have different feature",
    "# distributions and would carry different cutpoints.",
    "#",
    "# All five features describe the SAME development population of 10,000",
    "# applicants, binned five different ways. dev_counts is the single source",
    "# of truth; dev_props for categorical features is derived (asserted by",
    "# R/build_feature_breaks.R).",
    "#",
    "# DO NOT edit these values without re-running R/build_feature_breaks.R.",
    "",
    "feature_breaks <- list("
  )

  dev_total <- 10000L
  fnames <- names(feature_defs)
  for (fi in seq_along(fnames)) {
    fname <- fnames[fi]
    fdef <- feature_defs[[fname]]
    comma <- if (fi < length(fnames)) "," else ""

    if (fdef$type == "continuous") {
      brks <- seq(fdef$range[1], fdef$range[2], length.out = fdef$n_bins + 1L)
      count_per_bin <- dev_total %/% fdef$n_bins
      lines <- c(lines,
        sprintf("  %s = list(", fname),
        "    type = \"continuous\",",
        sprintf("    breaks = seq(%s, %s, length.out = %d),",
                fdef$range[1], fdef$range[2], fdef$n_bins + 1L),
        sprintf("    dev_counts = rep(%dL, %d)", count_per_bin, fdef$n_bins),
        sprintf("  )%s", comma)
      )
    } else {
      dev_counts <- as.integer(round(fdef$dev_weights * dev_total))
      lines <- c(lines,
        sprintf("  %s = list(", fname),
        "    type = \"categorical\",",
        sprintf("    levels = c(%s),",
                paste(sprintf("\"%s\"", fdef$levels), collapse = ", ")),
        sprintf("    dev_counts = c(%s)",
                paste(sprintf("%dL", dev_counts), collapse = ", ")),
        sprintf("  )%s", comma)
      )
    }
  }

  lines <- c(lines, ")")
  writeLines(lines, output_path)
}
