# Pass 3 — Execute: build-psi-calculation

Date: 2026-09-06  ·  Branch: pass3/build-psi-calculation

## What was implemented

### `R/build_dev_population.R` (NEW)

Generates the 120-row development population reference. Duplicates
`segment_breaks` from `orchestration_2.Rmd:179-192`. Derives `Lower_Range` and
`Upper_Range` as numeric vectors via `head(breaks, -1)` / `tail(breaks, -1)`
directly — no label string round-trip. Counts: 1000/bin for segments 0-4,
5000/bin for All Segments. Writes to `data/dev_population/dev_population.txt.gz`.

### `orchestration_2.Rmd` — region :236-442 replaced

**:236-260 (was :240-399)**: PENDING REBUILD comment block documenting the
refit range tables region. Includes explicit downstream status for each
commented-out object:
- `ranges_refit_pol` at :2014 (was :2074) — genuine orphan, KS task inherits
- `ranges` — reassigned at :504/:528/:540 before any post-:385 read, costs nothing
- `ranges_refit_plt`, `ranges_refit3`, `pol_data` — zero reads after :385, dead objects

**:261-382 (was :400-442)**: Rebuilt PSI chunk with:
- `source("R/build_dev_population.R")` + `build_dev_population()` call
- `full_join` from dev side (120 rows), `coalesce(counts, 0L)`
- Epsilon floor `psi_epsilon <- 0.0001` (D14)
- `epsilon_only` flag column + `warning()` for zero-application segments
- Column names matching downstream consumer at :782: `Population Divergence (K-L)`,
  `Difference (B-A)`, `Proportion (B/A)`, `Log of Proportion (B/A)`
- Total row appended to each tibble via `purrr::map` + `bind_rows`
- 5 `stopifnot` assertions (join NAs, row count, dev pcts, finite divergence)
- `psi_summary` with `current_count` and `epsilon_only` columns
- `openxlsx` write to `output_files/psi_quarterly.xlsx`, 6 tabs
- Comment documenting `Lower_Range` → `Lower.Range` `make.names()` transformation
  as a known downstream concern

## Deviations from spec

1. **Column names**: Spec used `difference`, `proportion`, `ln_proportion`,
   `population_divergence`. Changed to `Difference (B-A)`, `Proportion (B/A)`,
   `Log of Proportion (B/A)`, `Population Divergence (K-L)` per user's
   addition 2 — these are load-bearing for the downstream xlsx formatter at
   :782-787.

2. **Total row**: Added per user's addition 2 — :782 reads
   `psi_data[[1]]$Lower.Range == "Total"`. Total row has `Lower_Range = NA_real_`
   (not `"Total"` string) because the column is numeric. The downstream
   formatter uses `Lower.Range` (make.names'd) which will be character after
   xlsx round-trip. Documented as a known concern.

3. **`segment_total` column**: Added as intermediate for the zero-segment guard
   (user addition 3). Also drives `epsilon_only` flag. Retained in output for
   transparency.

4. **`epsilon_only` column and warning**: Per user addition 3, segments with
   zero applications are flagged rather than silently computed. No segments
   triggered on this run (all 6 have >= 4 applications).

5. **Downstream inventory clarifications**: Per user addition 1, the PENDING
   REBUILD comment now explicitly states:
   - `ranges` is NOT orphaned (reassigned before any post-:385 read)
   - `ranges_refit_plt` and `ranges_refit3` are dead (zero reads after :385)
   - Inheritance list is exactly ONE item: `ranges_refit_pol` at :2014

## Verification

### Render

```
rmarkdown::render("temp_psi_test.Rmd", ..., quiet = TRUE)
# RENDER SUCCESS — no errors, no warnings except lubridate version
```

### PSI summary (6 values)

```
  Scorecard    Population_Stability_Index current_count epsilon_only
  0                                  8.74             4 FALSE
  1                                  4.41            10 FALSE
  2                                  5.75             6 FALSE
  3                                  6.52             7 FALSE
  4                                  6.25             4 FALSE
  All Segments                       1.13            31 FALSE
```

PSI values are large (all > 1.0) because 31 applications across 120 bins means
most bins are empty and hit the epsilon floor. This validates the MECHANISM;
meaningful PSI requires the sample data generator (D6).

### Assertions passed

- `sum(is.na(psi_joined$counts_dev)) == 0` — PASS
- `nrow(psi_joined) == 120` — PASS (120 rows)
- `all(dev_pcts == 0.05)` — PASS
- `all(is.finite(psi_data$"Population Divergence (K-L)"))` — PASS
- `all_seg_total == per_seg_total` (in build_dev_population.R) — PASS (100,000 = 100,000)

### Per-segment current counts

```
  Scorecard    current_total
  0                        4
  1                       10
  2                        6
  3                        7
  4                        4
  All Segments            31
```

No zero-application segments on this seed data. The epsilon_only guard is
untested at runtime but is structurally correct (if_else on sum == 0).

### Output files

- `data/dev_population/dev_population.txt.gz` — EXISTS (gitignored by `data/**/*.txt.gz`)
- `output_files/psi_quarterly.xlsx` — EXISTS (gitignored by `output_files/`)
- xlsx has 6 tabs: 0, 1, 2, 3, 4, All Segments
- Each tab has 21 rows (20 bins + Total row)

## Untested

- `epsilon_only = TRUE` path — no segment has zero applications in current seed.
  Structurally correct but not exercised at runtime.
- xlsx round-trip: the downstream formatter at :722 (was :782) reads psi_data
  back from the xlsx. Column names after `make.names()`: `Lower.Range`,
  `Population.Divergence..K.L.`. This transformation is documented but not
  tested (the formatter is OCR-damaged and not in scope).

## Adjacent text reconciled

| File | What changed |
|---|---|
| `CLAUDE.md` | Line count 2669→2610. Validated frontier :236→:385. CSI anchors :452→:391, :456-458→:395-397. Decisions D1-D13→D1-D15. Added `build-psi-calculation` to completed list. |
| `.claude/docs/decisions.md` | D13 anchors updated (:452→:391, :456-458→:395-397). D14 (epsilon policy) and D15 (frozen vigintile) added. |
| `R/CATALOG.md` | Validated frontier :236→:385. Added `build_dev_population.R` entry. |
| `data/CATALOG.md` | Added `data/dev_population/` entry. |

## Line-count delta and citation re-derivation

Before: 2670 lines. After: 2610 lines. Delta: **-60 lines**.

| Citation | Before | After | Verified by |
|---|---|---|---|
| `# QC: Completed` | :234 | :234 | `grep -n` (unchanged) |
| `# QC: Validated` | :445 | :385 | `grep -n` |
| CSI chunk opening fence | :452 | :391 | `grep -n` |
| D13 stub | :456-458 | :395-397 | `grep -n` |
| `get_cc_scorecard_data` call | :112 | :110 | `grep -n` |
| `get_apps_data` call | :130 | :128 | `grep -n` |
| `source("R/build_dev_population.R")` | — (new) | :263 | `grep -n` |
| `build_dev_population()` call | — (new) | :264 | `grep -n` |
| `ranges_refit_pol` read | :2074 | :2014 | `grep -n` |
| `psi_data` reads | :782-787 | :722-727 | `grep -n` |
| `psi_summary` reads (commented) | :2461-2473 | :2401-2413 | `grep -n` |
