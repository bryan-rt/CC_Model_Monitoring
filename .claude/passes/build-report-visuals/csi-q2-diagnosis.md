# CSI Q2 2026 Defect Diagnosis

Date: 2026-09-07

## Symptom

CSI for Q2 2026 shows collapsed per-segment differentiation. feature_1 targets
span 14x (seg3=0.01 to seg0=0.14); observed values cluster within 1.4x
(0.032–0.045), all near the All Segments value (0.038). Same pattern in
feature_3.

## Root cause: STALE CACHED FEATURE FILES

The Q2 feature files on disk (`data/features/features_20260{4,5,6}.txt.gz`)
are from **Sep 6 18:55** — the initial create-features-table run.

The D20 task (build-performance-table-and-ks, Sep 7) regenerated ALL data via
`setup_supabase(mode = "generated")`, which calls `generate_cohort()` and writes
fresh data to Supabase. Phase 1 code changed (D20 added per-segment
approval-rate sampling at generate_cohort.R:458-459), which shifted the Phase 1
RNG stream. This changed which values `sample()` produced at :424 (product codes)
and :433 (row shuffle), altering the user_ref_num → row assignment.

Phase 2 resets the seed (`set.seed(seed + 1000L)` at :579), so the feature
values themselves are deterministic across runs. But the row ORDER within each
segment changed because Phase 1's shuffle changed which user_ref_num lands in
which position. Since `generate_feature_values()` shuffles its output (:169),
and the segment assignment order from `seg_for_app` (:592) depends on the
Phase 1 shuffle, each user_ref_num gets a DIFFERENT feature value in the new
run.

**Evidence**: For user 20000000070873 (Q2, segment 0):
- Stale cached file: feature_1 = 41.65
- Current Supabase: feature_1 = 29.88
- 34,207 of 34,210 Q2 feature values differ between stale file and Supabase

The Rmd's cache-miss logic (orchestration_2.Rmd:414) only pulls from Supabase
when the cached files don't exist. The Q2 files existed from Sep 6, so the pull
was skipped. The Q3 files were written on Sep 7 09:34 (same time as the apps
rebuild), so they are current. The Q1 files were re-pulled on Sep 7 15:26
during the Q1 backfill run.

## Why Q4 is unaffected

Q4 has alpha=0 for all segments (flat cohort). All segments draw from the
SAME uniform distribution. When you shuffle user_ref_nums across segments,
each segment still gets a uniform sample. Means match to 4 decimal places
between stale cache and Supabase: seg0=499.9084 in both.

## Why Q1 is unaffected

Q1 feature files were re-pulled on Sep 7 15:26 during the Q1 backfill. Their
timestamps match the Supabase data.

## Why Q3 is unaffected

Q3 feature files were written on Sep 7 09:34, same time as the full
regeneration. They read the current Supabase data.

## Affected quarters

| Quarter | Feature files timestamp | Apps/SC timestamp | Stale? | CSI affected? |
|---|---|---|---|---|
| Q4 2025 | Sep 6 18:43 | Sep 7 09:34 | YES | NO (alpha=0, all uniform) |
| Q1 2026 | Sep 7 15:26 | Sep 7 09:34 | NO | NO |
| Q2 2026 | Sep 6 18:55 | Sep 7 09:34 | YES | YES |
| Q3 2026 | Sep 7 09:34 | Sep 7 09:34 | NO | NO |

## create-features-table/3-execute.md verification claim

The claim "max |delta| 0.0011 across all 100 cells" (line 113) and the Q2
table (lines 140-149 showing seg0 feature_1 = 0.1398/0.14) **were true at the
time**. The verification ran against the generator output on Sep 6, when
Supabase data, cached files, and generator output were all consistent. The
D20 regeneration on Sep 7 invalidated the cached files without re-pulling them.

## The mechanism in detail

1. `generate_cohort()` Phase 1 uses `set.seed(42)`. `sample()` calls at :389,
   :399, :407, :416, :424, :433, :458, :459 consume RNG in order.
2. D20 added :458-459 (approval rate `runif` + `sample`). This shifted all
   subsequent `sample()` calls' outputs.
3. `all_rows[sample(n_total), ]` at :433 shuffles rows. Changed RNG = changed
   shuffle = different user_ref_num → row mapping.
4. Phase 2 (`set.seed(seed + 1000L)` at :579) resets the seed. Feature values
   are deterministic, but `seg_for_app` (:592) maps user_ref_nums to segments
   using the Phase 1 scorecard, and `seg_idx` (:621) selects rows by segment.
   Since user_ref_num → row mapping changed, the same user_ref_num now maps to
   a different position in the segment, receiving a different feature value.
5. The feature file on disk has OLD values. The scorecard file on disk has NEW
   segments. Join produces scrambled per-segment distributions.

## Fix (not applied — report only)

Delete the stale Q2 and Q4 feature files and re-run the Rmd for those quarters.
The cache-miss logic will re-pull from Supabase, getting the current data. Then
re-run the CSI and PSI cache writes for Q2 and Q4.

Alternatively, prevent recurrence: add a staleness check that compares file
timestamps against the most recent `setup_supabase` run, or always re-pull
when cohort_date != current quarter.
