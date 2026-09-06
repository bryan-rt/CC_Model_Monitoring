# Pass 2: Plan — build-csi-calculation

## Accepted requirements from review

1. **Bin index as join key** — `as.integer(cut(...))` / `as.integer(factor(...))`
   produces 1:n_bins. Dev side joins on `seq_len(n)`. Human-readable label is a
   display column only. Eliminates the formatting-risk class entirely.

2. **Split percent_dev assertion** — helper asserts `sum(percent_dev) == 1` per
   group. PSI call site keeps the tighter `all(percent_dev == 0.05)` assertion.

3. **source('R/pull_features.R') at :76** — approved. Must confirm PSI values
   unchanged after the edit, paste them, and re-derive all live citations (+1
   shift after :76).

## Implementation steps

### Step 1: Create R/compute_si.R

Extract the shared stability index kernel from the PSI chunk (:282-380).

```r
compute_stability_index <- function(joined_df, epsilon = 0.0001) {
  # Input: data.frame with Scorecard, bin_index, counts_dev, counts,
  #        plus any pass-through display columns
  # Returns: list($detail, $summary)

  # --- Formula ---
  si_data <- joined_df |>
    dplyr::group_by(Scorecard) |>
    dplyr::mutate(
      segment_total   = sum(counts),
      percent_dev     = counts_dev / sum(counts_dev),
      percent_current = dplyr::if_else(
        segment_total == 0, epsilon, counts / segment_total
      ),
      percent_current = dplyr::if_else(
        percent_current == 0, epsilon, percent_current
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

  stopifnot("Inf or NaN in Population Divergence (K-L)" =
              all(is.finite(si_data$`Population Divergence (K-L)`)))

  # Warn on epsilon-only segments
  eps_segs <- unique(si_data$Scorecard[si_data$epsilon_only])
  if (length(eps_segs) > 0) {
    warning("SI for these segments is meaningless (zero observations): ",
            paste(eps_segs, collapse = ", "))
  }

  # --- Split + Total row ---
  detail_list <- si_data |>
    dplyr::group_by(Scorecard) |>
    dplyr::group_split()
  names(detail_list) <- purrr::map_chr(detail_list, ~ .x$Scorecard[1])

  detail_list <- purrr::map(detail_list, function(tbl) {
    totals_row <- tibble::tibble(
      Scorecard                       = tbl$Scorecard[1],
      bin_index                       = NA_integer_,
      counts_dev                      = sum(tbl$counts_dev),
      counts                          = sum(tbl$counts),
      percent_dev                     = sum(tbl$percent_dev),
      percent_current                 = sum(tbl$percent_current),
      `Difference (B-A)`              = NA_real_,
      `Proportion (B/A)`              = NA_real_,
      `Log of Proportion (B/A)`       = NA_real_,
      `Population Divergence (K-L)`   = sum(tbl$`Population Divergence (K-L)`),
      epsilon_floored                 = NA,
      epsilon_only                    = tbl$epsilon_only[1]
    )
    dplyr::bind_rows(tbl, totals_row)
  })

  # --- Summary ---
  summary_df <- purrr::map_dfr(detail_list, function(x) {
    data_rows <- dplyr::filter(x, !is.na(bin_index))
    total_row <- dplyr::filter(x, is.na(bin_index))
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

  list(detail = detail_list, summary = summary_df)
}
```

**Pass-through columns**: The Total row constructor only carries the core
columns + `bin_index`. PSI has `Lower_Range`/`Upper_Range`; CSI has `bin_label`.
These display columns survive in `detail_list` elements (bind_rows fills them
with NA in the Total row), but the Total row constructor doesn't need to name
them explicitly — `bind_rows` handles mismatched columns with NA fill.

Wait — `bind_rows` WILL fill missing columns with NA, but `tibble::tibble()`
in the Total row only defines the columns listed. The display columns will get
NA automatically via `bind_rows`. This works.

### Step 2: Refactor PSI chunk to use compute_stability_index()

**Before** (lines 266-397, ~131 lines):
- :266-267 source + build dev pop
- :270-274 full_join
- :277-280 assertions (120 rows, no NA)
- :282-329 formula + assertions + warning   ← REPLACED by helper
- :331-397 split + total + summary + xlsx    ← REPLACED by helper + xlsx

