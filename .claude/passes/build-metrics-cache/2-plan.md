# Pass 2: Plan — build-metrics-cache

Date: 2026-09-07

## Execution constraint

Do NOT run orchestration_2.Rmd end to end. Unit-test cache functions against
small synthetic data frames constructed in R scripts. The user performs the
four-quarter backfill manually in RStudio.

## Pre-execution fixes from Pass 1 review

### Fix 1: n_booked collision at the join site (:719-723)

**Problem**: `dplyr::inner_join(ks_result$ks_by_segment, ks_baseline$ks, by = "segment")`
produces `n_booked.x` / `n_booked.y` because both frames have `n_booked`.
This shows in the display at :726 and in the xlsx at :791 — a defect visible
to readers.

**Fix**: Add `suffix = c("", "_dev")` to the inner_join call at :719.
This produces `n_booked` (current) and `n_booked_dev` (baseline).

**Downstream verification**: grep confirms no code references `n_booked` by
name after the join in the Rmd. `ks_comparison` is displayed (:726, :767),
joined to bootstrap CI (:761-765, which joins on `segment`), and written to
xlsx (:791). None select `n_booked` explicitly. Safe to rename.

The ks_baseline.R column `n_booked` becomes `n_booked_dev` via the suffix.
No file changes needed to ks_baseline.R itself.

### Fix 2: Enrich CSI cache with epsilon_share and current_count

**Source**: `csi_summary_long` (:499) has: Scorecard, SI_value, current_count,
epsilon_only, epsilon_share, feature.

**Plan**: The cache write joins `csi_ci` (30 rows: Scorecard, feature,
estimate, ci_lower, ci_upper, B) with `csi_summary_long` on
(Scorecard, feature) to pick up current_count and epsilon_share.

### Record: perf_date derivation

`perf_date <- cohort_date %m-% months(12)` at orchestration_2.Rmd:616.
This is the SOLE source of the KS data cohort. The data_cohort column in
KS summary CSVs will be derived as:
`paste0(lubridate::year(perf_date), "Q", lubridate::quarter(perf_date))`.
The assertion in the unit test will verify this equals report_quarter minus
4 quarters.

## Implementation plan

### Step 1: Create branch

```
git checkout -b pass3/build-metrics-cache
```

### Step 2: Fix n_booked collision (orchestration_2.Rmd:719-723)

Change:
```r
ks_comparison <- dplyr::inner_join(
  ks_result$ks_by_segment,
  ks_baseline$ks,
  by = "segment"
) |>
```

To:
```r
ks_comparison <- dplyr::inner_join(
  ks_result$ks_by_segment,
  ks_baseline$ks,
  by = "segment",
  suffix = c("", "_dev")
) |>
```

No line count change (adds parameter to existing call).

### Step 3: Extend dir_create (orchestration_2.Rmd:92)

Change:
```r
fs::dir_create(c('output_files', 'output_files/quarterly_stats'))
```

To:
```r
fs::dir_create(c('output_files', 'output_files/quarterly_stats',
                 'output_files/quarterly_stats/PSI',
                 'output_files/quarterly_stats/CSI',
                 'output_files/quarterly_stats/KS'))
```

+2 lines.

### Step 4: Enhance cohort_date comment (orchestration_2.Rmd:65-69)

Change:
```r
# cohort_date: override by setting before knitting; defaults to current quarter
# cohort_date <- as.Date('2026-04-01')
```

To:
```r
# --- COHORT DATE ---
# Override: uncomment and set to the quarter start date before running.
# Available quarters (generated data): 2025Q4, 2026Q1, 2026Q2, 2026Q3
# cohort_date <- as.Date('2026-07-01')
```

+2 lines. Net offset so far: +4 from :92 onward, +2 from :65 onward.

### Step 5: Create R/write_metrics_cache.R

Single function: `write_metrics_cache(kpi, data, cohort_date, perf_date = NULL)`

