# Pass 1: Explore — build-performance-table-and-ks

Date: 2026-09-06

## Current State

### Rmd structure
- `orchestration_2.Rmd`: 491 lines total
- `# QC: Completed` at :486
- `# QC: Validated` at :490
- KS section header `## KS and DQ90 Rank Ordering` at :485
- Free-text notes at :488 (between markers)
- PSI chunk: :103-325
- CSI chunk: :334-483

### Folder init (line 90)
```r
fs::dir_create(c('data', 'data/apps', 'data/scorecard', 'data/dq_24_mos', 'data/ks_driver_w_perf', 'data/performance_24'))
```
Missing: `data/features` (used by CSI at :337 but created there, not at :90).

### Folders on disk
- `data/dq_24_mos/` — EXISTS, EMPTY (no files)
- `data/performance_24/` — EXISTS, EMPTY (no files)
- `data/ks_driver_w_perf/` — EXISTS, EMPTY (no files)
- None are in `.gitignore` individually — caught by `data/**/*.txt.gz`

### .gitignore
- `data/**/*.txt.gz` covers all data subdirectories generically
- No folder-specific ignores needed for rename

### Generator (R/generate_cohort.R)
- 586 lines, produces 4 quarters: Q4 2025, Q1-Q3 2026
- Volumes: 30,500 core apps/quarter (5,500/8,000/6,000/5,500/5,500 per seg)
- Decision field at :360-364: random 60/20/5/5/10 split (Approve/Decline/Void/Withdraw/Pending)
  - NOT per-segment — uniform 60% across all segments
  - Task requires per-segment approval rates (85/70/60/40/55%)
- No performance/dq90 generation currently
- No mature quarter (Q3 2025) — earliest is Q4 2025

### Setup Supabase (R/setup_supabase.R)
- Drops applications, scorecard, features; creates via SQL; inserts generated data
- Does NOT handle performance table yet

### SQL files
- `sql/01_create_tables.sql` — applications + scorecard
- `sql/02_seed_minimal.sql` — minimal seed
- `sql/03_create_features_table.sql` — features

### Pull functions pattern
All follow: source db.R, glue SQL, floor_date/ceiling_date on performance_window[1],
dbGetQuery, on.exit(dbDisconnect), fwrite to data/X/X_YYYYMM.txt.gz, scipen=999.

### Rmd source loading (:76-79)
```r
source('R/pull_apps.R')
source('R/function_cc_scorecard_data.R')
source('R/pull_features.R')
```
Will need `source('R/pull_performance.R')` added here.

### Key design observations

1. **Two cohorts**: PSI/CSI uses Q3 2026 (cohort_date = 2026-07-01). KS uses
   Q3 2025 booked apps with 12-month DQ90 outcomes.

2. **Generator must add Q3 2025**: A fifth quarter at 3x volume (91,500 core apps).
   This quarter is the "mature" quarter — performance outcomes are available.
   It also serves as the origin for the development baseline.

3. **PSI/CSI invariance**: Adding Q3 2025 to the generator must NOT change
   Q4 2025 through Q3 2026 output. Strategy: prepend Q3 2025 with its own RNG
   block BEFORE set.seed(42). Or: use a separate seed for Q3 2025 generation.
   Actually, the generator iterates quarters in order — adding a quarter at the
   beginning would shift all RNG. Solution: generate Q3 2025 as a SEPARATE call
   or append it after the existing 4 quarters using a dedicated seed.

4. **Approval must be segment-aware**: Current generator uses uniform 60%
   approval. For the mature quarter, we need per-segment rates. For PSI/CSI
   quarters, the decision column is not load-bearing (filtered out before any
   PSI/CSI computation), so we could change it without affecting metrics. But
   safer to leave existing quarters alone and only apply segment-aware approval
   to the mature quarter.

5. **Performance table**: user_ref_num PK, origination_date, dq90. Approved only.

6. **KS computation**: Score-decile within booked population per segment.
   Cumulative goods vs cumulative bads. KS = max|cum%bad - cum%good|.