**After** (~45 lines):
```r
source(here::here("R/compute_si.R"))
source(here::here("R/build_dev_population.R"))
dev_pop <- build_dev_population(here::here("data/dev_population/dev_population.txt.gz"))

# Add bin_index for join (PSI uses Lower_Range as implicit index)
dev_pop$bin_index <- ave(seq_len(nrow(dev_pop)),
                         dev_pop$Scorecard,
                         FUN = seq_along) |> as.integer()

# Full join on Scorecard + bin_index
psi_joined <- dplyr::full_join(
  dev_pop, psi_raw_data,
  by = c("Scorecard", "Lower_Range", "Upper_Range")
) |>
  dplyr::mutate(counts = dplyr::coalesce(counts, 0L))

# Assertions
stopifnot("Dev bins have NAs" = sum(is.na(psi_joined$counts_dev)) == 0)
stopifnot("Expected 120 rows" = nrow(psi_joined) == 120)

# Compute SI
psi_result <- compute_stability_index(psi_joined)

# PSI-specific: assert uniform 5% dev (not true for CSI categorical features)
dev_pcts <- psi_joined |>
  dplyr::mutate(percent_dev = counts_dev / ave(counts_dev, Scorecard, FUN = sum)) |>
  dplyr::pull(percent_dev)
stopifnot("Dev percentages are not all 5%" = all(dev_pcts == 0.05))

psi_data_list <- psi_result$detail
psi_summary <- psi_result$summary |>
  dplyr::rename(Population_Stability_Index = SI_value)
psi_summary

# xlsx
wb <- openxlsx::createWorkbook()
purrr::walk(names(psi_data_list), function(nm) {
  openxlsx::addWorksheet(wb, nm)
  openxlsx::writeDataTable(wb, nm, psi_data_list[[nm]])
})
fs::dir_create(here::here("output_files"))
openxlsx::saveWorkbook(wb,
  here::here("output_files/psi_quarterly.xlsx"),
  overwrite = TRUE)
```

**Problem**: PSI's existing join uses `Lower_Range`/`Upper_Range` (numeric
range boundaries). The helper expects `bin_index`. Two options:

A. Add `bin_index` to both sides and keep `Lower_Range`/`Upper_Range` as
   display columns. Join stays on the existing 3-key join. Helper receives
   `bin_index` column for the Total row constructor.

B. Switch PSI join to `bin_index` too.

**Choice: A.** The PSI join on Lower_Range/Upper_Range is validated and works.
Adding a `bin_index` column to both sides is safe — it's computed from
`seq_along` within each Scorecard group. The helper only needs `bin_index`
for the Total row; the join doesn't change.

Actually, re-examining: the helper's Total row uses `bin_index = NA_integer_`
as the sentinel. The PSI chunk can keep its existing join keys AND add bin_index.
The bin_index column is added after the join for the helper's benefit, not used
in the join itself.

### Step 3: Add source('R/pull_features.R') at :76

Insert one line after :77 (source('R/function_cc_scorecard_data.R')):
```r
source('R/pull_features.R')
```

This shifts all subsequent line numbers by +1.

### Step 4: Build CSI chunk (replaces :405-451 region, which is :406-452 after +1)

The CSI chunk replaces the OCR stub. Structure:

