# Pass 3: Execute -- add-confidence-intervals

Date: 2026-09-07

## Changes

7 files changed (2 created, 5 modified).

| File | Action |
|------|--------|
| `R/wilson_ci.R` | CREATE: vectorized Wilson score CI (~18 lines) |
| `R/bootstrap_ci.R` | CREATE: stratified percentile bootstrap (~40 lines) |
| `orchestration_2.Rmd` | +173 lines: PSI bootstrap+tier (:318-369), CSI bootstrap (:506-562), KS bootstrap (:728-767), Wilson CI (:770-787), source calls (:270-271), CSI xlsx ci tab (:595) |
| `CLAUDE.md` | Frontier 635->800, anchors, contracts, completed list |
| `.claude/docs/decisions.md` | D21 added |
| `R/CATALOG.md` | 2 new entries, anchors re-derived |
| `.claude/passes/build-performance-table-and-ks/3-execute.md` | (corrected in Pass 1 commit) |

## V1. Point estimates unchanged

### PSI (before/after bootstrap wiring)

| Scorecard | Before | After |
|---|---|---|
| 0 | 0.29996442 | 0.29996442 |
| 1 | 0.09001510 | 0.09001510 |
| 2 | 0.25009364 | 0.25009364 |
| 3 | 0.04013091 | 0.04013091 |
| 4 | 0.14980100 | 0.14980100 |
| All Segments | 0.08351459 | 0.08351459 |

STATUS: VERIFIED -- `all(psi_summary$Population_Stability_Index == original) = TRUE`.

### CSI

Unchanged -- bootstrap adds `csi_ci` companion table, does not modify
`csi_summary`. CSI values confirmed identical in xlsx output.

### KS

| Segment | Before | After |
|---|---|---|
| All Segments | 28.53462 | 28.53462 |
| 0 | 33.22434 | 33.22434 |
| 1 | 39.08972 | 39.08972 |
| 2 | 37.21813 | 37.21813 |
| 3 | 33.88236 | 33.88236 |
| 4 | 25.16764 | 25.16764 |

STATUS: VERIFIED -- from ks_quarterly.xlsx.

## V2. PSI bootstrap CIs and tier assignments

B = 500, seed = 20260907 + 3000.

| Scorecard | PSI | ci_lower | ci_upper | tier | tier_certain |
|---|---|---|---|---|---|
| 0 | 0.2997 | 0.2753 | 0.3349 | investigate | TRUE |
| 1 | 0.0900 | 0.0803 | 0.1044 | stable | **FALSE** |
| 2 | 0.2501 | 0.2266 | 0.2790 | investigate | **FALSE** |
| 3 | 0.0401 | 0.0335 | 0.0546 | stable | TRUE |
| 4 | 0.1498 | 0.1328 | 0.1752 | watch | TRUE |
| All Segments | 0.0835 | 0.0779 | 0.0896 | stable | TRUE |

**tier_certain = FALSE for segments 1 and 2:**
- Segment 1: PSI 0.090, CI [0.080, 0.104] spans the 0.10 threshold. "Reads
  stable, but the interval reaches watch -- cannot call it stable on this
  quarter alone."
- Segment 2: PSI 0.250, CI [0.227, 0.279] spans the 0.25 threshold. "Reads
  at the watch/investigate boundary; the interval reaches both sides."

Expected per task brief: segment 0 PSI ~0.30, CI ~[0.275, 0.335]. Achieved:
[0.275, 0.335]. Exact match.

STATUS: VERIFIED -- PSI bootstrap ran in 28.3s.

## V3. Wilson CI assertions

### wilson_ci(0, 1538) = [0.0000, 0.0025]

Achieved: lower = 0.0000, upper = 0.002491. PASS.

This is the test case: the naive Wald interval returns [0, 0] -- perfect
certainty where there is least information. Wilson correctly reports a
nonzero upper bound.

### All 60 decile cells: lower >= 0, upper <= 1

PASS -- stopifnot assertions passed.

### Segment 0 decile Wilson CIs

| Decile | n | n_bads | bad_rate | ci_lower | ci_upper |
|---|---|---|---|---|---|
| 1 | 1538 | 0 | 0.0000 | 0.0000 | 0.0025 |
| 2 | 1538 | 3 | 0.0020 | 0.0007 | 0.0057 |
| 3 | 1538 | 10 | 0.0065 | 0.0035 | 0.0119 |
| 4 | 1538 | 26 | 0.0169 | 0.0116 | 0.0247 |
| 5 | 1538 | 43 | 0.0280 | 0.0208 | 0.0374 |
| 6 | 1538 | 36 | 0.0234 | 0.0170 | 0.0322 |
| 7 | 1538 | 21 | 0.0137 | 0.0089 | 0.0208 |
| 8 | 1538 | 24 | 0.0156 | 0.0105 | 0.0231 |
| 9 | 1538 | 51 | 0.0332 | 0.0253 | 0.0433 |
| 10 | 1537 | 129 | 0.0839 | 0.0711 | 0.0989 |

Expected from brief:
- Decile 5 (43/1538): [0.0208, 0.0374] -- achieved exactly
- Decile 7 (21/1538): [0.0089, 0.0208] -- achieved [0.0089, 0.0208]

**Substantive finding -- deciles 5/6/7:**
- Deciles 5 and 6 CIs: [0.021, 0.037] and [0.017, 0.032]. Heavy overlap --
  the 5->6 step (0.028->0.023) is noise.
- Deciles 5 and 7 CIs: [0.021, 0.037] and [0.009, 0.021]. Barely touch at
  0.021 -- the 5->7 drop (0.028->0.014) is real.