```r
write_metrics_cache <- function(kpi, data, cohort_date, perf_date = NULL) {
  # kpi: "PSI", "CSI", "KS", "KS_DECILES"
  # data: the summary data frame (psi_summary, enriched csi_ci, ks_comparison, decile_rates)
  # cohort_date: Date — report quarter
  # perf_date: Date — KS data cohort (required for KS/KS_DECILES, NULL for PSI/CSI)

  report_quarter <- paste0(lubridate::year(cohort_date), "Q",
                           lubridate::quarter(cohort_date))

  if (kpi %in% c("KS", "KS_DECILES")) {
    stopifnot(!is.null(perf_date))
    data_cohort <- paste0(lubridate::year(perf_date), "Q",
                          lubridate::quarter(perf_date))
  } else {
    data_cohort <- report_quarter
  }

  code_version <- tryCatch(
    system("git rev-parse --short HEAD", intern = TRUE),
    error = function(e) "unknown"
  )
  run_timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")

  # Add provenance columns (prepend)
  data <- data |>
    dplyr::mutate(
      report_quarter = report_quarter,
      data_cohort    = data_cohort,
      code_version   = code_version,
      run_timestamp  = run_timestamp,
      .before = 1
    )

  # File path
  folder_map <- c(PSI = "PSI", CSI = "CSI", KS = "KS", KS_DECILES = "KS")
  file_map <- c(
    PSI = paste0("psi_summary_", report_quarter, ".csv"),
    CSI = paste0("csi_summary_", report_quarter, ".csv"),
    KS  = paste0("ks_summary_", report_quarter, ".csv"),
    KS_DECILES = paste0("ks_deciles_", report_quarter, ".csv")
  )

  out_path <- here::here("output_files/quarterly_stats",
                          folder_map[[kpi]], file_map[[kpi]])
  data.table::fwrite(data, out_path)
  message("Cache: wrote ", out_path)
  invisible(out_path)
}
```

### Step 6: Create R/load_metrics_history.R

```r
load_metrics_history <- function(kpi, n_quarters = 4, end_quarter = NULL) {
  # kpi: "PSI" | "CSI" | "KS" | "KS_DECILES"
  # Returns: tibble of bind_rows'd CSVs, sorted by report_quarter

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

  # Find all matching CSVs
  pattern <- paste0("^", prefix_map[[kpi]], "\\d{4}Q[1-4]\\.csv$")
  files <- list.files(cache_dir, pattern = pattern, full.names = TRUE)

  if (length(files) == 0) {
    warning("No ", kpi, " cache files found in ", cache_dir)
    return(tibble::tibble())
  }

  all_data <- purrr::map_dfr(files, data.table::fread)
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

  # Version warning
  versions <- unique(all_data$code_version)
  if (length(versions) > 1) {
    warning("Trend window spans multiple code versions: ",
            paste(versions, collapse = ", "),
            ". Metric changes may reflect code changes, not population drift.")
  }

  all_data
}
```

### Step 7: Add cache writes to orchestration_2.Rmd

**After PSI xlsx write (current :380, becomes ~:386 after Steps 3-4)**:

```r
source(here::here("R/write_metrics_cache.R"))
write_metrics_cache("PSI", psi_summary, cohort_date)
```

Note: source once, reuse for CSI and KS. The source at the PSI site makes
it available for subsequent chunks. Actually, each chunk is independent in
Rmd execution — source must be in the same chunk or a prior chunk. Since
the PSI chunk is first, sourcing there covers CSI and KS chunks.

**After CSI xlsx write (current :598, shifts to ~:608)**:

```r
csi_cache <- csi_ci |>
  dplyr::rename(CSI = estimate) |>
  dplyr::select(-B) |>
  dplyr::left_join(
    csi_summary_long |> dplyr::select(Scorecard, feature, current_count, epsilon_share),
    by = c("Scorecard", "feature")
  )
write_metrics_cache("CSI", csi_cache, cohort_date)
```

**After KS xlsx write (current :795, shifts to ~:811)**:

```r
ks_cache <- ks_comparison |>
  dplyr::select(segment, ks_value, dev_ks, ks_delta, ci_lower, ci_upper, n_booked, n_bads)
write_metrics_cache("KS", ks_cache, cohort_date, perf_date = perf_date)
decile_cache <- ks_result$decile_rates |>
  dplyr::select(segment, decile, n, n_bads, bad_rate, ci_lower, ci_upper, min_score, max_score)
write_metrics_cache("KS_DECILES", decile_cache, cohort_date, perf_date = perf_date)
```

### Step 8: Unit tests (synthetic data, not full pipeline)

Create `tests/test_metrics_cache.R` — a standalone script (not testthat)
that sources the two new R files and exercises them:

1. **write + read round-trip**: Create synthetic psi_summary (6 rows),
   write via write_metrics_cache, read back, verify columns and values.

2. **data_cohort assertion**: For cohort_date = 2026-07-01:
   - PSI data_cohort must equal "2026Q3"
   - KS data_cohort must equal "2025Q3" (perf_date = 2025-07-01)
   - Assert KS data_cohort is report_quarter minus 4 quarters.

3. **Idempotent overwrite**: Write twice with different run_timestamp,
   verify only one file exists and it contains the second timestamp.

4. **load_metrics_history 4-quarter read**: Write 4 synthetic CSVs
   (2025Q4 through 2026Q3), load, verify 4 quarters returned in order.

5. **Short-window warning**: Request 4 quarters when only 2 exist.
   Capture warning, verify message.

6. **Mixed code_version warning**: Write files with different code_version
   values, load, capture warning, verify message.

