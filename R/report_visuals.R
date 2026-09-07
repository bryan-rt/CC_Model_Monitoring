# report_visuals.R
#
# Visualization functions for quarterly monitoring report (D23).
# All functions take tibbles from load_metrics_history() and return
# ggplot or flextable objects. Data is sourced from the cache, not
# from in-memory pipeline objects.

library(ggplot2)
library(flextable)

# --- Constants ---
PSI_WATCH <- 0.10
PSI_INVESTIGATE <- 0.25

TIER_BG <- c(stable = "#E8F5E9", watch = "#FFF3E0", investigate = "#FFEBEE")
TIER_SYMBOL <- c(stable = "S", watch = "W", investigate = "!")

SEGMENT_ORDER <- c("0", "1", "2", "3", "4", "All Segments")

THEME_REPORT <- theme_minimal(base_size = 11) +
  theme(
    strip.text = element_text(face = "bold"),
    panel.grid.minor = element_blank()
  )

# --- 1. PSI Trend Table (flextable) ---
psi_trend_table <- function(psi_hist) {
  # Build cell text: value + tier symbol; * if tier_certain == FALSE
  tbl <- psi_hist |>
    dplyr::mutate(
      cell = sprintf("%.3f %s%s",
                     Population_Stability_Index,
                     TIER_SYMBOL[tier],
                     ifelse(tier_certain == "TRUE" | tier_certain == TRUE, "", "*"))
    ) |>
    dplyr::select(report_quarter, Scorecard, cell) |>
    tidyr::pivot_wider(names_from = Scorecard, values_from = cell)

  # Ensure column order
  col_order <- intersect(SEGMENT_ORDER, names(tbl))
  tbl <- tbl |> dplyr::select(report_quarter, dplyr::all_of(col_order))

  # Build bg color matrix
  bg_df <- psi_hist |>
    dplyr::mutate(bg = TIER_BG[tier]) |>
    dplyr::select(report_quarter, Scorecard, bg) |>
    tidyr::pivot_wider(names_from = Scorecard, values_from = bg)

  ft <- flextable(tbl) |>
    set_header_labels(report_quarter = "Quarter") |>
    align(align = "center", part = "all") |>
    autofit()

  # Apply cell backgrounds
  seg_cols <- intersect(SEGMENT_ORDER, names(tbl))
  for (col_name in seg_cols) {
    for (i in seq_len(nrow(bg_df))) {
      ft <- bg(ft, i = i, j = col_name, bg = bg_df[[col_name]][i])
    }
  }

  ft <- add_footer_lines(ft,
    "S = stable, W = watch, ! = investigate. * CI spans a threshold; tier not statistically distinguishable.")
  ft <- fontsize(ft, size = 9, part = "footer")
  ft
}

# --- 2. PSI Trend Chart (ggplot, faceted) ---
psi_trend_chart <- function(psi_hist) {
  df <- psi_hist |>
    dplyr::mutate(Scorecard = factor(Scorecard, levels = SEGMENT_ORDER))

  y_max <- max(df$ci_upper, na.rm = TRUE) * 1.1

  ggplot(df, aes(x = report_quarter, y = Population_Stability_Index, group = 1)) +
    # Threshold bands
    annotate("rect", xmin = -Inf, xmax = Inf, ymin = 0, ymax = PSI_WATCH,
             fill = "#4DAF4A", alpha = 0.08) +
    annotate("rect", xmin = -Inf, xmax = Inf, ymin = PSI_WATCH, ymax = PSI_INVESTIGATE,
             fill = "#FF7F00", alpha = 0.08) +
    annotate("rect", xmin = -Inf, xmax = Inf, ymin = PSI_INVESTIGATE, ymax = Inf,
             fill = "#E41A1C", alpha = 0.08) +
    # CI ribbon + line
    geom_ribbon(aes(ymin = ci_lower, ymax = ci_upper), alpha = 0.25, fill = "steelblue") +
    geom_line(color = "steelblue", linewidth = 0.8) +
    geom_point(color = "steelblue", size = 2) +
    facet_wrap(~Scorecard, ncol = 3) +
    labs(x = NULL, y = "PSI",
         title = "Population Stability Index — 4-Quarter Trend",
         caption = "Shaded bands: green = stable (<0.10), orange = watch (0.10\u20130.25), red = investigate (>0.25)") +
    THEME_REPORT
}

# --- 3. CSI Heatmap (ggplot) ---
csi_heatmap <- function(csi_hist, quarter) {
  df <- csi_hist |>
    dplyr::filter(report_quarter == quarter) |>
    dplyr::mutate(Scorecard = factor(Scorecard, levels = SEGMENT_ORDER))

  ggplot(df, aes(x = feature, y = Scorecard, fill = CSI)) +
    geom_tile(color = "white", linewidth = 0.5) +
    geom_text(aes(label = sprintf("%.3f", CSI)), size = 3) +
    scale_fill_gradient2(low = "white", mid = "#FFF3E0", high = "#E41A1C",
                         midpoint = 0.10, limits = c(0, NA)) +
    labs(x = NULL, y = "Segment", fill = "CSI",
         title = paste("CSI Heatmap \u2014", quarter)) +
    THEME_REPORT +
    theme(panel.grid = element_blank())
}

