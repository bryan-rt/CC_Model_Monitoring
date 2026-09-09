# compute_si.R
#
# Shared stability index kernel used by both PSI and CSI calculations.
# Extracted from the PSI chunk to prevent formula drift between the two.
#
# Input contract:
#   joined_df must have columns: Scorecard, counts_dev, counts
#   Plus any pass-through display columns (Lower_Range/Upper_Range for PSI,
#   bin_label for CSI). These survive in the detail output via bind_rows
#   NA-fill; the helper does not reference them.
#
# Returns: list($detail, $summary)
#   $detail  — named list of tibbles (one per Scorecard), each with a Total row
#   $summary — tibble with one row per Scorecard: SI_value, current_count,
#              epsilon_only, epsilon_share

compute_stability_index <- function(joined_df, epsilon = 0.0001) {

  # --- Formula ---
  si_data <- joined_df |>
    dplyr::group_by(Scorecard) |>
    dplyr::mutate(
      segment_total   = sum(counts),
      percent_dev     = counts_dev / sum(counts_dev),

      percent_current = dplyr::case_when(
        segment_total == 0          ~ epsilon,  # segment absent entirely
        counts / segment_total == 0 ~ epsilon,  # bin empty within a populated segment
        TRUE                        ~ counts / segment_total
      ),
      epsilon_floored = (counts == 0 & segment_total > 0),
      epsilon_only    = segment_total == 0
    ) |>
    dplyr::ungroup()

  # Assert dev proportions sum to 1 per group
  dev_sums <- si_data |>
    dplyr::group_by(Scorecard) |>
    dplyr::summarise(s = sum(percent_dev), .groups = "drop")
  stopifnot("Dev proportions do not sum to 1" =
              all(abs(dev_sums$s - 1) < 1e-10))

  si_data <- si_data |>
    dplyr::mutate(
      `Difference (B-A)`            = percent_current - percent_dev,
      `Proportion (B/A)`            = percent_current / percent_dev,
      `Log of Proportion (B/A)`     = log(`Proportion (B/A)`),
      `Population Divergence (K-L)` = `Difference (B-A)` * `Log of Proportion (B/A)`
    )

  # Should be unreachable — the epsilon floor blocks NaN/-Inf and the dev
  # reference is uniform by construction. This is a tripwire: if it fires,
  # the epsilon floor or the dev population file has broken.
  stopifnot("Inf or NaN in Population Divergence (K-L)" =
              all(is.finite(si_data$`Population Divergence (K-L)`)))

  # Warn on epsilon-only segments
  eps_segs <- unique(si_data$Scorecard[si_data$epsilon_only])
  if (length(eps_segs) > 0) {
    warning("SI for these segments is meaningless (zero observations): ",
            paste(eps_segs, collapse = ", "))
  }

  # --- Split + Total row ---
  si_list <- si_data |>
    dplyr::group_by(Scorecard) |>
    dplyr::group_split()
  names(si_list) <- purrr::map_chr(si_list, ~ .x$Scorecard[1])

  # Addition of 'Totals' row to each segment
  si_list <- purrr::map(si_list, function(tbl) {
    totals_row <- tibble::tibble(
      Scorecard                       = tbl$Scorecard[1],
      counts_dev                      = sum(tbl$counts_dev),
      counts                          = sum(tbl$counts),
      percent_dev                     = sum(tbl$percent_dev),
      percent_current                 = sum(tbl$percent_current),
      `Difference (B-A)`              = NA_real_,
      `Proportion (B/A)`              = NA_real_,
      `Log of Proportion (B/A)`       = NA_real_,
      `Population Divergence (K-L)`   = sum(tbl$`Population Divergence (K-L)`),
      epsilon_floored                 = NA,
      epsilon_only                    = all(tbl$epsilon_only)
    )
    dplyr::bind_rows(tbl, totals_row)
  })

  # --- Summary ---
  summary_df <- purrr::map_dfr(si_list, function(x) {
    data_rows <- dplyr::filter(x, !is.na(counts_dev) | !is.na(dplyr::first(x$counts_dev)))
    # Identify total row: it has NA in pass-through columns filled by bind_rows.
    # Use row count: total row is always the last row appended.
    n <- nrow(x)
    total_row <- x[n, ]
    data_rows <- x[seq_len(n - 1), ]
    total_si <- total_row$`Population Divergence (K-L)`
    eps_divergence <- sum(
      data_rows$`Population Divergence (K-L)`[data_rows$epsilon_floored],
      na.rm = TRUE
    )
    tibble::tibble(
      Scorecard       = total_row$Scorecard,
      SI_value        = total_si,
      current_count   = total_row$counts,
      epsilon_only    = total_row$epsilon_only,
      epsilon_share   = dplyr::if_else(
        total_si > 0, eps_divergence / total_si, 0
      )
    )
  })

  list(detail = si_list, summary = summary_df)
}
