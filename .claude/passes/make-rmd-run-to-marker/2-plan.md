# Pass 2: Plan — make-rmd-run-to-marker

Date: 2026-09-06

## Edits to orchestration_2.Rmd (in line order)

### Item 1: :65 — unqualified glue()

Before:
```r
cohort_date <- as.Date(glue('{lubridate::floor_date(Sys.Date(),"quarter")}'))
```
After:
```r
cohort_date <- lubridate::floor_date(Sys.Date(), "quarter")
```
Rationale: the round-trip through glue + as.Date is pointless since
floor_date() already returns a Date. Simplify per brief.

Line count: 0 (edit in place).

### Item 2: :74-81 — source() calls to missing scripts

Before (8 lines):
```r
source('R/pull_trended_data.R')
source('R/pull_early_trended_data.R')
source('R/function_join_apps_perf.R')
source('R/pull_score_mapping.R')
source(here::here('R/calculate_early_ks.R'))
source(here::here('R/calculate_true_bad_ks.R'))
source(here::here('R/build_ks_report_tables.R'))
source(here::here('R/build_ks_rank_order.R'))
```
After (1 line):
```r
# PENDING TRANSCRIPTION — not yet OCR'd, not needed before :292
```

Decision: replace rather than comment-out. The scripts don't exist and
commented source() calls are noise. The marker is discoverable by grep.
The :292 reference in the comment will shift with the deletions; update it
after the final line count is known.

Line count: -7.

### Item 3: :84-85 — unused apps_path, perf_paths

Delete both lines. Verified unused by grep (assignment only at :84-85, zero
reads anywhere in the file).

Line count: -2. Cumulative: -9.

### Item 4: :111 — `[!which(...)]`

Before:
```r
paths <- fs::dir_ls('data/scorecard')[!which(basename(fs::dir_ls('data/scorecard')) %in% c(
```
After:
```r
paths <- fs::dir_ls('data/scorecard')[-which(basename(fs::dir_ls('data/scorecard')) %in% c(
```

Change `!` to `-`. Matches correct pattern at :128 (shifted to :119 after
prior edits).

Line count: 0.

### Item 5: :117, :135 — seq direction backward

Before (both lines):
```r
seq(cohort_date, cohort_date %m-% months(2), 'month')
```
After:
```r
seq(cohort_date, cohort_date %m+% months(2), 'month')
```

Line count: 0.

### Item 6: :129-131 — stray leading paren in apps cache check

Before:
```r
  glue::glue('(apps_{format(as.Date(cohort_date), "%Y%m")}.txt.gz'),
  glue::glue('(apps_{format(as.Date(cohort_date) %m+% months(1), "%Y%m")}.txt.gz'),
  glue::glue('(apps_{format(as.Date(cohort_date) %m+% months(2), "%Y%m")}.txt.gz')
```
After:
```r
  glue::glue('apps_{format(as.Date(cohort_date), "%Y%m")}.txt.gz'),
  glue::glue('apps_{format(as.Date(cohort_date) %m+% months(1), "%Y%m")}.txt.gz'),
  glue::glue('apps_{format(as.Date(cohort_date) %m+% months(2), "%Y%m")}.txt.gz')
```

Remove `(` from inside each string.

Line count: 0.

### Item 7: :156, :163 — missing closing %

Before:
```r
cohort_date %m+ months(i - 1)
```
After:
```r
cohort_date %m+% months(i - 1)
```

Why this is a parse error: `%` opens a special-operator token in R's lexer
and scans to the next `%`, so `%m+ months(i - 1), "%` lexes as one operator
name and the error points somewhere unrelated.

Line count: 0.

### Item 8: :171-210 — delete QC chunk (D12)

Delete the entire chunk (opening fence through closing fence), 40 lines.
Without the copied_from remapping at :197-198, its two branches are
byte-identical and it computes pre == post by construction.

Line count: -40. Cumulative: -49.

### Item 8 continued: :216-221 — delete copied_from/from_value/to_value from psi_df

Delete lines 216-221 (contiguous). These are:
```r
         from_value = as.numeric(substr(stringr::str_extract(copied_from, "(?<=FROM ) \\d+"),1,14)),
    to_value = as.numeric(substr(stringr::str_extract(copied_from,"(?<=TO ) \\d+"),1,14)),
    copied_flag = case_when(is.na(copied_from) ~ 1,
                             T ~ 0),
    user_ref_num = case_when(is.na(from_value) ~ user_ref_num,
                             T ~ from_value)) |>
```

