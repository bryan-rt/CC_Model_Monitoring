# Pass 2: Plan — build-performance-table-and-ks

Date: 2026-09-06

## Corrections from Pass 1 review

1. **Finding 2 corrected**: PSI/CSI are RNG-invariant (D17, verified
   empirically). Bin counts come from `deterministic_allocate()` (no
   randomness); integer scores with +1L boundary alignment map back to their
   originating bin under any RNG stream. CSI uses the same allocation. Adding a
   5th quarter shifts the RNG stream but cannot change PSI/CSI values. The
   `set.seed(seed + 2000L)` approach is retained for structural invariance —
   making the guarantee architectural rather than argued — not because it is
   required.

2. **Per-segment approval for ALL quarters**: The flat 60/20/5/5/10 decision
   split at `generate_cohort.R:360-364` applies uniformly across segments.
   Approval is NOT in the PSI/CSI filter chain (`client_product_cd`,
   `prim_score`, `has_segment`), so changing it everywhere cannot perturb those
   metrics. Applying per-segment rates only to Q3 2025 would leave Q3 2026
   carrying a flat 60% for no defensible reason.

   Fix `applied`: currently `ifelse(decision == "Approve", 1L, 0L)`, which
   conflates "applied for credit" with "approved". Everyone in an application
   table applied. Set `applied = 1L` for all rows + comment.

## Prediction: All Segments KS

All Segments KS will NOT be a weighted average of the five segment KSs.
Pooling populations with different bad rates and different score-to-risk
slopes blurs the ranking. Expect All Segments KS BELOW most per-segment
values — same pattern as All Segments PSI sitting under the segment maximum.
Compute, report, and do not treat a low value as a defect.

## Actual line anchors (verified against current Rmd)

CLAUDE.md cites `:487 = # QC: Validated` and `:327 = # QC: Completed`.
Verified actual positions:
- `:486` = `# QC: Completed`
- `:490` = `# QC: Validated`
- `:485` = `## KS and DQ90 Rank Ordering`
- `:335` = CSI chunk opening `\`\`\`{r}` (CLAUDE.md says :335, matches except
  the actual fence is at :334)
- `:267` = `source(here::here("R/compute_si.R"))` — matches CLAUDE.md

These discrepancies are from the last Rmd cleanup commit. The execute phase
will re-derive all citations after line-count changes.

---

## Execution plan

### Phase 0: Branch

Create branch `pass3/build-performance-table-and-ks` from main.

### Phase 1: Generator changes (R/generate_cohort.R)

#### 1a. Per-segment approval rates (all quarters)

Replace the uniform decision sampling at `:360-365` with segment-aware
approval. Define at module level (next to `segment_volumes`):

```r
# Per-segment approval rates (D20)
approval_rates <- c("0" = 0.85, "1" = 0.70, "2" = 0.60, "3" = 0.40, "4" = 0.55)
```

In the per-quarter loop, after `all_rows` is assembled and shuffled (:341+):
- For rows with known segment: look up `approval_rates[segment]`
- For rows with NA segment (noise rows): use blended rate (0.626)
- Generate decision: Approve with probability = rate; remaining probability
  split among Decline (53%), Void (13%), Withdraw (13%), Pending (21%) —
  preserving relative ratios of the non-Approve outcomes from the original
  20/5/5/10 split
- Fix `applied = 1L` for all rows (everyone applied for credit)
- Comment explaining the semantics

#### 1b. Bad-rate logistic solver

Add at module level (after `generate_feature_values`):

```r
# solve_logistic_params(scores, target_br, target_ks, bump_fn = NULL)
# Returns list(a, b, achieved_br, achieved_ks)
#
# P(dq90=1 | score) = logistic(a + b*score) [+ bump_fn(score)]
# b < 0 (higher score = lower risk)
#
# Outer bisection on b; inner bisection on a to hit target_br.
# KS = max|cum%bad - cum%good| on score-sorted population, reported 0-100.
```

The solver:
1. Bisects on `b` in `[-0.05, -0.001]`
2. For each `b`, bisects on `a` such that `mean(P_i) = target_br`
3. Computes KS for the resulting probabilities
4. Converges when `|KS - target_ks| < 0.5` (within 0.5 KS points)

