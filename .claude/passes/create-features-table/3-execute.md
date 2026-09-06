# Pass 3 — Execute: create-features-table

Date: 2026-09-06  ·  Branch: pass3/create-features-table

## What was implemented

### `sql/03_create_features_table.sql` (NEW, 14 lines)

Features table at D9 grain (one row per user_ref_num). 3 continuous NUMERIC
columns (feature_1-3), 2 categorical TEXT columns (feature_4-5), feature_date
DATE for monthly pull filtering.

### `R/pull_features.R` (NEW, ~45 lines)

Mirrors `R/pull_apps.R` exactly: source db.R, type contract comment block,
glue SQL with floor_date/ceiling_date on feature_date, on.exit(dbDisconnect),
fwrite to `data/features/features_YYYYMM.txt.gz` with scipen=999.

### `R/generate_cohort.R` (MODIFIED, 367 -> ~520 lines)

**Generalized solver (D17):**

`psi_from_alpha`, `solve_alpha`, `tilt_weights` accept optional `dev_weights`
for non-uniform dev distributions (categorical features). When dev_weights is
NULL, uniform 1/n_bins is used, recovering the original formula exactly. For
uniform q, sum(q_i * t_i) = 0, so the normalization denominator equals
sum(q_i) = 1 and w_i = q_i * (1 + alpha * t_i) = (1 + alpha * t_i) / n. For
non-uniform q, sum(q_i * (1 + alpha * t_i)) != 1 in general; the code
normalizes correctly via `raw / sum(raw)`.

`solve_alpha` accepts `tilt_dir` parameter. Returns positive alpha; evaluates
PSI at `alpha * tilt_dir` during bisection. This makes direction-dependent PSI
(non-uniform dev) solve correctly.

**Feature definitions (top-level constant):**

```r
feature_defs <- list(
  feature_1 = list(type = "continuous", n_bins = 10L, range = c(0, 1000), tilt_dir = 1L),
  feature_2 = list(type = "continuous", n_bins = 8L,  range = c(0, 500),  tilt_dir = 1L),
  feature_3 = list(type = "continuous", n_bins = 5L,  range = c(0, 100),  tilt_dir = 1L),
  feature_4 = list(type = "categorical", levels = c("A","B","C","D"),
                   dev_weights = c(0.45, 0.30, 0.15, 0.10), tilt_dir = -1L),
  feature_5 = list(type = "categorical", levels = c("X","Y","Z"),
                   dev_weights = c(0.60, 0.30, 0.10), tilt_dir = -1L)
)
```

Categorical tilt_dir = -1 so mass moves toward minority levels (D→10%, Z→10%).
Models channel-mix drift away from the dominant source.

**Feature targets default builder:**

`feature_targets = NULL` builds from Q3 CSI targets scaled 0/0.25/0.50/1.00.
Validated against `quarters` parameter: `setequal()` on quarter labels and
segment sets, fails loudly on mismatch.

**Phase 2 feature generation:**

Independent RNG stream (`set.seed(seed + 1000L)`) after Phase 1 completes.
PSI is RNG-invariant (verified: seed=42 vs seed=43 bit-identical), so separate
stream is defensive practice.

Core population filter (same as Rmd): `client_product_cd %in% CC/PLAT/GOLD`,
non-null prim_score, non-null segment. Core rows get per-segment drift;
non-core rows get alpha=0 (baseline distribution).

Features generated for ALL apps rows with non-NA user_ref_num. Asserted:
every non-NA URN in apps has a features row.

**`generate_feature_values` helper:**

Continuous: `runif()` within evenly-spaced bins on the feature range.
Categorical: `rep(levels, times = counts)`. Both shuffled to avoid bin-order
artifacts.

### `R/setup_supabase.R` (MODIFIED)

Added `DROP TABLE IF EXISTS features CASCADE`, `execute_sql_file` for
`03_create_features_table.sql`, `dbAppendTable` for features in generated mode.
Updated messages to include features count.

### `sql/02_seed_minimal.sql` (MODIFIED)

Appended 40 features rows matching scorecard URNs 01-40. feature_date matches
corresponding app dt_entered. Baseline distributions: f1~U[0,1000],
f2~U[0,500], f3~U[0,100], f4~(A=18,B=12,C=6,D=4), f5~(X=24,Y=12,Z=4).

