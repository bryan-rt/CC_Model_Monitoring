# Pass 1 — Explore: create-features-table

Date: 2026-09-06

## Inventory of touched systems

### 1. `R/generate_cohort.R` (367 lines)

**Solver functions that need generalization:**

- `psi_from_alpha(alpha, n_bins)` (:42-48) — hardcodes uniform dev: `p_dev <- 1/n_bins`.
  The tilt formula `w_i = (1 + alpha * (n+1-2i)/(n-1)) / n` assumes flat dev.
  Must generalize to accept a `dev_weights` vector (q_i) so categorical features
  with non-uniform dev proportions produce correct CSI.

- `solve_alpha(target_psi, n_bins)` (:51-62) — wraps `psi_from_alpha`. Must pass
  `dev_weights` through.

- `tilt_weights(alpha, n_bins)` (:65-68) — same formula as `psi_from_alpha`.
  Must accept `dev_weights` and compute:
  `w_i proportional to q_i * (1 + alpha * t_i)`, then normalize to sum=1.
  For uniform q this reduces to the current formula (subsumption check needed).

- `deterministic_allocate(N, weights)` (:71-81) — weight-agnostic, works as-is.

- `scores_in_bin(n, breaks, bin_index)` (:86-96) — integer score sampling for
  continuous bins. Features need an analogous function for continuous features
  (draw from within quantile bins) and categorical features (just assign the level).

**Main generator `generate_cohort()` (:123-366):**

- Currently emits `list(apps, scorecard, meta)`.
- Must add `features` to the output — a data.frame with `user_ref_num`,
  `feature_date`, `feature_1` through `feature_5`.
- Features join to apps on `user_ref_num` with `feature_date` matching the
  app's `dt_entered` month.
- Feature generation occurs inside the per-quarter loop (:142-343), after IDs
  and dates are assigned (:238-250).
- Features are per `user_ref_num`, same grain as scorecard. Only rows with
  `has_scorecard == TRUE` get scorecard rows currently; features could follow
  the same pattern OR cover all rows. Brief says `user_ref_num` is PK in features
  table matching scorecard grain (D9). Since the features table has feature_date
  as the pull filter (analogous to dt_entered/trans_date_ct), features should be
  generated for ALL rows (including noise), so the pull function returns them.

**Drift per feature per segment:**

The brief specifies per-segment, per-feature CSI targets. Each feature's bins
within each segment need their own alpha. This is a nested loop:
  for each quarter -> for each segment -> for each feature -> solve alpha, allocate.

But features are per-user, not per-segment. The segment is known from the
scorecard. So we can condition feature generation on segment membership.

For noise rows (no_match, null_seg), features should still be generated but
with alpha=0 (no drift) since they're filtered out before CSI computation anyway.

### 2. `sql/01_create_tables.sql` (31 lines)

Not modified — features gets its own file `sql/03_create_features_table.sql`.

### 3. `sql/02_seed_minimal.sql` (163 lines)

Needs features rows added. 40 scorecard rows have user_ref_nums — features should
match these 40 URNs. feature_date must match the dt_entered month of the
corresponding application.

### 4. `R/pull_apps.R` (63 lines) — TEMPLATE for `R/pull_features.R`

Pattern to mirror:
- source `R/db.R`
- Type contract comment block above SELECT
- `glue::glue()` SQL with `floor_date`/`ceiling_date` on `performance_window[1]`
- `on.exit(DBI::dbDisconnect(conn))`
- `if (write == TRUE) fwrite()` to `data/features/features_YYYYMM.txt.gz`
  with `scipen = 999, append = FALSE`

Key difference: filter column is `feature_date`, not `dt_entered`.

### 5. `R/setup_supabase.R` (38 lines)