# --- 4. CSI Drilldown Bars (list of ggplots, conditional on PSI tier) ---
csi_drilldown_bars <- function(csi_hist, psi_hist, quarter, max_segments = 3L) {
  # Identify flagged segments in this quarter
  flagged <- psi_hist |>
    dplyr::filter(report_quarter == quarter,
                  tier %in% c("watch", "investigate"),
                  Scorecard != "All Segments") |>
    dplyr::arrange(dplyr::desc(Population_Stability_Index))

  if (nrow(flagged) == 0) return(list())

  # Cap at max_segments
  flagged <- utils::head(flagged, max_segments)

  csi_q <- csi_hist |>
    dplyr::filter(report_quarter == quarter)

  plots <- list()
  for (seg in flagged$Scorecard) {
    seg_data <- csi_q |>
      dplyr::filter(Scorecard == seg) |>
      dplyr::arrange(dplyr::desc(CSI))

    seg_psi <- flagged$Population_Stability_Index[flagged$Scorecard == seg]
    seg_tier <- flagged$tier[flagged$Scorecard == seg]

    p <- ggplot(seg_data, aes(x = reorder(feature, CSI), y = CSI)) +
      geom_col(fill = ifelse(seg_tier == "investigate", "#E41A1C", "#FF7F00"),
               alpha = 0.7) +
      geom_errorbar(aes(ymin = ci_lower, ymax = ci_upper), width = 0.2) +
      coord_flip() +
      labs(x = NULL, y = "CSI",
           title = sprintf("Segment %s \u2014 Feature CSI (PSI = %.3f, %s)",
                           seg, seg_psi, seg_tier)) +
      THEME_REPORT

    plots[[seg]] <- p
  }
  plots
}

# --- 5. KS Comparison Chart (ggplot) ---
ks_comparison_chart <- function(ks_hist) {
  df <- ks_hist |>
    dplyr::mutate(segment = factor(segment, levels = SEGMENT_ORDER))

  df_long <- dplyr::bind_rows(
    df |> dplyr::transmute(segment, KS = dev_ks, Source = "Development"),
    df |> dplyr::transmute(segment, KS = ks_value, Source = "Current",
                           ci_lower = ci_lower, ci_upper = ci_upper)
  ) |>
    dplyr::mutate(Source = factor(Source, levels = c("Development", "Current")))

  ggplot(df_long, aes(x = segment, y = KS, fill = Source)) +
    geom_col(position = position_dodge(0.7), width = 0.6, alpha = 0.8) +
    geom_errorbar(aes(ymin = ci_lower, ymax = ci_upper),
                  position = position_dodge(0.7), width = 0.2, na.rm = TRUE) +
    scale_fill_manual(values = c(Development = "#999999", Current = "steelblue")) +
    labs(x = "Segment", y = "KS Statistic",
         title = "KS Comparison: Development vs Current",
         caption = "KS evaluates Q3 2025 bookings \u2014 the most recent cohort with a closed 12-month performance window.\nCI whiskers on current bars only (development baseline is frozen).") +
    THEME_REPORT
}

# --- 6. KS Change Table (flextable) ---
ks_change_table <- function(ks_hist) {
  tbl <- ks_hist |>
    dplyr::mutate(
      segment = factor(segment, levels = SEGMENT_ORDER),
      rel_change_pct = ks_delta / dev_ks * 100,
      ci_range = sprintf("[%.1f, %.1f]", ci_lower, ci_upper)
    ) |>
    dplyr::arrange(segment) |>
    dplyr::transmute(
      Segment = as.character(segment),
      `Dev KS` = sprintf("%.1f", dev_ks),
      `Current KS` = sprintf("%.1f", ks_value),
      `Abs Change` = sprintf("%+.1f", ks_delta),
      `Rel Change (%)` = sprintf("%+.1f%%", rel_change_pct),
      `95% CI` = ci_range,
      n_booked = format(n_booked, big.mark = ","),
      n_bads = format(n_bads, big.mark = ",")
    )

  ft <- flextable(tbl) |>
    align(align = "center", part = "all") |>
    autofit()

  # Conditional formatting on relative change
  rel_vals <- ks_hist |>
    dplyr::mutate(segment = factor(segment, levels = SEGMENT_ORDER)) |>
    dplyr::arrange(segment) |>
    dplyr::pull(ks_delta) / ks_hist |>
    dplyr::mutate(segment = factor(segment, levels = SEGMENT_ORDER)) |>
    dplyr::arrange(segment) |>
    dplyr::pull(dev_ks) * 100

  for (i in seq_along(rel_vals)) {
    if (rel_vals[i] < -15) {
      ft <- bg(ft, i = i, j = "Rel Change (%)", bg = "#FFEBEE")
    } else if (rel_vals[i] < -10) {
      ft <- bg(ft, i = i, j = "Rel Change (%)", bg = "#FFF3E0")
    }
  }

  ft
}

