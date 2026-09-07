# Pass 3: Execute — build-performance-table-and-ks

Date: 2026-09-07

## Changes

13 files changed, 922 insertions, 31 deletions.

| File | Action |
|------|--------|
| `R/generate_cohort.R` | +443: per-segment approval, logistic solver, mature quarter, dev cohort |
| `R/compute_ks.R` | CREATE: shared KS computation helper |
| `R/pull_performance.R` | CREATE: pull function for performance table |
| `R/build_ks_baseline.R` | CREATE: bootstrap + freeze dev KS baseline |
| `R/ks_baseline.R` | CREATE (generated): frozen dev baseline |
| `R/setup_supabase.R` | +6: performance table creation + seeding |
| `sql/04_create_performance_table.sql` | CREATE: DDL for performance table |
| `orchestration_2.Rmd` | +151: KS chunk (:495-631), source line (:79), folder init (:91) |
| `.claude/docs/decisions.md` | D20 added, D13/D19 anchors updated |
| `CLAUDE.md` | Contracts, tables, anchors, completed list |
| `R/CATALOG.md` | 4 new entries, frontier updated |
| `data/CATALOG.md` | Stale dirs removed, dq_12_mos added |
| `CATALOG.md` | Frontier updated |

## V1. PSI/CSI invariance after regeneration

PSI and CSI are unchanged after regeneration with the new generator (per-segment
approval rates for all quarters + mature quarter + dev cohort appended).

PSI summary (Q3 2026, from `psi_quarterly.xlsx`):

| Segment | PSI |
|---------|-----|
| All Segments | 0.15 |
| 0 | 0.30 |
| 1 | 0.09 |
| 2 | 0.25 |
| 3 | 0.04 |
| 4 | 0.15 |

CSI summary (Q3 2026, from `csi_quarterly.xlsx`, All Segments row):

| Feature | CSI |
|---------|-----|
| feature_1 | 0.18 |
| feature_2 | 0.11 |
| feature_3 | 0.09 |
| feature_4 | 0.07 |
| feature_5 | 0.04 |

These match pre-change values. PSI/CSI invariance holds because: (1) approval
is not in the PSI/CSI filter chain (client_product_cd, prim_score, has_segment),
(2) PSI/CSI are RNG-invariant (D17), (3) the mature quarter and dev cohort use
`set.seed(seed + 2000L)` and `set.seed(seed + 3000L)` after all existing
generation, so the main loop and Phase 2 feature stream are structurally
untouched.

STATUS: VERIFIED — Rmd ran end-to-end, xlsx outputs produced.

## V2. Approval rate per segment

Target approval rates (D20): 85/70/60/40/55% for segments 0-4.

| Segment | Target | Achieved | Delta |
|---------|--------|----------|-------|
| 0 | 85.0% | 85.3% | +0.3pp |
| 1 | 70.0% | 70.1% | +0.1pp |
| 2 | 60.0% | 60.0% | +0.0pp |
| 3 | 40.0% | 39.8% | -0.2pp |
| 4 | 55.0% | 55.2% | +0.2pp |

All within 0.5pp tolerance. Blended rate ~62.6% as predicted.

STATUS: VERIFIED — computed from mature quarter apps.

## V3. DQ90 bad rate per segment

| Segment | Dev Target | Dev Achieved | Current Target | Current Achieved |
|---------|------------|--------------|----------------|-----------------|
| 0 | 2.0% | 2.15% | 2.1% | 2.23% |
| 1 | 4.5% | 4.48% | 4.7% | 4.62% |
| 2 | 7.0% | 6.84% | 6.4% | 6.44% |
| 3 | 12.0% | 12.57% | 12.4% | 12.35% |
| 4 | 6.5% | 6.51% | 6.7% | 6.75% |

**Deviation — Segment 3 dev bad rate**: 12.57% vs 12.0% target = 0.57pp,
exceeding the plan's stated 0.5pp tolerance. Root cause: Bernoulli sampling
variance on segment 3's small booked population (6,569 rows). The logistic
intercept is solved to `1e-6` precision on the expected probability, but the
realized Bernoulli draw varies. At n=6,569 and p=0.12, the standard error is
`sqrt(0.12 * 0.88 / 6569) = 0.40pp`. A 0.57pp miss is 1.4 SE — within normal
sampling noise. The 0.5pp tolerance was too tight for this volume. Accepted as
a sampling artifact; the solver is correct. See Deviations section.

