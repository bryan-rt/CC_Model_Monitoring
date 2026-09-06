# Pass 3: Execute — build-csi-calculation

## What was built

1. **R/compute_si.R** — shared `compute_stability_index(joined_df, epsilon)`
   helper. Extracted from PSI chunk. Asserts `sum(percent_dev)==1` per group.
   Uses `all(tbl$epsilon_only)` in Total row.

2. **PSI chunk refactored** (orchestration_2.Rmd:265-325) — now calls
   `compute_stability_index()`. PSI-specific `percent_dev == 0.05` assertion
   kept at call site (:281-283). Column selection + ordering via
   `dplyr::select(dplyr::all_of(psi_col_order))` preserves exact downstream
   structure.

3. **source('R/pull_features.R')** added at :78, alongside other pull scripts.

4. **CSI chunk** (orchestration_2.Rmd:329-485) replaces OCR stub. Structure:
   - Pull + cache features (mirrors apps/scorecard pattern)
   - `as.numeric(user_ref_num)` coercion (integer64 → double, same as apps)
   - Inner join to `psi_df` on user_ref_num (identical population)
   - Per-feature loop: dispatch on type → `as.integer(cut/factor)` → aggregate
     → full_join dev_ref on `(Scorecard, bin_index)` → `compute_stability_index()`
   - CSI summary: 6 segments x 5 features pivot table
   - Epsilon share table
   - Grid assertions: 30 bins per segment, 180 total
   - xlsx: 5 tabs (one per feature), segment as column

## PSI structural comparison (before/after refactor)

All 6 segments: column names identical, column order identical, nrow identical
(21 = 20 data + 1 Total), data rows `all.equal: TRUE`, Total rows
`all.equal: TRUE`. PSI values bit-identical:

| Scorecard    | PSI (orig) | PSI (refactored) |
|---|---|---|
| 0            | 0.29996442 | 0.29996442 |
| 1            | 0.09001510 | 0.09001510 |
| 2            | 0.25009364 | 0.25009364 |
| 3            | 0.04013091 | 0.04013091 |
| 4            | 0.14980100 | 0.14980100 |
| All Segments | 0.08472267 | 0.08472267 |

Total row columns verified: Lower_Range=NA, Upper_Range=NA present in both.
Downstream formatter at :737 reads `psi_data[[1]]$Lower.Range` — preserved.

## Q3 2026 CSI (6x5) vs D17 targets

| Scorecard | f1 actual | f1 target | f2 actual | f2 target | f3 actual | f3 target | f4 actual | f4 target | f5 actual | f5 target |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 0.2794 | 0.28 | 0.0200 | 0.02 | 0.1897 | 0.19 | 0.0100 | 0.01 | 0.0299 | 0.03 |
| 1 | 0.0402 | 0.04 | 0.0200 | 0.02 | 0.0500 | 0.05 | 0.0100 | 0.01 | 0.0200 | 0.02 |
| 2 | 0.2201 | 0.02* | 0.0300 | 0.03 | 0.0601 | 0.06 | 0.0200 | 0.02 | 0.0400 | 0.04 |
| 3 | 0.0199 | 0.02 | 0.0099 | 0.01 | 0.0200 | 0.02 | 0.0100 | 0.01 | 0.0101 | 0.01 |
| 4 | 0.1098 | 0.11 | 0.0200 | 0.02 | 0.0401 | 0.04 | 0.0200 | 0.02 | 0.0299 | 0.03 |
| All | 0.1008 | ~0.101 | 0.0196 | — | 0.0599 | ~0.060 | 0.0134 | — | 0.0247 | — |

*Note: Task brief had a typo for segment 2 feature_1 target (listed 0.02).
Actual 0.2201 matches the D17 pattern (segment 2 "following" segment 0 in
deterioration). All values within 0.002 of targets except this corrected entry.

Epsilon share: 0 for all 30 cells (no empty bins at these volumes).

## Q4 2025 flat cohort self-test (all 30 cells)

| Scorecard | f1 | f2 | f3 | f4 | f5 |
|---|---|---|---|---|---|
| 0 | 0 | 5.289e-07 | 0 | 0 | 0 |
| 1 | 0 | 0 | 0 | 0 | 0 |
| 2 | 0 | 0 | 0 | 0 | 0 |
| 3 | 0 | 5.289e-07 | 0 | 0 | 0 |
| 4 | 0 | 5.289e-07 | 0 | 0 | 0 |
| All Segments | 0 | 1.548e-07 | 0 | 0 | 0 |

Max CSI value: 5.289e-07. All < 1e-6: **PASS**.
All Segments feature_2: 1.548e-07 — confirms ~1e-7 prediction, NOT 0.01.
No per-segment re-binning leak.

## Citation re-derivation (before → after)

Source: `source('R/pull_features.R')` inserted at :78 (+1 shift), then PSI
chunk refactored (net -72 lines: 133 removed, 61 added), CSI stub replaced
(net +105 lines: 51 removed, 156 added). Total Rmd delta: +34 lines
(2627 → 2661).

| Citation | Before | After | Anchor text | Verified |
|---|---|---|---|---|
| `# QC: Completed` | :399 | :327 | `# QC: Completed` | grep :327 |
| `# QC: Validated` | :453 | :487 | `# QC: Validated` | grep :487 |
| `# QC: Target` | :634 | :668 | `# QC: Target` | grep :668 |
| CSI chunk fence | :405 | :335 | `` ```{r} `` | grep :335 |
| source compute_si.R | — | :267 | `source(here::here("R/compute_si.R"))` | grep :267 |
| source build_dev_population | :266 | :268 | `source(here::here("R/build_dev_population.R"))` | grep :268 |
| source feature_breaks.R | — | :338 | `source(here::here("R/feature_breaks.R"))` | grep :338 |
| get_apps_data call | :132 | :133 | `get_apps_data` | grep :133 |
| get_cc_scorecard_data call | :114 | :115 | `get_cc_scorecard_data` | grep :115 |
| get_features_data call | — | :352 | `get_features_data` | grep :352 |
| PENDING TRANSCRIPTION | :78 | :79 | `# PENDING TRANSCRIPTION` | grep :79 |
| segment_breaks | :181-194 | :184-197 | `segment_breaks <- list(` | grep :184 |

## Deviations from plan

1. **integer64 → double coercion**: features' `user_ref_num` arrives as
   integer64 from fread (same serialization contract as apps/scorecard).
   Added `as.numeric(user_ref_num)` before the inner_join. Not in the plan
   because the plan didn't trace the fread type path for features.

2. **stopifnot with computed names**: R doesn't allow `paste0()` as the name
   in `stopifnot(name = expr)`. Replaced with `if (!cond) stop(...)` pattern
   for per-feature assertions. Plan noted the glue issue but didn't catch
   that paste0 has the same limitation.

3. **Segment 2 feature_1 target**: Task brief listed 0.02 for seg 2 f1.
   Actual is 0.2201, matching the D17 drift story (segment 2 following
   segment 0). The brief had a typo — the 0.02 line was truncated
   ("2 2   0.03   0.06..."). Actual value is within 0.002 of the correct
   target (0.22 from D17's segment 2 alpha).

## Files changed

| File | Action |
|---|---|
| `R/compute_si.R` | Created |
| `orchestration_2.Rmd` | Edited (source line, PSI refactor, CSI chunk) |
| `CLAUDE.md` | Updated (frontier, citations, contracts, decisions ref) |
| `.claude/docs/decisions.md` | Added D19, updated D13/D15 line refs |
| `R/CATALOG.md` | Updated (added compute_si.R, updated all line refs) |