```r
# --- CSI: Feature Stability ---
source(here::here("R/feature_breaks.R"))
fs::dir_create(here::here("data/features"))

# Pull + cache (mirrors apps/scorecard pattern)
feat_paths <- fs::dir_ls("data/features")[which(basename(fs::dir_ls("data/features")) %in% c(
  glue::glue("features_{format(as.Date(cohort_date), '%Y%m')}.txt.gz"),
  glue::glue("features_{format(as.Date(cohort_date) %m+% months(1), '%Y%m')}.txt.gz"),
  glue::glue("features_{format(as.Date(cohort_date) %m+% months(2), '%Y%m')}.txt.gz")
))]

if (length(feat_paths) != 3) {
  purrr::walk(seq(cohort_date, cohort_date %m+% months(2), "month"),
              function(m) get_features_data(performance_window = m, write = TRUE))
}

# Read from cache
features <- purrr::map_dfr(seq_len(number_of_month_window), function(i) {
  data.table::fread(glue::glue(
    "data/features/features_{format(cohort_date %m+% months(i - 1), '%Y%m')}.txt.gz"
  ))
})
names(features) <- tolower(names(features))

# Join to PSI population (guarantees identical population)
csi_df <- dplyr::inner_join(
  psi_df |> dplyr::select(user_ref_num),
  features,
  by = "user_ref_num"
)

# --- Per-feature CSI ---
csi_results <- list()
csi_summary_rows <- list()

for (fname in names(feature_breaks)) {
  fb <- feature_breaks[[fname]]
  vals <- csi_df[[fname]]

  # Bin: integer index (1:n_bins)
  if (fb$type == "continuous") {
    bin_idx <- as.integer(cut(vals, breaks = fb$breaks,
                              right = TRUE, include.lowest = TRUE))
    n_bins <- length(fb$dev_counts)
    bin_labels <- paste(head(fb$breaks, -1), tail(fb$breaks, -1), sep = " to ")
  } else {
    bin_idx <- as.integer(factor(vals, levels = fb$levels))
    n_bins <- length(fb$levels)
    bin_labels <- fb$levels
  }

  # Aggregation: per segment + All Segments
  binned <- dplyr::tibble(
    user_ref_num = csi_df$user_ref_num,
    segment      = psi_df$segment[match(csi_df$user_ref_num, psi_df$user_ref_num)],
    bin_index    = bin_idx
  )

  # Wait — psi_df's segment is already numeric. Need as.character.
  # Actually: let me carry segment from psi_df directly.

  agg_by_seg <- binned |>
    dplyr::mutate(Scorecard = as.character(as.numeric(segment))) |>
    dplyr::group_by(Scorecard, bin_index) |>
    dplyr::summarise(counts = dplyr::n(), .groups = "drop")

  agg_all <- binned |>
    dplyr::mutate(Scorecard = "All Segments") |>
    dplyr::group_by(Scorecard, bin_index) |>
    dplyr::summarise(counts = dplyr::n(), .groups = "drop")

  agg <- dplyr::bind_rows(agg_all, agg_by_seg)

  # Dev reference: 6 segments x n_bins rows
  dev_ref <- dplyr::bind_rows(lapply(
    c("All Segments", as.character(0:4)),
    function(seg) {
      dplyr::tibble(
        Scorecard  = seg,
        bin_index  = seq_len(n_bins),
        counts_dev = if (seg == "All Segments") {
          as.integer(fb$dev_counts * 5L)  # 5 segments pooled
        } else {
          fb$dev_counts
        },
        bin_label  = bin_labels
      )
    }
  ))

  # Full join from dev side
  csi_joined <- dplyr::full_join(dev_ref, agg,
                                  by = c("Scorecard", "bin_index")) |>
    dplyr::mutate(counts = dplyr::coalesce(counts, 0L))

  # Assert full grid
  stopifnot(glue::glue("{fname}: expected {n_bins * 6} rows, got {nrow(csi_joined)}") =
              nrow(csi_joined) == n_bins * 6)

  # Compute stability index
  result <- compute_stability_index(csi_joined, epsilon = psi_epsilon)

  csi_results[[fname]] <- result
  csi_summary_rows[[fname]] <- result$summary |>
    dplyr::mutate(feature = fname)
}

# --- CSI summary table: 6 segments x 5 features ---
csi_summary <- dplyr::bind_rows(csi_summary_rows) |>
  dplyr::select(Scorecard, feature, CSI = SI_value, epsilon_share) |>
  tidyr::pivot_wider(names_from = feature, values_from = c(CSI, epsilon_share))

csi_summary

# --- Assert full bin grid: 30 bins x 6 segments = 180 per feature ---
for (fname in names(csi_results)) {
  fb <- feature_breaks[[fname]]
  n_bins <- if (fb$type == "continuous") length(fb$dev_counts) else length(fb$levels)
  data_rows <- sum(purrr::map_int(csi_results[[fname]]$detail, ~ sum(!is.na(.x$bin_index))))
  stopifnot(glue::glue("{fname}: expected {n_bins * 6} data rows") =
              data_rows == n_bins * 6)
}
total_bins <- sum(purrr::map_int(names(feature_breaks), function(fn) {
  fb <- feature_breaks[[fn]]
  if (fb$type == "continuous") length(fb$dev_counts) else length(fb$levels)
}))
stopifnot("Total bins should be 30" = total_bins == 30)

# --- Write xlsx: one tab per feature, segment as column ---
wb_csi <- openxlsx::createWorkbook()
purrr::walk(names(csi_results), function(fname) {
  # Combine all segments into one table for the tab
  tab_data <- dplyr::bind_rows(csi_results[[fname]]$detail)
  openxlsx::addWorksheet(wb_csi, fname)
  openxlsx::writeDataTable(wb_csi, fname, tab_data)
})
openxlsx::saveWorkbook(wb_csi,
  here::here("output_files/csi_quarterly.xlsx"),
  overwrite = TRUE)
```

### Step 5: Carry segment through properly

**Critical detail**: `csi_df` needs the segment column from `psi_df`. The
inner_join on `user_ref_num` only selects that column from `psi_df`. Must
carry segment through:

```r
csi_df <- dplyr::inner_join(
  psi_df |> dplyr::select(user_ref_num, segment),
  features,
  by = "user_ref_num"
)
```

Then `binned$segment` comes directly from `csi_df$segment`.

### Step 6: "All Segments" dev_counts

