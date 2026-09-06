# Pass 2 — Plan: sample-data-generator

Date: 2026-09-06

## Corrections from Pass 1 review

1. **Alphas were wrong.** The proposed alphas (0/0.15/0.30/0.50) produce PSI
   0.00/0.008/0.034/0.098 — all in the stable band. The strongest barely
   reaches 0.098, never crossing an action line. PSI 0.30 requires alpha ~0.814.

2. **Volume increase required.** alpha 0.814 gives min weight 0.0095. At the
   original 2,500 apps/segment, the thinnest bin gets ~24 — below the 50 floor.
   Resolution: raise volumes so `N * min_weight >= 50`.

3. **Solve for alpha, do not hardcode.** PSI is a deterministic function of
   alpha given flat dev weights. Bisect for alpha from `target_psi`.

4. **Deterministic allocation.** Multinomial draw makes realized minimums vary
   ~±7, causing intermittent assertion failures. Use `round(N * w_i)` with
   remainder distributed to largest-fractional-part bins.

## Revised volumes (post-filter)

| Segment | Apps/quarter | Per bin (flat) | Min bin at alpha 0.814 |
|---|---|---|---|
| 0 | 5,500 | 275 | ~52 |
| 1 | 8,000 | 400 | ~76 |
| 2 | 6,000 | 300 | ~57 |
| 3 | 5,500 | 275 | ~52 |
| 4 | 5,500 | 275 | ~52 |
| **Total** | **30,500** | — | — |

Top bins at alpha 0.814 reach ~1,000. Above the 500 guideline — accepted. The
floor protects the statistic; the ceiling was cosmetic.

Noise on top (~16% ≈ 4,880 extra apps rows):
- ~8% SEC/MSC: 2,440
- ~4% NULL prim_score: 1,220
- ~4% no scorecard match: 1,220
- ~0.16% NULL segment: ~50

Total per quarter: ~35,380 apps, ~34,160 scorecard.
Across 4 quarters: ~141,500 apps, ~136,600 scorecard.

## Revised drift schedule

| Quarter | Target PSI | Alpha (solved) | Band |
|---|---|---|---|
| 2025 Q4 | 0.00 | 0.000 | stable |
| 2026 Q1 | 0.06 | ~0.396 | stable |
| 2026 Q2 | 0.13 | ~0.570 | monitor |
| 2026 Q3 | 0.30 | ~0.814 | investigate |

Alpha is solved at runtime via bisection. Values above are approximate targets;
the generator reports exact achieved PSI.

## Implementation steps

### Step 1: R/generate_cohort.R (NEW)

The generator. ~200 lines. Returns a list of two data.frames (apps, scorecard)
ready for `DBI::dbAppendTable()`.

#### 1a. Helper: `psi_from_alpha(alpha, n_bins = 20)`

Computes theoretical PSI for a linear tilt against flat 1/20 dev weights:

```r
psi_from_alpha <- function(alpha, n_bins = 20) {
  i <- seq_len(n_bins)
  w <- (1 + alpha * (n_bins + 1 - 2 * i) / (n_bins - 1)) / n_bins
  p_dev <- 1 / n_bins
  sum((w - p_dev) * log(w / p_dev))
}
```

This is the exact PSI for the per-segment case (20 bins, flat dev = 0.05).
"All Segments" PSI is an aggregate view of the same population through
different breaks and is not targeted independently.

#### 1b. Helper: `solve_alpha(target_psi, n_bins = 20, tol = 1e-6)`

Bisection on `psi_from_alpha`. Search range [0, 0.99] (alpha = 1 puts zero
weight on the last bin). ~20 iterations for tol = 1e-6. Returns alpha.

Special case: `target_psi == 0` returns alpha = 0 immediately.

#### 1c. Helper: `tilt_weights(alpha, n_bins = 20)`

```r
tilt_weights <- function(alpha, n_bins = 20) {
  i <- seq_len(n_bins)
  (1 + alpha * (n_bins + 1 - 2 * i) / (n_bins - 1)) / n_bins
}
```