The bump function for segment 0 current:
```r
# Gaussian bump: h * exp(-((score - mu)^2) / (2 * sigma^2))
# mu = center of deciles 4-6 score range for segment 0
# h, sigma tuned to break monotonicity in deciles 4-6 without
# changing overall bad rate by more than 0.1pp
```

The bump adds extra bad-rate probability in a localized score band,
breaking the logistic's inherent monotonicity. This requires a separate
solve: first find (a, b) WITHOUT bump to get baseline, then overlay the
bump and re-solve a to maintain the target bad rate.

#### 1c. Mature quarter (Q3 2025)

Append after the existing 4-quarter loop (after `:450`, before Phase 2
features at `:472`), guarded by `set.seed(seed + 2000L)`:

- Quarter start: `"2025-07-01"`
- Volume: `segment_volumes * 3L` → (16500, 24000, 18000, 16500, 16500)
  = 91,500 core apps
- PSI target: `c("0"=0, "1"=0, "2"=0, "3"=0, "4"=0)` (flat, pre-drift)
- Same noise-row generation (proportional to core)
- Per-segment approval rates (from 1a)
- Same ID/date generation pattern

For APPROVED rows only, generate dq90:
- Compute per-segment logistic parameters via `solve_logistic_params()`
- Target bad rates and KS per the brief's "story" profile:

  | Seg | Target BR | Target KS | Notes |
  |-----|-----------|-----------|-------|
  | 0   | 2.1%      | ~33       | Degraded + bump (deciles 4-6 non-monotonic) |
  | 1   | 4.7%      | ~39       | Near dev (within ~2 of 40) |
  | 2   | 6.4%      | ~37       | Near dev (within ~2 of 38) |
  | 3   | 12.4%     | ~34       | Near dev (within ~2 of 35) |
  | 4   | 6.7%      | ~25       | Mild decline from 28 |

- Draw `dq90 ~ Bernoulli(P_i)` for each approved row
- Collect into performance data frame: `user_ref_num, origination_date, dq90`

Append mature quarter apps to `all_apps`, scorecard to `all_scorecard`.
Return performance as `$performance` in the result list.

The mature quarter's features are NOT needed (KS uses score, not features).
Skip feature generation for Q3 2025 (it is not in the `quarters` list that
drives Phase 2 features).

#### 1d. Development cohort

After the mature quarter, with `set.seed(seed + 3000L)`:

Generate a development cohort using the SAME mechanisms:
- Same volume (91,500 core, 3x)
- Same score distribution (alpha=0, flat)
- Same approval rates
- DEV logistic parameters (no bump, target dev KS):

  | Seg | Target BR | Target KS |
  |-----|-----------|-----------|
  | 0   | 2.0%      | 42        |
  | 1   | 4.5%      | 40        |
  | 2   | 7.0%      | 38        |
  | 3   | 12.0%     | 35        |
  | 4   | 6.5%      | 28        |

- Pure logistic (no bump) → monotonic deciles guaranteed
- Return as `$dev_cohort` in the result: data frame with
  `user_ref_num, prim_score, segment, dq90`

The dev cohort is NOT inserted into any database table — it exists only
to produce the frozen baseline via `build_ks_baseline.R`.

### Phase 2: SQL + pull function + setup

#### 2a. sql/04_create_performance_table.sql

```sql
CREATE TABLE performance (
  user_ref_num     VARCHAR(14) PRIMARY KEY,
  origination_date DATE        NOT NULL,
  dq90             INTEGER     NOT NULL
);
```

#### 2b. R/pull_performance.R

Mirror `R/pull_apps.R` exactly:
- `source(here::here("R/db.R"))`
- Type annotation block
- `get_performance_data(performance_window, write = TRUE)`
- `floor_date`/`ceiling_date` on `origination_date`
- `on.exit(DBI::dbDisconnect(conn))`
- `fwrite` to `data/dq_12_mos/dq_12_mos_YYYYMM.txt.gz`
- `scipen = 999, append = FALSE`

#### 2c. R/setup_supabase.R

Add to the setup flow:
- `DBI::dbExecute(conn, "DROP TABLE IF EXISTS performance CASCADE")`
- `execute_sql_file(conn, here::here("sql/04_create_performance_table.sql"))`
- In generated mode: `DBI::dbAppendTable(conn, "performance", result$performance)`
- Update message to include performance row count