This is the Gaussian bump (D20) surfacing: the monotonicity break at deciles
5-8 in segment 0 is a genuine performance signal, but the individual step
from 5 to 6 is within noise. The Wilson intervals make this distinction
visible without a formal hypothesis test.

STATUS: VERIFIED.

## V4. Bootstrap CIs contain point estimates

- PSI: 6/6 groups -- all point estimates within [ci_lower, ci_upper]. PASS.
- CSI: 30/30 groups -- 0 misses. PASS.
- KS: 6/6 groups -- 0 misses. PASS.

STATUS: VERIFIED.

## V5. KS bootstrap CIs

| Segment | KS | ci_lower | ci_upper | B |
|---|---|---|---|---|
| All Segments | 28.53 | 27.12 | 30.12 | 500 |
| 0 | 33.22 | 28.17 | 38.41 | 500 |
| 1 | 39.09 | 35.83 | 42.12 | 500 |
| 2 | 37.22 | 34.36 | 40.28 | 500 |
| 3 | 33.88 | 30.65 | 37.40 | 500 |
| 4 | 25.17 | 22.40 | 29.00 | 500 |

Segment 0 has the widest CI (10.2 points) -- expected, since it has the
fewest bads (343) and the lowest bad rate (2.23%), making KS more volatile.

STATUS: VERIFIED -- KS bootstrap ran in 28.9s.

## Wall time

| Component | Time |
|---|---|
| PSI bootstrap (B=500, 30,500 rows) | 28.3s |
| CSI bootstrap (B=500, 30,500 rows, 5 features) | 62.5s |
| KS bootstrap (B=500, 61,820 rows, ntile per rep) | 28.9s |
| Total bootstrap | ~120s |
| Full Rmd end-to-end | User ran interactively |

CSI is the most expensive because each replicate computes 5 features x
6 segments = 30 stability indices. KS was budgeted for 30-60s; achieved
28.9s.

## Deviations from plan

### Deviation 1: Line count higher than estimated

**Plan (Pass 2)**: ~114 lines added, total ~741.
**Actual**: +173 lines, total 800.

The stat_fn closures are inline in the Rmd (not extracted to helper files),
which is correct (they reference chunk-local objects like `segment_breaks`,
`dev_pop`, `feature_breaks`). The closure bodies are larger than estimated
because they reproduce the full computation pipelines.

### Deviation 2: CSI bootstrap slower than PSI/KS

CSI (62.5s) > KS (28.9s) despite fewer rows (30,500 vs 61,820). The CSI
stat_fn computes 5 feature x 6 segment = 30 stability indices per replicate
(vs 6 for PSI and KS). The per-replicate cost is dominated by the 5 inner
loops through compute_stability_index(), not row count.

### No deviations from expected results

All expected values from the task brief matched:
- Segment 0 PSI CI: ~[0.275, 0.335] -- achieved [0.275, 0.335]
- Segment 0 decile 1 Wilson: ~[0.0000, 0.0025] -- achieved [0.0000, 0.0025]
- Segment 0 decile 5 Wilson: ~[0.0208, 0.0374] -- achieved [0.0208, 0.0374]
- Segment 0 decile 7 Wilson: ~[0.0089, 0.0208] -- achieved [0.0089, 0.0208]

## Bug fixes from Pass 2 review

1. **reps matrix sizing** (blocking): stat_fn returns groups not in the
   resampling strata (e.g., "All Segments", compound CSI keys). Fixed by
   calling stat_fn once on unresampled data to discover the group set.

2. **n_distinct vs n()** (silent): With-replacement resampling creates
   duplicate user_ref_nums. n_distinct() would thin to ~63% effective
   observations. Fixed: PSI stat_fn uses n() not n_distinct().

3. **estimate column**: Removed from bootstrap_ci output (was labeled
   "not the estimate" in a comment -- a trap for the next reader).

4. **rbind performance**: Replaced do.call(rbind, lapply()) with
   dplyr::bind_rows() in bootstrap_ci's inner loop.

## Line anchor reconciliation

| Anchor | Before | After |
|--------|--------|-------|
| `# QC: Completed` | :625 | :798 |
| `# QC: Validated` | :627 | :800 |
| `source("R/compute_si.R")` | :268 | :268 (unchanged) |
| `source("R/build_dev_population.R")` | :269 | :269 (unchanged) |
| `source("R/wilson_ci.R")` | — | :270 |
| `source("R/bootstrap_ci.R")` | — | :271 |
| CSI chunk opening fence | :335 | :390 |
| `source("R/feature_breaks.R")` | :337 | :392 |
| `source("R/compute_ks.R")` | :497 | :612 |
| `source("R/ks_baseline.R")` | :498 | :613 |
| KS chunk opening fence | :495 | :610 |
| PSI bootstrap | — | :318 |
| CSI bootstrap | — | :506 |
| KS bootstrap | — | :728 |
| Wilson CI | — | :770 |
| Total Rmd lines | 627 | 800 |

## Definition of done checklist

- [x] wilson_ci(0, 1538) returns ~[0.0000, 0.0025] -- asserted
- [x] wilson_ci never returns negative lower or upper > 1 -- asserted across all 60 cells
- [x] Bootstrap CIs contain their point estimates for all groups -- asserted
- [x] PSI, CSI, KS point estimates unchanged -- before/after pasted
- [x] psi_summary carries tier and tier_certain; segments 1 and 2 have tier_certain=FALSE
- [x] Rmd runs clean :1 through the marker; wall time: PSI 28s, CSI 63s, KS 29s
- [x] Line-count delta: 627 -> 800 (+173); every live citation re-derived
- [x] CLAUDE.md, decisions.md (D21), R/CATALOG.md updated
- [x] 3-execute.md written
- [x] Branch pass3/add-confidence-intervals, pushed
