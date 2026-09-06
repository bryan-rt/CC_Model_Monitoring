# feature_breaks.R
#
# Frozen feature binning reference for CSI calculation (D18).
# Analogous to segment_breaks for PSI — computed once from the development
# population and held fixed. If re-derived from each cohort, CSI would always
# be ~0 (the same trap as PSI with re-derived vigintiles).
#
# Continuous breaks are the generator's evenly-spaced bin boundaries — the
# development population's deciles by construction. Categorical dev_counts
# are the declared level proportions scaled to a common total.
#
# Global (not per-segment): the generator draws features from identical
# distributions for all segments. Per-segment breaks would be identical.
# Known simplification: in production, segments have different feature
# distributions and would carry different cutpoints.
#
# All five features describe the SAME development population of 10,000
# applicants, binned five different ways. dev_counts is the single source
# of truth; dev_props for categorical features is derived (asserted by
# R/build_feature_breaks.R).
#
# DO NOT edit these values without re-running R/build_feature_breaks.R.

feature_breaks <- list(
  feature_1 = list(
    type = "continuous",
    breaks = seq(0, 1000, length.out = 11),
    dev_counts = rep(1000L, 10)
  ),
  feature_2 = list(
    type = "continuous",
    breaks = seq(0, 500, length.out = 9),
    dev_counts = rep(1250L, 8)
  ),
  feature_3 = list(
    type = "continuous",
    breaks = seq(0, 100, length.out = 6),
    dev_counts = rep(2000L, 5)
  ),
  feature_4 = list(
    type = "categorical",
    levels = c("A", "B", "C", "D"),
    dev_counts = c(4500L, 3000L, 1500L, 1000L)
  ),
  feature_5 = list(
    type = "categorical",
    levels = c("X", "Y", "Z"),
    dev_counts = c(6000L, 3000L, 1000L)
  )
)