### Phase 3: KS computation helper + baseline

#### 3a. R/compute_ks.R

Shared helper used by both `build_ks_baseline.R` and the Rmd:

```r
# compute_ks_stats(df, score_col = "prim_score", outcome_col = "dq90",
#                  segment_col = "segment")
#
# Input: data frame with score, binary outcome (0/1), segment columns.
# Returns list:
#   $ks_by_segment — tibble: segment, ks_value (0-100), n_booked, n_bads
#   $decile_rates  — tibble: segment, decile (1-10), n, n_bads, bad_rate,
#                    cum_pct_good, cum_pct_bad, ks_at_decile
#   $min_bads_per_decile — integer
```

The function:
1. For each segment (including "All Segments"):
   - Sort by score descending (riskiest first)
   - Assign deciles via `ntile(desc(score), 10)` — decile 1 = highest risk
   - Per decile: count goods, count bads, bad rate
   - Cumulative: `cum_pct_good = cumsum(goods) / total_goods`
   - Cumulative: `cum_pct_bad = cumsum(bads) / total_bads`
   - KS at each decile = `|cum_pct_bad - cum_pct_good| * 100`
   - KS = max of KS_at_decile values

CRITICAL comment at the binning call: KS deciles are RE-DERIVED from the
booked cohort, NOT frozen. This is the OPPOSITE of PSI/CSI and correctly
so: PSI asks whether the population moved relative to development, KS
asks whether the score still separates within THIS population.

#### 3b. R/build_ks_baseline.R

Bootstrap script (analogous to `R/build_feature_breaks.R`):
1. Sources `R/generate_cohort.R` and `R/compute_ks.R`
2. Calls `generate_cohort()` to get `$dev_cohort`
3. Runs `compute_ks_stats()` on the dev cohort
4. Writes `R/ks_baseline.R` as literal R source:

```r
# R/ks_baseline.R — frozen development baseline for KS comparison (D20)
# Generated by R/build_ks_baseline.R. DO NOT edit manually.
ks_baseline <- list(
  ks = tibble::tibble(
    segment  = c("All Segments", "0", "1", "2", "3", "4"),
    dev_ks   = c(...),  # computed values
    dev_br   = c(...)   # computed bad rates
  ),
  decile_rates = tibble::tibble(
    segment = ..., decile = ..., dev_bad_rate = ..., dev_n = ...
  )
)
```

5. Validates: asserts monotonic decile bad rates for all segments, asserts
   dev KS within 1.5 of targets, asserts min bads per decile >= 28.

#### 3c. R/ks_baseline.R

Output of 3b. Committed to repo. Literal R source — diffable, greppable,
per D18 convention.

### Phase 4: Rmd changes (orchestration_2.Rmd)

#### 4a. Source addition (current :78)

Insert after `source('R/pull_features.R')`:
```r
source('R/pull_performance.R')
```
This shifts all subsequent lines by +1.

#### 4b. Folder init (current :90, becomes :91 after 4a)

Replace:
```r
fs::dir_create(c('data', 'data/apps', 'data/scorecard', 'data/dq_24_mos', 'data/ks_driver_w_perf', 'data/performance_24'))
```
With:
```r
fs::dir_create(c('data', 'data/apps', 'data/scorecard', 'data/features', 'data/dq_12_mos'))
```

Removes: `data/dq_24_mos`, `data/ks_driver_w_perf`, `data/performance_24`
Adds: `data/features` (was missing), `data/dq_12_mos` (renamed from dq_24_mos)

#### 4c. KS chunk (replaces :487-489, between markers)

Replace the free-text notes at :487-489 with a code chunk. The chunk:

```
Performance-based metrics use a DIFFERENT cohort than PSI/CSI. PSI/CSI
evaluate Q3 2026 through-the-door applications (current quarter input
distribution). KS and DQ90 rank ordering evaluate Q3 2025 BOOKED
applications whose 12-month outcome window has now closed. The lag is
inherent to outcome monitoring: performance evidence is always 12 months
behind the input distribution that PSI measures.

```{r}
# --- KS and DQ90 Rank Ordering ---
source(here::here("R/compute_ks.R"))
source(here::here("R/ks_baseline.R"))