For All Segments, the dev counts should be 5x the per-segment counts because
there are 5 segments pooled (0-4). `feature_breaks` stores per-feature
dev_counts for the 10,000-applicant dev population. All Segments sums all 5
segments' dev populations. Since breaks are global (same for all segments),
dev_counts for All Segments is simply `fb$dev_counts * 5L`.

Wait — check this. The dev_counts in feature_breaks total 10,000 per feature.
That's the ENTIRE dev population. Per segment, each has 10,000/5 = 2,000
applicants? No — per D18, "All five features describe the SAME development
population of 10,000 applicants, binned five different ways."

But PSI's dev population has 20,000 per segment (1,000 per bin x 20 bins) and
100,000 for All Segments. These are notional — only percentages matter.

For CSI, the dev_counts in feature_breaks are global (10,000 total). Since
CSI's breaks are global (same for all segments), every segment uses the same
dev_counts. "All Segments" should also use the same dev_counts — the
proportions are identical. The counts are notional; what matters is
`percent_dev = counts_dev / sum(counts_dev)`, which gives the same proportions
regardless of scaling.

**Decision**: Use `fb$dev_counts` for ALL segments including "All Segments".
The proportions are identical because the breaks are global. No 5x multiplier
needed — the multiplier only matters for counts, not for percentages, and
the formula only uses percentages.

Actually, reconsidering: using the SAME dev_counts for per-segment and
All Segments is correct because the proportions are what matter. But it's
cleaner and more transparent to scale All Segments by 5 (matching PSI's
convention where All Segments has 5x the per-segment counts). Either works
because percent_dev normalizes. I'll use the same dev_counts for all to keep
it simple.

### Step 7: Self-test

After the CSI computation, add the flat-cohort self-test:

The self-test runs as part of the normal Q3 2026 execution? No — the task
brief says "Flat cohort (2025 Q4, cohort_date override) must give CSI < 1e-6."
This is a verification run, not an inline assertion. I'll run it manually
during Pass 3 execution by setting `cohort_date <- as.Date("2025-10-01")`.

But the task brief says "Assert, do not eyeball" — so I should add an inline
assertion that can be toggled. Actually, I'll add the assertion as a separate
verification block that I run during Pass 3, then remove or comment it.

Better: I'll run the full Rmd with `cohort_date <- as.Date("2025-10-01")` in
Pass 3 and assert programmatically.

### Step 8: Citation re-derivation

**+1 shift from source('R/pull_features.R') insertion at :78 (after current :77)**

| Citation | Before | After | Anchor |
|---|---|---|---|
| `# QC: Completed` | :399 | :400 | grep confirms |
| `# QC: Validated` | :453 | :454 | grep confirms |
| CSI chunk opening fence | :405 | :406 | grep confirms |
| D13 stub | :409-411 | :410-412 | grep confirms |
| source + build_dev_population | :266 | :267 | grep confirms |
| get_apps_data call | :132 | :133 | grep confirms |
| get_cc_scorecard_data call | :114 | :115 | grep confirms |
| PENDING TRANSCRIPTION | :78 | :79 | grep confirms |

**PSI chunk refactor** will change line counts further. The net delta depends
on how many lines the refactored PSI chunk saves vs how many the CSI chunk
adds. Must be re-derived by grep AFTER all edits, not predicted.

### Step 9: Documentation updates

- **CLAUDE.md**: Update frontier line numbers, add CSI description, update
  pull function contracts table, add compute_si.R
- **decisions.md**: Add D19 (CSI calculation design choices)
- **R/CATALOG.md**: Add compute_si.R entry, update pull_features.R reader
- **CATALOG.md**: Check for line number references

## Execution order

1. Create `R/compute_si.R` (helper)
2. Add `source('R/pull_features.R')` at :78
3. Add `source(here::here("R/compute_si.R"))` before PSI computation
4. Refactor PSI chunk to use `compute_stability_index()`
5. Run Rmd through PSI to confirm identical output — paste PSI values
6. Build CSI chunk (replace :406-452 after +1 shift)
7. Run Rmd through CSI — paste Q3 2026 CSI table
8. Run flat-cohort self-test (Q4 2025) — assert all < 1e-6
9. Re-derive all live citations by grep
10. Update CLAUDE.md, decisions.md, R/CATALOG.md
11. Commit, push

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| PSI output changes after refactor | Run before/after comparison, paste both |
| Total row bind_rows column mismatch | Helper uses bind_rows which fills NA for extra columns |
| bin_index for PSI | Add bin_index after existing join, don't change join keys |
| All Segments CSI residual at flat | User prediction: should be ~1e-7, not 0.01. If 0.01, per-segment binning leak |
| glue::glue in stopifnot | R 4.x stopifnot with named arguments needs literal string, not glue. Use paste0 instead |
