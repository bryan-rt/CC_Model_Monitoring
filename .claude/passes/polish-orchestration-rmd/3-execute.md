# Pass 3: Execute — polish-orchestration-rmd

Date: 2026-09-07
Branch: pass3/polish-orchestration-rmd

## Line-count delta

907 → 896 lines (net -11). Plan predicted -15; actual difference:
- E1 was +4 (added NOTE line about in-file override, not +3)
- E3 rewrite: 1 long line → 2 wrapped lines (+1)
- E5 rewrite: 1 long line → 2 wrapped lines (+1)
- E10: +3 lines (same as plan, blank line was already present)
- All other edits matched plan exactly

## Comments removed (with justification)

| Old line(s) | Content | Justification |
|---|---|---|
| 74 | `# Gates which R methodologies can/cannot, wired into logic starting [checkpoint 5` | OCR garbage. Unclosed bracket. No meaning in current file. |
| 75 | `ks_methods <- c('live', 'fixed', 'true')` | Dead code. Never referenced anywhere in the codebase. |
| 76 | `stopifnot(all(unlist(ks_methods %in% c('live', 'fixed', 'true'))))` | Tautological assertion on the dead code above. |
| 91 | `#------------------------------- Folder Structure ---------------------------------` | Redundant with section header "5) Folder Init" two lines above. |
| 144 | `gc()` | Standalone gc() between pull and read chunks. Reclaims nothing meaningful; largest object at this point is ~3 MB. Against readability goal. |
| 252 | `# --- PENDING REBUILD: refit range tables ---` | All citations false. File is 896 lines; references to :2031, :518, :542, :554, :453, :445, :385 are from a 2,661-line version. |
| 253-268 | 16 lines of PENDING REBUILD detail | Objects referenced (ranges_refit_pol, ranges_refit_plt, ranges_refit3, pol_data) do not exist. KS task is done and rebuilt none of them. |
| 304 | `# Restore PSI column selection and order for downstream compatibility.` | False claim: no downstream consumer reads the xlsx back. |
| 305 | `# Downstream formatters at :737 read psi_data back FROM the xlsx cache.` | :737 was a KS join line. No formatter reads psi_data from xlsx. grep for Lower.Range: zero hits. |
| 306 | `# openxlsx::read.xlsx applies make.names(): Lower_Range -> Lower.Range.` | Hazard does not exist; consumer was in the deleted 2,175 lines. |
| 307 | `# This is a known transformation; the formatter must account for it.` | (part of the same 4-line block) |
| 817 | `# Decile bad rates` | Orphan label. Redundant with `# --- Decile bad-rate Wilson CI ---` on the next line. |

Total: 28 lines removed (comments + dead code).

## Comments added

| New line(s) | Content | Purpose |
|---|---|---|
| 11-14 | Clean-slate rm(list = ls()) with NOTE about in-file override | Prevents stale objects across re-runs; documents the console override pitfall |
| 255-256 | 2-line provenance note replacing PENDING REBUILD | Records where the original dev references went |
| 292 | `# Stable column order for diffable xlsx output across quarterly runs.` | True justification for psi_col_order (replaces stale make.names comment) |

## Line citations converted to relative references

| Old line | Old citation | New text |
|---|---|---|
| 414 | `mirrors apps/scorecard pattern at :103-137` | `mirrors apps/scorecard pull pattern above` |
| 665 | `mirrors apps pattern at :104` | `mirrors apps pull pattern above` |

10 additional stale line citations eliminated by deletion of the PENDING
REBUILD block (:252-268) and make.names() comment (:304-307).

**Zero in-file line citations remain.** Verified by `grep ':\d{2,}' orchestration_2.Rmd`.

## Lead sentences added

| Section | New line(s) | Content |
|---|---|---|
| PSI (two-cohort xref) | 107-109 | PSI/CSI evaluate current quarter TTD; KS uses a different cohort; see KS section |
| PSI (pull chunk) | 110-111 | Pull from Supabase or read from local cache; write gzipped CSVs |
| PSI (join/bin chunk) | 149-151 | Read cached files, join, filter to scored population, bin into vigintiles |
| Rank ordering | 847-850 | Compare current vs dev decile bad rates; Wilson CI band; monotonicity breaks |

## Anchor re-derivation (before → after)

| Anchor | Old | New | Verification |
|---|---|---|---|
| EOF / validated frontier | :911 | :896 | `wc -l orchestration_2.Rmd` = 896 |
| cohort_date block | :65-71 | :69-75 | grep `cohort_date <- as.Date` → :72 |
| source compute_si.R | :272 | :261 | grep → :261 |
| CSI chunk fence | :409 | :395 | grep `CSI: Feature Stability` → :396 (fence at :395) |
| CSI section | :409-627 | :395-612 | grep closing fence → :612 |
| source compute_ks.R | :659 | :645 | grep → :645 |
| KS chunk fence | :657 | :643 | grep `KS and DQ90` → :644 (fence at :643) |
| KS section | :648-850 | :643-835 | grep closing fence → :835 |
| PSI bootstrap | :323 | :309 | grep `bootstrap_ci(` → :309 |
| CSI bootstrap | :531 | :517 | grep → :517 |
| KS bootstrap | :778 | :764 | grep → :764 |
| Wilson CI | :819 | :808 | grep `wilson_ci(` → :808 |
| perf_date | :663 | :649 | grep `perf_date <- cohort_date` → :649 |
| PSI visuals chunk | :394 | :380 | grep `psi_visuals` → :380 |
| CSI visuals chunk | :637 | :623 | grep `csi_visuals` → :623 |
| KS visuals chunk | :854 | :839 | grep `ks_visuals` → :839 |
| Rank ordering chunk | :862 | :851 | grep `rank_order_visuals` → :851 |
| Executive summary chunk | :903 | :892 | grep `executive_summary` → :892 |

## Files updated

| File | Changes |
|---|---|
| orchestration_2.Rmd | 13 edits (E1-E13), -11 lines |
| CLAUDE.md | Line count 911→896, all 18 anchors re-derived, cohort_date override note updated, loop position updated |
| .claude/docs/decisions.md | 11 line-citation updates across D11/D13/D19/D20/D21/D22/D23/D24 |
| R/CATALOG.md | 16 line-citation updates, PENDING TRANSCRIPTION marker removed, 8 unneeded scripts noted |
| .claude/passes/polish-orchestration-rmd/2-plan.md | Added 17-comment verification table, rm() ordering confirmation |

## Deviations from plan

1. **Line count -11 vs planned -15.** E1 added an extra NOTE line (+1). E3 and
   E5 each wrapped to 2 lines instead of staying at 1 (+2 total). E10 reused
   an existing blank line instead of adding one (+1 saved, but the prose was
   still 3 new lines). Net: 4 fewer lines removed than planned.

2. **rm(list = ls()) comment includes explicit NOTE.** Plan said 3 lines; actual
   is 4 (added "NOTE: cohort_date must be overridden IN-FILE" per user's
   instruction to document the console-override failure mode).

## Constraints checklist

- [x] No computed value, variable name, or chunk order changed
- [x] No R/*.R files touched
- [x] No rm()/gc() added (existing gc() removed; rm(list=ls()) in setup only)
- [x] Every deletion justified in comments-removed table above
- [x] Zero in-file line citations remain (verified by grep)
- [x] All doc anchors re-derived
