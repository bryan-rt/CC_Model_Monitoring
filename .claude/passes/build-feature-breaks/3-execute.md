# Pass 3 — Execute: build-feature-breaks

Date: 2026-09-06  ·  Branch: pass3/build-feature-breaks

## What was implemented

### `R/feature_breaks.R` (NEW, ~50 lines)

Frozen feature binning reference for CSI calculation. Literal R source — a
single `feature_breaks` list with `$type` dispatch field per entry.

- Continuous breaks use `seq()` (generator's evenly-spaced boundaries)
- Categorical entries carry `levels` and `dev_counts`
- `dev_counts` is the single source of truth; categorical `dev_props` is
  derived and asserted by `build_feature_breaks.R`
- All five features total 10,000 (one dev population binned five ways):
  - feature_1: rep(1000L, 10) = 10,000
  - feature_2: rep(1250L, 8) = 10,000
  - feature_3: rep(2000L, 5) = 10,000
  - feature_4: 4500 + 3000 + 1500 + 1000 = 10,000
  - feature_5: 6000 + 3000 + 1000 = 10,000
- No redundant fields: categorical entries do NOT store dev_props (derived
  from dev_counts); continuous entries do NOT store n_bins (= length(breaks)-1)

### `R/build_feature_breaks.R` (NEW, ~160 lines)

Bootstrap and freeze-check script. Two modes:

1. **Bootstrap** (file absent): generates `R/feature_breaks.R` from
   `feature_defs` in `R/generate_cohort.R` via `emit_feature_breaks()` helper
2. **Freeze-check** (file present): validates committed file against
   feature_defs AND against actual generated data

Freeze-check assertions:
- Every feature in feature_defs has a matching entry
- Types match
- Continuous: `breaks == seq(range[1], range[2], length.out = n_bins + 1)`
- Categorical: `levels` match, `dev_counts / sum(dev_counts) == dev_weights`
- All dev_counts totals are equal across features
- Continuous flat cohort counts == pooled per-segment deterministic_allocate
- Categorical flat cohort proportions == dev_counts / sum(dev_counts)
- No undeclared feature_4/feature_5 levels in entire features table
- All bin/level counts >= 50

## Deviations from spec

1. **feature_2 counts not exactly uniform.** 5500/8 = 687.5, so segments 0/3/4
   each contribute a ±1 remainder. Pooled result: bins 1-4 get 3814, bins 5-8
   get 3811 (delta = 3, 0.08%). This is a property of pooling per-segment
   deterministic allocations when n_bins does not divide all segment volumes,
   not a pipeline error. The assertion validates against the pooled
   deterministic_allocate result (exact match) rather than against N/n_bins.

   Feature_1 (10 bins) and feature_3 (5 bins) divide all segment volumes
   evenly and ARE exactly uniform.

## Verification

### Flat-cohort binned counts (Q4 2025 core, N=30,500, VERIFIED)

```
feature_1: 10 bins, all counts = 3050 (exact uniform)
feature_2:  8 bins, counts [3811, 3814] (per-segment remainder, max delta = 3)
feature_3:  5 bins, all counts = 6100 (exact uniform)
feature_4:  4 levels — A=0.4500, B=0.3000, C=0.1500, D=0.1000 (exact)
feature_5:  3 levels — X=0.6000, Y=0.3000, Z=0.1000 (exact)
```

### Flat-cohort CSI residual from feature_2 remainder

feature_2's per-segment remainder stacking produces counts [3814, 3814, 3814,
3814, 3811, 3811, 3811, 3811] against an expected uniform of 3812.5. The
resulting CSI at alpha=0 is **1.548e-07** — not algebraically zero, but seven
orders of magnitude below any meaningful value.

Consequence for build-csi-calculation: the flat-cohort self-test must assert
CSI < 1e-6, NOT == 0. An equality assertion fails on feature_2 for a fully
correct pipeline. The 1e-6 threshold still catches real breakage by a wide
margin — the smallest genuine target in the schedule is 0.01, four orders of
magnitude above it.

### Minimum bin/level count

3050 (feature_1, 30500/10). All >= 50. PASS.

### Undeclared levels

Zero undeclared levels in the entire features table (all 4 quarters). PASS.

### Freeze-check

feature_breaks.R matches feature_defs: PASS.
All dev_counts totals = 10,000: PASS.

### Bootstrap path

Tested: removed R/feature_breaks.R, ran build_feature_breaks() — file
regenerated from feature_defs, all checks passed. PASS.

## Documentation updated

| File | What changed |
|---|---|
| `.claude/docs/decisions.md` | D18 added: frozen feature breaks, global vs per-segment, generator boundaries, dev_counts as single source of truth, bootstrap + freeze-check |
| `CLAUDE.md` | Added build-feature-breaks to completed list. Updated next sequence. Added build_feature_breaks to contracts. D1-D17 -> D1-D18. |
| `R/CATALOG.md` | Added feature_breaks.R and build_feature_breaks.R entries. |