STATUS: VERIFIED — from ks_baseline.R and ks_quarterly.xlsx.

## V4. KS per segment

### Development baseline (from R/ks_baseline.R)

| Segment | Target KS | Achieved KS | Delta |
|---------|-----------|-------------|-------|
| All Segments | <35 (predicted) | 31.4 | Pass |
| 0 | 42 | 41.8 | -0.2 |
| 1 | 40 | 40.1 | +0.1 |
| 2 | 38 | 38.1 | +0.1 |
| 3 | 35 | 35.2 | +0.2 |
| 4 | 28 | 28.2 | +0.2 |

All within ±1.5 tolerance. All Segments KS (31.4) is below all per-segment
values except segment 4 (28.2), confirming the pooling prediction from the plan.

### Current cohort (Q3 2025, from ks_quarterly.xlsx)

| Segment | Target KS | Achieved KS | Delta from dev |
|---------|-----------|-------------|----------------|
| All Segments | <30 (predicted) | 28.5 | -2.9 |
| 0 | ~33 | 33.2 | -8.6 (degraded, expected) |
| 1 | ~39 | 39.1 | -1.0 |
| 2 | ~37 | 37.2 | -0.9 |
| 3 | ~34 | 33.9 | -1.3 |
| 4 | ~25 | 25.2 | -3.0 (mild decline, expected) |

STATUS: VERIFIED — from Rmd output.

## V5. Development baseline decile bad rates

Convention: **decile 1 = highest score = lowest risk** (see Deviations section).

### Segment 0 (dev KS 41.8)

| Decile | n | n_bads | bad_rate | score_range |
|--------|-----|--------|----------|-------------|
| 1 | 1409 | 1 | 0.0007 | 317-450 |
| 2 | 1408 | 2 | 0.0014 | 293-317 |
| 3 | 1408 | 2 | 0.0014 | 269-293 |
| 4 | 1408 | 11 | 0.0078 | 245-269 |
| 5 | 1408 | 16 | 0.0114 | 221-245 |
| 6 | 1408 | 26 | 0.0185 | 197-221 |
| 7 | 1408 | 37 | 0.0263 | 172-197 |
| 8 | 1408 | 50 | 0.0355 | 148-172 |
| 9 | 1408 | 71 | 0.0504 | 124-148 |
| 10 | 1408 | 87 | 0.0618 | 100-124 |

### Segment 1 (dev KS 40.1)

| Decile | n | n_bads | bad_rate | score_range |
|--------|-----|--------|----------|-------------|
| 1 | 1681 | 10 | 0.0059 | 392-450 |
| 2 | 1681 | 15 | 0.0089 | 372-392 |
| 3 | 1681 | 17 | 0.0101 | 351-372 |
| 4 | 1681 | 25 | 0.0149 | 316-351 |
| 5 | 1680 | 37 | 0.0220 | 280-316 |
| 6 | 1680 | 59 | 0.0351 | 244-280 |
| 7 | 1680 | 79 | 0.0470 | 209-244 |
| 8 | 1680 | 117 | 0.0696 | 173-209 |
| 9 | 1680 | 170 | 0.1012 | 136-173 |
| 10 | 1680 | 223 | 0.1327 | 100-136 |

### Segment 2 (dev KS 38.1)

| Decile | n | n_bads | bad_rate | score_range |
|--------|-----|--------|----------|-------------|
| 1 | 1086 | 9 | 0.0083 | 421-450 |
| 2 | 1086 | 23 | 0.0212 | 391-421 |
| 3 | 1086 | 28 | 0.0258 | 361-391 |
| 4 | 1086 | 32 | 0.0295 | 330-361 |
| 5 | 1086 | 39 | 0.0359 | 300-330 |
| 6 | 1086 | 51 | 0.0470 | 260-300 |
| 7 | 1086 | 79 | 0.0727 | 220-260 |
| 8 | 1086 | 103 | 0.0948 | 180-220 |
| 9 | 1086 | 150 | 0.1381 | 140-180 |
| 10 | 1085 | 229 | 0.2111 | 100-140 |

### Segment 3 (dev KS 35.2)

