# Pass 3: Execute — make-rmd-run-to-marker

Date: 2026-09-06

## Render result

orchestration_2.Rmd knits clean from line 1 to the `# QC: Validated` marker
at :236 (formerly :292) against live Supabase. No errors.

## psi_df diagnostics

```
psi_df rows: 31
psi_df segment distribution:

 0  1  2  3  4
 4 10  6  7  4

has_score distribution:

 1
31

has_segment distribution:

 1
31
```

- 31 rows after filtering (50 apps → remove 5 SEC/MSC, 5 NULL prim_score,
  6 NULL segment, 3 prim_score < 100 → 31 remaining; exact count depends on
  overlap of filter conditions).
- All 5 segments (0-4) represented with varying volumes.
- has_score = 1 for all rows (no < 100 or > 450 survived the filter).
- has_segment = 1 for all rows (filter requires has_segment == 1).

## psi_raw_data

```
psi_raw_data nrow: 39

# A tibble: 39 x 4
   Scorecard    counts Lower_Range Upper_Range
   <chr>         <int>       <dbl>       <dbl>
 1 0                 4         328         450
 2 1                 1         410         450
 3 1                 1         372         382
 4 1                 1         362         372
 5 1                 1         352         362
 6 1                 3         334         352
 7 1                 1         298         316
 8 1                 1         280         298
 9 1                 1         190         208
10 2                 2         260         280
11 2                 1         240         260
12 2                 1         220         240
13 2                 1         180         200
14 2                 1         140         160
15 3                 1         230         250
16 3                 1         170         190
17 3                 1         125         150
18 3                 4         100         125
19 4                 1         380         390
20 4                 1         300         320
21 4                 1         100         130
22 4                 1         220         240
23 All Segments      2         423         450
24 All Segments      2         406         423
25 All Segments      2         389         406
26 All Segments      1         372         389
27 All Segments      1         355         372
28 All Segments      3         338         355
29 All Segments      1         321         338
30 All Segments      2         304         321
31 All Segments      1         287         304
32 All Segments      2         270         287
33 All Segments      1         253         270
34 All Segments      2         236         253
35 All Segments      1         219         236
36 All Segments      3         185         202
37 All Segments      1         151         168
38 All Segments      3         117         134
39 All Segments      3         100         117
```

## Full render output

```
processing file: temp_test.Rmd
  |====                                                  |   7%
  |=======                                               |  13% [setup]
  |==========                                            |  20%
  |==============                                        |  27% [unnamed-chunk-1]
  |=================                                     |  33%
  |=====================                                 |  40% [unnamed-chunk-2]
  |========================                              |  47%
  |============================                          |  53% [unnamed-chunk-3]
  |===============================                       |  60%
  |===================================                   |  67% [unnamed-chunk-4]
  |======================================                |  73%
  |==========================================            |  80% [unnamed-chunk-5]
  |=============================================         |  87%
  |=================================================     |  93% [unnamed-chunk-6]
  |====================================================  | 100%

output file: temp_test.knit.md
Output created: temp_test.html
```

## Edits applied

| # | Original line | Edit | Line count |
|---|---|---|---|
| 1 | :65 | `as.Date(glue(...))` → `lubridate::floor_date(Sys.Date(), "quarter")` | 0 |
| 2 | :74-81 | 8 source() → 1 comment marker | -7 |
| 3 | :84-85 | Delete unused `apps_path`, `perf_paths` | -2 |
| 4 | :111 | `[!which(` → `[which(` | 0 |
| 5 | :117, :135 | `%m-%` → `%m+%` | 0 |
| 6 | :129-131 | Remove stray `(` from apps cache strings | 0 |
| 7 | :156, :163 | `%m+` → `%m+%` | 0 |
| 8 | :171-210 | Delete QC chunk (D12) + inter-chunk blank | -41 |
| 8b | :215-221 | Close mutate at :215 `) |>`, delete :216-221 | -6 |
| 9 | :225 | `< 100 < -1` → `< 100 ~ -1` | 0 |