# Performance cohort: 12 months prior to current quarter
perf_date <- cohort_date %m-% months(12)

# Pull + cache performance data (3 months, mirrors apps pattern at :103)
perf_paths <- fs::dir_ls("data/dq_12_mos")[which(
  basename(fs::dir_ls("data/dq_12_mos")) %in% c(
    glue::glue("dq_12_mos_{format(perf_date, '%Y%m')}.txt.gz"),
    glue::glue("dq_12_mos_{format(perf_date %m+% months(1), '%Y%m')}.txt.gz"),
    glue::glue("dq_12_mos_{format(perf_date %m+% months(2), '%Y%m')}.txt.gz")
  )
)]

if (length(perf_paths) != 3) {
  purrr::walk(seq(perf_date, perf_date %m+% months(2), "month"),
              function(m) get_performance_data(performance_window = m, write = TRUE))
}

perf <- purrr::map_dfr(seq_len(number_of_month_window), function(i) {
  data.table::fread(glue::glue(
    "data/dq_12_mos/dq_12_mos_{format(perf_date %m+% months(i - 1), '%Y%m')}.txt.gz"
  ))
})
names(perf) <- tolower(names(perf))

# Pull Q3 2025 apps + scorecard for score and segment
perf_apps_paths <- fs::dir_ls("data/apps")[which(
  basename(fs::dir_ls("data/apps")) %in% c(
    glue::glue("apps_{format(perf_date, '%Y%m')}.txt.gz"),
    glue::glue("apps_{format(perf_date %m+% months(1), '%Y%m')}.txt.gz"),
    glue::glue("apps_{format(perf_date %m+% months(2), '%Y%m')}.txt.gz")
  )
)]

if (length(perf_apps_paths) != 3) {
  purrr::walk(seq(perf_date, perf_date %m+% months(2), "month"),
              function(m) get_apps_data(performance_window = m, write = TRUE))
}

perf_apps <- purrr::map_dfr(seq_len(number_of_month_window), function(i) {
  data.table::fread(glue::glue(
    "data/apps/apps_{format(perf_date %m+% months(i - 1), '%Y%m')}.txt.gz"
  ))
})
names(perf_apps) <- tolower(names(perf_apps))

perf_sc_paths <- fs::dir_ls("data/scorecard")[which(
  basename(fs::dir_ls("data/scorecard")) %in% c(
    glue::glue("scorecard_{format(perf_date, '%Y%m')}.txt.gz"),
    glue::glue("scorecard_{format(perf_date %m+% months(1), '%Y%m')}.txt.gz"),
    glue::glue("scorecard_{format(perf_date %m+% months(2), '%Y%m')}.txt.gz")
  )
)]

if (length(perf_sc_paths) != 3) {
  purrr::walk(seq(perf_date, perf_date %m+% months(2), "month"),
              function(m) get_cc_scorecard_data(performance_window = m, write = TRUE))
}

perf_sc <- purrr::map_dfr(seq_len(number_of_month_window), function(i) {
  data.table::fread(glue::glue(
    "data/scorecard/scorecard_{format(perf_date %m+% months(i - 1), '%Y%m')}.txt.gz"
  ))
})
names(perf_sc) <- tolower(names(perf_sc))

# Join: performance -> apps -> scorecard
ks_df <- perf |>
  dplyr::mutate(user_ref_num = as.numeric(user_ref_num)) |>
  dplyr::inner_join(
    perf_apps |> dplyr::mutate(user_ref_num = as.numeric(user_ref_num)) |>
      dplyr::select(user_ref_num, prim_score, decision),
    by = "user_ref_num"
  ) |>
  dplyr::inner_join(
    perf_sc |> dplyr::mutate(user_ref_num = as.numeric(user_ref_num)) |>
      dplyr::select(user_ref_num, segment),
    by = "user_ref_num"
  )

# Assert: all performance rows are approved (table-level constraint)
stopifnot("Performance rows with non-Approve decision" =
            all(ks_df$decision == "Approve"))

# Compute KS and decile bad rates (shared helper)
ks_result <- compute_ks_stats(ks_df)

