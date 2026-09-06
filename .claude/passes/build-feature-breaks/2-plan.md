# Pass 2 — Plan: build-feature-breaks

Date: 2026-09-06

## Corrections from Pass 1

### 1. Use generator boundaries, not empirical quantiles

Pass 1 reported "0.00% deviation" AND "breaks not identical to nominal range" —
a contradiction. The generator (`generate_cohort.R:152`) draws runif() inside
evenly-spaced bins:

```r
breaks <- seq(fdef$range[1], fdef$range[2], length.out = fdef$n_bins + 1L)
```

So feature_1 bins are exactly 0, 100, 200, ..., 1000. The bin boundaries
already exist and are exact. Using empirical quantiles would add sampling noise
for no gain.

Using the generator boundaries:
- Binning the flat cohort gives EXACTLY uniform counts (deterministic_allocate
  assigns exactly N/n_bins per bin, and every runif() draw stays inside its bin)
- All Segments CSI at alpha=0 is EXACTLY 0.0000
- The DoD tightens from "< 2% deviation" to exact equality for continuous
  features on the flat cohort

Framing for D18: the generator simulates a development population whose
deciles are exactly those boundaries. Self-consistent, and the breaks remain
frozen because they live in a committed file.

### 2. Write R source, not RDS

R/feature_breaks.R contains the list definition as literal R source:
- Diffable, greppable, reviewable
- Follows the same pattern as segment_breaks (literal list() in the Rmd)
- A committed .R file has the same freeze property as an RDS
- Sidesteps the .gitignore question entirely

The Rmd sources R/feature_breaks.R. It does NOT source R/generate_cohort.R —
the breaks are a pipeline input, the generator is a demo artifact.

## Implementation plan

### Step 1: R/feature_breaks.R (NEW, ~45 lines)

Literal list definition. Sourced by the Rmd (and later by build-csi-calculation).

```r
# feature_breaks.R
#
# Frozen feature binning reference for CSI calculation (D18).
# Analogous to segment_breaks for PSI — computed once from the development
# population and held fixed. If re-derived from each cohort, CSI would always
# be ~0 (the same trap as PSI with re-derived vigintiles).
#
# Continuous breaks are the generator's evenly-spaced bin boundaries.
# Categorical dev_props are the declared level proportions.
# Global (not per-segment): the generator draws features from identical
# distributions for all segments.
#
# DO NOT edit these values without re-running R/build_feature_breaks.R.

feature_breaks <- list(
  feature_1 = list(
    type = "continuous",
    n_bins = 10L,
    breaks = seq(0, 1000, length.out = 11),
    dev_counts = rep(1000L, 10)
  ),
  feature_2 = list(
    type = "continuous",
    n_bins = 8L,
    breaks = seq(0, 500, length.out = 9),
    dev_counts = rep(1000L, 8)
  ),
  feature_3 = list(
    type = "continuous",
    n_bins = 5L,
    breaks = seq(0, 100, length.out = 6),
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

Using `seq()` rather than spelling out `c(0, 100, 200, ...)` — it's exact for
integer-aligned breaks and more readable. `seq(0, 1000, length.out = 11)`
produces exactly `c(0, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000)`.

### Step 2: R/build_feature_breaks.R (NEW, ~80 lines)

Script that validates feature_breaks.R against the generator's feature_defs.
NOT sourced by the Rmd — run manually to regenerate or verify.

```r
build_feature_breaks <- function(output_path = here::here("R/feature_breaks.R"),
                                 seed = 42L) {
  # Source generator to get feature_defs
  source(here::here("R/generate_cohort.R"))

  # Source the existing breaks file
  source(output_path)

  # Validate consistency: breaks must match feature_defs
  for (fname in names(feature_defs)) {
    fdef <- feature_defs[[fname]]
    fbrk <- feature_breaks[[fname]]

    stopifnot(paste(fname, "missing from feature_breaks") =
                !is.null(fbrk))
    stopifnot(paste(fname, "type mismatch") =
                fbrk$type == fdef$type)

    if (fdef$type == "continuous") {
      expected_breaks <- seq(fdef$range[1], fdef$range[2],
                             length.out = fdef$n_bins + 1L)
      stopifnot(paste(fname, "n_bins mismatch") =
                  fbrk$n_bins == fdef$n_bins)
      stopifnot(paste(fname, "breaks mismatch") =
                  identical(fbrk$breaks, expected_breaks))
    } else {
      stopifnot(paste(fname, "levels mismatch") =
                  identical(fbrk$levels, fdef$levels))
      stopifnot(paste(fname, "dev_props mismatch") =
                  identical(fbrk$dev_props, fdef$dev_weights))
    }
  }

  # Generate cohort and validate against actual data
  result <- generate_cohort(seed = seed)
  # ... filter to Q4 2025 core, bin with feature_breaks, assert exact uniformity
  # ... assert categorical proportions match dev_props exactly
  # ... assert all feature values fall within declared ranges/levels

  message("feature_breaks.R validated against feature_defs and generated data.")
  invisible(feature_breaks)
}
```

The consistency check:
1. Every feature in feature_defs has a corresponding entry in feature_breaks
2. Types match
3. Continuous breaks = seq(range[1], range[2], length.out = n_bins + 1)
4. Categorical levels and dev_props match
5. Binning the Q4 2025 flat cohort gives exactly uniform continuous counts
6. Categorical proportions in the flat cohort match dev_props exactly
7. Every feature_4/feature_5 value appears in the declared level set

### Step 3: Documentation

**D18 in decisions.md:**
Frozen feature breaks (analogous to D15 for segment_breaks). Global breaks —
one per feature, not per-segment. Generator draws from identical distributions
for all segments, so per-segment breaks would be identical. Known
simplification: production segments have different feature distributions.
Continuous breaks are the generator's evenly-spaced bin boundaries (the
development population's deciles by construction). At alpha=0, All Segments
CSI is exactly 0.0000 — no re-binning residual (tighter self-test than PSI's
0.0111). The breaks live in R/feature_breaks.R as literal R source (diffable,
greppable, reviewable). R/build_feature_breaks.R validates but does not
regenerate — it asserts the committed file matches feature_defs and fails
loudly on mismatch.

**CLAUDE.md:** Add build-feature-breaks to completed list. Add
build_feature_breaks to contracts table. Update next sequence.

**R/CATALOG.md:** Add feature_breaks.R and build_feature_breaks.R entries.

**data/CATALOG.md:** No change needed — the breaks live in R/, not data/.

## Execution order

1. Write R/feature_breaks.R (the frozen breaks definition)
2. Write R/build_feature_breaks.R (the validator/builder)
3. Run build_feature_breaks() — validate + produce DoD evidence
4. Documentation (D18, CLAUDE.md, R/CATALOG.md)
5. 3-execute.md

## DoD checks (tightened)

- Continuous: binning Q4 2025 core with these breaks gives EXACTLY uniform
  counts (not "< 2%" — exact equality)
- Categorical: level proportions in Q4 2025 core match dev_props EXACTLY
- Every feature_4/5 value in the features table appears in the declared level
  set (zero undeclared levels)
- Min bin/level count >= 50; report the minimum
- feature_breaks consistency check passes (breaks match feature_defs)
