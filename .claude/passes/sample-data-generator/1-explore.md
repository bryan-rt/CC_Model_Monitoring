# Pass 1 — Explore: sample-data-generator

Date: 2026-09-06

## Task summary

Build a parameterized cohort generator producing four quarters of drifting data
to replace the 50-row minimal seed as the primary demo dataset. The generator
makes PSI values meaningful (currently sparsity artifacts from 31 apps across
120 bins). Adds `epsilon_share` to the PSI chunk. Makes `cohort_date` an
explicit overridable parameter.

## Files examined

| File | Lines | Relevance |
|---|---|---|
| `orchestration_2.Rmd:58-75` | Setup chunk | `cohort_date` at :65, `source()` calls at :72-73 |
| `orchestration_2.Rmd:98-134` | Cache-miss pull | Pulls 3 months per quarter, writes `.txt.gz` |
| `orchestration_2.Rmd:139-158` | Read-back chunk | Reads `.txt.gz` via `fread`, stacks 3 months |
| `orchestration_2.Rmd:160-192` | PSI join + breaks | Filter chain, `segment_breaks` definition |
| `orchestration_2.Rmd:261-382` | PSI calculation | Full join, epsilon floor, `epsilon_only`, xlsx write |
| `R/pull_apps.R` | 63 lines | `get_apps_data()` — SELECT + date filter + `fwrite` |
| `R/function_cc_scorecard_data.R` | 47 lines | `get_cc_scorecard_data()` — same pattern |
| `R/build_dev_population.R` | 62 lines | 120-row dev pop ref, `segment_breaks` duplicate |
| `R/setup_supabase.R` | 27 lines | DROP + CREATE + seed from SQL files |
| `R/db.R` | 20 lines | `db_connect()` from `SUPABASE_DB_URL` |
| `sql/01_create_tables.sql` | 30 lines | Schema: `applications` PK `app_num`, `scorecard` PK `user_ref_num` |
| `sql/02_seed_minimal.sql` | 163 lines | 50 apps, 40 scorecard, URN 10000000000001+ |
| `.gitignore` | 37 lines | `data/**/*.txt.gz` is gitignored |

## Critical observations

### 1. Bin-width asymmetry (the core constraint)

The `segment_breaks` are unequal width. Segment 0 is the most extreme:

| Bins | Width | Count |
|---|---|---|
| 1-19 | 12 points each | 19 |
| 20 | 122 points (328-450) | 1 |

Drawing from any smooth distribution over 100-450 would pile ~35% of mass
into bin 20 (covers 122/350 = 34.9% of the range), producing large PSI from
the generator, not from drift.

**Required construction** (per task brief): sample the BIN first (by weight
vector), then draw `prim_score ~ Uniform(breaks[i], breaks[i+1])` within that
bin. The weight vector IS the drift parameter.

### 2. Filter chain (what gets dropped)

`orchestration_2.Rmd:160-175`:
1. Left join apps ↔ scorecard on `user_ref_num` (coerced to numeric)
2. Drop `client_product_cd %in% c('SEC', 'MSC')`
3. Drop `is.na(prim_score)`
4. Drop `has_segment == 0` (NA segment after join = no scorecard match OR NULL segment)
5. Drop `prim_score < 100`

The task brief says volumes are POST-FILTER targets, with noise rows added on
top. So the generator produces:
- Core rows: 14,500/quarter that survive all filters
- Noise rows: ~8% SEC/MSC, ~4% NULL prim_score, ~4% no scorecard match, a few NULL segment

### 3. Table constraints and ID ranges

| Table | PK | Minimal seed range | Generator range |
|---|---|---|---|
| `applications` | `app_num` (INTEGER) | 1001-1050 | 100001+ |
| `scorecard` | `user_ref_num` (VARCHAR(14)) | 10000000000001-10000000000040 | 20000000000001+ |
| `applications` | `user_ref_num` (VARCHAR(14)) | same as scorecard | same |

All user_ref_nums must be globally unique across all 4 quarters because the
scorecard PK enforces uniqueness. The date filter isolates quarters at read
time, but all data coexists in one table.