Returns a vector of length 20 summing to 1. Monotonically decreasing:
w_1 > w_2 > ... > w_20 (more mass in low-score bins).

#### 1d. Helper: `deterministic_allocate(N, weights)`

```r
deterministic_allocate <- function(N, weights) {
  raw <- N * weights
  counts <- floor(raw)
  remainder <- N - sum(counts)
  if (remainder > 0) {
    fracs <- raw - counts
    top_idx <- order(fracs, decreasing = TRUE)[seq_len(remainder)]
    counts[top_idx] <- counts[top_idx] + 1L
  }
  counts
}
```

Guarantees `sum(counts) == N` and each count is as close to `N * w_i` as
possible. No randomness — fully deterministic and reproducible.

#### 1e. Main: `generate_cohort(quarters, seed = 42)`

Parameters:
- `quarters`: a named list where names are quarter start dates (as strings
  "YYYY-MM-DD") and values are target_psi. Example:
  ```r
  list("2025-10-01" = 0.00, "2026-01-01" = 0.06,
       "2026-04-01" = 0.13, "2026-07-01" = 0.30)
  ```
- `seed`: RNG seed for the random components (dates, filler columns).

Algorithm per quarter:

```
1. alpha <- solve_alpha(target_psi)
2. weights <- tilt_weights(alpha)
3. For each segment in 0:4:
   a. N <- segment_volumes[segment]  # 5500/8000/6000/5500/5500
   b. bin_counts <- deterministic_allocate(N, weights)
   c. Assert min(bin_counts) >= 50
   d. For each bin i in 1:20:
      - Generate bin_counts[i] rows:
        * prim_score <- runif(bin_counts[i],
            segment_breaks[[seg]][i], segment_breaks[[seg]][i+1])
        * Round prim_score to integer (scores are whole numbers in the seed data)
        * segment <- seg (as character)
      - Accumulate into a combined data.frame
4. Assign user_ref_num: sequential 14-digit from offset
5. Assign app_num: sequential integer from offset
6. Distribute rows across 3 months (roughly equal thirds, random day within month)
7. Fill remaining columns (filler — not load-bearing for PSI):
   - client_product_cd: 'CC' for core rows (with ~5% 'PLAT', ~2% 'GOLD')
   - decision, applied, strategy_version, etc. (weighted random draws)
8. Generate noise rows:
   - SEC/MSC rows: 2,440 with valid scores/segments (filtered by product code)
   - NULL prim_score rows: 1,220 with scorecard match (filtered by is.na)
   - No-match rows: 1,220 apps with no scorecard row (filtered by has_segment)
   - NULL segment rows: ~50 with scorecard match but NULL segment
9. Split into apps_df and scorecard_df:
   - apps_df: all rows (core + noise), with prim_score, no segment
   - scorecard_df: rows that have a scorecard match, with segment, no prim_score
10. Return list(apps = apps_df, scorecard = scorecard_df, meta = ...)
```

The `meta` component reports: alpha, theoretical PSI, bin counts min/max per
segment, total rows.

**ID offset strategy**: Each quarter gets a contiguous block.
- Quarter 1 (Q4 2025): user_ref_num 20000000000001+, app_num 100001+, sq_num 500001+
- Quarter 2 (Q1 2026): offset by max rows per quarter (~36,000)
- Quarter 3, 4: continue sequential

This guarantees global uniqueness across all quarters and non-collision with
the minimal seed range.

**segment_breaks**: Duplicated from `orchestration_2.Rmd:179-192` and
`R/build_dev_population.R:18-31`. This is the third copy. The breaks are
frozen (D15) and load-bearing. A comment documents the duplication and
references both sources.

#### 1f. Self-test function: `self_test_flat_psi()`

Runs the full pipeline for Q4 2025 (alpha=0) through a temporary Rmd render
or equivalent R evaluation. Too complex for the generator itself. Instead,
the self-test is run in Pass 3 execution by:
1. Loading Q4 2025 data
2. Running the Rmd with `cohort_date <- as.Date("2025-10-01")`
3. Asserting PSI < 0.05 for all segments in `psi_summary`

