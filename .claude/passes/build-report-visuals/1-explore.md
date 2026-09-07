# Pass 1 Explore: build-report-visuals

## What exists

### Cache inventory (actual files on disk)

**PSI** — 4 quarters: `psi_summary_{2025Q4,2026Q1,2026Q2,2026Q3}.csv`
- 6 rows each (header + 6 data rows: segments 0-4 + All Segments)
- Columns (12): `report_quarter, data_cohort, code_version, run_timestamp, Scorecard, Population_Stability_Index, ci_lower, ci_upper, tier, tier_certain, current_count, epsilon_share`
- `Scorecard` values: `0, 1, 2, 3, 4, All Segments` (character)
- `tier`: stable/watch/investigate; `tier_certain`: TRUE/FALSE
- Q3 story: seg0=0.300 investigate(TRUE), seg1=0.090 stable(FALSE — CI spans 0.10), seg2=0.250 investigate(FALSE — CI spans 0.25), seg3=0.040 stable(TRUE), seg4=0.150 watch(TRUE), All=0.084 stable(TRUE)

**CSI** — 4 quarters: `csi_summary_{2025Q4,2026Q1,2026Q2,2026Q3}.csv`
- 30 rows each (header + 30 data rows: 6 segments x 5 features)
- Columns (11): `report_quarter, data_cohort, code_version, run_timestamp, Scorecard, feature, CSI, ci_lower, ci_upper, current_count, epsilon_share`
- Features: feature_1 through feature_5
- Q3 hot spots: feature_1 seg0=0.279, seg2=0.220; feature_3 seg0=0.190

**KS** — 1 quarter: `ks_summary_2026Q3.csv`
- 6 rows (segments 0-4 + All Segments)
- Columns (12): `report_quarter, data_cohort, code_version, run_timestamp, segment, ks_value, dev_ks, ks_delta, ci_lower, ci_upper, n_booked, n_bads`
- `data_cohort` = 2025Q3 (12-month lag)
- Relative changes: seg0 41.8→33.2 = **-20.6%**, seg1 40.1→39.1 = -2.5%, seg2 38.1→37.2 = -2.3%, seg3 35.2→33.9 = -3.7%, seg4 28.2→25.2 = -10.6%

**KS_DECILES** — 1 quarter: `ks_deciles_2026Q3.csv`
- 60 rows (6 segments x 10 deciles)
- Columns (13): `report_quarter, data_cohort, code_version, run_timestamp, segment, decile, n, n_bads, bad_rate, ci_lower, ci_upper, min_score, max_score`
- Dev decile rates available from `R/ks_baseline.R` (ks_baseline$decile_rates)
- Seg 0 monotonicity break visible: decile 5=0.028, decile 6=0.023, decile 7=0.014 (bump in 4-6)

### Loader contract

`load_metrics_history(kpi, n_quarters, end_quarter)` — valid kpis: PSI, CSI, KS, KS_DECILES.
Returns a tibble with all provenance + metric columns. Warns on short window; errors on schema mismatch.

### Rmd structure

- Line 1-6: YAML header (date hardcoded "2026-04-28")
- Line 60: `library(ggplot2)` — already loaded
- Lines 271-391: PSI chunk (ends with cache write at :390)
- Lines 393-617: CSI section (markdown intro at :393-399, chunk :400-617)
- Lines 619-821: KS section (markdown intro at :619-627, chunk :628-821)
- Line 822-825: QC markers

Current line count: 825 (last line: `# QC: Validated`)

### Package state

ggplot2 and scales already in renv.lock. flextable and officer are NOT present.
118 packages currently in renv.lock.

## Plan

### New files

1. **`R/report_visuals.R`** — All visualization functions:
   - `psi_trend_table(psi_hist)` → flextable
   - `psi_trend_chart(psi_hist)` → ggplot (faceted, CI ribbon, threshold bands)
   - `csi_heatmap(csi_hist, quarter)` → ggplot
   - `csi_drilldown_bars(csi_hist, psi_hist, quarter)` → list of ggplots (conditional on tier)
   - `ks_comparison_chart(ks_hist)` → ggplot + relative change annotation
   - `rank_order_chart(decile_hist, dev_baseline)` → ggplot (faceted, free y)
   - `executive_summary_table(psi_hist, ks_hist, decile_hist, dev_baseline)` → flextable

   Rationale: one file, all visuals. Keeps orchestration_2.Rmd chunks short (source + call).

### Rmd changes

Insert 6 new chunks after the existing KPI sections and at the end:

1. **After PSI chunk (:391)**: PSI visuals chunk — sources `R/report_visuals.R` and `R/load_metrics_history.R`, loads PSI history, renders table + chart
2. **After CSI chunk (:617)**: CSI visuals chunk — loads CSI + PSI history, renders heatmap + conditional drilldowns
3. **After KS chunk (:821)**: KS + rank-ordering visuals chunk — loads KS + KS_DECILES history + ks_baseline, renders comparison chart + rank-order chart
4. **After KS visuals**: Methods note (markdown) — thresholds, actions, bootstrap/Wilson caveat
5. **After methods note**: Executive summary chunk — loads all histories, renders summary table
6. **YAML :4**: `date: "\`r Sys.Date()\`"` (dynamic)

### Line-count impact

Estimated additions: ~60-80 lines of Rmd (6 chunks, markdown sections, methods note). All existing anchors shift by the delta of lines inserted BEFORE them; PSI visuals insert after :391 so CSI/KS/QC markers all shift. Will compute exact deltas in Pass 3.

### flextable installation

`renv::install("flextable")` then `renv::snapshot()`. flextable pulls officer, xml2, and a few others. The diff in renv.lock will show flextable + its transitive deps.

### Key design decisions for D23

1. **flextable over gt/kableExtra**: Word-compatible output; same object renders in HTML and docx.
2. **CSI framing as "candidate drivers"**: CSI does not decompose PSI. Label section accordingly. State the limitation explicitly in the Rmd text.
3. **Executive summary placement**: At the end of the Rmd (values need prior computation). Comment that it moves to front during docx assembly.
4. **Single R file for all visuals**: Keeps Rmd chunks minimal; all chart logic testable in isolation.
5. **All data from cache**: Every visual calls `load_metrics_history()`, not in-memory objects.

### Testing strategy

Build synthetic data frames matching cache schemas. Test each function in isolation via `Rscript -e`. Verify:
- flextable renders without error
- ggplot objects build without error
- Tier encoding visible in greyscale (text symbols, not just color)
- Conditional drilldown logic fires only for watch/investigate segments

### Risks

1. **flextable deps**: May pull many transitive packages. Mitigated by renv isolation.
2. **KS single quarter**: Charts will look sparse. Mitigated by caption explaining why.
3. **Segment 1 tier_certain=FALSE**: CI spans 0.10 threshold. Must be marked in table.

## Questions for approval

1. Should `R/report_visuals.R` be a single file with all visual functions, or split per KPI? I recommend single file — there are only ~7 functions and they share theme/color constants.

2. The brief says "horizontal bar chart per flagged segment" for CSI drilldown. Should these render inline (one after another in the Rmd) or should they be combined into a single faceted chart for flagged segments only?

3. KS relative change column: render as a separate flextable beside the chart, or annotate the chart directly with text labels? I recommend a companion flextable — cleaner than chart annotations and survives docx conversion.
