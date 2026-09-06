# Pass 2 — Plan: create-features-table

Date: 2026-09-06

## Corrected RNG reasoning (from Pass 1)

Pass 1 claimed adding sample() calls would shift the RNG stream and break PSI.
This is wrong. PSI is RNG-invariant because:

1. Bin counts come from `deterministic_allocate()` — no randomness.
2. Scores are integers from `sample(lo:hi)` with `lo = breaks[j] + 1L` for j > 1.
3. The +1L offset ensures every integer maps back to its originating bin under
   `cut(right=TRUE, include.lowest=TRUE)` — no boundary leakage.
4. PSI = f(bin counts / N) — which specific scores fall in each bin is irrelevant.

**Empirical confirmation (VERIFIED):** `generate_cohort(seed=42)` and
`generate_cohort(seed=43)` produce bit-identical PSI tables across all 20
segment-quarter cells.

The integer sampling with +1L boundary alignment is why this works. If scores
were continuous (e.g., runif()) and rounded, boundary leakage could make PSI
wobble — but that's not the case here.

**Decision:** Keep a separate RNG stream for features anyway. Independent streams
per concern is good practice and makes the invariance argument unnecessary.
Feature generation uses `set.seed(seed + 1000L)` after all apps+scorecard
generation is complete, in a second pass over the data.

## Feature row population

Features are generated for ALL apps rows that have a non-NA user_ref_num. This
includes noise rows (SEC/MSC, null_score, null_seg) — not just the core rows
that survive Rmd filters. Rationale:

- More realistic: in production, the features table has a row for every
  applicant, not just those passing downstream filters.
- Simpler: no need to track which rows survive filters during generation.
- The no_match rows (have apps row but no scorecard) get features too — they
  have a user_ref_num. Only the 2 NULL-URN rows in minimal seed are excluded.

For drift: only core rows (those with a known segment and non-NA prim_score)
get segment-specific drift applied. Noise rows get alpha=0 (baseline
distribution). This matches production reality — CSI is computed on the
filtered population, and the filtered population IS the core rows.

DoD check "every apps user_ref_num has a features row" asserts: for every
non-NA user_ref_num in apps, a matching row exists in features.

## Implementation plan

### Step 1: `sql/03_create_features_table.sql` (new)

```sql
CREATE TABLE features (
  user_ref_num VARCHAR(14) PRIMARY KEY,
  feature_date DATE        NOT NULL,
  feature_1    NUMERIC,
  feature_2    NUMERIC,
  feature_3    NUMERIC,
  feature_4    TEXT,
  feature_5    TEXT
);
```

feature_date = dt_entered from the matching application. The pull function
filters on feature_date by month, same window as apps/scorecard.

### Step 2: Generalize solver in `R/generate_cohort.R`

Replace three functions with generalized versions. All three accept an optional
`dev_weights` parameter (default NULL = uniform).

**`psi_from_alpha(alpha, n_bins, dev_weights = NULL)`**
```r
psi_from_alpha <- function(alpha, n_bins = 20L, dev_weights = NULL) {
  if (alpha == 0) return(0)
  q <- if (is.null(dev_weights)) rep(1 / n_bins, n_bins) else dev_weights
  n <- length(q)
  i <- seq_len(n)
  t_i <- (n + 1 - 2 * i) / (n - 1)
  raw <- q * (1 + alpha * t_i)
  w <- raw / sum(raw)
  sum((w - q) * log(w / q))
}
```

**`solve_alpha(target_psi, n_bins, dev_weights = NULL, tol = 1e-6)`**
```r
solve_alpha <- function(target_psi, n_bins = 20L, dev_weights = NULL, tol = 1e-6) {
  if (target_psi == 0) return(0)
  lo <- 0; hi <- 0.99
  for (iter in seq_len(100)) {
    mid <- (lo + hi) / 2
    psi_mid <- psi_from_alpha(mid, n_bins, dev_weights)
    if (abs(psi_mid - target_psi) < tol) return(mid)
    if (psi_mid < target_psi) lo <- mid else hi <- mid
  }
  mid
}
```

**`tilt_weights(alpha, n_bins, dev_weights = NULL)`**
```r
tilt_weights <- function(alpha, n_bins = 20L, dev_weights = NULL) {
  q <- if (is.null(dev_weights)) rep(1 / n_bins, n_bins) else dev_weights
  n <- length(q)
  i <- seq_len(n)
  t_i <- (n + 1 - 2 * i) / (n - 1)
  raw <- q * (1 + alpha * t_i)
  raw / sum(raw)
}
```

