# generate_cohort.R
#
# Parameterized cohort generator for PSI/CSI demonstration (D6, D16, D17).
# Produces four quarters of applications + scorecard + features data with
# controlled drift via bin-weight tilting. Alpha is solved from target PSI/CSI
# via bisection. Bin counts are deterministic (round + remainder); scores and
# feature values are random within bins.
#
# Coupling: prim_score (applications) and segment (scorecard) are generated
# from the same draw, then split across two tables joined on user_ref_num.
# Features are generated in a second phase with an independent RNG stream.
#
# segment_breaks duplicated from orchestration_2.Rmd:181-194 and
# R/build_dev_population.R:18-31. Third copy — breaks are frozen (D15).
#
# "All Segments" PSI diverges from per-segment targets because the pooled
# population is re-binned through a different break vector that does not nest
# inside the per-segment vectors. At alpha=0 the residual is ~0.01 (not zero).
# This is a property of the synthetic data, not a defect. In production the
# All Segments breaks ARE the pooled vigintiles so the residual is zero by
# construction. See D16.
#
# Solver generalization (D17): psi_from_alpha, solve_alpha, and tilt_weights
# accept an optional dev_weights vector for non-uniform dev distributions
# (categorical features). When dev_weights is NULL (continuous features),
# the uniform case 1/n_bins is used, recovering the original formula exactly.
# For uniform q, sum(t_i) = 0, so sum(q_i * (1 + alpha*t_i)) = 1 and
# w_i = (1 + alpha*t_i)/n. For non-uniform q, the normalization
# sum(q_i * (1 + alpha*t_i)) != 1 in general.
#
# Categorical tilt direction (D17): tilt_dir = -1 reverses which end of the
# level list is boosted. For feature_4 and feature_5 this moves mass from the
# dominant level toward the minority level, modeling channel-mix drift away
# from the dominant source.

# --- segment_breaks (frozen, D15) ---
segment_breaks <- list(
  "All Segments" = c(100, 117, 134, 151, 168, 185, 202, 219, 236, 253,
                     270, 287, 304, 321, 338, 355, 372, 389, 406, 423, 450),
  "0" = c(100, 112, 124, 136, 148, 160, 172, 184, 196, 208,
          220, 232, 244, 256, 268, 280, 292, 304, 316, 328, 450),
  "1" = c(100, 118, 136, 154, 172, 190, 208, 226, 244, 262,
          280, 298, 316, 334, 352, 362, 372, 382, 392, 410, 450),
  "2" = c(100, 120, 140, 160, 180, 200, 220, 240, 260, 280,
          300, 315, 330, 345, 360, 375, 390, 405, 420, 435, 450),
  "3" = c(100, 125, 150, 170, 190, 210, 230, 250, 270, 290,
          310, 325, 340, 355, 370, 385, 395, 405, 420, 435, 450),
  "4" = c(100, 130, 155, 180, 200, 220, 240, 260, 280, 300,
          320, 335, 350, 365, 380, 390, 400, 410, 425, 440, 450)
)

# --- Post-filter segment volumes (D16) ---
segment_volumes <- c("0" = 5500L, "1" = 8000L, "2" = 6000L,
                     "3" = 5500L, "4" = 5500L)

# --- Feature definitions (D17) ---
# type: "continuous" (quantile bins, uniform dev) or "categorical" (level set,
#   non-uniform dev). tilt_dir: +1 boosts first element, -1 boosts last.
#   Categorical features use tilt_dir = -1 so mass moves toward the minority
#   level (recognizable channel-mix drift). See D17.
feature_defs <- list(
  feature_1 = list(type = "continuous", n_bins = 10L,
                   range = c(0, 1000), tilt_dir = 1L),
  feature_2 = list(type = "continuous", n_bins = 8L,
                   range = c(0, 500),  tilt_dir = 1L),
  feature_3 = list(type = "continuous", n_bins = 5L,
                   range = c(0, 100),  tilt_dir = 1L),
  feature_4 = list(type = "categorical",
                   levels = c("A", "B", "C", "D"),
                   dev_weights = c(0.45, 0.30, 0.15, 0.10), tilt_dir = -1L),
  feature_5 = list(type = "categorical",
                   levels = c("X", "Y", "Z"),
                   dev_weights = c(0.60, 0.30, 0.10), tilt_dir = -1L)
)

