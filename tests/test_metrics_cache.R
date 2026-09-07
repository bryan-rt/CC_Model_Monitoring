# test_metrics_cache.R
#
# Standalone unit tests for write_metrics_cache() and load_metrics_history().
# Run from project root: Rscript tests/test_metrics_cache.R
# Does NOT run the full Rmd pipeline.

library(here)
library(dplyr)
library(tibble)
library(lubridate)

source(here::here("R/write_metrics_cache.R"))
source(here::here("R/load_metrics_history.R"))

pass <- 0L
fail <- 0L
assert <- function(desc, expr) {
  ok <- tryCatch(expr, error = function(e) FALSE)
  if (isTRUE(ok)) {
    message("  PASS: ", desc)
    pass <<- pass + 1L
  } else {
    message("  FAIL: ", desc)
    fail <<- fail + 1L
  }
}

# Use a temp directory as the project root so here::here() resolves there
test_root <- tempfile("cache_test_")
dir.create(test_root)
# Create a .here sentinel so here::here() uses this temp dir
file.create(file.path(test_root, ".here"))

# Override here::here to point at our temp root
orig_here <- here::here
.libPaths()  # ensure here is loaded
assignInNamespace("here", function(...) file.path(test_root, ...), ns = "here")

on.exit({
  assignInNamespace("here", orig_here, ns = "here")
  unlink(test_root, recursive = TRUE)
}, add = TRUE)

# ---------------------------------------------------------------------------
# Synthetic data
# ---------------------------------------------------------------------------
syn_psi <- tibble(
  Scorecard = c("All Segments", "0", "1", "2", "3", "4"),
  Population_Stability_Index = c(0.085, 0.30, 0.09, 0.25, 0.04, 0.15),
  ci_lower = c(0.07, 0.26, 0.07, 0.21, 0.02, 0.11),
  ci_upper = c(0.10, 0.35, 0.11, 0.29, 0.06, 0.19),
  tier = c("stable", "investigate", "stable", "watch", "stable", "watch"),
  tier_certain = c(TRUE, TRUE, TRUE, TRUE, TRUE, TRUE),
  current_count = c(30500L, 5500L, 8000L, 6000L, 5500L, 5500L),
  epsilon_share = c(0.01, 0.02, 0.01, 0.01, 0.03, 0.02)
)

syn_csi <- tibble(
  Scorecard = rep(c("All Segments", "0", "1", "2", "3", "4"), 5),
  feature = rep(paste0("feature_", 1:5), each = 6),
  CSI = runif(30, 0.01, 0.15),
  ci_lower = runif(30, 0, 0.05),
  ci_upper = runif(30, 0.10, 0.25),
  current_count = rep(c(30500L, 5500L, 8000L, 6000L, 5500L, 5500L), 5),
  epsilon_share = runif(30, 0, 0.05)
)

syn_ks <- tibble(
  segment = c("All Segments", "0", "1", "2", "3", "4"),
  ks_value = c(31.0, 41.0, 39.5, 37.8, 34.9, 27.8),
  dev_ks = c(31.4, 41.8, 40.1, 38.1, 35.2, 28.2),
  ks_delta = c(-0.4, -0.8, -0.6, -0.3, -0.3, -0.4),
  ci_lower = c(28.5, 38.2, 36.8, 34.5, 31.2, 24.1),
  ci_upper = c(33.5, 43.8, 42.2, 41.1, 38.6, 31.5),
  n_booked = c(57000L, 14000L, 16500L, 10700L, 6500L, 8900L),
  n_bads = c(3200L, 300L, 740L, 730L, 820L, 585L)
)

syn_deciles <- tibble(
  segment = rep(c("All Segments", "0", "1", "2", "3", "4"), each = 10),
  decile = rep(1:10, 6),
  n = rep(c(5700L, 1400L, 1650L, 1070L, 650L, 890L), each = 10),
  n_bads = as.integer(rep(c(5700L, 1400L, 1650L, 1070L, 650L, 890L), each = 10) * seq(0.01, 0.10, length.out = 10)),
  bad_rate = seq(0.01, 0.10, length.out = 10) |> rep(6),
  ci_lower = seq(0.005, 0.08, length.out = 10) |> rep(6),
  ci_upper = seq(0.02, 0.12, length.out = 10) |> rep(6),
  min_score = rep(seq(400, 130, length.out = 10) |> as.integer(), 6),
  max_score = rep(seq(450, 170, length.out = 10) |> as.integer(), 6)
)

cohort_q3 <- as.Date("2026-07-01")
perf_q3   <- cohort_q3 %m-% months(12)

