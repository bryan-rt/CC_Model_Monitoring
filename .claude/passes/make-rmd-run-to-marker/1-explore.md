# Pass 1: Explore — make-rmd-run-to-marker

Date: 2026-09-06

## Uncommitted working-copy changes

`git diff orchestration_2.Rmd` shows 5 edits:

| Lines | Change | Disposition |
|---|---|---|
| :186, :206 | `data =` -> `date =` (yearqtr grouping) | Inside QC chunk :171-210, deleted by item 8. Expected loss. |
| :201 | `prim_score < 100 < -1` -> `prim_score < 100 ~ -1` | Inside QC chunk :171-210, deleted by item 8. Expected loss. |
| :297 | Trailing whitespace cleanup on chunk fence | Past :292, out of scope. Preserved. |
| :506 | CSI narrative rewrite | Past :292, out of scope. Preserved. |
| :554-600 | CSI chunk body cleanup (removed broken OCR code) | Past :292, out of scope. Preserved. |

No edits are lost that aren't inside the deletion scope.

## Actual first failure (run evidence)

```
Quitting from lines 59-86 [unnamed-chunk-2] (temp_test.Rmd)
RENDER ERROR: could not find function "glue"
```

First blocker: line 65, unqualified `glue()`. Matches brief item 1.

## Item-by-item verification

| # | Brief claim | Verified? | Evidence |
|---|---|---|---|
| 1 | :65 unqualified glue() | YES | Render error at :65. glue in renv.lock. |
| 2 | :74-81 source() to missing scripts | YES | All 8 files confirmed non-existent by ls. |
| 3 | :84-85 apps_path/perf_paths unused | YES | grep finds only :84-85 (assignment). Zero reads. |
| 4 | :111 negating integer vector | YES | `[!which(...)]` negates integer indices. Should be `[-which(...)]` per :128 pattern. |
| 5 | :117, :135 seq backward | YES | `seq(date, date %m-% months(2), 'month')` errors: "wrong sign in 'by' argument". |
| 6 | :129-131 stray leading paren | YES | `'(apps_{...}'` — paren inside string prevents cache match. |
| 7 | :156, :163 missing closing % | YES | `%m+` not `%m+%`. grep confirms :113-114 are correct. |
| 8 | :171-210 delete QC chunk (D12) | YES | All copied_from refs (:176, :193-198, :216-218, :220-221) inside scope. |
| 9 | :225 prim_score chained comparison | YES | `< 100 < -1` in working copy (user fixed :201 but not :225). |

No surprises. All 9 items confirmed by either the run or direct inspection.

## Additional observation

Item 4 has a subtlety: `[!which(...)]` when `which()` returns an empty integer
vector gives `[!integer(0)]` which is `[logical(0)]`, returning zero rows
instead of all rows. This means if all expected files exist, the "delete stale
files" path deletes EVERYTHING. The correct form `[-which(...)]` with an empty
vector returns all rows (no indices to exclude). This matches the brief's fix
and the pattern at :128.

## Line count impact estimate

Deletions:
- :84-85 (apps_path, perf_paths): -2 lines
- :171-210 (QC chunk): -40 lines
- :216-218, :220-221 (from psi_df): -5 lines

Total: ~47 lines deleted. Final line count shifts all citations below :84 by
varying amounts. Need exact accounting in Pass 2.