### 4. Coupling: prim_score ↔ segment

- `prim_score` lives in `applications`
- `segment` lives in `scorecard`
- The bin depends on both (segment determines which `segment_breaks` to use,
  and prim_score falls within the bin of those breaks)
- Must be generated together from the same draw, then split across two tables,
  joined on `user_ref_num`

### 5. Month distribution within quarters

The Rmd pulls 3 months per quarter and stacks them. Each quarter spans
months M, M+1, M+2. Rows need `dt_entered` (apps) and `trans_date_ct`
(scorecard) in each of the 3 months. The task brief says trans_date_ct must be
in the same month as dt_entered for matching rows.

Quarter → months:
- 2025 Q4: Oct/Nov/Dec 2025
- 2026 Q1: Jan/Feb/Mar 2026
- 2026 Q2: Apr/May/Jun 2026
- 2026 Q3: Jul/Aug/Sep 2026

### 6. setup_supabase.R modification

Currently: DROP + CREATE + seed from `02_seed_minimal.sql`.
Need: a parameter to choose between minimal seed (SQL file) and generated data
(loaded via `DBI::dbAppendTable()`).

Approach: `setup_supabase(mode = c("minimal", "generated"))`. In "generated"
mode, `source("R/generate_cohort.R")` and call the generator, then
`dbAppendTable()` the result data frames.

### 7. cohort_date parameterization

`orchestration_2.Rmd:65`: `cohort_date <- lubridate::floor_date(Sys.Date(), "quarter")`

Make this an explicit parameter with a default. Demo works by overriding this
line. Simplest approach: check if `cohort_date` already exists in the
environment before assigning:

```r
if (!exists("cohort_date")) {
  cohort_date <- lubridate::floor_date(Sys.Date(), "quarter")
}
```

### 8. epsilon_share (deferred from build-psi-calculation)

Currently `epsilon_only` is a boolean per segment (TRUE when segment_total == 0).
`epsilon_share` = fraction of total PSI contributed by epsilon-floored bins.

Per segment:
- A bin is epsilon-floored when its original `counts / segment_total == 0`
  (i.e., `counts == 0` and `segment_total > 0`)
- `epsilon_share` = sum of `Population Divergence (K-L)` for epsilon-floored
  bins / total PSI for that segment

At the target volumes (125-200 per bin), epsilon_share should be ~0 because
few or no bins will be empty.

### 9. Drift design

Weight vector per quarter, same for all segments. Linear tilt toward lower
scores (higher weights for low-index bins = low-score bins).

Tilt function: `w_i = (1 + alpha * (21 - 2*i) / 19) / 20` for i=1..20
- alpha = 0: flat (1/20)
- alpha > 0: more mass in low-score bins

**Minimum bin count constraint** (50 per bin per segment):
- Segment 0/3/4: 2500 apps, 125/bin flat → 125*(1-alpha) ≥ 50 → alpha ≤ 0.6
- Segment 1: 4000 apps, 200/bin flat → 200*(1-alpha) ≥ 50 → alpha ≤ 0.75
- Segment 2: 3000 apps, 150/bin flat → 150*(1-alpha) ≥ 50 → alpha ≤ 0.667
- Binding: alpha ≤ 0.6 (from segments 0/3/4)

Target alpha values (to be tuned empirically):
- Q4 2025: alpha = 0 (flat) → PSI ~0.02 (statistical noise)
- Q1 2026: alpha ≈ 0.15 → PSI ~0.06
- Q2 2026: alpha ≈ 0.30 → PSI ~0.13
- Q3 2026: alpha ≈ 0.50 → PSI ~0.30

### 10. Volume breakdown

Per quarter (post-filter):

| Segment | Apps | Per bin (flat) |
|---|---|---|
| 0 | 2,500 | 125 |
| 1 | 4,000 | 200 |
| 2 | 3,000 | 150 |
| 3 | 2,500 | 125 |
| 4 | 2,500 | 125 |
| **Total** | **14,500** | — |

