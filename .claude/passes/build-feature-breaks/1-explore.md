# Pass 1 — Explore: build-feature-breaks

Date: 2026-09-06

## Empirical inspection of generated feature data (Q4 2025, core population)

Generated with `generate_cohort(seed = 42)`, filtered to core population
(client_product_cd in CC/PLAT/GOLD, non-null prim_score, non-null segment),
Q4 2025 only. N = 30,500.

### Continuous features — ranges and empirical quantiles

| Feature | n_bins | Min | Max | Mean | SD |
|---|---|---|---|---|---|
| feature_1 | 10 | 0.0229 | 999.9627 | 500.00 | 288.89 |
| feature_2 | 8 | 0.0355 | 499.9676 | 249.97 | 144.42 |
| feature_3 | 5 | 0.0041 | 99.9991 | 50.05 | 28.93 |

Empirical quantile breaks (from the actual data, not the nominal range):

**feature_1** (11 cutpoints for 10 bins):
  0.02, 100.00, 200.04, 300.02, 400.00, 499.96, 600.02, 699.98, 799.98,
  899.91, 999.96

**feature_2** (9 cutpoints for 8 bins):
  0.04, 62.45, 124.95, 187.45, 249.88, 312.45, 374.88, 437.46, 499.97

**feature_3** (6 cutpoints for 5 bins):
  0.00, 20.00, 40.00, 60.00, 80.00, 100.00

Bin counts are EXACTLY uniform:
  feature_1: 3050 per bin (10 bins, total 30500)
  feature_2: 3813 or 3812 per bin (8 bins, total 30500, remainder distributed)
  feature_3: 6100 per bin (5 bins, total 30500)

Max deviation from 1/n_bins: 0.0000 (0.00%) for all three features.

This is because `deterministic_allocate()` with alpha=0 assigns exactly
N/n_bins (or N/n_bins +/- 1 for the remainder) counts per bin, and values are
drawn inside each bin via `runif()`. The quantile breaks then recover this
exact allocation. The breaks are close to the evenly-spaced nominal range
(0/100/200/.../1000 for f1) but not identical due to runif() sampling variation.

### Categorical features — level counts

**feature_4**: A=13725 (0.4500), B=9150 (0.3000), C=4575 (0.1500), D=3050 (0.1000)
  Total: 30,500. All 4 levels present.

**feature_5**: X=18300 (0.6000), Y=9150 (0.3000), Z=3050 (0.1000)
  Total: 30,500. All 3 levels present.

Proportions match dev_weights EXACTLY. This is deterministic_allocate at work.

### Per-segment dev counts

  segment 0: 5,500
  segment 1: 8,000
  segment 2: 6,000
  segment 3: 5,500
  segment 4: 5,500

These are exactly segment_volumes. Global bins are appropriate: the generator
draws features from the same distributions for every segment, so per-segment
quantiles would be identical.

## Existing pattern: build_dev_population.R

`R/build_dev_population.R` (62 lines):
- Hardcodes `segment_breaks` (frozen D15, third copy)
- Builds a data.frame: Scorecard, Lower_Range, Upper_Range, counts_dev
- 1000 per bin for segments 0-4, 5000 per bin for All Segments
- Writes CSV via `fwrite()` to `data/dev_population/dev_population.txt.gz`
- Called at `orchestration_2.Rmd:266-267`

Key difference: PSI breaks are hardcoded integers. Feature breaks must be
derived from empirical quantiles (continuous features), which depend on the
random seed. Once computed and written to disk, they are frozen.

## Output format decision

PSI dev population uses CSV because it's a flat data.frame (Scorecard,
Lower_Range, Upper_Range, counts_dev). Feature breaks are a nested list with
mixed types (continuous breaks + categorical levels/props). Two options:

**Option A: RDS file** — preserves the list structure exactly. `saveRDS()` /
`readRDS()`. Simple, native R, but not human-readable.

**Option B: CSV flat file + separate structure** — would need to encode type,
feature name, bin index, break values, levels, and dev counts in a flat table.
Awkward for categorical features.

**Recommendation: RDS.** The structure carries its own schema ($type field per
entry). The Rmd reads it with `readRDS()` — one line. The 3-execute artifact
records the exact break values for human audit.