Changes needed:
- Add `DROP TABLE IF EXISTS features CASCADE` (:21-22 area)
- Add `execute_sql_file(conn, here::here("sql/03_create_features_table.sql"))` (:24 area)
- In `minimal` mode: load features seed from `sql/02_seed_minimal.sql` (already
  there if we append features INSERT to that file)
- In `generated` mode: `DBI::dbAppendTable(conn, "features", result$features)` (:32-33 area)

### 6. `data/features/.gitkeep`

Needs creation. No existing `data/*/.gitkeep` files found — the subdirectories
(apps, scorecard, dev_population, etc.) exist as directories tracked by git
through their contents or created at runtime. `.gitignore` already covers
`data/**/*.txt.gz`.

### 7. `orchestration_2.Rmd` — NOT MODIFIED

Brief explicitly says: do not modify anything before :399, do not compute CSI.
The CSI region (:401-453) is untouched by this task.

## Generalization of the solver — mathematical analysis

**Current uniform formula** (`psi_from_alpha`, :42-48):
```
w_i = (1 + alpha * (n+1-2i)/(n-1)) / n
p_dev = 1/n
PSI = sum((w - p_dev) * log(w / p_dev))
```

**Generalized formula** (brief's spec):
```
t_i = (n+1-2i)/(n-1)     # same tilt schedule
w_i proportional to q_i * (1 + alpha * t_i)
normalize: w_i = q_i * (1 + alpha * t_i) / sum(q_j * (1 + alpha * t_j))
PSI = sum((w_i - q_i) * log(w_i / q_i))
```

**Subsumption check**: When q_i = 1/n for all i:
```
w_i = (1/n) * (1 + alpha * t_i) / sum((1/n) * (1 + alpha * t_j))
     = (1 + alpha * t_i) / sum(1 + alpha * t_j)
     = (1 + alpha * t_i) / (n + alpha * sum(t_j))
```
sum(t_j) for j=1..n: sum((n+1-2j)/(n-1)) = sum((n+1-2j)) / (n-1)
  = (n*(n+1) - 2*n*(n+1)/2) / (n-1) = (n(n+1) - n(n+1)) / (n-1) = 0

So denominator = n, and w_i = (1 + alpha*t_i)/n. Matches current formula. CONFIRMED subsumption.

**Brief's verification**: q = c(.45,.30,.15,.10), alpha=0.835 -> CSI=0.280.
Should verify in pass 2 or 3.

## Feature generation strategy

**Continuous features (f1, f2, f3):**
- 10, 8, 5 quantile bins respectively
- Dev distribution is uniform by construction (quantile bins)
- Use uniform dev_weights = rep(1/n, n)
- Generate values as random draws within bin ranges
- Need to define value ranges for each feature. Simplest: feature_1 in [0, 1000],
  feature_2 in [0, 500], feature_3 in [0, 100]. Exact ranges don't matter —
  only the bin counts matter for CSI.
- Quantile break computation: evenly spaced breaks across the range
  (since dev is uniform by construction, the breaks are just linspace)

**Categorical features (f4, f5):**
- 4 levels (A/B/C/D), 3 levels (X/Y/Z) respectively
- Dev proportions: 0.45/0.30/0.15/0.10 and 0.60/0.30/0.10
- Use these as dev_weights in the generalized solver
- Generate values by assigning level labels directly (no range sampling)

## Drift target matrix (from brief)

Q3 2026 targets (full drift):
```
Segment  PSI    f1    f2    f3    f4    f5
0        0.30   0.28  0.02  0.19  0.01  0.03
1        0.09   0.04  0.02  0.05  0.01  0.02
2        0.25   0.22  0.03  0.06  0.02  0.04
3        0.04   0.02  0.01  0.02  0.01  0.01
4        0.15   0.11  0.02  0.04  0.02  0.03
```

Scale for earlier quarters: Q1 ~1/4, Q2 ~1/2, Q4 = 0.

This means the `quarters` parameter structure needs extension, OR a parallel
`feature_targets` parameter. Separate parameter is cleaner — avoids breaking
the existing PSI-only interface.

## Risks and open questions

1. **Seed stability**: Extending `generate_cohort()` adds `sample()` calls
   that consume RNG state. Even though features come AFTER apps+scorecard
   generation, any new `sample()` call before the existing ones would shift
   the RNG stream and change PSI values. Must verify features are generated
   AFTER all existing sample() calls, or use a separate RNG stream.

   Looking at the code flow: the per-quarter loop generates core scores (:166),
   noise rows (:191-224), shuffles (:236), assigns IDs (:239-246), dates (:249),
   filler columns (:253-277), then builds apps/scorecard. Features would go
   AFTER scorecard construction (~:327) but BEFORE the next quarter's iteration.
   This means new sample() calls happen after all existing ones within a quarter.
   BUT: the shuffle at :236 (`sample(n_total)`) and date generation (:249-250)
   use the RNG. If we add feature generation after :250 but before :253,
   it would shift filler columns. If we add it after :327, it's after all
   existing sample() calls for the quarter. **Place feature generation at the
   end of the quarter loop, after scorecard_df is built, to avoid RNG disruption.**

   Wait — the next quarter's iteration starts with a fresh set of sample() calls.
   If we add calls at the end of quarter 1, those consume RNG state and shift
   quarter 2's draws. **This WILL change PSI values.**

   **Mitigation**: Use a separate sub-seed for features. After the existing
   generation, save the RNG state, set a deterministic sub-seed based on
   `seed + q_idx`, generate features, then restore the RNG state. Or simpler:
   restructure so features use their own `set.seed()` after the main generation
   is complete (second pass over the data).

   **Cleanest approach**: Two-phase generation. Phase 1: existing code, unchanged,
   produces apps+scorecard (RNG stream identical). Phase 2: `set.seed(seed + 1000)`
   or similar, generates features for all quarters using the already-created
   apps+scorecard data. This guarantees PSI invariance.

2. **Feature value ranges**: For continuous features, we need ranges to generate
   actual numeric values. The exact values don't matter for CSI (only bin counts
   do), but they need to look plausible. Could use arbitrary ranges.