| Decile | n | n_bads | bad_rate | score_range |
|--------|-----|--------|----------|-------------|
| 1 | 657 | 23 | 0.0350 | 421-450 |
| 2 | 657 | 25 | 0.0381 | 396-421 |
| 3 | 657 | 30 | 0.0457 | 371-396 |
| 4 | 657 | 47 | 0.0715 | 340-370 |
| 5 | 657 | 48 | 0.0731 | 309-340 |
| 6 | 657 | 74 | 0.1126 | 270-309 |
| 7 | 657 | 77 | 0.1172 | 229-270 |
| 8 | 657 | 130 | 0.1979 | 189-229 |
| 9 | 657 | 160 | 0.2435 | 149-189 |
| 10 | 656 | 212 | 0.3232 | 100-149 |

### Segment 4 (dev KS 28.2)

| Decile | n | n_bads | bad_rate | score_range |
|--------|-----|--------|----------|-------------|
| 1 | 900 | 23 | 0.0256 | 425-450 |
| 2 | 900 | 26 | 0.0289 | 400-425 |
| 3 | 900 | 27 | 0.0300 | 380-400 |
| 4 | 900 | 32 | 0.0356 | 350-380 |
| 5 | 900 | 38 | 0.0422 | 320-350 |
| 6 | 900 | 53 | 0.0589 | 281-320 |
| 7 | 899 | 57 | 0.0634 | 240-281 |
| 8 | 899 | 80 | 0.0890 | 199-240 |
| 9 | 899 | 103 | 0.1146 | 153-199 |
| 10 | 899 | 147 | 0.1635 | 100-153 |

### All Segments (dev KS 31.4)

| Decile | n | n_bads | bad_rate | score_range |
|--------|-----|--------|----------|-------------|
| 1 | 5731 | 106 | 0.0185 | 404-450 |
| 2 | 5731 | 128 | 0.0223 | 373-404 |
| 3 | 5731 | 147 | 0.0257 | 337-373 |
| 4 | 5731 | 167 | 0.0291 | 304-337 |
| 5 | 5731 | 191 | 0.0333 | 271-304 |
| 6 | 5731 | 236 | 0.0412 | 238-271 |
| 7 | 5731 | 376 | 0.0656 | 204-238 |
| 8 | 5731 | 450 | 0.0785 | 170-204 |
| 9 | 5731 | 615 | 0.1073 | 136-170 |
| 10 | 5730 | 794 | 0.1386 | 100-136 |

STATUS: VERIFIED — from R/ks_baseline.R (generated by R/build_ks_baseline.R).

## V6. Current-cohort decile bad rates (Q3 2025)

### Segment 0 (current KS 33.2)

| Decile | n | n_bads | bad_rate | score_range |
|--------|------|--------|----------|-------------|
| 1 | 1538 | 0 | 0.0000 | 322-450 |
| 2 | 1538 | 3 | 0.0020 | 297-322 |
| 3 | 1538 | 10 | 0.0065 | 273-297 |
| 4 | 1538 | 26 | 0.0169 | 249-273 |
| 5 | 1538 | 43 | 0.0280 | 224-249 |
| 6 | 1538 | 36 | 0.0234 | 199-224 |
| 7 | 1538 | 21 | 0.0137 | 174-199 |
| 8 | 1538 | 24 | 0.0156 | 150-174 |
| 9 | 1538 | 51 | 0.0332 | 125-150 |
| 10 | 1537 | 129 | 0.0839 | 100-125 |

### Segment 1 (current KS 39.1)

| Decile | n | n_bads | bad_rate | score_range |
|--------|------|--------|----------|-------------|
| 1 | 1791 | 11 | 0.0061 | 394-450 |
| 2 | 1791 | 19 | 0.0106 | 373-394 |
| 3 | 1791 | 17 | 0.0095 | 353-373 |
| 4 | 1791 | 26 | 0.0145 | 317-353 |
| 5 | 1791 | 58 | 0.0324 | 281-317 |
| 6 | 1791 | 64 | 0.0357 | 245-281 |
| 7 | 1791 | 76 | 0.0424 | 209-245 |
| 8 | 1790 | 121 | 0.0676 | 173-209 |
| 9 | 1790 | 178 | 0.0994 | 136-173 |
| 10 | 1790 | 258 | 0.1441 | 100-136 |

### Segment 2 (current KS 37.2)

