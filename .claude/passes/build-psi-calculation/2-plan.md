# Pass 2 — Plan: build-psi-calculation

Date: 2026-09-06  ·  Grounded in: 1-explore.md

## Objective

After this change: `R/build_dev_population.R` generates a 120-row development
population reference file. A new PSI chunk in `orchestration_2.Rmd` joins it
with `psi_raw_data`, computes PSI per segment, and writes to xlsx. The
OCR-damaged refit/KS code in the same region is commented out with a marker,
not deleted.

## Downstream inventory (:240-442 objects read after :445)

Grepped every object assigned in :240-442 for reads after :445.

| Object | Read after :445 | Line(s) | Status | Disposition |
|---|---|---|---|---|
| `ranges_refit` | Yes (as `ranges_refit_pol`) | :2074 | OCR-damaged KS section | Comment out, do not delete |
| `ranges_refit_plt` | No | — | — | Comment out with region |
| `ranges_refit3` | No | — | — | Comment out with region |
| `pol_data` | No | — | — | Comment out with region |
| `ranges` | Reassigned at :534 | :534 | CSI section overwrites | Comment out with region |
| `psi_summary` | Yes | :2461-2473 | ALL references commented out already | Safe; our rebuilt `psi_summary` replaces it |
| `psi_data` | Yes | :782-787 | OCR-damaged xlsx formatting section | Our rebuilt `psi_data` replaces it |
| `data_1`, `this_a_df_list`, `this_q_refit_list`, `albefile*`, `glue_names` | No | — | Local to the region | Comment out with region |

### Objects this task leaves broken (inherited by KS task)

| Object | Consumer | Line | What KS task must do |
|---|---|---|---|
| `ranges_refit_pol` | `dt_ks_bins_pol = ranges_refit_pol \|>` | :2074 | Reconstruct the refit-pol object from build_dev_population output or a new source |

## Changes

### `R/build_dev_population.R` (NEW)

Generates the development population reference.

- Duplicates `segment_breaks` from `orchestration_2.Rmd:179-192` (the Rmd
  defines it inside a chunk; sourcing the Rmd is not viable).
- For each segment: derive `Lower_Range` and `Upper_Range` as numeric vectors
  via `head(breaks, -1)` and `tail(breaks, -1)` directly — no label
  construction, no string splitting. All break values are integers, so float
  equality is exact; comment notes this would not hold for fractional breaks.
- Counts: 1000 per bin for segments "0"-"4", 5000 per bin for "All Segments".
  "All Segments" total (100,000) = sum of five segment totals (5 × 20,000).
- Comment documents WHY uniform: segment_breaks are frozen development-population
  vigintile cutpoints. A population binned by its own quantiles is 5% per bin
  by construction. If re-derived each run PSI would always be ~0.
- Returns a data.frame with columns: `Scorecard` (chr), `Lower_Range` (num),
  `Upper_Range` (num), `counts_dev` (int). 120 rows.
- Writes to `data/dev_population/dev_population.txt.gz` via
  `data.table::fwrite(..., scipen = 999)`, matching the existing cache
  convention. Creates `data/dev_population/` if needed.
- The function is `build_dev_population(output_path)` — takes an explicit path,
  returns the data.frame invisibly.

### `orchestration_2.Rmd` — region :240-442

The 203-line region splits into two parts:

**Part A: Refit range tables (:240-399) — COMMENT OUT**

Replace :240-399 (the xlsx reads, `ranges_refit`, `ranges_refit_plt`,
`ranges_refit3`, `pol_data` construction) with:

```r
# PENDING REBUILD — refit range tables. Originally loaded development population
# from xlsx files and constructed ranges_refit, ranges_refit_plt, ranges_refit3,
# pol_data. Consumed downstream at :2074 (ranges_refit_pol -> dt_ks_bins_pol).
# Not required for PSI; will be rebuilt in the KS task.
```

Followed by the new PSI chunk. This preserves the information about what was
here without leaving broken code that could be mistaken for live.

**Part B: PSI calculation (:400-442) — REBUILD**

New chunk (replaces the OCR-damaged PSI logic):