# --- Assertions ---
# Monotonicity: decile bad rates should increase with decile number
# (decile 1 = highest score = lowest risk)
for (seg in c("1", "2", "3", "4")) {
  seg_rates <- ks_result$decile_rates |>
    dplyr::filter(segment == seg) |>
    dplyr::arrange(decile)
  diffs <- diff(seg_rates$bad_rate)
  stopifnot(paste0("Seg ", seg, ": decile bad rates not monotonic") =
              all(diffs >= 0))
}

# Segment 0: monotonicity break in deciles 4-6
seg0_rates <- ks_result$decile_rates |>
  dplyr::filter(segment == "0") |>
  dplyr::arrange(decile)
seg0_diffs <- diff(seg0_rates$bad_rate)
# At least one negative diff in the decile 4-6 range (indices 4-5 in diff)
stopifnot("Seg 0: expected monotonicity break in deciles 4-6" =
            any(seg0_diffs[4:5] < 0))

# Min bads per decile
stopifnot("Minimum bads per decile < 28" =
            ks_result$min_bads_per_decile >= 28)

# --- Compare to development baseline ---
ks_comparison <- dplyr::inner_join(
  ks_result$ks_by_segment,
  ks_baseline$ks,
  by = "segment"
)

ks_comparison

# --- Cache ---
openxlsx::write.xlsx(
  list(ks_comparison = ks_comparison,
       decile_rates = ks_result$decile_rates),
  here::here("output_files/ks_quarterly.xlsx"),
  overwrite = TRUE
)
```
```

The `# QC: Completed` marker moves to after the closing fence.
The `# QC: Validated` marker stays at the end.

### Phase 5: Filesystem cleanup

- Remove empty directory `data/performance_24/` (rmdir, not rm -rf)
- Rename `data/dq_24_mos/` to `data/dq_12_mos/` (both empty, so create new + remove old)
- Keep `data/ks_driver_w_perf/` — remove via rmdir (empty, unused)

### Phase 6: Documentation

#### 6a. D20 in decisions.md

**D20**: Performance table and KS/DQ90 rank ordering. Performance table
(`performance`) holds approved applications only — user_ref_num PK,
origination_date, dq90 (0/1). KS uses a 12-month-lagged cohort (Q3 2025
bookings for Q3 2026 reporting). Bad-rate model:
`P(dq90=1|score) = logistic(a + b*score)` solved per segment for (bad rate,
KS) jointly. Segment 0 current quarter adds a Gaussian bump
`h*exp(-((score-mu)^2)/(2*sigma^2))` to break monotonicity in deciles 4-6 —
this is the performance signal that pairs with segment 0's elevated PSI
(0.30). Development baseline frozen to `R/ks_baseline.R` (literal R source,
per D18 convention). All Segments KS expected below most per-segment values
due to pooling of populations with different bad rates and score-to-risk
slopes. Per-segment approval rates (85/70/60/40/55% for segments 0-4)
applied to ALL quarters; `applied` column set to 1L for all rows
(everyone in the table applied for credit).

#### 6b. CLAUDE.md updates

- Add `get_performance_data()` to pull function contracts table
- Add `performance` to Supabase tables table
- Add `compute_ks_stats()` to function contracts
- Add `ks_baseline` to function contracts
- Update validated frontier line number
- Update all line anchors (re-derive by grep after edits)
- Add `build-performance-table-and-ks` to completed list

#### 6c. R/CATALOG.md

Add entries for:
- `pull_performance.R` — CREATED, pull performance data (3 cols)
- `compute_ks.R` — CREATED, shared KS computation helper
- `build_ks_baseline.R` — CREATED, bootstrap + freeze KS baseline
- `ks_baseline.R` — CREATED, frozen dev KS baseline (D20)

#### 6d. data/CATALOG.md

- Remove `data/performance_24/` entry
- Rename `data/dq_24_mos/` → `data/dq_12_mos/`, update purpose
- Remove `data/ks_driver_w_perf/` entry

#### 6e. sql/ — no existing CATALOG.md

Note: no sql/CATALOG.md exists. Create if the evidence discipline requires
documenting sql/04, or add to data/CATALOG.md. Defer to user preference.

---

## Verification plan

