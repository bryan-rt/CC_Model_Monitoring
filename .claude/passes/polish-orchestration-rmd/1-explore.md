# Pass 1: Explore — polish-orchestration-rmd

Date: 2026-09-07

## File facts

- Current line count: 907 (not 911 as CLAUDE.md states; anchor needs update)
- Chunk count: 13 (setup, renv, globals, folder-init, psi-pull, psi-read, psi-join, psi-calc, psi_visuals, csi, csi_visuals, ks, ks_visuals, rank_order_visuals, executive_summary) — actually 14 executable chunks
- Section flow: setup -> renv -> credentials -> paths -> functions/globals -> folder init -> PSI pull -> PSI read -> PSI join+bin -> PSI compute+CI+xlsx -> PSI visuals -> CSI -> CSI visuals -> KS+CI+xlsx -> KS visuals -> rank ordering -> methods note -> executive summary
  - Flow is correct top-to-bottom. No out-of-order sections.

## Comment inventory

### STALE — must remove or rewrite

| Line(s) | Content | Why stale |
|---|---|---|
| 252-268 | `PENDING REBUILD: refit range tables` | 18 lines of false citations. File is 907 lines; references to :2031, :518, :542, :554, :453, :445, :385 are all from a 2,661-line version that no longer exists. The KS task is DONE. Objects listed (ranges_refit_pol, ranges_refit_plt, ranges_refit3, pol_data) do not exist in the file. |
| 74 | `Gates which R methodologies can/cannot, wired into logic starting [checkpoint 5` | OCR garbage. Unclosed bracket. No meaning in current file. |
| 75-76 | `ks_methods <- c('live', 'fixed', 'true')` + `stopifnot(...)` | Dead code. `ks_methods` is never referenced anywhere else in the codebase. The stopifnot is tautological (asserts elements of a literal are in the same literal). |
| 144 | `gc()` | Standalone gc() between pull and read chunks. Reclaims nothing meaningful (data was just written to disk, not held in memory). Against task brief. |

### STALE LINE-NUMBER CITATIONS — must fix or remove

| Line | Citation | Current reality |
|---|---|---|
| 253 | `:240-399` | Stale. Inside PENDING REBUILD block being deleted. |
| 258 | `:2031` | Stale. File is 907 lines. |
| 261 | `:518, :542, :554` | Stale. |
| 262 | `:385, :453` | Stale. |
| 263 | `:453` | Stale. |
| 264 | `:453` | Stale. |
| 265 | `:445` | Stale. |
| 305 | `:737` | Stale. Currently line 737 is `dplyr::select(user_ref_num, segment)` in KS join, not a formatter. The comment says "Downstream formatters at :737 read psi_data back FROM the xlsx cache" — no such formatter exists in the Rmd. The point about make.names() is valid but the line reference is wrong. Rewrite without line number. |
| 414 | `:103-137` | Close but wrong. The apps/scorecard pull+cache pattern is at :108-142. Rewrite as "mirrors apps/scorecard pull+cache pattern above" without line number. |
| 665 | `:104` | Wrong. Line 104 is `## PSI` heading. The apps pull starts at :108. Rewrite as "mirrors apps pull+cache pattern above" without line number. |

### LOAD-BEARING — keep (verify wording still accurate)

| Line(s) | Content | Decision/reason |
|---|---|---|
| 65-71 | Cohort date override block | Core parameter. Accurate. |
| 278 | `Full join: dev side drives the 120-row frame; coalesce empty current bins to 0` | Explains join direction. Accurate. |
| 291 | `Zero-bin policy (D14): floor at epsilon to avoid ln(0) = -Inf.` | Records D14 decision. Accurate. |
| 294-299 | PSI-specific dev pct assertion | Documents the 5% vigintile invariant. Keep. |
| 301 | `Compute stability index (shared helper -- also used by CSI)` | Links PSI and CSI computation. Keep. |
| 304-307 | make.names() Lower_Range -> Lower.Range note | Non-obvious serialization hazard. Keep but remove stale `:737` citation. |
| 437 | `Join to PSI population (guarantees identical population -- same filters applied)` | Documents the CSI=PSI identity constraint. Keep. |
| 452-461 | Binning logic with type dispatch (continuous vs categorical) | Structural, not a comment. Keep. |
| 464 | `Assert no NA bin index` | Guards against out-of-range values. Keep. |
| 498 | `Full join from dev side; coalesce empty current bins to 0` | Same pattern as PSI, consistent. Keep. |
| 509 | `Compute stability index (same helper as PSI)` | Cross-reference. Keep. |
| 526-527 | `Resample application rows ONCE per replicate; recompute all 5 features from the same draw to preserve correlation structure.` | Records a non-obvious bootstrap design choice. Keep. |
| 590 | `Assert full bin grid: 10+8+5+4+3 = 30 bins per segment, 180 total` | Documents the expected grid math. Keep. |
| 628-635 | Candidate drivers prose | D23 framing. Accurate. Keep. |
| 648-655 | Two-cohort structure prose | Critical explanation. Accurate. Keep but deserves expansion. |
| 745-748 | KS deciles RE-DERIVED vs frozen | D20 decision. Critical distinction from PSI. Keep. |
| 751 | `Monitoring flags (observations, not hard stops)` | Frames monotonicity checks correctly. Keep. |
| 819-822 | Wilson CI screening disclaimer | Explains per-decile independence. Keep. |
| 830-833 | Test case: segment 0 decile 1 | Regression guard for specific known edge case. Keep. |
| 900-901 | Placement note for exec summary | Explains knit-order constraint. Keep. |

