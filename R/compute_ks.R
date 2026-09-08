# compute_ks.R
#
# Shared KS computation helper used by both the Rmd KS chunk and
# R/build_ks_baseline.R. Single KS definition in the codebase.
#
# Input: data frame with score, binary outcome (0/1), segment columns.
# Returns list:
#   $ks_by_segment     — tibble: segment, ks_value (0-100), n_booked, n_bads
#   $decile_rates      — tibble: segment, decile, n, n_bads, bad_rate,
#                         min_score, max_score, cum_pct_good, cum_pct_bad,
#                         ks_at_decile
#   $min_bads_per_decile — integer

compute_ks_stats <- function(df,
                             score_col = "prim_score",
                             outcome_col = "dq90",
                             segment_col = "segment") {

  # Rename to internal names for consistency
  work <- dplyr::tibble(
    score   = df[[score_col]],
    outcome = df[[outcome_col]],
    segment = as.character(df[[segment_col]])
  )

  # Build "All Segments" by appending a copy with relabeled segment
  all_segs <- dplyr::bind_rows(
    work,
    work |> dplyr::mutate(segment = "All Segments")
  )

  # --- Per-segment KS ---
  # Convention: decile 1 = highest score = LOWEST risk. Rows are sorted
  # desc(score), then ntile() assigns group 1 to the first (highest-scoring)
  # rows. Bad rates increase with decile number.
  #
  # ntile() creates equal-SIZED groups. With integer scores (~350 distinct
  # values over ~14,000 booked rows per segment), identical scores split
  # across adjacent deciles by row order. This is a stated design choice (D20):
  # equal-sized bins are the right choice for rank-ordering because they
  # guarantee each decile has comparable statistical power. Decile boundaries
  # are NOT score boundaries — decile 4's score range may overlap decile 3
  # and 5. Score ranges (min_score, max_score) are reported per decile to
  # make tie-splitting visible.
  compute_one <- function(seg_df, seg_name) {
    n_booked <- nrow(seg_df)
    if (n_booked == 0) return(NULL)

    seg_df <- seg_df |>
      dplyr::arrange(dplyr::desc(score)) |>
      dplyr::mutate(decile = dplyr::ntile(dplyr::desc(score), 10))

    decile_stats <- seg_df |>
      dplyr::group_by(decile) |>
      dplyr::summarise(
        n         = dplyr::n(),
        n_bads    = sum(outcome),
        bad_rate  = mean(outcome),
        min_score = min(score),
        max_score = max(score),
        .groups   = "drop"
      ) |>
      dplyr::arrange(decile)

    total_goods <- sum(decile_stats$n - decile_stats$n_bads)
    total_bads  <- sum(decile_stats$n_bads)

    decile_stats <- decile_stats |>
      dplyr::mutate(
        cum_pct_good  = cumsum(n - n_bads) / total_goods,
        cum_pct_bad   = cumsum(n_bads) / total_bads,
        ks_at_decile  = abs(cum_pct_bad - cum_pct_good) * 100,
        segment       = seg_name
      )

    ks_val <- max(decile_stats$ks_at_decile)

    list(
      ks_row = dplyr::tibble(
        segment  = seg_name,
        ks_value = ks_val,
        n_booked = n_booked,
        n_bads   = total_bads
      ),
      decile_stats = decile_stats
    )
  }

  segments <- unique(all_segs$segment)
  # Order: All Segments first, then 0-4
  segments <- c("All Segments", sort(setdiff(segments, "All Segments")))

  results <- lapply(segments, function(seg) {
    compute_one(all_segs |> dplyr::filter(segment == seg), seg)
  })
  results <- results[!vapply(results, is.null, logical(1))]

  ks_by_segment <- dplyr::bind_rows(lapply(results, `[[`, "ks_row"))
  decile_rates  <- dplyr::bind_rows(lapply(results, `[[`, "decile_stats"))

  # Reorder columns
  decile_rates <- decile_rates |>
    dplyr::select(segment, decile, n, n_bads, bad_rate,
                  min_score, max_score,
                  cum_pct_good, cum_pct_bad, ks_at_decile)

  min_bads <- min(decile_rates$n_bads[decile_rates$segment != "All Segments"])

  list(
    ks_by_segment        = ks_by_segment,
    decile_rates         = decile_rates,
    min_bads_per_decile  = as.integer(min_bads)
  )
}