Noise on top (~16% overhead ≈ 2,320 extra rows):
- ~8% SEC/MSC: ~1,160 rows (split SEC/MSC)
- ~4% NULL prim_score: ~580 rows (have scorecard match but NULL score)
- ~4% no scorecard match: ~580 rows (apps with no matching scorecard row)
- A few NULL segment: ~20 rows (scorecard match but segment = NULL)

Total per quarter: ~16,820 apps rows, ~14,920 scorecard rows
(14,500 core + ~420 for NULL prim_score + NULL segment, minus ~580 no-match)

Across 4 quarters: ~67,280 apps rows, ~59,680 scorecard rows

### 11. Other generated columns

Beyond `prim_score`, `segment`, `user_ref_num`, and dates, the generator needs
to fill all other columns in both tables:

**applications** (14 columns):
- `app_num`: sequential integer starting from 100001
- `client_product_cd`: 'CC' for core, 'SEC'/'MSC' for noise, with some
  'PLAT'/'GOLD' variety
- `strategy_version`: 'V2.0'/'V2.1'
- `decision`: weighted draw from 'Approve'/'Decline'/'Void'/'Withdraw'/'Pending'
- `applied`: 1 if Approve, 0 otherwise
- `assigned_credit_lim`: random, NULL for declines
- `org_paper_type`: 'ELECTRONIC'/'PAPER'
- `lao_credit_lmt`: ≈ assigned_credit_lim
- `fico_score`: random 500-850
- `bureau_used`: 'EXP'/'TU'/'EQ'
- `acq`: 'WEB'/'BRANCH'

**scorecard** (8 columns):
- `sq_num`: sequential integer starting from 500001
- `score`: random 400-850 (not prim_score — this is a different score)
- `actduty`: 'Y'/'N' (mostly 'N')
- `proc_date_ct`: trans_date_ct + 1 day (sometimes NULL)
- `primemdt`: mostly NULL, occasionally a date string

### 12. Self-test assertion

The most valuable test: with flat weights (Q4 2025), PSI < 0.05 for all
segments. This validates the entire pipeline end-to-end. If it fails, something
is wrong in the generator, the join, or the formula.

## Open questions

1. **Should the generator be runnable standalone?** Or only via
   `setup_supabase(mode = "generated")`? I lean toward standalone (returns
   data frames), with setup_supabase calling it and loading via dbAppendTable.

2. **Alpha values for target PSI**: Need empirical tuning. The linear tilt
   formula is an approximation; actual PSI depends on the interaction with
   non-uniform bin widths. Plan: implement, run, adjust.

3. **Random seed**: Use `set.seed()` inside the generator for reproducibility?
   The Rmd already sets `set.seed(42)` at :63. Generator should have its own
   seed parameter.

## Risks

1. **Bin-width interaction with tilt**: The unequal bin widths mean same-alpha
   produces different PSI per segment. The "All Segments" breaks differ from
   per-segment breaks, so All Segments PSI is an aggregate view, not directly
   comparable. Monitor per-segment PSI individually.

2. **user_ref_num PK collision**: 4 quarters × ~15,000 scorecard rows = ~60,000
   unique user_ref_nums. Using a contiguous range starting from 20000000000001
   eliminates collision with minimal seed and within generated data.

3. **Date boundary edge cases**: `ceiling_date(month) - 1` in the pull function
   gives the last day of the month. Generated dates must fall within
   `[floor_date, ceiling_date - 1]` for each month.

## Deliverables summary

| Deliverable | New/Modified |
|---|---|
| `R/generate_cohort.R` | NEW |
| `R/setup_supabase.R` | MODIFY — add `mode` parameter |
| `orchestration_2.Rmd:65` | MODIFY — `cohort_date` override-friendly |
| `orchestration_2.Rmd:283-299` | MODIFY — add `epsilon_share` |
| `CLAUDE.md` | UPDATE |
| `.claude/docs/decisions.md` | ADD D16 |
| `R/CATALOG.md` | ADD `generate_cohort.R` entry |
| `data/CATALOG.md` | No change (generated data is gitignored) |
| `.claude/passes/sample-data-generator/` | 3 pass artifacts |
