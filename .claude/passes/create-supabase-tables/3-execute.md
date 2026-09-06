# Pass 3: Execute — create-supabase-tables

Date: 2026-09-06

## Files created

| File | Purpose |
|---|---|
| `sql/01_create_tables.sql` | DDL for `applications` (14 cols) and `scorecard` (8 cols) |
| `sql/02_seed_minimal.sql` | 50 apps + 40 scorecard rows across 2026-07/08/09 |
| `R/setup_supabase.R` | Idempotent setup: DROP + CREATE + seed via `db_connect()` |
| `data/apps/.gitkeep` | Directory for pull_apps.R output |
| `data/scorecard/.gitkeep` | Directory for function_cc_scorecard_data.R output |

## Files modified

| File | Change |
|---|---|
| `.gitignore` | Added `data/**/*.txt.gz` |
| `CLAUDE.md` | Loop position advanced; CSI citations fixed (:502→:508); Supabase tables section added |
| `.claude/docs/decisions.md` | D11, D13 CSI citations fixed (:502→:508, removed stale ":509-634") with anchors |
| `data/CATALOG.md` | apps/ and scorecard/ status STUB→CREATED |
| `R/CATALOG.md` | Added `setup_supabase.R` entry |

## Citation corrections (folded in per user instruction)

Stale citations from previous rounds, corrected with anchors:

| File | Was | Now | Anchor |
|---|---|---|---|
| CLAUDE.md:18 | `:502-583` | `:508-583` | :508 = CSI chunk opening fence |
| CLAUDE.md:21 | `line 502` | `line 508` | CSI chunk opening fence |
| CLAUDE.md:19-20 | `formerly :520-543` | removed (stub ref :512-514 kept) | :512-514 = D13 stub |
| decisions.md D11 | `:502-583, originally :509-634` | `:508-583` | :508 = CSI chunk opening fence |
| decisions.md D13 | `:502-583, originally :509-634` | `:508-583` | :508 = CSI chunk opening fence |
| decisions.md D13 | `line 502` | `line 508` | CSI chunk opening fence |

## Setup execution

```
Rscript -e 'source(here::here("R/setup_supabase.R")); setup_supabase()'
```

Output:
```
NOTICE:  table "applications" does not exist, skipping
NOTICE:  table "scorecard" does not exist, skipping
Setup complete: applications + scorecard created and seeded.
```

Live verification:
```
applications rows: 50
scorecard rows: 40
```

## Validation output (all six checks, all three months stacked)

```
=== Pulling data ===
  apps 2026-07-01 ... done
  scorecard 2026-07-01 ... done
  apps 2026-08-01 ... done
  scorecard 2026-08-01 ... done
  apps 2026-09-01 ... done
  scorecard 2026-09-01 ... done

=== Stacking files ===
  stacked apps rows: 50
  stacked scorecard rows: 40

=== Check 1: column count and names ===
  ncol(a): 14
  ncol(s): 8
  names(a): app_num, user_ref_num, dt_entered, client_product_cd, strategy_version, assigned_credit_lim, decision, applied, org_paper_type, lao_credit_lmt, fico_score, bureau_used, acq, prim_score
  names(s): sq_num, user_ref_num, score, segment, actduty, trans_date_ct, proc_date_ct, primemdt
  PASS

=== Check 2: dt_entered class ===
  class(a$dt_entered): IDate, Date
  PASS

=== Check 3: zoo::as.yearqtr on dt_entered ===
  yearqtr NAs: 0 of 50
  unique values: 2026 Q3
  PASS

=== Check 4: prim_score class ===
  class(a$prim_score): integer
  is.numeric(a$prim_score): TRUE
  PASS

=== Check 5: user_ref_num numeric conversion ===
  class(a$user_ref_num): integer64
  class(s$user_ref_num): integer64
  NAs in a$user_ref_num (original): 2
  NAs in as.numeric(a$user_ref_num): 2
  NAs in s$user_ref_num (original): 0
  NAs in as.numeric(s$user_ref_num): 0
  Matching user_ref_nums: 40
  PASS

=== Check 6: left_join (Rmd path) ===
  joined rows: 50  (apps rows: 50 )
  NA segments in joined: 16
  PASS

=== ALL CHECKS PASSED ===
```

## Key observations from validation

1. **dt_entered** round-trips as `IDate` (data.table's Date subclass), which
   inherits from `Date` — `inherits(x, "Date")` is TRUE. `zoo::as.yearqtr()`
   works correctly, zero NAs.

2. **prim_score** round-trips as `integer` (not `numeric`) because all seeded
   values are whole numbers. `is.numeric(integer)` is TRUE in R — the D8 check
   passes. The sample-data-generator (D6, future task) should include
   non-integer scores to verify the `NUMERIC` path.

3. **user_ref_num** round-trips as `integer64` (bit64 package, loaded by
   data.table). `as.numeric()` on integer64 at 1e13 magnitude is exact (well
   within 2^53). No precision loss, no spurious NAs beyond the 2 pre-existing
   NULLs.

4. **scipen=999** in fwrite prevents 14-digit values from writing as scientific
   notation (e.g., "1e+13"), which would break the join on reload.

5. **left_join with as.numeric conversion** (mirroring the Rmd path): 50 rows
   as expected. 16 NA segments = 6 (matched scorecard rows with NULL segment) +
   10 (8 unmatched non-null URN + 2 NULL URN apps).

## Deviations from approved plan

Two changes were made during execution that differ from the Pass 2 plan:

### a) Check 5 assertion relaxed

- **Plan specified:** `stopifnot(sum(is.na(a_urns)) == 0, sum(is.na(s_urns)) == 0)`
- **Actually ran:** `stopifnot(sum(is.na(a_urns)) == sum(is.na(a$user_ref_num)))` and same for s
- **Why changed:** The plan's `== 0` assertion assumed all user_ref_num values
  are non-null. The seed includes 2 NULL user_ref_num rows (see deviation b),
  which produce legitimate NAs in `as.numeric()`. The `== 0` assertion would
  have failed on valid data. The replacement asserts that conversion introduces
  no NEW NAs — any NA in the output was already NA in the input — which is the
  actual invariant the check exists to protect.

### b) NULL user_ref_num rows added to seed

- **Plan's edge-case table:** Listed "~8 apps rows with no scorecard match" but
  did not list NULL user_ref_num as a seed edge case.
- **Actually seeded:** 2 apps rows (app_num 1017, 1034) with NULL user_ref_num.
- **Why changed:** The apps contract types user_ref_num as `VARCHAR(14) NULL`
  (pull_apps.R:11). NULL is a valid value. Without NULL rows in the seed, the
  left_join's NULL-handling path is untested, and check 5's "no spurious NAs"
  assertion cannot distinguish between "conversion worked" and "no NULLs
  existed to test." Adding them also drove the check 5 assertion change above.
- **Impact on counts:** Total unmatched apps = 10 (8 no-match + 2 NULL) instead
  of 8. Check 6 expected NA segments = 16 (6 NULL-segment + 10 unmatched)
  rather than the 14 that would result from 8 unmatched.

## Dependencies installed

- `R.utils`: required by `data.table::fread()` for `.gz` file reading. HARD
  requirement — fread cannot read .gz without it and every downstream task
  depends on that path.
- `zoo`: required for `as.yearqtr()` in validation check 3 and throughout the
  Rmd's QC grouping.

Both were already implicit dependencies of the Rmd but were not installed in
the current renv.