**Subsumption verification** (VERIFIED): When dev_weights = NULL (uniform),
the generalized formula recovers the current formula exactly. sum(t_i) = 0
makes sum(raw) = sum(q * 1) = 1 (since q sums to 1), so w_i = q_i * (1 +
alpha * t_i) = (1 + alpha * t_i) / n. Matches the original.

**Additional verification** (VERIFIED):
- 4-level (0.45/0.30/0.15/0.10), alpha=0.835 -> CSI=0.2799 (brief: 0.280)
- 3-level (0.60/0.30/0.10), alpha=0.850 -> CSI=0.2798 (brief: 0.280)
- Uniform 20-bin, alpha=0.814: current and generalized both return 0.299659

### Step 3: Feature definitions (constants at top of generate_cohort.R)

```r
feature_defs <- list(
  feature_1 = list(type = "continuous", n_bins = 10L,
                   range = c(0, 1000)),
  feature_2 = list(type = "continuous", n_bins = 8L,
                   range = c(0, 500)),
  feature_3 = list(type = "continuous", n_bins = 5L,
                   range = c(0, 100)),
  feature_4 = list(type = "categorical", levels = c("A", "B", "C", "D"),
                   dev_weights = c(0.45, 0.30, 0.15, 0.10)),
  feature_5 = list(type = "categorical", levels = c("X", "Y", "Z"),
                   dev_weights = c(0.60, 0.30, 0.10))
)
```

This list declares the type alongside the parameters, so downstream code
(build-feature-breaks, build-csi-calculation) can dispatch on `$type` rather
than branching on feature name. Continuous features have `dev_weights = NULL`
(uniform by construction from quantile bins).

### Step 4: Feature CSI target matrix (default parameter)

New parameter `feature_targets` on `generate_cohort()`. Structure: named list
keyed by quarter label, each containing a named list keyed by segment, each
containing a named numeric vector keyed by feature name.

```r
feature_targets = list(
  "2025-10-01" = list(
    "0" = c(f1=0, f2=0, f3=0, f4=0, f5=0),
    "1" = c(f1=0, f2=0, f3=0, f4=0, f5=0),
    ...
  ),
  "2026-01-01" = list(
    "0" = c(f1=0.07, f2=0.005, f3=0.0475, f4=0.0025, f5=0.0075),
    ...
  ),
  ...
)
```

Q1 = Q3 * 1/4, Q2 = Q3 * 1/2, Q4 = all zeros.

**Validation** (at top of generate_cohort body):
```r
stopifnot("feature_targets quarters must match quarters" =
            identical(sort(names(feature_targets)), sort(names(quarters))))
for (qt in names(feature_targets)) {
  stopifnot("feature_targets segments must match" =
              identical(sort(names(feature_targets[[qt]])),
                        sort(names(quarters[[qt]]))))
}
```

Fails loudly on mismatch.

### Step 5: Feature generation in generate_cohort()

**Placement:** After the existing per-quarter loop completes (after :343),
in a separate phase. Uses `set.seed(seed + 1000L)` for an independent RNG
stream (defensive, not required — PSI is RNG-invariant).

**Algorithm for each quarter:**
1. Identify core rows: those with non-NA segment AND non-NA prim_score
   (equivalent to has_scorecard AND has segment AND has prim_score).
   Actually: we need segment info, which lives in scorecard_df. Join
   apps_df to scorecard_df on user_ref_num to get segment.
2. For each segment in 0-4:
   - For each feature in feature_defs:
     - Look up CSI target from feature_targets
     - Solve alpha: `solve_alpha(target, n_bins, dev_weights)`
     - Compute tilted weights: `tilt_weights(alpha, n_bins, dev_weights)`
     - Allocate counts: `deterministic_allocate(N_seg, weights)`
     - Generate values:
       - Continuous: draw from quantile bin ranges (analogous to scores_in_bin)
       - Categorical: assign level labels by count
3. For noise rows (not in core): generate with alpha=0 (baseline distribution).
4. Assign feature_date = dt_entered from apps_df.

**Continuous value generation:**
Quantile bins on [lo, hi] with n_bins evenly-spaced breaks:
  breaks = seq(lo, hi, length.out = n_bins + 1)
  bin j: draw runif(count_j, breaks[j], breaks[j+1])

Note: continuous features use runif, not integer sampling, so boundary
alignment matters. With runif and right-open bins, values at exact boundaries
could leak. Using `runif(n, breaks[j] + eps, breaks[j+1])` for j > 1 avoids
this, but since we're not computing CSI in this task (just generating data),
the exact bin membership will be validated by build-feature-breaks/
build-csi-calculation. For generation, we need counts to be correct — draw
within the interior of each bin.

