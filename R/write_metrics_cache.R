# write_metrics_cache.R
#
# Writes per-quarter summary CSVs to output_files/quarterly_stats/{PSI,CSI,KS}/.
# Idempotent: re-running a quarter overwrites that quarter's file.
# Provenance columns (report_quarter, data_cohort, code_version, run_timestamp)
# prepended to every row.
#
# D22: cache layout, report-quarter naming, provenance rationale.

# Expected column sets per KPI (excludes provenance columns, which are prepended)
.cache_schemas <- list(
  PSI = c("Scorecard", "Population_Stability_Index", "ci_lower", "ci_upper",
          "tier", "tier_certain", "current_count", "epsilon_share"),
  CSI = c("Scorecard", "feature", "CSI", "ci_lower", "ci_upper",
          "current_count", "epsilon_share"),
  KS  = c("segment", "ks_value", "dev_ks", "ks_delta", "ci_lower", "ci_upper",
          "n_booked", "n_bads"),
  KS_DECILES = c("segment", "decile", "n", "n_bads", "bad_rate", "ci_lower",
                 "ci_upper", "min_score", "max_score")
)

write_metrics_cache <- function(kpi, data, cohort_date, perf_date = NULL) {
  valid_kpis <- names(.cache_schemas)
  if (!kpi %in% valid_kpis) {
    stop("kpi must be one of: ", paste(valid_kpis, collapse = ", "))
  }

  # Schema validation: assert expected columns before writing

  expected <- .cache_schemas[[kpi]]
  actual <- names(data)
  missing <- setdiff(expected, actual)
  extra <- setdiff(actual, expected)
  if (length(missing) > 0 || length(extra) > 0) {
    msg <- paste0("Schema mismatch for ", kpi, ".")
    if (length(missing) > 0) msg <- paste0(msg, " Missing: ", paste(missing, collapse = ", "), ".")
    if (length(extra) > 0) msg <- paste0(msg, " Extra: ", paste(extra, collapse = ", "), ".")
    stop(msg)
  }

  report_quarter <- paste0(lubridate::year(cohort_date), "Q",
                           lubridate::quarter(cohort_date))

  if (kpi %in% c("KS", "KS_DECILES")) {
    stopifnot("perf_date required for KS/KS_DECILES" = !is.null(perf_date))
    data_cohort <- paste0(lubridate::year(perf_date), "Q",
                          lubridate::quarter(perf_date))
  } else {
    data_cohort <- report_quarter
  }

  code_version <- tryCatch({
    v <- suppressWarnings(system("git rev-parse --short HEAD", intern = TRUE))
    if (length(v) != 1 || !nzchar(v)) "unknown" else v
  }, error = function(e) "unknown", warning = function(w) "unknown")

  run_timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")

  data <- data |>
    dplyr::mutate(
      report_quarter = report_quarter,
      data_cohort    = data_cohort,
      code_version   = code_version,
      run_timestamp  = run_timestamp,
      .before = 1
    )

  folder_map <- c(PSI = "PSI", CSI = "CSI", KS = "KS", KS_DECILES = "KS")
  file_map <- c(
    PSI        = paste0("psi_summary_", report_quarter, ".csv"),
    CSI        = paste0("csi_summary_", report_quarter, ".csv"),
    KS         = paste0("ks_summary_", report_quarter, ".csv"),
    KS_DECILES = paste0("ks_deciles_", report_quarter, ".csv")
  )

  out_path <- here::here("output_files/quarterly_stats",
                         folder_map[[kpi]], file_map[[kpi]])
  fs::dir_create(dirname(out_path))
  data.table::fwrite(data, out_path)
  message("Cache: wrote ", out_path)
  invisible(out_path)
}