3. **feature_date alignment**: Brief says feature_date must match the application's
   dt_entered MONTH. Simplest: `feature_date <- dt_entered` (same date). Or
   `floor_date(dt_entered, "month")`. Using dt_entered itself is cleanest — the
   pull function filters by month anyway.

4. **Which rows get features?**: All rows with user_ref_num (since features PK
   is user_ref_num). Rows with NULL user_ref_num (2 in minimal seed) cannot have
   features. For generated data: all rows in all_rows that have non-NA
   user_ref_num should get features.

## Files to create/modify

| File | Action | Lines affected |
|---|---|---|
| `sql/03_create_features_table.sql` | CREATE | New file |
| `R/pull_features.R` | CREATE | New file (~45 lines) |
| `R/generate_cohort.R` | MODIFY | Generalize solver (:42-68), add feature generation phase |
| `R/setup_supabase.R` | MODIFY | Add features table drop/create/load |
| `sql/02_seed_minimal.sql` | MODIFY | Append features INSERT for 40 URNs |
| `data/features/.gitkeep` | CREATE | Empty file |
| `.claude/docs/decisions.md` | MODIFY | Add D17 |
| `CLAUDE.md` | MODIFY | Update contracts, tables |
| `R/CATALOG.md` | MODIFY | Add pull_features.R |
| `data/CATALOG.md` | MODIFY | Add data/features/ |

## Constraints confirmed

- orchestration_2.Rmd: NOT modified (no lines before :399, no CSI computation)
- No feature_breaks creation (that's build-feature-breaks)
- No CSI computation (that's build-csi-calculation)
- sql/02_seed_minimal.sql: features appended, existing rows untouched
- PSI values must be unchanged after regeneration (two-phase RNG isolation)
