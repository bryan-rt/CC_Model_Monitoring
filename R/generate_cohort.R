# generate_cohort.R
#
# Parameterized cohort generator for PSI demonstration (D6, D16).
# Produces four quarters of applications + scorecard data with controlled
# drift via bin-weight tilting. Alpha is solved from target_psi via bisection.
# Bin counts are deterministic (round + remainder); scores are random within bins.
#
# Coupling: prim_score (applications) and segment (scorecard) are generated
# from the same draw, then split across two tables joined on user_ref_num.
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

# --- Theoretical PSI for linear tilt against flat dev ---
psi_from_alpha <- function(alpha, n_bins = 20L) {
  if (alpha == 0) return(0)
  i <- seq_len(n_bins)
  w <- (1 + alpha * (n_bins + 1 - 2 * i) / (n_bins - 1)) / n_bins
  p_dev <- 1 / n_bins
  sum((w - p_dev) * log(w / p_dev))
}

# --- Bisect for alpha given target PSI ---
solve_alpha <- function(target_psi, n_bins = 20L, tol = 1e-6) {
  if (target_psi == 0) return(0)
  lo <- 0
  hi <- 0.99
  for (iter in seq_len(100)) {
    mid <- (lo + hi) / 2
    psi_mid <- psi_from_alpha(mid, n_bins)
    if (abs(psi_mid - target_psi) < tol) return(mid)
    if (psi_mid < target_psi) lo <- mid else hi <- mid
  }
  mid
}

# --- Linear tilt weight vector ---
tilt_weights <- function(alpha, n_bins = 20L) {
  i <- seq_len(n_bins)
  (1 + alpha * (n_bins + 1 - 2 * i) / (n_bins - 1)) / n_bins
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
generate_cohort <- function(
  quarters = list(
    "2025-10-01" = c("0" = 0.00, "1" = 0.00, "2" = 0.00, "3" = 0.00, "4" = 0.00),
    "2026-01-01" = c("0" = 0.08, "1" = 0.03, "2" = 0.05, "3" = 0.02, "4" = 0.04),
    "2026-04-01" = c("0" = 0.18, "1" = 0.05, "2" = 0.12, "3" = 0.03, "4" = 0.08),
    "2026-07-01" = c("0" = 0.30, "1" = 0.09, "2" = 0.25, "3" = 0.04, "4" = 0.15)
  ),
  seed = 42L
) {
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

  list(apps = apps, scorecard = scorecard, meta = meta)
}
