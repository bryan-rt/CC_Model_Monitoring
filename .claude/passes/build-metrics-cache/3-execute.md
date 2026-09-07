# Pass 3: Execute — build-metrics-cache

Date: 2026-09-07

## HANDOFF — User actions required

1. **Backfill the cache**: Run orchestration_2.Rmd once per quarter in RStudio.
   Set cohort_date before each run:
   ```r
   cohort_date <- as.Date("2025-10-01")  # 2025Q4
   cohort_date <- as.Date("2026-01-01")  # 2026Q1
   cohort_date <- as.Date("2026-04-01")  # 2026Q2
   cohort_date <- as.Date("2026-07-01")  # 2026Q3
   ```
   Each run writes 4 CSVs to `output_files/quarterly_stats/{PSI,CSI,KS}/`.

2. **Verify the backfill**: After all 4 runs, call from the R console:
   ```r
   source("R/load_metrics_history.R")
   load_metrics_history("PSI")       # expect 4 quarters
   load_metrics_history("KS")        # data_cohort should be 1 year behind
   load_metrics_history("CSI")       # 30 rows per quarter
   load_metrics_history("KS_DECILES") # 60 rows per quarter
   ```

3. **Cannot verify computed values**: Cache writes are pass-through wrappers.
   No computed values were changed. The unit tests verify the MECHANISM
   (write, read, provenance, schema validation, warnings) not the CONTENT.
   Content verification requires a full Rmd run in RStudio.

## Changes made

### New files

| File | Purpose | Lines |
|---|---|---|
| `R/write_metrics_cache.R` | Per-quarter CSV writer with schema validation + provenance | 83 |
| `R/load_metrics_history.R` | Multi-quarter CSV loader with schema/version warnings | 78 |
| `tests/test_metrics_cache.R` | Standalone unit tests (27 assertions) | 194 |

### Modified files

| File | Change |
|---|---|
| `orchestration_2.Rmd` | 6 edits: cohort_date comment, dir_create, n_booked suffix, PSI/CSI/KS cache writes |
| `CLAUDE.md` | Anchors, execution constraint, D22 ref, new function contracts |
| `.claude/docs/decisions.md` | D22 added, D13/D19/D20/D21 anchors updated |
| `R/CATALOG.md` | 2 new entries, 10 line references updated |
| `CATALOG.md` | Validated frontier line updated |

### orchestration_2.Rmd edits (6 sites)

1. **:65-68** — Cohort date comment enhanced (+2 lines)
2. **:94-97** — dir_create extended with PSI/CSI/KS subdirs (+3 lines)
3. **:386-387** — PSI cache write: source + write_metrics_cache call (+2 lines)
4. **:606-613** — CSI cache write: enrich csi_ci with current_count/epsilon_share, write (+8 lines)
5. **:737-738** — n_booked suffix fix: `suffix = c("", "_dev")` on inner_join (+1 line)
6. **:812-817** — KS cache writes: ks_summary + ks_deciles (+6 lines, -1 closing fence = +5 net)

**Line count**: 801 -> 822 (+21 lines)

### Fixes from Pass 2 review

1. **n_booked collision** fixed at the join site (:734-739), not in the cache
   write. `suffix = c("", "_dev")` produces clean `n_booked` and `n_booked_dev`
   columns. Verified: no downstream code references n_booked by name.

2. **CSI cache enriched** with `current_count` and `epsilon_share` from
   `csi_summary_long` via left_join at :609-612.

3. **code_version fallback** hardened: `suppressWarnings()` + length/nzchar
   check handles `character(0)` from non-git directories. Tested by running
   writer from a temp dir with `setwd()`.

4. **Schema validation** on both write and read. Write: asserts expected
   column set per KPI, stops on mismatch. Read: compares column names across
   files, stops on mismatch.

5. **dir_create in writer**: `fs::dir_create(dirname(out_path))` ensures the
   writer works standalone without the Rmd's dir_create having run.

## Deviations from plan

1. **Line delta was +21, not +18**. The dir_create expansion was +3 (not +2)
   and the CSI cache block was +8 (not +6) because the left_join pipeline
   needed more lines than estimated.

2. **Test 9 (missing folder)** tests the error message construction rather
   than calling load_metrics_history with a truly nonexistent KPI (since the
   function validates KPI names first). The test manually checks dir.exists
   to exercise the error path.

## Anchor shift table (verified by grep)

| Anchor | Old | New | Verified |
|---|---|---|---|
| `# QC: Validated` | :800 | :822 | grep |
| `# QC: Completed` | :798 | :820 | grep |
| `source(compute_si.R)` | :268 | :273 | grep |
| CSI chunk fence | :390 | :397 | grep |
| CSI range end | :598 | :614 | read |
| KS chunk fence | :610 | :625 | grep |
| `source(compute_ks.R)` | :612 | :627 | grep |
| perf_date | :616 | :631 | grep |
| PSI bootstrap | :318 | :323 | grep |
| CSI bootstrap | :506 | :513 | grep |
| KS bootstrap | :728 | :744 | grep |
| Wilson CI | :770 | :786 | grep |
| ks_comparison join | :719 | :734 | grep |
| PSI xlsx write | :378 | :383 | read |
| CSI xlsx write | :596 | :603 | read |
| KS xlsx write | :793 | :809 | read |
| source(wilson_ci.R) | :270 | :275 | grep |
| source(bootstrap_ci.R) | :271 | :276 | grep |
| source(build_dev_population.R) | :269 | :274 | grep |
| source(feature_breaks.R) | :392 | :399 | grep |
| source(ks_baseline.R) | :613 | :628 | grep |
| get_features_data call | :406 | :413 | grep |
| get_apps_data call | :133 | :139 | grep |
| get_cc_scorecard_data call | :115 | :121 | grep |
| get_performance_data call | :629 | :644 | grep |

## Test output

All 27 assertions passed. Key demonstrations:

```
=== Test 1: PSI write + read round-trip ===
  PASS: PSI file exists
  PASS: PSI has provenance columns
  PASS: PSI report_quarter = 2026Q3
  PASS: PSI data_cohort = 2026Q3 (same as report for PSI)
  PASS: PSI has 6 rows
  PASS: PSI values preserved

=== Test 2: KS data_cohort assertion ===
  PASS: KS data_cohort = 2025Q3 (12 months prior)
  PASS: KS report_quarter = 2026Q3
  PASS: KS data_cohort is exactly 4 quarters before report_quarter

=== Test 5: Idempotent overwrite ===
  PASS: Only one PSI file after re-write
  PASS: Timestamp updated on overwrite

=== Test 7: Short-window warning ===
  PASS: Short-window warning fires

=== Test 8: Mixed code_version warning ===
  PASS: Mixed code_version warning fires

=== Test 10: Schema mismatch on WRITE ===
  PASS: Write schema error on missing column
  PASS: Write schema error on extra column

=== Test 11: Schema mismatch on READ ===
  PASS: Read schema error on column mismatch

=== Test 12: code_version fallback in non-git directory ===
fatal: not a git repository (or any of the parent directories): .git
  PASS: File written from non-git dir
  PASS: code_version = 'unknown' in non-git dir

=== RESULTS ===
Passed: 27 / 27
All tests passed.
```