Output path: `data/feature_breaks/feature_breaks.rds`
Companion: `data/feature_breaks/.gitkeep` (not needed — the RDS is committed,
unlike the gzipped CSV data files which are gitignored. But RDS should also be
gitignored since it's derived from the generator.)

Wait — should the RDS be committed or gitignored? PSI's dev_population.txt.gz
IS gitignored (`data/**/*.txt.gz`). But .rds files are NOT currently gitignored
(only `data/*.rds` is in .gitignore, and this is in `data/feature_breaks/`
which matches `data/**/*.rds` — but that glob isn't in .gitignore).

Current .gitignore:
```
data/*.csv
data/*.rds
data/*.xlsx
data/**/*.txt.gz
```

`data/feature_breaks/feature_breaks.rds` matches `data/**/*.rds`? No — the
existing pattern `data/*.rds` does NOT match subdirectories. Need to check.

`data/*.rds` only matches `data/foo.rds`, not `data/feature_breaks/foo.rds`.
So the RDS would be committed by default. The brief says the file is the
authority and should be frozen — committing it IS the freeze mechanism. Unlike
the gzipped data files (which are large and regenerated), the breaks file is
small and should be version-controlled.

**Decision: commit the RDS.** It's the frozen reference. Regeneration is
explicit (re-run the script). No .gitkeep needed — the RDS itself tracks
the directory.

## Proposed structure for feature_breaks

```r
feature_breaks <- list(
  feature_1 = list(
    type = "continuous",
    n_bins = 10L,
    breaks = c(0.02, 100.00, 200.04, 300.02, 400.00, 499.96,
               600.02, 699.98, 799.98, 899.91, 999.96),
    dev_counts = rep(1000L, 10)
  ),
  feature_2 = list(
    type = "continuous",
    n_bins = 8L,
    breaks = c(0.04, 62.45, 124.95, 187.45, 249.88,
               312.45, 374.88, 437.46, 499.97),
    dev_counts = rep(1000L, 8)
  ),
  feature_3 = list(
    type = "continuous",
    n_bins = 5L,
    breaks = c(0.00, 20.00, 40.00, 60.00, 80.00, 100.00),
    dev_counts = rep(1000L, 5)
  ),
  feature_4 = list(
    type = "categorical",
    levels = c("A", "B", "C", "D"),
    dev_props = c(0.45, 0.30, 0.15, 0.10),
    dev_counts = c(4500L, 3000L, 1500L, 1000L)
  ),
  feature_5 = list(
    type = "categorical",
    levels = c("X", "Y", "Z"),
    dev_props = c(0.60, 0.30, 0.10),
    dev_counts = c(6000L, 3000L, 1000L)
  )
)
```

## Files to create/modify

| File | Action | Purpose |
|---|---|---|
| `R/build_feature_breaks.R` | CREATE | Script: generates cohort, computes quantile breaks from Q4 2025 core, writes RDS |
| `data/feature_breaks/feature_breaks.rds` | CREATE | Frozen breaks file (committed, not gitignored) |
| `.claude/docs/decisions.md` | MODIFY | D18: frozen breaks, global vs per-segment |
| `CLAUDE.md` | MODIFY | Add build_feature_breaks to contracts, completed list |
| `R/CATALOG.md` | MODIFY | Add build_feature_breaks.R |
| `data/CATALOG.md` | MODIFY | Add data/feature_breaks/ |

## Key constraint: no R/generate_cohort.R modifications

If any break vector disagrees with feature_defs: STOP and report. The empirical
data shows perfect agreement — ranges match, levels match, proportions match.

## Global vs per-segment: GLOBAL recommended

The generator draws features from the same distributions for every segment
(same ranges, same level proportions). Per-segment quantiles would be identical.
Global breaks are correct and carry 5 definitions instead of 30.

Known simplification: in production, segments genuinely have different feature
distributions and would carry different cutpoints.

Consequence: at alpha=0, global bins produce exactly uniform counts for ALL
populations (including pooled All Segments). CSI at Q4 2025 will be exactly
0.0000 — no re-binning residual. This is a TIGHTER self-test than PSI's 0.0111.

## Predicted All Segments CSI under global bins (Q3 2026)

Segments 1, 3, 4 are near flat. When pooled, the aggregate CSI sits well below
the segment maximum. Expected:
  feature_1 ~ 0.101 (segment max 0.2796)
  feature_3 ~ 0.060 (segment max 0.1889)
Same pattern as PSI: "All Segments" < max(per-segment).