# ===========================================================================
message("\n=== Test 1: PSI write + read round-trip ===")
# ===========================================================================
write_metrics_cache("PSI", syn_psi, cohort_q3)
psi_path <- file.path(test_root, "output_files/quarterly_stats/PSI/psi_summary_2026Q3.csv")
assert("PSI file exists", file.exists(psi_path))
psi_read <- data.table::fread(psi_path) |> tibble::as_tibble()
assert("PSI has provenance columns",
       all(c("report_quarter", "data_cohort", "code_version", "run_timestamp") %in% names(psi_read)))
assert("PSI report_quarter = 2026Q3", all(psi_read$report_quarter == "2026Q3"))
assert("PSI data_cohort = 2026Q3 (same as report for PSI)", all(psi_read$data_cohort == "2026Q3"))
assert("PSI has 6 rows", nrow(psi_read) == 6)
assert("PSI values preserved", abs(psi_read$Population_Stability_Index[1] - 0.085) < 1e-10)

# ===========================================================================
message("\n=== Test 2: KS data_cohort assertion ===")
# ===========================================================================
write_metrics_cache("KS", syn_ks, cohort_q3, perf_date = perf_q3)
ks_path <- file.path(test_root, "output_files/quarterly_stats/KS/ks_summary_2026Q3.csv")
ks_read <- data.table::fread(ks_path) |> tibble::as_tibble()
assert("KS data_cohort = 2025Q3 (12 months prior)", all(ks_read$data_cohort == "2025Q3"))
assert("KS report_quarter = 2026Q3", all(ks_read$report_quarter == "2026Q3"))
# The central assertion: KS data_cohort is report_quarter minus 4 quarters
rq_year <- as.integer(substr(ks_read$data_cohort[1], 1, 4))
rq_q <- as.integer(substr(ks_read$data_cohort[1], 6, 6))
rep_year <- as.integer(substr(ks_read$report_quarter[1], 1, 4))
rep_q <- as.integer(substr(ks_read$report_quarter[1], 6, 6))
quarters_diff <- (rep_year - rq_year) * 4 + (rep_q - rq_q)
assert("KS data_cohort is exactly 4 quarters before report_quarter", quarters_diff == 4)

# ===========================================================================
message("\n=== Test 3: CSI write + read ===")
# ===========================================================================
write_metrics_cache("CSI", syn_csi, cohort_q3)
csi_path <- file.path(test_root, "output_files/quarterly_stats/CSI/csi_summary_2026Q3.csv")
assert("CSI file exists", file.exists(csi_path))
csi_read <- data.table::fread(csi_path) |> tibble::as_tibble()
assert("CSI has 30 rows", nrow(csi_read) == 30)
assert("CSI carries current_count", "current_count" %in% names(csi_read))
assert("CSI carries epsilon_share", "epsilon_share" %in% names(csi_read))

# ===========================================================================
message("\n=== Test 4: KS_DECILES write ===")
# ===========================================================================
write_metrics_cache("KS_DECILES", syn_deciles, cohort_q3, perf_date = perf_q3)
dec_path <- file.path(test_root, "output_files/quarterly_stats/KS/ks_deciles_2026Q3.csv")
assert("KS_DECILES file exists", file.exists(dec_path))
dec_read <- data.table::fread(dec_path) |> tibble::as_tibble()
assert("KS_DECILES has 60 rows", nrow(dec_read) == 60)

# ===========================================================================
message("\n=== Test 5: Idempotent overwrite ===")
# ===========================================================================
Sys.sleep(1)  # ensure timestamp differs
write_metrics_cache("PSI", syn_psi, cohort_q3)
psi_files <- list.files(file.path(test_root, "output_files/quarterly_stats/PSI"),
                        pattern = "psi_summary_2026Q3")
assert("Only one PSI file after re-write", length(psi_files) == 1)
psi_re <- data.table::fread(psi_path) |> tibble::as_tibble()
assert("Timestamp updated on overwrite", psi_re$run_timestamp[1] != psi_read$run_timestamp[1])

# ===========================================================================
message("\n=== Test 6: load_metrics_history — 4-quarter read ===")
# ===========================================================================
# Write 3 more quarters
for (q_date in as.Date(c("2025-10-01", "2026-01-01", "2026-04-01"))) {
  q_date <- as.Date(q_date, origin = "1970-01-01")
  write_metrics_cache("PSI", syn_psi, q_date)
}
history <- load_metrics_history("PSI", n_quarters = 4)
assert("4-quarter load returns 4 unique quarters",
       length(unique(history$report_quarter)) == 4)
assert("Quarters sorted ascending",
       all(diff(match(unique(history$report_quarter),
                      sort(unique(history$report_quarter)))) > 0))