:215 must change from trailing comma to `) |>` to close mutate() and pipe:
```r
         user_ref_num = as.numeric(user_ref_num)) |>
```

:221's `)) |>` closed both the inner case_when and the outer mutate(). After
deletion, the closing paren on :215 takes over the mutate() close.

Line count: -6. Cumulative: -55.

### Item 9: :225 — prim_score chained comparison

Before:
```r
prim_score < 100 < -1,
```
After:
```r
prim_score < 100 ~ -1,
```

User already fixed the identical occurrence at :201 (inside the deleted chunk).
This one at :225 (shifted to :170 after prior deletions) is the surviving copy.

Line count: 0.

## Total line count change: -55

## Citation re-derivation plan

Every citation referencing orchestration_2.Rmd lines must be re-derived after
edits. The shift is not uniform:
- Lines 1-73: no shift
- Lines 74-81: replaced by 1 comment line (:74)
- Lines 82-83: shift -7
- Lines 84-85: deleted
- Lines 86-170: shift -9
- Lines 171-210: deleted
- Lines 211-215: shift -49
- Lines 216-221: deleted
- Lines 222+: shift -55

**Known citations to update:**

| File | Current citation | Old line | Expected new line |
|---|---|---|---|
| CLAUDE.md | "line 292" | 292 | 237 |
| CLAUDE.md | ":508-583" | 508-583 | 453-528 |
| CLAUDE.md | ":512-514" | 512-514 | 457-459 |
| CLAUDE.md | "line 508" | 508 | 453 |
| decisions.md D7 | "lines 296-500" | 296-500 | 241-445 |
| decisions.md D11 | ":508-583" | 508-583 | 453-528 |
| decisions.md D11 | ":512-514" | 512-514 | 457-459 |
| decisions.md D12 | ":171-210" | deleted | note: chunk deleted |
| decisions.md D12 | ":197-198" | deleted | note: deleted |
| decisions.md D12 | ":216-221" | deleted | note: deleted |
| decisions.md D13 | ":508-583" | 508-583 | 453-528 |
| decisions.md D13 | ":512-514" | 512-514 | 457-459 |
| decisions.md D13 | "line 508" | 508 | 453 |
| R/CATALOG.md | "line 292" | 292 | 237 |
| R/CATALOG.md | ":139" | 139 | 130 |
| R/CATALOG.md | ":121" | 121 | 112 |
| R/CATALOG.md | ":74-81" | 74-81 | :74 (single comment line) |
| data/CATALOG.md | ":171" | deleted | update ref to fread reader |
| data/CATALOG.md | ":164" | 164 | 155 |
| data/CATALOG.md | ":93" | 93 | 93 (no shift, before :84) |

All will be verified by grep against anchors AFTER the edits are made, not by
arithmetic alone. Expected values above are the hypothesis; grep is the test.

## Execution order

1. Create branch `pass3/make-rmd-run-to-marker`
2. Apply all 9 edits to orchestration_2.Rmd in line order (top to bottom)
3. Attempt render of lines 1-:237 (shifted :292)
4. If render succeeds, capture psi_df diagnostics
5. Grep all anchors to verify shifted line numbers
6. Update CLAUDE.md, decisions.md, R/CATALOG.md, data/CATALOG.md with
   verified line numbers and anchors
7. Write 3-execute.md with deviations section
8. Commit, push

## Validation script

After edits, render lines 1 through the QC marker, then:

```r
cat("psi_df rows:", nrow(psi_df), "\n")
cat("psi_df segment distribution:\n")
print(table(psi_df$segment, useNA = "ifany"))
cat("has_score distribution:\n")
print(table(psi_df$has_score, useNA = "ifany"))
cat("has_segment distribution:\n")
print(table(psi_df$has_segment, useNA = "ifany"))
```

Wait — has_score and has_segment are consumed by the filter, not retained in
psi_df. The filter at :230-233 keeps only has_segment == 1 and
!is.na(prim_score) and prim_score >= 100. So psi_df will only contain rows
that passed the filter. The diagnostics should reflect the FILTERED state.

Expected: psi_df has rows for segments 0-4 only (no NAs — has_segment == 1
filter removes them). prim_score all >= 100 (filter removes < 100 and NA).
No SEC/MSC rows. has_score == 1 for all rows (since has_score == -1 needs
prim_score < 100 which is filtered out, and has_score == 9999 needs > 450
which is also filtered if we have no scores above 450... actually the seed
has prim_score = 445, which is <= 450, so has_score = 1 for all surviving rows).

Also report psi_raw_data since that's the final output before the marker.
