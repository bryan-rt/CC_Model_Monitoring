# load_metrics_history.R
#
# Reads per-quarter summary CSVs from the cache and returns a single
# bind_rows'd tibble sorted by report_quarter. Warns on short windows
# and mixed code versions. Errors on schema mismatches across files.
#
# D22: cache layout, report-quarter naming.

load_metrics_history <- function(kpi, n_quarters = 4, end_quarter = NULL) {
  valid_kpis <- c("PSI", "CSI", "KS", "KS_DECILES")
  if (!kpi %in% valid_kpis) {
    stop("kpi must be one of: ", paste(valid_kpis, collapse = ", "))
  }

  folder_map <- c(PSI = "PSI", CSI = "CSI", KS = "KS", KS_DECILES = "KS")
  prefix_map <- c(PSI = "psi_summary_", CSI = "csi_summary_",
                  KS = "ks_summary_", KS_DECILES = "ks_deciles_")

  cache_dir <- here::here("output_files/quarterly_stats", folder_map[[kpi]])
  if (!dir.exists(cache_dir)) {
    stop("Cache folder does not exist: ", cache_dir)
  }

  pattern <- paste0("^", prefix_map[[kpi]], "\\d{4}Q[1-4]\\.csv$")
  files <- list.files(cache_dir, pattern = pattern, full.names = TRUE)

  if (length(files) == 0) {
    warning("No ", kpi, " cache files found in ", cache_dir)
    return(tibble::tibble())
  }

  # Read all files and validate schema consistency
  frames <- lapply(files, data.table::fread)
  col_sets <- lapply(frames, names)
  ref_cols <- col_sets[[1]]
  for (i in seq_along(col_sets)) {
    if (!identical(col_sets[[i]], ref_cols)) {
      missing <- setdiff(ref_cols, col_sets[[i]])
      extra <- setdiff(col_sets[[i]], ref_cols)
      stop("Schema mismatch in ", basename(files[[i]]), " vs ", basename(files[[1]]), ".",
           if (length(missing) > 0) paste0(" Missing: ", paste(missing, collapse = ", "), ".") else "",
           if (length(extra) > 0) paste0(" Extra: ", paste(extra, collapse = ", "), ".") else "")
    }
  }

  all_data <- dplyr::bind_rows(frames)
  # String sort on YYYYQn is correct: 2025Q4 < 2026Q1 lexicographically.
  # This holds because the year dominates and Q1-Q4 sort naturally within a year.
  all_data <- all_data |> dplyr::arrange(report_quarter)

  # Filter to window
  available_quarters <- unique(all_data$report_quarter)
  if (!is.null(end_quarter)) {
    available_quarters <- available_quarters[available_quarters <= end_quarter]
    all_data <- all_data |> dplyr::filter(report_quarter <= end_quarter)
  }

  if (length(available_quarters) > n_quarters) {
    keep <- tail(sort(available_quarters), n_quarters)
    all_data <- all_data |> dplyr::filter(report_quarter %in% keep)
  }

  actual_n <- length(unique(all_data$report_quarter))
  if (actual_n < n_quarters) {
    warning("Requested ", n_quarters, " quarters but only ",
            actual_n, " available for ", kpi)
  }

  versions <- unique(all_data$code_version)
  if (length(versions) > 1) {
    warning("Trend window spans multiple code versions: ",
            paste(versions, collapse = ", "),
            ". Metric changes may reflect code changes, not population drift.")
  }

  all_data
}