### V1. PSI/CSI invariance

After generator changes (per-segment approval for all quarters + mature
quarter appended), regenerate data and run Rmd through :483 (CSI closing
fence). Paste PSI summary and CSI summary tables. Must be bit-identical to
pre-change values.

Why this will pass: Approval is not in the PSI/CSI filter chain. PSI/CSI
are RNG-invariant (D17). The mature quarter uses `set.seed(seed + 2000L)`
after all existing generation, so the main loop's deterministic allocations
and the Phase 2 feature stream (`seed + 1000L`) are structurally untouched.

### V2. KS targets

| Seg | Dev KS | Current KS | Tolerance |
|-----|--------|------------|-----------|
| 0   | 42     | ~33        | ±1.5      |
| 1   | 40     | ~39        | ±1.5      |
| 2   | 38     | ~37        | ±1.5      |
| 3   | 35     | ~34        | ±1.5      |
| 4   | 28     | ~25        | ±1.5      |
| All | <35*   | <30*       | report    |

*All Segments values are predictions, not targets. Expect below most
per-segment values due to pooling effects.

### V3. Approval rates

Per segment, within 0.5pp of target (85/70/60/40/55%). Blended ~62.6%.

### V4. DQ90 rates

Per segment, within 0.5pp of target (2.0/4.5/7.0/12.0/6.5% for dev;
2.1/4.7/6.4/12.4/6.7% for current).

### V5. Decile monotonicity

- Segments 1-4: assert `all(diff(bad_rate) >= 0)` per segment
- Segment 0: assert `any(diff(bad_rate)[4:5] < 0)` (break in deciles 4-6)

### V6. Minimum bads per decile

At 3x volume (91,500 core), segment 0 (16,500 core × 85% approval = 14,025
booked, × 2% bad rate = ~280 bads, / 10 deciles = ~28 bads/decile).
Assert >= 28.

### V7. Round-trip

`get_performance_data()` returns 3 columns, `origination_date` is Date,
`dq90` is integer.

### V8. Full Rmd run

Rmd runs clean :1 through new `# QC: Completed` position.

---

## Line-count estimate

| Change | Lines |
|--------|-------|
| :79 insert source('R/pull_performance.R') | +1 |
| :91 folder init rewrite | 0 (in-place) |
| :487-489 → KS chunk (~100 lines of code + narrative) | +~97 |
| Net | +~98 |

Estimated new total: ~589 lines. All pre-:78 citations unchanged. Citations
:79+ shift by +1. Post-KS-chunk citations will be re-derived.

---

## File change summary

| File | Action | Risk |
|------|--------|------|
| `R/generate_cohort.R` | MAJOR EDIT: per-seg approval, mature quarter, logistic solver, dev cohort | High — PSI/CSI invariance |
| `sql/04_create_performance_table.sql` | CREATE | Low |
| `R/pull_performance.R` | CREATE | Low — mirrors existing pattern |
| `R/compute_ks.R` | CREATE | Medium — shared helper, must match both callers |
| `R/build_ks_baseline.R` | CREATE | Medium — generates frozen baseline |
| `R/ks_baseline.R` | CREATE (generated) | Low — output of build script |
| `R/setup_supabase.R` | EDIT: add performance table | Low |
| `orchestration_2.Rmd` | EDIT: 3 sites (:78, :90, :485-490) | Medium |
| `.claude/docs/decisions.md` | EDIT: add D20 | Low |
| `CLAUDE.md` | EDIT: contracts, tables, citations | Low |
| `R/CATALOG.md` | EDIT: add 4 entries | Low |
| `data/CATALOG.md` | EDIT: rename/remove entries | Low |

## Execution order

1. `R/generate_cohort.R` — all generator changes
2. `sql/04_create_performance_table.sql`
3. `R/pull_performance.R`
4. `R/setup_supabase.R`
5. `R/compute_ks.R`
6. `R/build_ks_baseline.R` → generates `R/ks_baseline.R`
7. `orchestration_2.Rmd` — all 3 edit sites
8. Filesystem cleanup (remove empty dirs)
9. Verify: regenerate, run Rmd, paste PSI/CSI/KS
10. Documentation (CLAUDE.md, decisions.md, catalogs)
11. Commit, push, review