Simpler approach: generate values as `breaks[j] + runif(n) * (breaks[j+1] - breaks[j])`
which is in [breaks[j], breaks[j+1]). For the last bin, use `breaks[j] + runif(n) * (breaks[j+1] - breaks[j])` capped at breaks[j+1]. Since CSI computation will re-derive quantile breaks from the dev cohort, exact boundary alignment isn't critical — what matters is that count allocation is deterministic.

**Categorical value generation:**
Simply `rep(levels, times = counts)` — no randomness in values, only in
ordering (which doesn't affect CSI).

### Step 6: `R/pull_features.R` (new, ~45 lines)

Mirror `R/pull_apps.R`:
```r
source(here::here("R/db.R"))

get_features_data <- function(performance_window, write = TRUE) {
  conn <- db_connect()
  on.exit(DBI::dbDisconnect(conn))

  # -- Type contract (Postgres DDL source) --------------------------------
  # user_ref_num  VARCHAR(14)  NOT NULL  PK, join key -> apps/scorecard (D9)
  # feature_date  DATE         NOT NULL  pull filter column
  # feature_1     NUMERIC      NULL      continuous, 10 quantile bins
  # feature_2     NUMERIC      NULL      continuous, 8 quantile bins
  # feature_3     NUMERIC      NULL      continuous, 5 quantile bins
  # feature_4     TEXT         NULL      categorical, 4 levels (A/B/C/D)
  # feature_5     TEXT         NULL      categorical, 3 levels (X/Y/Z)

  df <- DBI::dbGetQuery(conn, glue::glue("
    SELECT user_ref_num, feature_date, feature_1, feature_2, feature_3,
           feature_4, feature_5
    FROM features
    WHERE feature_date >= '{lubridate::floor_date(performance_window[1], 'month')}'
      AND feature_date <= '{lubridate::ceiling_date(performance_window[1], 'month') - 1}'
  "))

  if (write == TRUE) {
    data.table::fwrite(
      x = df,
      file = glue::glue(here::here(
        "data/features/features_{format(as.Date(min(performance_window)), '%Y%m')}.txt.gz"
      )),
      sep = ",", compress = "auto", append = FALSE,
      scipen = 999, showProgress = TRUE
    )
  }
  return(df)
}
```

### Step 7: `R/setup_supabase.R` modifications

```r
# Add after existing DROP statements:
DBI::dbExecute(conn, "DROP TABLE IF EXISTS features CASCADE")

# Add after 01_create_tables.sql execution:
execute_sql_file(conn, here::here("sql/03_create_features_table.sql"))

# In generated mode, add:
DBI::dbAppendTable(conn, "features", result$features)

# Update message to include features count
```

### Step 8: `sql/02_seed_minimal.sql` — append features

40 features rows matching the 40 scorecard URNs (10000000000001-10000000000040).
feature_date = same date as the corresponding app's dt_entered.
Feature values: plausible mix of continuous values and categorical levels.
Segment-aware drift not needed for minimal seed — just realistic-looking values.

### Step 9: `data/features/.gitkeep` (new)

Empty file. `.gitignore` already covers `data/**/*.txt.gz`.

### Step 10: Documentation updates

**D17 in decisions.md:**
Feature design: 5 features (3 continuous, 2 categorical). Categorical dev
reference carries real proportions, not uniform. Generalized solver subsumes
uniform case. Feature table at D9 grain (one row per user_ref_num).

**CLAUDE.md:**
- Add `get_features_data()` to pull function contracts table
- Add `features` to Supabase tables table
- Add generate_cohort's new `feature_targets` parameter
- Add `create-features-table` to completed list

**R/CATALOG.md:** Add `pull_features.R` entry.
**data/CATALOG.md:** Add `data/features/` entry.

## Execution order

1. `sql/03_create_features_table.sql` — no dependencies
2. Generalize solver in `R/generate_cohort.R` — verify uniform case still works
3. Add feature_defs, feature_targets, validation, generation to generate_cohort.R
4. `R/pull_features.R` — no dependencies beyond db.R
5. `R/setup_supabase.R` — depends on step 1 and 3
6. `sql/02_seed_minimal.sql` — append features rows
7. `data/features/.gitkeep`
8. Run `generate_cohort()`, verify:
   - PSI unchanged (4 x 6 table)
   - Feature CSI targets met (achieved vs target)
   - Min bin/level count >= 50
9. Documentation (D17, CLAUDE.md, catalogs)

## Risks

1. **Continuous feature boundary alignment**: runif() values at bin edges could
   cause off-by-one in CSI computation later. Mitigated: CSI computation
   (build-csi-calculation) will derive its own breaks from dev data, so
   generation just needs approximately correct counts.

2. **feature_targets default parameter size**: 4 quarters x 5 segments x 5
   features = 100 values. The default will be verbose but explicit. Could
   build it programmatically from Q3 targets + scaling factors to reduce
   copy-paste errors.
