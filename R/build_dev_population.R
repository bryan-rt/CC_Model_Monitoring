# build_dev_population.R
#
# Generates the development-population reference file for PSI calculation.
#
# segment_breaks are frozen development-population vigintile cutpoints (D15).
# A population binned by its own quantiles is 5% per bin by construction —
# uniform counts are correct, not an approximation. If re-derived each run,
# PSI would always be ~0 because the bins would track the current distribution.
#
# Counts: 1000 per bin for segments 0-4 (20,000 per segment), 5000 per bin for
# "All Segments" (100,000 total = sum of 5 x 20,000). These are notional;
# only the percentages (all exactly 5%) matter for PSI.

build_dev_population <- function(output_path) {

  # Duplicated from orchestration_2.Rmd:179-192. The Rmd defines these inside a
  # chunk so they cannot be sourced directly.
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

  # Build one row per bin per segment.
  # Lower_Range and Upper_Range are derived as numeric vectors directly from
  # head(breaks, -1) and tail(breaks, -1) — no label string round-trip.
  # All break values are integers, so float equality in the downstream join is
  # exact. This would NOT hold if a future break were fractional.
  rows <- lapply(names(segment_breaks), function(seg) {
    brks <- segment_breaks[[seg]]
    counts_per_bin <- if (seg == "All Segments") 5000L else 1000L
    data.frame(
      Scorecard   = seg,
      Lower_Range = head(brks, -1),
      Upper_Range = tail(brks, -1),
      counts_dev  = counts_per_bin,
      stringsAsFactors = FALSE
    )
  })
  dev_pop <- do.call(rbind, rows)

  # Reconciliation: "All Segments" total must equal sum of per-segment totals
  all_seg_total <- sum(dev_pop$counts_dev[dev_pop$Scorecard == "All Segments"])
  per_seg_total <- sum(dev_pop$counts_dev[dev_pop$Scorecard != "All Segments"])
  stopifnot("All Segments total != sum of per-segment totals" =
              all_seg_total == per_seg_total)

  # Write to disk
  fs::dir_create(dirname(output_path))
  data.table::fwrite(dev_pop, output_path, scipen = 999)

  # invisible(): return the data for callers who want it, without printing
  # 120 rows to the console/report on every run.
  invisible(dev_pop)
}