```r
# --- PSI Calculation ---
# Load development population reference (frozen vigintile bins, uniform counts)
source(here::here("R/build_dev_population.R"))
dev_pop <- build_dev_population(here::here("data/dev_population/dev_population.txt.gz"))

# Full join: dev side drives the 120-row frame; coalesce empty current bins to 0
psi_joined <- dplyr::full_join(
  dev_pop, psi_raw_data,
  by = c("Scorecard", "Lower_Range", "Upper_Range")
) |>
  dplyr::mutate(counts = dplyr::coalesce(counts, 0L))

# --- Assertions ---
stopifnot("Dev bins have NAs — join key mismatch" =
            sum(is.na(psi_joined$counts_dev)) == 0)
stopifnot("Expected 120 rows (6 segments x 20 bins)" =
            nrow(psi_joined) == 120)

# --- PSI formula ---
# Zero-bin policy: floor at epsilon to avoid ln(0) = -Inf.
# Flooring biases PSI upward; the alternative (dropping empty bins) understates
# drift by hiding exactly the bins where the population vanished.
psi_epsilon <- 0.0001

psi_data <- psi_joined |>
  dplyr::group_by(Scorecard) |>
  dplyr::mutate(
    percent_dev     = counts_dev / sum(counts_dev),
    percent_current = counts / sum(counts),
    percent_current = dplyr::if_else(percent_current == 0, psi_epsilon, percent_current),
    percent_dev     = dplyr::if_else(percent_dev == 0, psi_epsilon, percent_dev)
  ) |>
  dplyr::ungroup()

# Assert dev percentages are all exactly 5% (before epsilon, but epsilon only
# fires on zeros and dev has no zeros by construction)
dev_pcts <- psi_data |>
  dplyr::distinct(Scorecard, Lower_Range, .keep_all = TRUE) |>
  dplyr::pull(percent_dev)
stopifnot("Dev percentages are not all 5%" = all(dev_pcts == 0.05))

psi_data <- psi_data |>
  dplyr::mutate(
    difference  = percent_current - percent_dev,
    proportion  = percent_current / percent_dev,
    ln_proportion = log(proportion),
    population_divergence = difference * ln_proportion
  )

# Assert no Inf/NaN in population_divergence
stopifnot("Inf or NaN in population_divergence" =
            all(is.finite(psi_data$population_divergence)))

# --- Split into per-segment tibbles ---
psi_data_list <- psi_data |>
  dplyr::group_by(Scorecard) |>
  dplyr::group_split()

names(psi_data_list) <- purrr::map_chr(psi_data_list, ~ .x$Scorecard[1])

# --- PSI summary ---
psi_summary <- purrr::map_dfr(psi_data_list, function(x) {
  tibble::tibble(
    Scorecard = x$Scorecard[1],
    Population_Stability_Index = sum(x$population_divergence)
  )
})

psi_summary

# --- Write xlsx ---
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

### Column names in psi_data (for downstream consumers at :782-787)

The :782-787 region reads `psi_data[[1]]$Lower.Range` and
`psi_data[[1]]$"Population Divergence (K-L)"`. Our columns are `Lower_Range`
and `population_divergence`. That region is OCR-damaged and will need its own
rebuild — it is not in scope for this task. The `psi_data` list structure
(list of tibbles, one per segment) matches what :782 expects.

## Carrying paths verified

| Value | Produced at | Hops | Consumed at |
|---|---|---|---|
| `segment_breaks` | `orchestration_2.Rmd:179-192` | Duplicated into `R/build_dev_population.R` | `build_dev_population()` uses to derive Lower/Upper_Range |
| `Lower_Range`, `Upper_Range` (dev) | `R/build_dev_population.R` via `head(breaks,-1)`, `tail(breaks,-1)` | Returned in data.frame | `full_join` in Rmd by `Lower_Range`, `Upper_Range` |
| `Lower_Range`, `Upper_Range` (current) | `orchestration_2.Rmd:226-228` via `separate() + as.numeric()` | In `psi_raw_data` | `full_join` in Rmd |
| `Scorecard` (dev) | `R/build_dev_population.R` | Character column in data.frame | `full_join` in Rmd |
| `Scorecard` (current) | `orchestration_2.Rmd:229` via `rename(Scorecard = segment)` | In `psi_raw_data` | `full_join` in Rmd |
| `counts_dev` | `R/build_dev_population.R` | In dev_pop data.frame | PSI formula in Rmd |
| `counts` (current) | `psi_raw_data$counts` | Coalesced after join | PSI formula in Rmd |
| `psi_data` | Rmd PSI chunk | List of tibbles | :782 reads `psi_data[[1]]` (OCR-damaged, not this task's scope) |
| `psi_summary` | Rmd PSI chunk | data.frame | :2461-2473 (all commented out) |

## Blast radius

| What | Where consumed | Impact |
|---|---|---|
| `ranges_refit` (commented out) | :2074 as `ranges_refit_pol` | Already broken (OCR damage); commenting makes it explicit |
| `psi_data` (rebuilt) | :782-787 | Column names differ; :782 is OCR-damaged and not live |
| `psi_summary` (rebuilt) | :2461-2473 | All commented out; no runtime impact |

## Edge cases and how each is handled

1. **Zero-count bins (81 of 120)**: `coalesce(counts, 0L)` after join.
   `percent_current` floored at `psi_epsilon = 0.0001`. Documented in code.

2. **sum(counts) = 0 for an entire segment**: If a segment has zero
   applications, `percent_current = counts / sum(counts)` = `0/0` = `NaN`.
   With 31 apps across 5 segments this could happen. Guard:
   `sum(counts)` per segment — if zero, all bins get `psi_epsilon`.
   Handle with `dplyr::if_else(sum(counts) == 0, psi_epsilon, counts / sum(counts))`.

3. **Float equality on integer breaks**: All break values are integers (100-450).
   `head(c(100L, 117L, ...), -1)` produces exact integer vectors. Float
   equality in the join is safe. Comment documents this.

4. **"All Segments" total reconciliation**: 5 × 20,000 = 100,000; "All Segments"
   = 20 × 5,000 = 100,000. Assertion in `build_dev_population.R`.

## Discovered during planning

1. `psi_data` at :782-787 reads `psi_data[[1]]$Lower.Range` (with a dot, not
   underscore) and `$"Population Divergence (K-L)"`. This is OCR-damaged code
   in the xlsx formatting section. Our column names (`Lower_Range`,
   `population_divergence`) are correct standard names; :782 will need its own
   rebuild in a future task. This does NOT invalidate any Pass 1 finding.

2. `ranges_refit_pol` at :2074 appears only as a read, never as an assignment
   anywhere in the file. This suggests OCR damage — the original likely had an
   intermediate assignment `ranges_refit_pol <- ...` that was lost. The KS task
   inherits this.

## Unresolved

None. All design decisions are grounded in Pass 1 findings or the user's scope
correction.

## Decisions to record

**D14 — Zero-bin epsilon policy**: `psi_epsilon <- 0.0001` floors zero
percentages. Flooring biases PSI upward; dropping empty bins understates drift
by hiding bins where the population vanished. Named parameter, not inline magic
number.

**D15 — Frozen vigintile finding**: `segment_breaks` are frozen
development-population vigintile cutpoints. Uniform dev counts (5% per bin) is
correct by construction — a population binned by its own quantiles produces
equal-frequency bins. If re-derived each run, PSI would always be ~0. This
closes the "frozen or re-derived" open question.

## Definition of done

- [ ] `R/build_dev_population.R` runs and produces `data/dev_population/dev_population.txt.gz`
- [ ] Bin labels join with ZERO NAs: `stopifnot(sum(is.na(joined$counts_dev)) == 0)`
- [ ] Joined frame is 120 rows (6 segments × 20 bins): `stopifnot(nrow(...) == 120)`
- [ ] Per-segment dev percentages are all exactly 5%: `stopifnot(all(... == 0.05))`
- [ ] No Inf or NaN in population_divergence: `stopifnot(all(is.finite(...)))`
- [ ] 6 tibbles produced; xlsx written with 6 tabs
- [ ] Rmd runs clean from :1 through the new chunk
- [ ] OCR-damaged refit region commented out with PENDING REBUILD marker
- [ ] Line-count delta reported; every live citation re-derived by grep
- [ ] `decisions.md`: D14 (epsilon policy), D15 (frozen vigintile)
- [ ] `3-execute.md` with deviations section
- [ ] `data/CATALOG.md` and `R/CATALOG.md` updated
- [ ] Branch `pass3/build-psi-calculation`, committed and pushed