The generator itself asserts:
- `min(bin_counts) >= 50` for each segment/quarter
- `sum(bin_counts) == N` for each segment
- No NA in prim_score for core rows
- All prim_score in [100, 450] for core rows
- `user_ref_num` globally unique

### Step 2: R/setup_supabase.R (MODIFY)

Add `mode` parameter:

```r
setup_supabase <- function(mode = c("minimal", "generated")) {
  mode <- match.arg(mode)
  conn <- db_connect()
  on.exit(DBI::dbDisconnect(conn))

  # Always: DROP + CREATE from schema
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS applications CASCADE")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS scorecard CASCADE")
  execute_sql_file(conn, here::here("sql/01_create_tables.sql"))

  if (mode == "minimal") {
    execute_sql_file(conn, here::here("sql/02_seed_minimal.sql"))
    message("Setup complete: minimal seed loaded.")
  } else {
    source(here::here("R/generate_cohort.R"))
    result <- generate_cohort(
      quarters = list(
        "2025-10-01" = 0.00,
        "2026-01-01" = 0.06,
        "2026-04-01" = 0.13,
        "2026-07-01" = 0.30
      )
    )
    DBI::dbAppendTable(conn, "applications", result$apps)
    DBI::dbAppendTable(conn, "scorecard", result$scorecard)
    message("Setup complete: generated cohorts loaded (",
            nrow(result$apps), " apps, ",
            nrow(result$scorecard), " scorecard rows).")
  }
}
```

`execute_sql_file` stays as the existing private helper (unchanged).
`sql/02_seed_minimal.sql` is KEPT AS IS — fast-reset path for debugging.

### Step 3: orchestration_2.Rmd:65 — cohort_date override (MODIFY)

Change:
```r
cohort_date <- lubridate::floor_date(Sys.Date(), "quarter")
```
To:
```r
if (!exists("cohort_date")) {
  cohort_date <- lubridate::floor_date(Sys.Date(), "quarter")
}
```

This is a 1-line semantic change. The demo works by setting `cohort_date`
before sourcing/knitting. The `if (!exists(...))` pattern is the standard R
idiom for "override if pre-set, default otherwise."

**Line count impact**: +2 lines (the `if` and closing `}`). This shifts all
downstream line citations by +2. Re-derivation required per evidence discipline.

### Step 4: orchestration_2.Rmd PSI chunk — epsilon_share (MODIFY)

#### 4a. Add `epsilon_floored` flag to `psi_data` (at :295, after second percent_current)

Insert after line 295 (`percent_current = dplyr::if_else(percent_current == 0, psi_epsilon, percent_current),`):
```r
    # Flag individual bins that were epsilon-floored (had zero counts)
    epsilon_floored = (counts == 0 & segment_total > 0),
```

#### 4b. Add `epsilon_floored` to `psi_data_list` select (at :328-331)

Add `epsilon_floored` to the select list (after `epsilon_only`).

#### 4c. Add `epsilon_floored` to Total row (at :339-352)

Add to `totals_row`:
```r
    epsilon_floored                 = NA  # not meaningful for Total row
```

#### 4d. Compute `epsilon_share` in `psi_summary` (at :357-365)

Replace psi_summary computation:
```r
psi_summary <- purrr::map_dfr(psi_data_list, function(x) {
  data_rows <- dplyr::filter(x, !is.na(Lower_Range))
  total_row <- dplyr::filter(x, is.na(Lower_Range))
  total_psi <- total_row$`Population Divergence (K-L)`
  eps_divergence <- sum(
    data_rows$`Population Divergence (K-L)`[data_rows$epsilon_floored],
    na.rm = TRUE
  )
  tibble::tibble(
    Scorecard                   = total_row$Scorecard,
    Population_Stability_Index  = total_psi,
    current_count               = total_row$counts,
    epsilon_only                = total_row$epsilon_only,
    epsilon_share               = dplyr::if_else(
      total_psi > 0, eps_divergence / total_psi, 0
    )
  )
})
```