7. **Missing folder error**: Request KPI with nonexistent folder, verify stop().

### Step 9: Update documentation

- **CLAUDE.md**: Add no-end-to-end-runs execution constraint, D22 reference,
  new file paths, update validated frontier line numbers.
- **decisions.md**: Add D22 (cache layout, report-quarter naming, provenance).
- **R/CATALOG.md**: Add write_metrics_cache.R, load_metrics_history.R.
- **CATALOG.md**: Update validated frontier if line number changes.

### Step 10: Line-count re-derivation

After all edits, grep for every anchor pattern in CLAUDE.md, decisions.md,
R/CATALOG.md and report before/after table.

Changes that shift line numbers:
- Step 4 (cohort_date comment): +2 lines at :65 → everything from :67 onward shifts +2
- Step 3 (dir_create): +2 lines at :92 (now :94) → everything from :94 onward shifts +4
- Step 7 PSI cache: +2 lines after :380 (now :384) → shifts +6 from there
- Step 7 CSI cache: +6 lines after :598 (now :604) → shifts +12 from there
- Step 7 KS cache: +5 lines after :795 (now :807) → shifts +17 from there
- Step 2 (n_booked suffix): +1 line at :719 (now :723) → shifts +18 from there

Wait — let me recount. The suffix addition fits on the existing line group
(adds `,` + newline + `suffix = c("", "_dev")`). That's +1 line.

**Precise delta accounting**:

| Step | Location (original) | Lines added | Cumulative offset at that point |
|---|---|---|---|
| Step 4 | :65-66 | +2 | +2 |
| Step 3 | :92 | +2 | +4 |
| Step 7a (PSI source+write) | after :380 | +2 | +6 |
| Step 7b (CSI cache+write) | after :598 | +6 | +12 |
| Step 2 (n_booked suffix) | :719 | +1 | +13 |
| Step 7c (KS cache+write) | after :795 | +5 | +18 |

Final line count: 800 + 18 = 818.

**Anchor shift table** (to be verified by grep in Pass 3):

| Anchor | Original | New | Notes |
|---|---|---|---|
| cohort_date default | :67-68 | :69-70 | After comment expansion |
| dir_create | :92 | :96 | After comment + dir expansion |
| source(compute_si.R) | :268 | :272 | +4 |
| PSI bootstrap | :318 | :322 | +4 |
| PSI xlsx write | :378 | :382 | +4 |
| CSI chunk fence | :390 | :396 | +6 (after PSI cache write) |
| CSI bootstrap | :506 | :512 | +6 |
| CSI xlsx write | :596 | :602 | +6 |
| KS chunk fence | :610 | :622 | +12 (after CSI cache write) |
| perf_date | :616 | :628 | +12 |
| source(compute_ks.R) | :612 | :624 | +12 |
| ks_comparison join | :719 | :731 | +12 |
| KS bootstrap | :728 | :741 | +13 (after n_booked fix) |
| Wilson CI | :770 | :783 | +13 |
| KS xlsx write | :793 | :806 | +13 |
| QC: Completed | :798 | :816 | +18 (after KS cache write) |
| QC: Validated | :800 | :818 | +18 |

## File manifest

| File | Action | Lines |
|---|---|---|
| `R/write_metrics_cache.R` | CREATE | ~45 |
| `R/load_metrics_history.R` | CREATE | ~55 |
| `tests/test_metrics_cache.R` | CREATE | ~120 |
| `orchestration_2.Rmd` | EDIT | +18 lines (6 edits) |
| `CLAUDE.md` | EDIT | Update anchors, add constraint + D22 ref |
| `.claude/docs/decisions.md` | EDIT | Add D22 |
| `R/CATALOG.md` | EDIT | Add 2 entries |
| `CATALOG.md` | EDIT | Update frontier line if changed |

## Risks and mitigations

1. **Cannot verify computed values**: Cache writes are wrappers around existing
   objects. Values pass through unchanged. The unit test verifies the MECHANISM
   (write, read, provenance, warnings) not the CONTENT.

2. **Anchor drift**: 18-line delta with 17+ anchors to update. Will use grep
   to verify every anchor mechanically in Pass 3.

3. **source() ordering in Rmd**: `write_metrics_cache.R` is sourced in the PSI
   chunk. CSI and KS chunks execute after PSI, so the function is available.
   If a user runs only the KS chunk in isolation, the source won't have fired.
   This matches the existing pattern (compute_si.R sourced in PSI, used in CSI).

## Handoff items (for 3-execute.md)

The user must:
1. Run orchestration_2.Rmd once per quarter (cohort_date set) to populate cache
2. Available quarters for backfill: 2025Q4, 2026Q1, 2026Q2, 2026Q3
3. After backfill, call `load_metrics_history("PSI")` etc. to verify 4-quarter read