# --- 7. Rank Order Chart (ggplot, faceted with free y) ---
rank_order_chart <- function(decile_hist, dev_decile_rates) {
  current <- decile_hist |>
    dplyr::mutate(segment = factor(segment, levels = SEGMENT_ORDER))

  dev <- dev_decile_rates |>
    dplyr::mutate(segment = factor(segment, levels = SEGMENT_ORDER)) |>
    dplyr::rename(dev_bad_rate = dev_bad_rate)

  df <- dplyr::left_join(current, dev |> dplyr::select(segment, decile, dev_bad_rate),
                         by = c("segment", "decile"))

  ggplot(df, aes(x = factor(decile))) +
    geom_col(aes(y = bad_rate), fill = "steelblue", alpha = 0.7) +
    geom_errorbar(aes(ymin = ci_lower, ymax = ci_upper), width = 0.2) +
    geom_line(aes(y = dev_bad_rate, group = 1), linetype = "dashed",
              color = "#E41A1C", linewidth = 0.7) +
    geom_point(aes(y = dev_bad_rate), color = "#E41A1C", size = 1.5, shape = 4) +
    facet_wrap(~segment, scales = "free_y", ncol = 3) +
    scale_y_continuous(labels = scales::percent_format()) +
    labs(x = "Decile (1 = lowest risk)", y = "DQ90 Bad Rate",
         title = "Rank Ordering: Current vs Development Decile Bad Rates",
         caption = "Bars = current quarter with Wilson CI whiskers. Dashed line + X = development baseline.\nWilson intervals are per-decile and independent; these are screening intervals for triage, not hypothesis tests.") +
    THEME_REPORT
}

# --- 8. Executive Summary Table (flextable) ---
executive_summary_table <- function(psi_hist, ks_hist, decile_hist, dev_decile_rates) {
  current_q <- max(psi_hist$report_quarter)

  # PSI current quarter
  psi_current <- psi_hist |>
    dplyr::filter(report_quarter == current_q) |>
    dplyr::select(Scorecard, Population_Stability_Index, tier, tier_certain)

  # KS (may be empty if no KS data)
  has_ks <- nrow(ks_hist) > 0

  # Monotonicity check from decile_hist
  mono_check <- if (nrow(decile_hist) > 0) {
    decile_hist |>
      dplyr::group_by(segment) |>
      dplyr::arrange(decile, .by_group = TRUE) |>
      dplyr::summarise(monotonic = all(diff(bad_rate) >= 0), .groups = "drop")
  } else {
    dplyr::tibble(segment = character(), monotonic = logical())
  }

  # Build summary rows
  rows <- psi_current |>
    dplyr::mutate(segment = Scorecard) |>
    dplyr::left_join(
      if (has_ks) {
        ks_hist |> dplyr::transmute(
          segment,
          ks_rel_pct = ks_delta / dev_ks * 100,
          dev_ks_fmt = sprintf("%.1f", dev_ks),
          current_ks_fmt = sprintf("%.1f", ks_value)
        )
      } else {
        dplyr::tibble(segment = character(), ks_rel_pct = numeric(),
                      dev_ks_fmt = character(), current_ks_fmt = character())
      },
      by = "segment"
    ) |>
    dplyr::left_join(mono_check, by = "segment")

  # Status logic
  rows <- rows |>
    dplyr::mutate(
      ks_rel_pct = dplyr::coalesce(ks_rel_pct, 0),
      monotonic = dplyr::coalesce(monotonic, NA),
      status = dplyr::case_when(
        tier == "investigate" | ks_rel_pct < -15 | (!is.na(monotonic) & !monotonic) ~ "Action required",
        tier == "watch" | ks_rel_pct < -10 ~ "Review",
        TRUE ~ "Stable"
      )
    )

  tbl <- rows |>
    dplyr::mutate(
      segment = factor(segment, levels = SEGMENT_ORDER)
    ) |>
    dplyr::arrange(segment) |>
    dplyr::transmute(
      Segment = as.character(segment),
      PSI = sprintf("%.3f", Population_Stability_Index),
      Tier = tier,
      `Tier Certain` = ifelse(tier_certain == "TRUE" | tier_certain == TRUE, "Yes", "No"),
      `Dev KS` = dplyr::coalesce(dev_ks_fmt, "\u2014"),
      `Current KS` = dplyr::coalesce(current_ks_fmt, "\u2014"),
      `KS Rel Change` = ifelse(is.na(dev_ks_fmt) | dev_ks_fmt == "\u2014", "\u2014",
                                sprintf("%+.1f%%", ks_rel_pct)),
      Monotonic = dplyr::case_when(
        is.na(monotonic) ~ "\u2014",
        monotonic ~ "Yes",
        TRUE ~ "No"
      ),
      Status = status
    )

  ft <- flextable(tbl) |>
    align(align = "center", part = "all") |>
    autofit()

  # Color status column
  for (i in seq_len(nrow(tbl))) {
    bg_color <- switch(tbl$Status[i],
                       "Action required" = "#FFEBEE",
                       "Review" = "#FFF3E0",
                       "#E8F5E9")
    ft <- bg(ft, i = i, j = "Status", bg = bg_color)
  }

  ft
}