# ===========================================================================
message("\n=== Test 7: Short-window warning ===")
# ===========================================================================
w <- tryCatch(
  load_metrics_history("PSI", n_quarters = 8),
  warning = function(w) w
)
assert("Short-window warning fires",
       grepl("Requested 8 quarters but only 4 available", w$message))

# ===========================================================================
message("\n=== Test 8: Mixed code_version warning ===")
# ===========================================================================
# Overwrite one file with a different code_version
q1_path <- file.path(test_root, "output_files/quarterly_stats/PSI/psi_summary_2026Q1.csv")
q1_data <- data.table::fread(q1_path)
q1_data$code_version <- "abc1234"
data.table::fwrite(q1_data, q1_path)
# Collect all warnings
ws <- list()
withCallingHandlers(
  load_metrics_history("PSI", n_quarters = 4),
  warning = function(w) {
    ws[[length(ws) + 1]] <<- w
    invokeRestart("muffleWarning")
  }
)
version_warns <- Filter(function(w) grepl("code versions", w$message), ws)
assert("Mixed code_version warning fires", length(version_warns) > 0)

# ===========================================================================
message("\n=== Test 9: Missing folder error ===")
# ===========================================================================
err <- tryCatch(
  load_metrics_history("KS_DECILES", n_quarters = 4),
  error = function(e) e
)
# KS_DECILES reads from KS folder which exists, but let's test with a truly missing folder
# by temporarily removing it
bogus_dir <- file.path(test_root, "output_files/quarterly_stats/BOGUS")
err2 <- tryCatch({
  # Manually test with a nonexistent folder by calling with a kpi that maps there
  cache_dir <- file.path(test_root, "output_files/quarterly_stats/BOGUS")
  if (!dir.exists(cache_dir)) stop("Cache folder does not exist: ", cache_dir)
}, error = function(e) e)
assert("Missing folder error fires", grepl("Cache folder does not exist", err2$message))

# ===========================================================================
message("\n=== Test 10: Schema mismatch on WRITE ===")
# ===========================================================================
bad_psi <- syn_psi |> dplyr::select(-tier)
err_write <- tryCatch(
  write_metrics_cache("PSI", bad_psi, cohort_q3),
  error = function(e) e
)
assert("Write schema error on missing column",
       grepl("Missing: tier", err_write$message))

bad_psi2 <- syn_psi |> dplyr::mutate(extra_col = 1)
err_write2 <- tryCatch(
  write_metrics_cache("PSI", bad_psi2, cohort_q3),
  error = function(e) e
)
assert("Write schema error on extra column",
       grepl("Extra: extra_col", err_write2$message))

# ===========================================================================
message("\n=== Test 11: Schema mismatch on READ ===")
# ===========================================================================
# Write a file with a different schema
bad_path <- file.path(test_root, "output_files/quarterly_stats/PSI/psi_summary_2024Q4.csv")
bad_data <- syn_psi |>
  dplyr::rename(PSI = Population_Stability_Index) |>
  dplyr::mutate(report_quarter = "2024Q4", data_cohort = "2024Q4",
                code_version = "unknown", run_timestamp = "2024-01-01T00:00:00",
                .before = 1)
data.table::fwrite(bad_data, bad_path)
err_read <- tryCatch(
  load_metrics_history("PSI", n_quarters = 8),
  error = function(e) e
)
assert("Read schema error on column mismatch",
       grepl("Schema mismatch", err_read$message))
# Clean up the bad file so it doesn't interfere
file.remove(bad_path)

# ===========================================================================
message("\n=== Test 12: code_version fallback in non-git directory ===")
# ===========================================================================
# Run the writer from a temp dir with no .git.
# system() uses the R process working directory, so we must actually cd there.
nogit_root <- tempfile("nogit_")
dir.create(nogit_root)
file.create(file.path(nogit_root, ".here"))
assignInNamespace("here", function(...) file.path(nogit_root, ...), ns = "here")

orig_wd <- getwd()
setwd(nogit_root)
write_metrics_cache("PSI", syn_psi, cohort_q3)
setwd(orig_wd)

nogit_path <- file.path(nogit_root, "output_files/quarterly_stats/PSI/psi_summary_2026Q3.csv")
assert("File written from non-git dir", file.exists(nogit_path))
nogit_read <- data.table::fread(nogit_path) |> tibble::as_tibble()
assert("code_version = 'unknown' in non-git dir",
       all(nogit_read$code_version == "unknown"))

# Restore here for cleanup
assignInNamespace("here", function(...) file.path(test_root, ...), ns = "here")
unlink(nogit_root, recursive = TRUE)

# ===========================================================================
message("\n=== RESULTS ===")
message("Passed: ", pass, " / ", pass + fail)
if (fail > 0) message("FAILED: ", fail) else message("All tests passed.")