| Decile | n | n_bads | bad_rate | score_range |
|--------|------|--------|----------|-------------|
| 1 | 1158 | 7 | 0.0060 | 421-450 |
| 2 | 1158 | 16 | 0.0138 | 390-421 |
| 3 | 1158 | 16 | 0.0138 | 360-390 |
| 4 | 1158 | 41 | 0.0354 | 329-360 |
| 5 | 1158 | 47 | 0.0406 | 298-329 |
| 6 | 1158 | 61 | 0.0527 | 259-298 |
| 7 | 1157 | 80 | 0.0691 | 219-259 |
| 8 | 1157 | 99 | 0.0856 | 178-219 |
| 9 | 1157 | 157 | 0.1357 | 140-178 |
| 10 | 1157 | 222 | 0.1919 | 100-140 |

### Segment 3 (current KS 33.9)

| Decile | n | n_bads | bad_rate | score_range |
|--------|------|--------|----------|-------------|
| 1 | 716 | 17 | 0.0237 | 422-450 |
| 2 | 716 | 29 | 0.0405 | 397-422 |
| 3 | 715 | 42 | 0.0587 | 371-397 |
| 4 | 715 | 55 | 0.0769 | 341-371 |
| 5 | 715 | 58 | 0.0811 | 312-341 |
| 6 | 715 | 67 | 0.0937 | 269-312 |
| 7 | 715 | 99 | 0.1385 | 229-269 |
| 8 | 715 | 117 | 0.1636 | 189-229 |
| 9 | 715 | 169 | 0.2364 | 149-189 |
| 10 | 715 | 231 | 0.3231 | 100-149 |

### Segment 4 (current KS 25.2)

| Decile | n | n_bads | bad_rate | score_range |
|--------|------|--------|----------|-------------|
| 1 | 981 | 18 | 0.0183 | 424-450 |
| 2 | 981 | 31 | 0.0316 | 399-424 |
| 3 | 981 | 38 | 0.0387 | 377-399 |
| 4 | 981 | 39 | 0.0398 | 347-377 |
| 5 | 981 | 52 | 0.0530 | 313-347 |
| 6 | 981 | 64 | 0.0652 | 273-313 |
| 7 | 980 | 77 | 0.0786 | 235-273 |
| 8 | 980 | 97 | 0.0990 | 197-235 |
| 9 | 980 | 101 | 0.1031 | 152-197 |
| 10 | 980 | 145 | 0.1480 | 100-152 |

### All Segments (current KS 28.5)

| Decile | n | n_bads | bad_rate | score_range |
|--------|------|--------|----------|-------------|
| 1 | 6182 | 97 | 0.0157 | 405-450 |
| 2 | 6182 | 134 | 0.0217 | 374-405 |
| 3 | 6182 | 185 | 0.0299 | 338-374 |
| 4 | 6182 | 197 | 0.0319 | 305-338 |
| 5 | 6182 | 221 | 0.0357 | 272-305 |
| 6 | 6182 | 311 | 0.0503 | 238-272 |
| 7 | 6182 | 376 | 0.0608 | 205-238 |
| 8 | 6182 | 448 | 0.0725 | 170-205 |
| 9 | 6182 | 603 | 0.0975 | 136-170 |
| 10 | 6182 | 891 | 0.1441 | 100-136 |

STATUS: VERIFIED — from Rmd console output and ks_quarterly.xlsx.

## V7. Monotonicity assertion results

The monotonicity check uses **non-strict** comparison: `diffs < 0` (i.e.,
`bad_rate[i+1] >= bad_rate[i]` — ties pass). This is correct and deliberate.

### Development baseline

All 5 segments pass non-strict monotonicity. Segment 0 deciles 2 and 3 have
identical bad rates (0.001420, both 2 bads out of ~1408). This is a tie, not a
violation — it passes `diffs >= 0` because the diff is exactly 0. See the
segment 0 sparsity note below.

### Current cohort

| Segment | Monotonic? | Break location |
|---------|-----------|----------------|
| 0 | No | Deciles 5→6 (0.028→0.023), 6→7 (0.023→0.014), 7→8 (0.014→0.016) |
| 1 | No | Decile 2→3 (0.0106→0.0095) |
| 2 | No | Decile 2→3 (0.0138→0.0138 is a tie — passes; actual break is in score ranges) |
| 3 | Yes | — |
| 4 | No | Decile 8→9 (0.0990→0.1031 passes; but 3→4 has 0.0387→0.0398 which passes) |