# --- Theoretical PSI/CSI for linear tilt ---
# Generalized: dev_weights = NULL uses uniform 1/n_bins; otherwise uses the
# supplied vector. alpha can be negative (tilt_dir = -1 applied by caller).
psi_from_alpha <- function(alpha, n_bins = 20L, dev_weights = NULL) {
  if (alpha == 0) return(0)
  q <- if (is.null(dev_weights)) rep(1 / n_bins, n_bins) else dev_weights
  n <- length(q)
  i <- seq_len(n)
  t_i <- (n + 1 - 2 * i) / (n - 1)
  raw <- q * (1 + alpha * t_i)
  w <- raw / sum(raw)
  sum((w - q) * log(w / q))
}

# --- Bisect for alpha given target PSI/CSI ---
# Returns positive alpha. tilt_dir controls evaluation direction: the solver
# finds alpha >= 0 such that psi_from_alpha(alpha * tilt_dir, ...) == target.
solve_alpha <- function(target_psi, n_bins = 20L, dev_weights = NULL,
                        tilt_dir = 1L, tol = 1e-6) {
  if (target_psi == 0) return(0)
  lo <- 0
  hi <- 0.99
  for (iter in seq_len(100)) {
    mid <- (lo + hi) / 2
    psi_mid <- psi_from_alpha(mid * tilt_dir, n_bins, dev_weights)
    if (abs(psi_mid - target_psi) < tol) return(mid)
    if (psi_mid < target_psi) lo <- mid else hi <- mid
  }
  mid
}

# --- Linear tilt weight vector ---
# Generalized: dev_weights = NULL uses uniform 1/n_bins. alpha can be negative.
tilt_weights <- function(alpha, n_bins = 20L, dev_weights = NULL) {
  q <- if (is.null(dev_weights)) rep(1 / n_bins, n_bins) else dev_weights
  n <- length(q)
  i <- seq_len(n)
  t_i <- (n + 1 - 2 * i) / (n - 1)
  raw <- q * (1 + alpha * t_i)
  raw / sum(raw)
}

# --- Deterministic allocation: round + remainder ---
deterministic_allocate <- function(N, weights) {
  raw <- N * weights
  counts <- floor(raw)
  remainder <- as.integer(N - sum(counts))
  if (remainder > 0L) {
    fracs <- raw - counts
    top_idx <- order(fracs, decreasing = TRUE)[seq_len(remainder)]
    counts[top_idx] <- counts[top_idx] + 1
  }
  as.integer(counts)
}

# --- Generate integer scores within a bin ---
# Bin 1 (include.lowest, right=TRUE): [breaks[1], breaks[2]] -> breaks[1]:breaks[2]
# Bin j>1 (right=TRUE):               (breaks[j], breaks[j+1]] -> (breaks[j]+1):breaks[j+1]
scores_in_bin <- function(n, breaks, bin_index) {
  if (n == 0L) return(integer(0))
  if (bin_index == 1L) {
    lo <- breaks[1]
    hi <- breaks[2]
  } else {
    lo <- breaks[bin_index] + 1L
    hi <- breaks[bin_index + 1]
  }
  sample(lo:hi, n, replace = TRUE)
}

# --- Generate feature values from bin/level counts ---
# Continuous: draws runif within evenly-spaced bins on fdef$range.
# Categorical: assigns level labels by count.
# Returns shuffled vector (avoids bin-order artifacts).
generate_feature_values <- function(fdef, counts) {
  if (fdef$type == "continuous") {
    breaks <- seq(fdef$range[1], fdef$range[2], length.out = fdef$n_bins + 1L)
    vals <- numeric(sum(counts))
    pos <- 1L
    for (j in seq_along(counts)) {
      if (counts[j] == 0L) next
      vals[pos:(pos + counts[j] - 1L)] <- runif(counts[j], breaks[j], breaks[j + 1])
      pos <- pos + counts[j]
    }
  } else {
    vals <- rep(fdef$levels, times = counts)
  }
  vals[sample(length(vals))]
}

# --- Generate dates spread across 3 months of a quarter ---
generate_dates <- function(n, quarter_start) {
  all_months <- seq(as.Date(quarter_start), by = "month", length.out = 4)
  month_starts <- all_months[1:3]
  month_ends <- all_months[2:4] - 1L

  month_idx <- rep(1:3, length.out = n)

  dates <- as.Date(rep(NA_integer_, n), origin = "1970-01-01")
  for (m in 1:3) {
    idx <- which(month_idx == m)
    days_range <- as.integer(month_ends[m] - month_starts[m])
    dates[idx] <- month_starts[m] + sample(0:days_range, length(idx), replace = TRUE)
  }
  dates
}

