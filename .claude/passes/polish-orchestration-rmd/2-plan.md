# Pass 2: Plan — polish-orchestration-rmd

Date: 2026-09-07

## Re-verification of load-bearing comments

Method: grepped the project for the variable, function, or assertion each
comment references. All 17 confirmed VERIFIED — every referenced thing still
exists in live code.

| # | Line(s) | Claim | Grep | Result |
|---|---|---|---|---|
| 1 | :65-71 | cohort_date is overridable, used downstream | `cohort_date` in Rmd | 24 hits across pull/read/cache/perf sections. VERIFIED. |
| 2 | :278 | Full join produces 120-row frame | `psi_joined` in Rmd | Defined :279, asserted `nrow==120` at :289. VERIFIED. |
| 3 | :291 | Epsilon floors zero bins (D14) | `epsilon` in R/compute_si.R | Used at :17, :27, :31 in compute_si.R; `psi_epsilon` set :292. VERIFIED. |
| 4 | :294-299 | Dev pcts are all 5% | `dev_pcts` in Rmd | Defined :295-298, asserted :299. VERIFIED. |
| 5 | :301 | compute_stability_index shared by PSI+CSI | `compute_stability_index` in Rmd | Called :302 (PSI) and :510 (CSI). VERIFIED. |
| 6 | :437 | CSI inner_joins to psi_df | `psi_df` in CSI section | inner_join at :438-442. VERIFIED. |
| 7 | :464 | Assert no NA bin index | `anyNA(bin_idx)` in Rmd | stopifnot at :465. VERIFIED. |
| 8 | :485 | Dev ref: 6 segments x n_bins | `dev_ref` in Rmd | Built :486-496 from c("All Segments", 0:4). VERIFIED. |
| 9 | :498 | Full join from dev side, coalesce 0 | `csi_joined` in Rmd | full_join :499-501. VERIFIED. |
| 10 | :509 | Same SI helper as PSI | `compute_stability_index` at :510 | Called with csi_joined. VERIFIED. |
| 11 | :526-527 | Bootstrap resamples rows once, all 5 features | `csi_boot_data` in Rmd | Defined :528; bootstrap_ci :531; stat_fn loops all features. VERIFIED. |
| 12 | :590 | 10+8+5+4+3=30 bins, 180 total | `total_data_rows` + `180` in Rmd | Summed :591; asserted :603-604. VERIFIED. |
| 13 | :628-635 | Candidate drivers, not decomposition | Read prose | CSI != PSI decomposition stated explicitly. VERIFIED. |
| 14 | :648-655 | Two-cohort: PSI current, KS 12mo prior | Read prose | Explains lag, names both quarters. VERIFIED. |
| 15 | :745-748 | KS deciles re-derived, not frozen | `compute_ks_stats` at :749 | Called on ks_df (live cohort); no frozen decile ref. VERIFIED. |
| 16 | :751 | Monotonicity checks are warnings, not stops | `warning(` at :760-761 | Uses warning(), not stop(). VERIFIED. |
| 17 | :819-822 | Wilson CI screening disclaimer | `wilson_ci` at :823 | Called with decile_rates. VERIFIED. |
| 18 | :830-833 | Regression test: seg 0 decile 1 | `seg0_d1` in Rmd | Defined :831; two stopifnot :832-833. VERIFIED. |
| 19 | :900-901 | Exec summary placement note | Read prose | "During docx assembly it moves to the front." VERIFIED. |

## Reclassification: :304-307 make.names() comment

**Reclassified: STALE.** The comment claims "Downstream formatters at :737 read
psi_data back FROM the xlsx cache." Verified:
- No `read.xlsx` call for `psi_quarterly.xlsx` exists anywhere in the project
- :737 is `dplyr::select(user_ref_num, segment)` — a KS join line
- `Lower.Range` (dot form) appears nowhere in the codebase

**Decision on psi_col_order:** KEEP the variable. It serves a real purpose:
stable, diffable column order in the output xlsx tabs. But rewrite the comment
to say THAT instead of warning about a deleted consumer.

## Edit plan (line numbers are pre-edit; apply top-to-bottom)

### E1. Clean-slate guard (:9)