### EXPLANATORY — restates the code (evaluate for keep/cut)

| Line(s) | Content | Recommendation |
|---|---|---|
| 91 | `Folder Structure` comment | Redundant with section header. Cut banner. |
| 187-188 | `Define vigintile breaks per segment (20 buckets each)` | Helpful orientation for reader. Keep. |
| 204 | `Helper: cut scores into labeled bins using segment-specific breaks` | Standard docstring for local helper. Keep. |
| 210 | `"All Segments" row` | Orientation label. Keep. |
| 217 | `Per-segment rows` | Orientation label. Keep. |
| 270 | `PSI Calculation` section banner | Orientation. Keep. |
| 285 | `Assertions` section banner | Orientation. Keep. |
| 375 | `Write xlsx` section banner | Orientation. Keep. |
| 410 | `CSI: Feature Stability` section banner | Orientation. Keep. |
| 444 | `Per-feature CSI` section banner | Implicit from loop. Could cut but harmless. Keep. |
| 467 | `Aggregation: per segment + All Segments` | Restates code. Harmless context. Keep. |
| 485 | `Dev reference: 6 segments x n_bins rows (global breaks -- same for all)` | Explains why dev is duplicated across segments. Keep. |
| 503 | `Assert full grid` | Orientation. Keep. |
| 525 | `CSI Bootstrap CI` section banner | Orientation. Keep. |
| 572 | `Parse compound group key back to Scorecard + feature` | Explains non-obvious step. Keep. |
| 583-586 | `Epsilon share` | Orientation. Keep. |
| 606 | `Write xlsx: one tab per feature, segment as column` | Orientation. Keep. |
| 658 | `KS and DQ90 Rank Ordering` section banner | Orientation. Keep. |
| 727 | `Join: performance -> apps -> scorecard` | Documents join chain. Keep. |
| 765 | `Compare to development baseline` | Orientation. Keep. |
| 776 | `KS Bootstrap CI` section banner | Orientation. Keep. |
| 817 | `Decile bad rates` comment-only line | Redundant with following Wilson CI block. Cut. |
| 837 | `Cache` section banner | Orientation. Keep. |

## Items from task brief — status

1. **:251-268 PENDING REBUILD block** — VERIFIED PRESENT at :252-268. All citations false. Must delete/replace.
2. **:74 OCR garbage** — VERIFIED at :74. Must delete with :75-76 (dead `ks_methods`).
3. **:78 PENDING TRANSCRIPTION** — NOT FOUND. No TRANSCRIPTION marker exists. The line :78 is `source('R/pull_apps.R')`. This item is already resolved.
4. **:38-39 `# renv::init()`** — VERIFIED at :38-39. The `renv::init()` is commented out under a prose section explaining it. The prose at :20-36 already explains the purpose. The commented-out call is how the user runs it (uncomment, execute). Keep as-is — it is the intended UX.
5. **:42 Credential Setup** — VERIFIED at :42-46. Text says `.Renviron` + `.Renviron.example`. Accurate post-scrub. No changes needed.
6. **Stale line citations** — Found 10, all cataloged above.

## Sections missing lead sentences

| Section | Line | Current opening | Needs |
|---|---|---|---|
| PSI (first chunk) | 108 | Cold — starts with `paths <- ...` | Lead sentence: what this chunk does (pull+cache raw data) |
| PSI (read chunk) | 149 | Existing prose at :147 covers this | OK |
| PSI (join+bin chunk) | 170 | Cold — starts with `psi_df <- ...` | Covered by prose at :245-249 but that prose is AFTER the chunk. Move or add lead. Actually :147 partially covers, and :245-249 is before the calc chunk. The join/bin chunk at :170 starts cold. |
| PSI (calc chunk) | 251 | Starts with PENDING REBUILD | After cleanup, needs lead sentence for PSI calculation |
| KS | 657 | Has good lead prose at :648-655 | OK |
| Rank ordering | 862 | Cold — just chunk tag | Needs one-line lead |
| Exec summary | 903 | Has placement note at :900-901 | OK |

## Two-cohort structure

Currently explained at :648-655 in a markdown paragraph before the KS chunk. This is adequate but could be more prominent. The task brief asks for prose in the document body, which this IS — it's markdown text, not a code comment. Recommend keeping and possibly adding a brief note in the PSI section that cross-references this.

## Clean-slate guard

Not present. Must add `rm(list = ls())` at top of setup chunk (:8, after `knitr::opts_chunk$set`).

## gc() inventory

Single `gc()` at :144. Task brief says do not add gc() elsewhere, and the existing one is unnecessary. Recommend removing it.

## Plan input summary

Edits needed:
1. Add `rm(list = ls())` to setup chunk (line 9)
2. Delete lines 74-76 (OCR garbage + dead ks_methods)
3. Delete lines 252-268 (PENDING REBUILD), replace with 2-line note
4. Fix line-number citation at :305 (remove `:737`)
5. Fix line-number citation at :414 (remove `:103-137`)
6. Fix line-number citation at :665 (remove `:104`)
7. Remove gc() at :144
8. Remove `# Decile bad rates` standalone comment at :817
9. Remove `#------ Folder Structure ------` banner at :91
10. Add lead sentences for: PSI pull chunk, PSI join/bin chunk, PSI calc chunk, rank ordering
11. Expand two-cohort prose or add cross-reference in PSI section
12. Re-derive all CLAUDE.md anchors after line-count change