7. **Development baseline**: Frozen KS + decile bad rates per segment. Generated
   from a labeled dev cohort through the same code path, then frozen to
   R/ks_baseline.R.

8. **Segment 0 story**: KS drops 42→33, monotonicity break in deciles 4-6.
   Requires non-monotonic bad-rate function (logistic + localized bump).

## Files to create
1. `sql/04_create_performance_table.sql`
2. `R/pull_performance.R`
3. `R/ks_baseline.R` (frozen baseline, generated then committed)

## Files to modify
1. `R/generate_cohort.R` — add mature quarter (Q3 2025) with:
   - 3x volume (91,500 core)
   - Per-segment approval rates
   - Logistic bad-rate model for dq90
   - Segment 0 non-monotonic bump
   - Development cohort generation
2. `R/setup_supabase.R` — handle performance table (drop + create + insert)
3. `orchestration_2.Rmd`:
   - :78 → add `source('R/pull_performance.R')`
   - :90 → rename dq_24_mos → dq_12_mos, remove performance_24, add features
   - :485-490 → replace free-text with KS chunk
4. `CLAUDE.md` — pull function contract, table, citations
5. `.claude/docs/decisions.md` — D20
6. `R/CATALOG.md` — add pull_performance.R, ks_baseline.R
7. `data/CATALOG.md` — rename dq_24_mos → dq_12_mos, remove performance_24

## Critical design decisions needed

### PSI/CSI invariance strategy
The generator uses `set.seed(42)` at :239. Adding a quarter changes the loop
iteration count, which shifts ALL downstream RNG. Options:

**Option A**: Generate mature quarter in a SEPARATE function/call with its own
seed (e.g., seed=99). The main `generate_cohort()` stays untouched for the 4
PSI/CSI quarters. A new function `generate_mature_quarter(seed=99)` returns
apps + performance.

**Option B**: Generate mature quarter AFTER the 4 existing quarters in the same
function, using a new seed block (`set.seed(seed + 2000L)`) after all existing
generation is complete.

**Option C**: Prepend but re-seed before the original 4 quarters begin.

Recommendation: **Option B** — append after existing loop, with dedicated seed.
The existing loop's RNG is untouched. Feature Phase 2 (seed+1000) is also
untouched. Mature quarter uses seed+2000.

### Performance table placement
The performance table is separate from applications — it only has approved rows.
It goes in its own SQL file (04) and its own setup step.

### Monotonicity break mechanism (segment 0)
A logistic P(bad|score) is monotonic by construction. For the monotonicity break
in deciles 4-6, add a localized Gaussian bump to the logistic probability:
```
P(bad|score) = logistic(a + b*score) + h * exp(-((score - mu)^2) / (2*sigma^2))
```
where mu is centered on the score range spanning deciles 4-6 for segment 0,
h controls bump height, sigma controls width. Clip to [0,1].

### Development baseline
Generate a "dev" cohort (can be Q4 2025 = flat quarter, or a separate labeled
cohort). Compute KS and decile bad rates through the same function. Freeze to
R/ks_baseline.R as literal R source.

Per the brief: development baseline is a SEPARATE labeled cohort, not Q4 2025.
It should have the target KS values (42/40/38/35/28) and clean monotonic deciles.
The "current" Q3 2025 booked population then shows deviation from this baseline.

## Risk inventory
1. PSI/CSI invariance — highest risk. Must verify bit-identical PSI/CSI after
   generator changes.
2. RNG seeding — mature quarter must not affect existing seeds.
3. Approval rate interaction with noise rows — noise rows have random decisions;
   mature quarter needs segment-aware approval only for core rows.
4. Score range for decile computation — scores are 100-450, generated from
   segment_breaks bins.
5. Logistic solver — must jointly achieve target bad rate AND target KS per
   segment. Brief says verified reachable.

## Questions for user
None — the brief is comprehensive. Proceeding to Pass 2 plan.