# --- Main generator ---
# quarters: named list. Each element is a named numeric vector of per-segment
# target PSI values (names "0"-"4"). Each segment solves its own alpha.
# Shuffling applications between segments post-hoc does NOT produce distinct
# per-segment PSIs — PSI is computed on percentages, so moving rows between
# segments leaves each segment's bin distribution unchanged. The only real
# effect comes from re-binning through different break vectors, which is
# uncontrollable. Per-segment alpha is the correct mechanism.
#
# feature_targets: named list keyed by quarter label, each containing a named
# list keyed by segment ("0"-"4"), each containing a named numeric vector of
# per-feature CSI targets (feature_1 through feature_5). NULL = build from
# default Q3 schedule scaled proportionally.
generate_cohort <- function(
  quarters = list(
    "2025-10-01" = c("0" = 0.00, "1" = 0.00, "2" = 0.00, "3" = 0.00, "4" = 0.00),
    "2026-01-01" = c("0" = 0.08, "1" = 0.03, "2" = 0.05, "3" = 0.02, "4" = 0.04),
    "2026-04-01" = c("0" = 0.18, "1" = 0.05, "2" = 0.12, "3" = 0.03, "4" = 0.08),
    "2026-07-01" = c("0" = 0.30, "1" = 0.09, "2" = 0.25, "3" = 0.04, "4" = 0.15)
  ),
  feature_targets = NULL,
  seed = 42L
) {
  # --- Build default feature_targets if NULL ---
  if (is.null(feature_targets)) {
    q3_csi <- list(
      "0" = c(feature_1 = 0.28, feature_2 = 0.02, feature_3 = 0.19,
              feature_4 = 0.01, feature_5 = 0.03),
      "1" = c(feature_1 = 0.04, feature_2 = 0.02, feature_3 = 0.05,
              feature_4 = 0.01, feature_5 = 0.02),
      "2" = c(feature_1 = 0.22, feature_2 = 0.03, feature_3 = 0.06,
              feature_4 = 0.02, feature_5 = 0.04),
      "3" = c(feature_1 = 0.02, feature_2 = 0.01, feature_3 = 0.02,
              feature_4 = 0.01, feature_5 = 0.01),
      "4" = c(feature_1 = 0.11, feature_2 = 0.02, feature_3 = 0.04,
              feature_4 = 0.02, feature_5 = 0.03)
    )
    qt_names <- names(quarters)
    n_qt <- length(qt_names)
    csi_scales <- c(0, 0.25, 0.50, 1.00)
    if (n_qt != 4L) csi_scales <- seq(0, 1, length.out = n_qt)
    feature_targets <- setNames(lapply(seq_along(qt_names), function(i) {
      lapply(q3_csi, function(v) v * csi_scales[i])
    }), qt_names)
  }

  # --- Validate feature_targets matches quarters ---
  stopifnot("feature_targets quarters must match quarters" =
              setequal(names(feature_targets), names(quarters)))
  for (qt in names(quarters)) {
    if (!setequal(names(feature_targets[[qt]]), names(quarters[[qt]]))) {
      stop("feature_targets segments must match quarters segments for ", qt,
           call. = FALSE)
    }
  }

  set.seed(seed)

  all_apps <- vector("list", length(quarters))
  all_scorecard <- vector("list", length(quarters))
  meta <- list()

  next_app_num <- 100001L
  next_urn <- 20000000000001
  next_sq_num <- 500001L

  for (q_idx in seq_along(quarters)) {
    quarter_start <- names(quarters)[q_idx]
    target_psi_vec <- quarters[[q_idx]]

    # --- Core rows (survive all Rmd filters) ---
    core_list <- vector("list", length(segment_volumes))
    bin_stats <- list()
    alphas <- numeric(length(segment_volumes))
    names(alphas) <- names(segment_volumes)

    for (s_idx in seq_along(segment_volumes)) {
      seg_name <- names(segment_volumes)[s_idx]
      N <- segment_volumes[s_idx]
      brks <- segment_breaks[[seg_name]]

      seg_target <- target_psi_vec[seg_name]
      seg_alpha <- solve_alpha(seg_target)
      alphas[seg_name] <- seg_alpha
      weights <- tilt_weights(seg_alpha)
      bin_counts <- deterministic_allocate(N, weights)

      stopifnot(min(bin_counts) >= 50)
      stopifnot(sum(bin_counts) == N)

      scores <- unlist(lapply(seq_along(bin_counts), function(i) {
        scores_in_bin(bin_counts[i], brks, i)
      }))

      core_list[[s_idx]] <- data.frame(
        prim_score = as.numeric(scores),
        segment = seg_name,
        stringsAsFactors = FALSE
      )
      bin_stats[[seg_name]] <- bin_counts
    }

    core_df <- do.call(rbind, core_list)
    rownames(core_df) <- NULL
    n_core <- nrow(core_df)

    # --- Noise rows ---
    n_sec_msc <- round(n_core * 0.08)
    n_sec <- round(n_sec_msc * 0.6)
    n_msc <- n_sec_msc - n_sec
    n_null_score <- round(n_core * 0.04)
    n_no_match <- round(n_core * 0.04)
    n_null_seg <- 50L

    # SEC/MSC: valid scores and segments, filtered by product code
    sec_msc_df <- data.frame(
      prim_score = as.numeric(sample(100L:450L, n_sec_msc, replace = TRUE)),
      segment = sample(as.character(0:4), n_sec_msc, replace = TRUE),
      client_product_cd = c(rep("SEC", n_sec), rep("MSC", n_msc)),
      has_scorecard = TRUE,
      stringsAsFactors = FALSE
    )

    # NULL prim_score: have scorecard match, filtered by is.na(prim_score)
    null_score_df <- data.frame(
      prim_score = rep(NA_real_, n_null_score),
      segment = sample(as.character(0:4), n_null_score, replace = TRUE),
      client_product_cd = rep("CC", n_null_score),
      has_scorecard = TRUE,
      stringsAsFactors = FALSE
    )

    # No scorecard match: have prim_score, filtered by has_segment after join
    no_match_df <- data.frame(
      prim_score = as.numeric(sample(100L:450L, n_no_match, replace = TRUE)),
      segment = rep(NA_character_, n_no_match),
      client_product_cd = rep("CC", n_no_match),
      has_scorecard = FALSE,
      stringsAsFactors = FALSE
    )

    # NULL segment: have scorecard match but segment NULL
    null_seg_df <- data.frame(
      prim_score = as.numeric(sample(100L:450L, n_null_seg, replace = TRUE)),
      segment = rep(NA_character_, n_null_seg),
      client_product_cd = rep("CC", n_null_seg),
      has_scorecard = TRUE,
      stringsAsFactors = FALSE
    )

    # Core rows get realistic product codes
    core_df$client_product_cd <- sample(
      c("CC", "PLAT", "GOLD"), n_core, replace = TRUE,
      prob = c(0.93, 0.05, 0.02)
    )
    core_df$has_scorecard <- TRUE

    # Combine and shuffle
    all_rows <- rbind(core_df, sec_msc_df, null_score_df, no_match_df, null_seg_df)
    n_total <- nrow(all_rows)
    all_rows <- all_rows[sample(n_total), ]

    # --- Assign IDs ---
    urns <- sprintf("%014.0f", next_urn + seq_len(n_total) - 1)
    next_urn <- next_urn + n_total

    app_nums <- seq.int(next_app_num, length.out = n_total)
    next_app_num <- next_app_num + n_total

    all_rows$user_ref_num <- urns
    all_rows$app_num <- app_nums

    # --- Dates ---
    dt_entered <- generate_dates(n_total, quarter_start)
    all_rows$dt_entered <- dt_entered

    # --- Filler columns (not load-bearing for PSI) ---
    decisions <- sample(
      c("Approve", "Decline", "Void", "Withdraw", "Pending"),
      n_total, replace = TRUE, prob = c(0.60, 0.20, 0.05, 0.05, 0.10)
    )
    all_rows$decision <- decisions
    all_rows$applied <- ifelse(decisions == "Approve", 1L, 0L)
    all_rows$strategy_version <- sample(
      c("V2.0", "V2.1"), n_total, replace = TRUE, prob = c(0.3, 0.7)
    )

    credit_lims <- round(runif(n_total, 1000, 15000), -2)
    credit_lims[decisions %in% c("Decline", "Void")] <- NA
    all_rows$assigned_credit_lim <- credit_lims
    all_rows$lao_credit_lmt <- credit_lims

    all_rows$org_paper_type <- sample(
      c("ELECTRONIC", "PAPER"), n_total, replace = TRUE, prob = c(0.85, 0.15)
    )
    all_rows$fico_score <- as.numeric(sample(500L:850L, n_total, replace = TRUE))
    all_rows$bureau_used <- sample(
      c("EXP", "TU", "EQ"), n_total, replace = TRUE, prob = c(0.4, 0.35, 0.25)
    )
    all_rows$acq <- sample(
      c("WEB", "BRANCH"), n_total, replace = TRUE, prob = c(0.80, 0.20)
    )

    # --- Build applications data.frame ---
    apps_df <- data.frame(
      app_num             = all_rows$app_num,
      user_ref_num        = all_rows$user_ref_num,
      dt_entered          = all_rows$dt_entered,
      client_product_cd   = all_rows$client_product_cd,
      strategy_version    = all_rows$strategy_version,
      assigned_credit_lim = all_rows$assigned_credit_lim,
      decision            = all_rows$decision,
      applied             = all_rows$applied,
      org_paper_type      = all_rows$org_paper_type,
      lao_credit_lmt      = all_rows$lao_credit_lmt,
      fico_score          = all_rows$fico_score,
      bureau_used         = all_rows$bureau_used,
      acq                 = all_rows$acq,
      prim_score          = all_rows$prim_score,
      stringsAsFactors    = FALSE
    )

    # --- Build scorecard data.frame ---
    sc_mask <- all_rows$has_scorecard
    sc_rows <- all_rows[sc_mask, ]
    n_sc <- nrow(sc_rows)

    sq_nums <- seq.int(next_sq_num, length.out = n_sc)
    next_sq_num <- next_sq_num + n_sc

    proc_dates <- sc_rows$dt_entered + sample(0:2, n_sc, replace = TRUE)
    null_proc_idx <- sample(n_sc, round(n_sc * 0.05))
    proc_dates[null_proc_idx] <- NA

    primemdt_vals <- rep(NA_character_, n_sc)
    primemdt_idx <- sample(n_sc, round(n_sc * 0.05))
    primemdt_vals[primemdt_idx] <- format(
      sc_rows$dt_entered[primemdt_idx] - sample(30:365, length(primemdt_idx), replace = TRUE),
      "%Y-%m-%d"
    )

    scorecard_df <- data.frame(
      sq_num          = sq_nums,
      user_ref_num    = sc_rows$user_ref_num,
      score           = as.numeric(sample(400L:850L, n_sc, replace = TRUE)),
      segment         = sc_rows$segment,
      actduty         = sample(c("Y", "N"), n_sc, replace = TRUE, prob = c(0.05, 0.95)),
      trans_date_ct   = sc_rows$dt_entered,
      proc_date_ct    = proc_dates,
      primemdt        = primemdt_vals,
      stringsAsFactors = FALSE
    )

    all_apps[[q_idx]] <- apps_df
    all_scorecard[[q_idx]] <- scorecard_df

    all_bin_counts <- unlist(bin_stats, use.names = FALSE)
    meta[[quarter_start]] <- list(
      target_psi       = target_psi_vec,
      alphas           = alphas,
      n_apps           = n_total,
      n_scorecard      = n_sc,
      n_core           = n_core,
      bin_stats        = bin_stats,
      min_bin          = min(all_bin_counts),
      max_bin          = max(all_bin_counts)
    )
  }

  apps <- do.call(rbind, all_apps)
  scorecard <- do.call(rbind, all_scorecard)
  rownames(apps) <- NULL
  rownames(scorecard) <- NULL

  stopifnot("Duplicate user_ref_num in scorecard" =
              !anyDuplicated(scorecard$user_ref_num))
  stopifnot("Duplicate app_num in applications" =
              !anyDuplicated(apps$app_num))

  message("Generated ", nrow(apps), " apps rows, ", nrow(scorecard), " scorecard rows")
  for (qs in names(meta)) {
    m <- meta[[qs]]
    tgt_str <- paste(sprintf("%s=%.2f", names(m$target_psi), m$target_psi), collapse = " ")
    alpha_str <- paste(sprintf("%s=%.3f", names(m$alphas), m$alphas), collapse = " ")
    message(sprintf("  %s: bins=[%d,%d] apps=%d", qs, m$min_bin, m$max_bin, m$n_apps))
    message(sprintf("    targets: %s", tgt_str))
    message(sprintf("    alphas:  %s", alpha_str))
  }

  # --- Phase 2: Feature generation (independent RNG stream, D17) ---
  # PSI is RNG-invariant (bin counts are deterministic, integer scores with +1L
  # boundary alignment always map back to their originating bin). Separate RNG
  # stream is defensive good practice, not a requirement.
  set.seed(seed + 1000L)
  all_features <- vector("list", length(quarters))

  for (q_idx in seq_along(quarters)) {
    quarter_start <- names(quarters)[q_idx]
    apps_df <- all_apps[[q_idx]]
    scorecard_df <- all_scorecard[[q_idx]]
    ft <- feature_targets[[quarter_start]]

    n <- nrow(apps_df)

    # Segment lookup from scorecard
    seg_map <- setNames(scorecard_df$segment, scorecard_df$user_ref_num)
    seg_for_app <- seg_map[apps_df$user_ref_num]

    # Core population: same filters as Rmd PSI pipeline
    is_core <- apps_df$client_product_cd %in% c("CC", "PLAT", "GOLD") &
               !is.na(apps_df$prim_score) &
               !is.na(seg_for_app)

    feat_matrix <- vector("list", length(feature_defs))
    names(feat_matrix) <- names(feature_defs)
    feat_alphas <- list()
    feat_min_counts <- integer(0)

    for (fname in names(feature_defs)) {
      fdef <- feature_defs[[fname]]
      if (fdef$type == "continuous") {
        vals <- rep(NA_real_, n)
        nb <- fdef$n_bins
        dw <- NULL
      } else {
        vals <- rep(NA_character_, n)
        nb <- length(fdef$dev_weights)
        dw <- fdef$dev_weights
      }

      seg_alphas <- numeric(length(segment_volumes))
      names(seg_alphas) <- names(segment_volumes)

      # Core rows: per-segment drift
      for (seg in names(segment_volumes)) {
        seg_idx <- which(is_core & seg_for_app == seg)
        N_seg <- length(seg_idx)
        if (N_seg == 0L) next

        target_csi <- ft[[seg]][fname]
        alpha <- solve_alpha(target_csi, nb, dw, fdef$tilt_dir)
        seg_alphas[seg] <- alpha
        weights <- tilt_weights(alpha * fdef$tilt_dir, nb, dw)
        counts <- deterministic_allocate(N_seg, weights)
        stopifnot(min(counts) >= 50)
        feat_min_counts <- c(feat_min_counts, min(counts))
        vals[seg_idx] <- generate_feature_values(fdef, counts)
      }

      # Non-core rows: baseline (alpha = 0)
      non_core_idx <- which(!is_core)
      if (length(non_core_idx) > 0L) {
        N_nc <- length(non_core_idx)
        if (fdef$type == "continuous") {
          w_nc <- rep(1 / fdef$n_bins, fdef$n_bins)
        } else {
          w_nc <- fdef$dev_weights
        }
        counts_nc <- deterministic_allocate(N_nc, w_nc)
        vals[non_core_idx] <- generate_feature_values(fdef, counts_nc)
      }

      feat_matrix[[fname]] <- vals
      feat_alphas[[fname]] <- seg_alphas
    }

    features_df <- data.frame(
      user_ref_num = apps_df$user_ref_num,
      feature_date = apps_df$dt_entered,
      stringsAsFactors = FALSE
    )
    for (fname in names(feat_matrix)) {
      features_df[[fname]] <- feat_matrix[[fname]]
    }
    all_features[[q_idx]] <- features_df

    # Add feature meta to existing quarter meta
    meta[[quarter_start]]$feature_alphas <- feat_alphas
    meta[[quarter_start]]$feature_min_count <- min(feat_min_counts)
    meta[[quarter_start]]$n_features <- nrow(features_df)
  }

  features <- do.call(rbind, all_features)
  rownames(features) <- NULL

  stopifnot("Duplicate user_ref_num in features" =
              !anyDuplicated(features$user_ref_num))

  # Every non-NA user_ref_num in apps has a features row
  apps_urns <- apps$user_ref_num[!is.na(apps$user_ref_num)]
  stopifnot("All apps URNs have features" =
              all(apps_urns %in% features$user_ref_num))

  message("Generated ", nrow(features), " features rows")
  for (qs in names(meta)) {
    m <- meta[[qs]]
    if (!is.null(m$feature_min_count)) {
      message(sprintf("  %s: feature min_count=%d", qs, m$feature_min_count))
    }
  }

  list(apps = apps, scorecard = scorecard, features = features, meta = meta)
}
