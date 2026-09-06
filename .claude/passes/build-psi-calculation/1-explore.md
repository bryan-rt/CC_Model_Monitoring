# Pass 1: Explore — build-psi-calculation

Date: 2026-09-06

## Runtime observation of psi_raw_data

Rendered `orchestration_2.Rmd` to :232 (chunk closing fence), sourced the
extracted R, and inspected `psi_raw_data` in the live environment.

### psi_raw_data shape and columns

```
str(psi_raw_data)
tibble [39 x 4] (S3: tbl_df/tbl/data.frame)
 $ Scorecard  : chr   — "0","1","2","3","4","All Segments"
 $ counts     : int   — count of distinct user_ref_num per bin
 $ Lower_Range: num   — lower bound of the score bin (numeric, not character)
 $ Upper_Range: num   — upper bound of the score bin (numeric, not character)
```

- **39 rows** (not 120). Only bins containing >= 1 application appear.
  `group_by |> summarise` at :204/:216 emits no row for empty bins.
- **6 unique Scorecard values**: `"0", "1", "2", "3", "4", "All Segments"`.
- Lower_Range/Upper_Range are **numeric** after `separate()` + `as.numeric()`
  at :226-228. The original `all_bucket_aligned` column was character
  ("100 to 117") but it was split and cast to double.

### How bin labels are generated

`orchestration_2.Rmd:196`:
```r
labels <- paste(head(breaks, -1), tail(breaks, -1), sep = " to ")
```

Then at :226 `tidyr::separate(all_bucket_aligned, c('Lower_Range', 'Upper_Range'), sep = ' to ')`
converts these to two numeric columns. The join must therefore match on
**Scorecard + Lower_Range + Upper_Range** (all three), not on a single label string.

### segment_breaks (observed at runtime)

```
"All Segments" = c(100,117,134,151,168,185,202,219,236,253,270,287,304,321,338,355,372,389,406,423,450)
"0" = c(100,112,124,136,148,160,172,184,196,208,220,232,244,256,268,280,292,304,316,328,450)
"1" = c(100,118,136,154,172,190,208,226,244,262,280,298,316,334,352,362,372,382,392,410,450)
"2" = c(100,120,140,160,180,200,220,240,260,280,300,315,330,345,360,375,390,405,420,435,450)
"3" = c(100,125,150,170,190,210,230,250,270,290,310,325,340,355,370,385,395,405,420,435,450)
"4" = c(100,130,155,180,200,220,240,260,280,300,320,335,350,365,380,390,400,410,425,440,450)
```

Each has 21 elements → 20 bins per segment. 6 segments x 20 = 120 total bins.

### Observed All Segments bin data (17 of 20 bins populated)

Bins 134-151, 168-185, 202-219 have zero applications. With 31 apps spread
across 120 bins, 81 bins are empty — confirming the task brief's warning.

### Join design (critical)

The dev population file must have columns: `Scorecard`, `Lower_Range`,
`Upper_Range`, `counts_dev` (or similar). The join is:

```r
full_join(dev_pop, psi_raw_data, by = c("Scorecard", "Lower_Range", "Upper_Range"))
```

Must be full_join FROM the dev side (120 rows), not left_join from psi_raw_data
(39 rows). After join: `counts = coalesce(counts, 0L)`.

### Output convention

- Existing data files: `data/apps/apps_YYYYMM.txt.gz`, `data/scorecard/scorecard_YYYYMM.txt.gz`
- .gitignore: `data/**/*.txt.gz` covers subdirectories
- Dev population: `data/dev_population/dev_population.txt.gz` — matches convention, auto-gitignored

### OCR damage assessment (:240-442)

Lines 240-442 are extensively damaged. Key recognizable fragments:
- :242 `albefile <- 'Output/Quarterly_Q2_1/...'` — references old xlsx output path
- :335 `ranges_refit` — the dev population reference (what we're generating)
- :400 `full_join` — confirms original used full_join
- :412-416 — PSI formula fragments: `Percent_B`, `Percent_A`, `Proportion (B/A)`,
  `Log of Proportion`, `Population Divergence`
- :419-431 — `group_split()` + `purrr::map` for per-segment tibbles with totals row
- :434 `psi_summary` — summary object
- :441 `psi_summary` — print

The original read dev population from an xlsx file and joined on `Scorecard`,
`Lower_Range`, `Upper_Range`. Our rebuild generates the dev population
programmatically instead.

### xlsx output path

The original used `Output/Quarterly_Q2_1/...`. The `output_files/` dir is
gitignored. Line 86 creates `output_files/quarterly_stats/`. For the PSI xlsx,
use `output_files/psi_quarterly.xlsx`.

### Risks and open items

1. **Zero-bin epsilon**: With 81 empty bins, `pct_cur = 0` → `ln(0) = -Inf`.
   Need `psi_epsilon <- 0.0001` floor. This is a POLICY decision (D14).

2. **Frozen vigintile finding**: segment_breaks are hardcoded development-population
   quantile cutpoints. Uniform counts (5% per bin) is correct by construction.
   This is a FINDING to record (D15).

3. **Line count impact**: Replacing :240-442 (203 lines) with clean code will
   change line count. All anchors after :234 must be re-derived.

## Plan sketch (for Pass 2)

1. **R/build_dev_population.R**: Generate dev population reference.
   - Source `segment_breaks` from orchestration or duplicate the list (prefer
     duplicating since the Rmd defines it inside a chunk, not a standalone file).
   - For each segment: generate Lower_Range/Upper_Range from breaks, counts = 1000
     (segments 0-4) or 5000 ("All Segments").
   - Write to `data/dev_population/dev_population.txt.gz`.

2. **orchestration_2.Rmd :240-442 replacement**: ~40-50 lines of clean code.
   - Source build_dev_population.R, load dev_pop
   - full_join on Scorecard + Lower_Range + Upper_Range
   - coalesce counts, compute percentages with epsilon floor
   - PSI formula: difference, proportion, log, divergence
   - Assertions (stopifnot)
   - group_split into 6 tibbles
   - openxlsx write with 6 tabs

3. **Decisions**: D14 (epsilon policy), D15 (frozen vigintile)

4. **.gitignore**: Already covers `data/**/*.txt.gz` — no change needed.

5. **data/CATALOG.md**: Add dev_population entry.