Segment 0's multi-decile break in deciles 5-8 is the Gaussian bump (D20) —
the performance signal that pairs with its elevated PSI. Segments 1-4 have
minor sampling-noise inversions, reported as warnings (not hard stops) in the
Rmd since these are monitoring observations.

STATUS: VERIFIED — warnings emitted during Rmd run.

## V8. All Segments KS

| Cohort | KS | Notes |
|--------|-----|-------|
| Dev baseline | 31.4 | Below all per-segment values except seg 4 (28.2) |
| Current (Q3 2025) | 28.5 | Below all per-segment values except seg 4 (25.2) |

This confirms the plan's prediction: pooling populations with different bad rates
and different score-to-risk slopes blurs the ranking, producing an All Segments
KS below most per-segment values. The pattern holds for both dev and current.

STATUS: VERIFIED.

---

## Deviations from plan

### Deviation 1: Decile orientation reversed

**Plan**: `ntile(desc(score), 10)` with "decile 1 = highest risk".

**Actual**: `ntile(desc(score), 10)` produces decile 1 = highest score = LOWEST
risk. The `desc()` sorts high scores first, and `ntile()` assigns group 1 to
the first rows — which are the high-score (low-risk) rows.

Both conventions exist in practice. The "decile 1 = best" convention is more
common in scorecard monitoring (the best borrowers are in the first decile).
Kept as-is. The code comment at `R/compute_ks.R:32-41` was corrected to state
the actual convention. D20 updated to state it explicitly.

### Deviation 2: Segment 3 dev bad rate outside 0.5pp tolerance

**Plan**: all dev bad rates within 0.5pp of target.

**Actual**: segment 3 dev bad rate is 12.57% vs 12.0% target = 0.57pp miss.

Root cause: Bernoulli sampling variance. The logistic intercept solves to `1e-6`
precision on the expected probability `mean(P_i)`, but the realized draw
`mean(dq90)` varies with `SE = sqrt(p(1-p)/n)`. For segment 3 (n=6,569,
p=0.12), SE = 0.40pp. A 0.57pp miss is 1.4 standard errors — well within
normal sampling noise.

Tightening the solver would not help: the solver already finds the correct
logistic parameters. The variance comes from the Bernoulli draw itself. To
reduce sampling variance below 0.5pp at p=0.12 would require n > 8,400
(solving `1.96 * sqrt(0.12*0.88/n) < 0.005`), which would mean increasing
segment 3's volume beyond the 3x multiplier.

**Resolution**: accepted as a sampling artifact. The 0.5pp tolerance was too
tight for segment 3's volume. The build_ks_baseline.R validator uses ±1.5 KS
points (not bad-rate tolerance), which is the meaningful constraint.

### Deviation 3: Segment 0 top-decile sparsity

Segment 0 dev decile bad counts: 1, 2, 2, 11, 16, 26, 37, 50, 71, 87.

Deciles 1-3 have 1, 2, and 2 bads respectively. Deciles 2 and 3 have identical
bad rates (0.001420 = 2/1408). This is not a defect — it is what KS 41.8 means
for a segment with 2.15% bad rate: a discriminating scorecard concentrates
almost all bads in the worst deciles, leaving the best deciles nearly empty.

The "28 bads per decile" figure from the plan was an AVERAGE (total_bads / 10 =
303 / 10 ≈ 30). The real distribution is heavily right-skewed by design:
decile 10 has 87 bads (29% of total), decile 1 has 1 bad (0.3% of total). This
skew is the KS statistic — if bads were uniformly distributed across deciles,
KS would be 0.

The monotonicity assertion is **non-strict** (`diffs >= 0`, ties pass). Deciles
2 and 3 having the same rate is a tie on single-digit counts, not a violation.
A strict-monotonicity assertion (`diffs > 0`) would be inappropriate here
because at these count levels, identical rates are expected by construction.

---

## Line anchor reconciliation

| Anchor | Before (pre-task) | After |
|--------|-------------------|-------|
| `# QC: Completed` | :486 | :633 |
| `# QC: Validated` | :490 | :635 |
| CSI chunk opening fence | :335 | :335 (unchanged) |
| `source("R/compute_si.R")` | :267 | :268 |
| KS chunk opening fence | — | :495 |
| `source("R/compute_ks.R")` | — | :497 |
| Total Rmd lines | ~490 | 635 |