### `data/features/.gitkeep` (NEW)

## Deviations from spec

None.

## Verification

### PSI unchanged (VERIFIED — 4 x 6 table)

```
Segment            2025 Q4    2026 Q1    2026 Q2    2026 Q3
All Segments        0.0111     0.0209     0.0442     0.0847
0                   0.0000     0.0801     0.1795     0.3000
1                   0.0000     0.0299     0.0500     0.0900
2                   0.0000     0.0499     0.1201     0.2501
3                   0.0000     0.0200     0.0300     0.0401
4                   0.0000     0.0401     0.0801     0.1498
```

Identical to pre-feature-generation values.

### CSI achieved vs target (core population only, VERIFIED)

Max |delta| = 0.0011. All 100 cells within 0.002 of target.

**Q4 2025 (all zero — self-test):** All 25 cells exactly 0.0000. PASS.

**Q3 2026 (full drift — hardest test):**

```
Seg  feature_1  feature_2  feature_3  feature_4  feature_5
     ach/tgt    ach/tgt    ach/tgt    ach/tgt    ach/tgt
0    .2796/.28  .0199/.02  .1889/.19  .0100/.01  .0299/.03
1    .0405/.04  .0202/.02  .0503/.05  .0100/.01  .0200/.02
2    .2201/.22  .0300/.03  .0601/.06  .0200/.02  .0400/.04
3    .0198/.02  .0097/.01  .0200/.02  .0100/.01  .0101/.01
4    .1098/.11  .0199/.02  .0400/.04  .0200/.02  .0299/.03
```

**Q1 2026 (~1/4 drift):**

```
Seg  feature_1  feature_2  feature_3  feature_4  feature_5
0    .0699/.07  .0049/.005 .0474/.0475 .0025/.0025 .0075/.0075
1    .0101/.01  .0051/.005 .0124/.0125 .0025/.0025 .0050/.005
2    .0550/.055 .0074/.0075 .0150/.015 .0050/.005  .0100/.01
3    .0051/.005 .0024/.0025 .0051/.005 .0025/.0025 .0025/.0025
4    .0277/.0275 .0049/.005 .0100/.01  .0050/.005  .0075/.0075
```

**Q2 2026 (~1/2 drift):**

```
Seg  feature_1  feature_2  feature_3  feature_4  feature_5
0    .1398/.14  .0098/.01  .0945/.095  .0050/.005  .0150/.015
1    .0201/.02  .0101/.01  .0251/.025  .0050/.005  .0100/.01
2    .1097/.11  .0150/.015 .0300/.03   .0100/.01   .0199/.02
3    .0101/.01  .0049/.005 .0100/.01   .0050/.005  .0050/.005
4    .0550/.055 .0099/.01  .0199/.02   .0100/.01   .0150/.015
```

### Minimum bin/level count (VERIFIED)

| Quarter | Feature min count | PSI min bin |
|---|---|---|
| Q4 2025 | 550 | 275 |
| Q1 2026 | 327 | 150 |
| Q2 2026 | 241 | 94 |
| Q3 2026 | 135 | 51 |

All >= 50. PASS.

### Generator assertions

- No duplicate user_ref_num in features: PASS
- No duplicate user_ref_num in scorecard: PASS
- No duplicate app_num in applications: PASS
- All non-NA apps URNs have features rows: PASS

### Row counts

- apps: 141,720 (unchanged)
- scorecard: 136,840 (unchanged)
- features: 141,720 (= apps, one row per user_ref_num)

## Documentation updated

| File | What changed |
|---|---|
| `.claude/docs/decisions.md` | D17 added: feature design, generalized solver, categorical tilt direction, RNG invariance, core population CSI filter |
| `CLAUDE.md` | Added create-features-table to completed list. Updated next sequence. Added get_features_data and generate_cohort signature to contracts. Added features table. Updated load modes. D1-D16 -> D1-D17. |
| `R/CATALOG.md` | Added pull_features.R. Updated generate_cohort.R description and signature. |
| `data/CATALOG.md` | Added data/features/ entry. |