`epsilon_share` is the fraction of each segment's PSI that comes from
epsilon-floored bins (bins where `counts == 0` was replaced by the epsilon
floor). At the target volumes, this should be ~0 because few or no bins will
be empty.

**Line count impact**: ~+6 lines from epsilon_share additions. Combined with
step 3's +2, total delta is ~+8 lines.

### Step 5: Documentation updates

#### 5a. D16 in `.claude/docs/decisions.md`

| D16 | 2026-09-06 | Drift schedule: volumes raised to 30,500/quarter (from 14,500) to support alpha 0.814 for PSI 0.30. Alpha solved via bisection, not hardcoded. Allocation deterministic (round + remainder), not multinomial. Top bins may exceed 500; accepted — floor protects the statistic, ceiling was cosmetic. | Decided | PSI is a deterministic function of alpha; hardcoded alphas were wrong (all landed in stable band). The 50-count floor and PSI 0.30 target conflict at lower volumes. | `R/generate_cohort.R`, `R/setup_supabase.R` |

#### 5b. CLAUDE.md updates

- Add `generate_cohort.R` to completed list
- Add `R/generate_cohort.R` to pull function contracts table
- Update Supabase tables section (row counts after generation)
- Note `cohort_date` override pattern

#### 5c. R/CATALOG.md

Add entry for `generate_cohort.R`:
| `generate_cohort.R` | CREATED | Parameterized cohort generator (4 quarters, drift via tilt weights, D6/D16) | `generate_cohort(quarters, seed)` | `R/setup_supabase.R` (mode="generated") |

#### 5d. Line citation re-derivation

The Rmd changes add ~8 lines. All live citations shift by +8. Before/after
table to be computed in Pass 3 after final line count is confirmed.

Affected citations (from CLAUDE.md, decisions.md, R/CATALOG.md):
- `# QC: Validated` — currently :385, will become :393
- `# QC: Completed` — currently :234, unchanged (above edit region)
- CSI chunk fence — currently :391, will become :399
- D13 stub — currently :395-397, will become :403-405
- `source("R/build_dev_population.R")` — currently :263, will shift
- `build_dev_population()` call — currently :264, will shift
- `get_cc_scorecard_data` call — currently :110, unchanged
- `get_apps_data` call — currently :128, unchanged
- cohort_date line — currently :65, becomes :65-67

## Execution order

1. Create `R/generate_cohort.R` with all helpers + main function
2. Modify `R/setup_supabase.R` — add `mode` parameter
3. Modify `orchestration_2.Rmd:65` — `cohort_date` override
4. Modify `orchestration_2.Rmd` PSI chunk — `epsilon_floored` + `epsilon_share`
5. Run `setup_supabase(mode = "generated")` — load all 4 quarters
6. Run Rmd for each quarter (override `cohort_date`), capture PSI tables
7. Assert: Q4 2025 PSI < 0.05 for all segments
8. Assert: no per-segment bin below 50
9. Report actual PSI per quarter per segment + epsilon_share
10. Update CLAUDE.md, decisions.md, R/CATALOG.md
11. Re-derive line citations
12. Write 3-execute.md

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| `prim_score` rounding to integer creates ties at bin boundaries | `cut(..., include.lowest = TRUE, right = TRUE)` in the Rmd means the right endpoint is included. Generate `runif(min, max)` where min/max are the break values; `cut` handles boundary assignment. Verify no off-by-one. |
| "All Segments" PSI diverges from per-segment targets | "All Segments" uses different breaks than per-segment. Alpha is solved for the per-segment formula. All Segments PSI is an aggregate view — report it, don't target it. |
| `dbAppendTable` type coercion | The schema uses VARCHAR(14) for `user_ref_num`. R's `character` type maps cleanly. `prim_score` as R numeric maps to Postgres NUMERIC. Test with a small batch first. |
| Line citation drift compounds | Compute final delta from `wc -l` before/after. Re-derive ALL live citations from grep, not arithmetic. |