**Total: -56 lines** (plan said -55; extra line from inter-chunk blank in
item 8 deletion).

## Line-count delta: 292 → 236

## Citation re-derivation (all verified by grep, not arithmetic)

| File | Citation | Old | New | Anchor |
|---|---|---|---|---|
| CLAUDE.md | line count | ~2,775 | ~2,669 | wc -l |
| CLAUDE.md | validated frontier | line 292 | line 236 | `# QC: Validated` marker |
| CLAUDE.md | CSI range | :508-583 | :452-527 | :452 = CSI chunk opening fence |
| CLAUDE.md | D13 stub | :512-514 | :456-458 | D13 stub comment block |
| CLAUDE.md | CSI marker reach | line 508 | line 452 | CSI chunk opening fence |
| decisions.md D7 | lines 296-500 | lines 296-500 | lines 240-445 | :240 = narrative after QC marker |
| decisions.md D11 | :508-583 | :508-583 | :452-527 | :452 = CSI chunk opening fence |
| decisions.md D11 | :512-514 | :512-514 | :456-458 | D13 stub |
| decisions.md D12 | :171-210, :197-198, :216-221 | (all deleted) | status → Executed | pre-deletion ranges retained as history |
| decisions.md D13 | :508-583 | :508-583 | :452-527 | :452 = CSI chunk opening fence |
| decisions.md D13 | :512-514 | :512-514 | :456-458 | D13 stub |
| decisions.md D13 | line 508 | line 508 | line 452 | CSI chunk opening fence |
| R/CATALOG.md | frontier line | line 292 | line 236 | `# QC: Validated` |
| R/CATALOG.md | pull_apps.R read-by | :139 | :130 | get_apps_data call in cache-miss branch |
| R/CATALOG.md | function_cc_scorecard_data.R read-by | :121 | :112 | get_cc_scorecard_data call in cache-miss branch |
| R/CATALOG.md | 8 script source lines | :74-81 | :74 | PENDING TRANSCRIPTION marker |
| data/CATALOG.md | data/apps/ read-by | :171 | :154 | fread apps in map_df |
| data/CATALOG.md | data/scorecard/ read-by | :164 | :147 | fread scorecard in map_df |
| data/CATALOG.md | data/performance_24/ | :93 | :87 | dir_create in folder init |

## Deviations from approved plan

### a) Line count -56 not -55

The plan computed item 8 (QC chunk deletion) as -40 lines. The actual deletion
was -41 because the blank line between the QC chunk's closing fence and the
psi_df chunk's opening fence was included in the Edit tool's match. This is
correct — the two chunks merged into one, eliminating the inter-chunk blank.

### b) Item 4: `[which(` not `[-which(`

The Pass 2 plan specified `[-which(` (later corrected by the user in review).
Executed as `[which(` per user correction. Rationale: `[!which(` negated an
integer vector (wrong type); `[-which(` would exclude the expected files
(wrong semantics — permanently skipping cache); `[which(` selects the expected
files (correct — matching :119 pattern). The plan item was wrong in a way
that reads as a fix, which is why it survived into the plan.

### c) CLAUDE.md ":520-543" stale citation

The user flagged this as still present on main. Inspecting CLAUDE.md, the
stale reference had already been removed in the create-supabase-tables task
(replaced with "D13 stub replaces original connection block"). No action
needed — the citation does not exist in the current file.

## Uncommitted working-copy changes (preserved)

Pre-existing user edits at :297, :506, :554-600 (all past :236) are preserved
in the working copy. Edits at :186, :201, :206 were inside the deleted QC
chunk — expected loss, documented in Pass 1.

## Files modified

| File | Change |
|---|---|
| `orchestration_2.Rmd` | 9 edits, -56 lines, runs to QC marker |
| `CLAUDE.md` | Frontier → VALIDATED at :236, loop position advanced, CSI citations updated |
| `.claude/docs/decisions.md` | D7, D11, D13 citations updated; D12 status → Executed |
| `R/CATALOG.md` | All line refs updated with anchors |
| `data/CATALOG.md` | All line refs updated with anchors |