Insert after `knitr::opts_chunk$set(echo = TRUE)`:

```r
# Clean slate: prevents objects from a previous cohort_date persisting across
# an interactive re-run. Knit starts fresh; this protects "Run All Chunks".
rm(list = ls())
```

Net: +3 lines.

**rm() ordering:** The guard is in the setup chunk (:8-12). cohort_date is
assigned at :65-72 in a LATER chunk (Loading Functions & Globals). Knit and
"Run All Chunks" both execute chunks sequentially, so rm() fires before
cohort_date is set. Order is correct.

**Failure mode:** If the user sets cohort_date at the R console BEFORE clicking
"Run All Chunks", rm(list = ls()) silently discards it and the in-file default
(:68) takes over — a quiet wrong-quarter render. The override comment at :65-67
already says "uncomment and set", meaning the override is intended to be
edited in-file, not set at the console. Document this explicitly in the guard
comment. Use `rm(list = ls())` (not setdiff) since the intent is a true clean
slate and the in-file override is the contract.

**YAML params note:** No params block exists today, so bare ls() is safe. If a
params block is added later, knitr injects params before the setup chunk runs,
and rm(list = ls()) would wipe it. This is a future concern, not a current one.

### E2. Delete OCR garbage + dead ks_methods (:74-76)

Delete:
```
# Gates which R methodologies can/cannot, wired into logic starting [checkpoint 5
ks_methods <- c('live', 'fixed', 'true')
stopifnot(all(unlist(ks_methods %in% c('live', 'fixed', 'true'))))
```

Net: -3 lines.

### E3. Add lead sentence before PSI pull chunk (:106-107)

Current :106 is prose about "pulls the most recent Starters application..."
which references "PATH" (a production path that no longer exists). Rewrite:

```
Pull the current quarter's scorecard and application data from Supabase (or
read from local cache if already present) and write gzipped CSVs to `data/`.
```

Net: 0 lines (rewrite in place).

### E4. Remove gc() at :144

Delete: `gc()`

Net: -1 line.

### E5. Add lead sentence before PSI join/bin chunk (:147-148)

Current :147 reads: "This section pulls in the most recent quarter of
application and scorecard data and uses predefined custom score ranges to set
PSI bins in accordance with the model development population."

This is adequate as a lead sentence but slightly inaccurate — the chunk at :149
READS cached files, it doesn't pull from the database. Rewrite:

```
Read the cached scorecard and application files, join them, filter to the
scored population, and bin scores into frozen development-population vigintiles
for PSI comparison.
```

Net: 0 lines (rewrite in place).

### E6. Delete PENDING REBUILD block (:252-268)

Delete 17 lines. Replace with 2-line note:

```r
# The original pipeline loaded development references from external xlsx.
# That function is now R/build_dev_population.R (and R/ks_baseline.R for KS).
```

Net: -15 lines.

### E7. Rewrite make.names() comment (:304-307)

Delete:
```r
# Restore PSI column selection and order for downstream compatibility.
# Downstream formatters at :737 read psi_data back FROM the xlsx cache.
# openxlsx::read.xlsx applies make.names(): Lower_Range -> Lower.Range.
# This is a known transformation; the formatter must account for it.
```

Replace with:
```r
# Stable column order for diffable xlsx output across quarterly runs.
```

Net: -3 lines.

### E8/E9. Convert all remaining line citations to relative references

Grepped `:\d{2,}` in the Rmd. Found 12 occurrences across 10 lines. Of these:
- 10 are inside blocks being deleted (E6: :252-268, E7: :304-307)
- 2 are live and need conversion:
  - :414 `# Pull + cache (mirrors apps/scorecard pattern at :103-137)` → `above`
  - :665 `# Pull + cache performance data (3 months, mirrors apps pattern at :104)` → `above`

**Total converted to relative references: 2.** Remaining 10 eliminated by
deletion. After this pass, zero in-file line citations remain.

Net: 0 lines.

### E10. Add two-cohort cross-reference in PSI section

After the PSI section heading (around :104, after `## PSI`), add a brief note:

```
PSI and CSI evaluate the current quarter's through-the-door applications —
the model's input distribution. Performance metrics (KS, DQ90) use a
different cohort; see the KS section for the two-cohort rationale.
```

Net: +3 lines.

### E11. Remove orphan comment at :817

Delete: `# Decile bad rates`

Net: -1 line.

### E12. Add lead sentence before rank ordering chunk (:860-861)

Before the chunk fence at :862, add:

```
Compare current and development decile bad rates by segment. Each panel
shows the rate curve and Wilson confidence band; monotonicity breaks are
visible as inversions.
```

Net: +3 lines.

### E13. Remove Folder Structure banner at :91

Change: `#------------------------------- Folder Structure ---------------------------------`
To: (delete line)

Net: -1 line.

## Line-count delta

| Change | Lines |
|---|---|
| E1 clean-slate guard | +3 |
| E2 OCR + ks_methods | -3 |
| E3 PSI pull lead | 0 |
| E4 gc() | -1 |
| E5 PSI join/bin lead | 0 |
| E6 PENDING REBUILD | -15 |
| E7 make.names() | -3 |
| E8 CSI citation | 0 |
| E9 KS citation | 0 |
| E10 two-cohort xref | +3 |
| E11 orphan comment | -1 |
| E12 rank order lead | +3 |
| E13 folder banner | -1 |
| **Total** | **-15** |

907 → 892 lines.

## Anchor re-derivation plan

After edits, every live citation in CLAUDE.md, decisions.md, CATALOG.md, and
R/CATALOG.md must be re-derived by grep. The delta is -15 lines, but edits
are distributed:
- E1 (+3 at :9) shifts everything after :9 by +3
- E2 (-3 at :74-76) shifts everything after :76 by -3 (net: 0 from :9)
- E4 (-1 at :144) shifts after :144 by -1 (net: -1)
- E6 (-15 at :252-268) shifts after :268 by -15 (net: -16)
- E7 (-3 at :304-307) shifts after :307 by -3 (net: -19)
- E10 (+3 near :104) shifts after :104 by +3 (net: -16)
  Wait — E10 is between E2 and E4 in file order. Let me re-order by file position.

Correct order by file position:
1. E1: +3 at :9 → cumulative shift after :12 = +3
2. E13: -1 at :91 → cumulative shift after :91 = +2
3. E10: +3 near :104 → cumulative shift after :107 = +5
4. E3: 0 at :106 → +5
5. E2: -3 at :74-76 → Wait, :74 is BEFORE :91. Re-order again.

**Correct file-position order:**
1. E1: +3 at line 9
2. E2: -3 at lines 74-76
3. E13: -1 at line 91
4. E10: +3 near line 104
5. E3: 0 at line 106
6. E5: 0 at line 147
7. E4: -1 at line 144
8. E6: -15 at lines 252-268
9. E7: -3 at lines 304-307
10. E8: 0 at line 414
11. E9: 0 at line 665
12. E11: -1 at line 817
13. E12: +3 at line 861

Cumulative shifts at key anchors (will compute precisely in execute pass after
all edits are applied). The execute pass will grep every anchor fresh.

## Comments to be removed (for 3-execute.md tracking)

| Line | Content | Justification |
|---|---|---|
| 74 | `# Gates which R methodologies can/cannot...` | OCR garbage, unclosed bracket, no meaning |
| 75-76 | `ks_methods` + stopifnot | Dead code, never referenced |
| 91 | `#--- Folder Structure ---` | Redundant with section header "Folder Init" |
| 144 | `gc()` | Reclaims nothing; against readability goal |
| 252-268 | `PENDING REBUILD: refit range tables` (17 lines) | All citations false; objects and lines referenced no longer exist |
| 304-307 | make.names() / downstream formatter warning (4 lines) | Consumer deleted; xlsx is never read back |
| 817 | `# Decile bad rates` | Orphan label; redundant with Wilson CI block following it |

Total: 28 lines of comments/code removed.

## Constraints checklist

- [ ] No computed value, variable name, or chunk order changed
- [ ] No R/*.R files touched
- [ ] No rm()/gc() added (existing gc() removed; rm(list=ls()) is in setup only)
- [ ] Every deletion justified above
