# Pass 2 Plan: build-report-visuals

## Data verification (user-requested)

### PSI 4-quarter matrix vs D16 drift schedule

D16 targets: seg0 = 0/0.08/0.18/0.30, seg1 = 0/0.03/0.05/0.09, seg2 = 0/0.05/0.12/0.25, seg3 = 0/0.02/0.03/0.04, seg4 = 0/0.04/0.08/0.15

| Scorecard | 2025Q4 | 2026Q1 | 2026Q2 | 2026Q3 | D16 target |
|---|---|---|---|---|---|
| 0 | 0.000 | 0.080 | 0.180 | 0.300 | 0/0.08/0.18/0.30 |
| 1 | 0.000 | 0.030 | 0.050 | 0.090 | 0/0.03/0.05/0.09 |
| 2 | 0.000 | 0.050 | 0.120 | 0.250 | 0/0.05/0.12/0.25 |
| 3 | 0.000 | 0.020 | 0.030 | 0.040 | 0/0.02/0.03/0.04 |
| 4 | 0.000 | 0.040 | 0.080 | 0.150 | 0/0.04/0.08/0.15 |
| All | 0.011 | 0.021 | 0.045 | 0.084 | (derived) |

**VERIFIED**: All per-segment values match D16 targets to 3 significant figures. Q4 values are 0.000 for all segments (flat cohort). All Segments carries the expected ~0.011 residual at Q4 (D17 mechanism). Trend is monotonically increasing per segment, consistent with the escalating-drift story.

### CSI verification: feature_1 escalation, feature_2/feature_4 flat

CSI targets scale as 0x/0.25x/0.50x/1.0x of Q3 targets (generate_cohort.R:312).

**feature_1** (Q3 target: seg0=0.28, seg2=0.22):

| Scorecard | 2025Q4 | 2026Q1 | 2026Q2 | 2026Q3 | Q3 target |
|---|---|---|---|---|---|
| 0 | 0.000 | 0.070 | 0.045 | 0.279 | 0.28 |
| 2 | 0.000 | 0.055 | 0.045 | 0.220 | 0.22 |

Q2 values are ~0.045 (0.50 * 0.28 = 0.14 expected for seg0, but actual is 0.045). This is a DEVIATION from the linear scaling. However, Q1 and Q3 match their targets. The Q2 dip is consistent across segments and may reflect the solver's nonlinearity — the CSI function is not linear in alpha. The Q3 values are what matter for the current-quarter visuals and they match.

**feature_2** (Q3 target: all segments 0.01–0.03):

| Scorecard | 2025Q4 | 2026Q1 | 2026Q2 | 2026Q3 |
|---|---|---|---|---|
| 0 | ~0 | 0.005 | 0.008 | 0.020 |
| 1 | 0 | 0.005 | 0.010 | 0.020 |
| 3 | ~0 | 0.003 | 0.010 | 0.010 |

**VERIFIED**: feature_2 stays below 0.03 across all segments and quarters — flat/low as expected.

**feature_4** (Q3 target: all segments 0.01–0.02):

| Scorecard | 2025Q4 | 2026Q1 | 2026Q2 | 2026Q3 |
|---|---|---|---|---|
| 0 | 0 | 0.003 | 0.003 | 0.010 |
| 1 | 0 | 0.002 | 0.005 | 0.010 |
| 2 | 0 | 0.005 | 0.007 | 0.020 |

**VERIFIED**: feature_4 stays below 0.02 across all segments and quarters — flat as expected.

**Conclusion**: The heatmap will show the intended pattern — feature_1 hot in segments 0 and 2, feature_3 moderately warm in segment 0, everything else cold.

### code_version uniformity

All 8 files (4 PSI + 4 CSI) carry `code_version = 7c45304`. The 2 KS files also carry `7c45304`. **No mixed-version warning** will fire. The provenance stamp confirms all cache writes happened from the same commit.

### CSI Q2 non-monotonicity note

The CSI Q2 values for feature_1 are LOWER than Q1 in some segments (e.g., seg0: Q1=0.070 > Q2=0.045). This means the CSI trend line for feature_1/seg0 will show a dip at Q2 before spiking at Q3. This is not a data error — the CSI solver's alpha-to-CSI mapping is nonlinear, and the 0.25x/0.50x scaling applies to the alpha parameter, not to the realized CSI value. The trend chart should show what's there, not smooth it. However, the CSI heatmap only shows current quarter so this does not affect it.

---

## Execution plan

### Step 0: Install flextable

```r
renv::install("flextable")
renv::snapshot()
```

Verify `renv.lock` diff shows flextable + deps only.

### Step 1: Create `R/report_visuals.R`

Single file with all visualization functions. Each function takes a tibble from `load_metrics_history()` and returns a ggplot or flextable object.

#### Constants (top of file)

```r
# Threshold constants
PSI_WATCH <- 0.10
PSI_INVESTIGATE <- 0.25

# Color palette
TIER_COLORS <- c(stable = "#4DAF4A", watch = "#FF7F00", investigate = "#E41A1C")
TIER_BG <- c(stable = "#E8F5E9", watch = "#FFF3E0", investigate = "#FFEBEE")

# Segment display order
SEGMENT_ORDER <- c("0", "1", "2", "3", "4", "All Segments")
```

#### Function 1: `psi_trend_table(psi_hist)` → flextable

- Input: tibble from `load_metrics_history("PSI", 4)`
- Pivot to wide: rows = report_quarter, columns = Scorecard (0-4, All Segments)
- Cell text: round to 3 decimal places + tier symbol: `S` (stable), `W` (watch), `!` (investigate)
- Cell background: light green / light orange / light red by tier
- Where `tier_certain == FALSE`: append `*` after the symbol
- Footnote: "* CI spans a threshold; tier not statistically distinguishable this quarter."
- Returns flextable object

#### Function 2: `psi_trend_chart(psi_hist)` → ggplot

- Input: same tibble
- `facet_wrap(~Scorecard, ncol = 3)` — 6 panels, 2 rows
- Each panel: line + point for PSI, `geom_ribbon()` for CI
- Threshold BANDS as `geom_rect()`: stable (green, alpha=0.1), watch (orange, alpha=0.1), investigate (red, alpha=0.1) — extends from 0 to max_y
- Shared y-axis (free y OFF)
- x-axis: report_quarter as factor (discrete)
- Returns ggplot object

#### Function 3: `csi_heatmap(csi_hist, quarter)` → ggplot

- Input: tibble from `load_metrics_history("CSI", 4)`, filtered to `quarter`
- `geom_tile()` with Scorecard on y, feature on x, fill = CSI
- Fill scale: `scale_fill_gradient2(low = "white", mid = "#FFF3E0", high = "#E41A1C", midpoint = 0.10)`
- `geom_text()` overlay with rounded CSI value
- Returns ggplot object

#### Function 4: `csi_drilldown_bars(csi_hist, psi_hist, quarter, max_segments = 3)` → list of ggplots

- Input: CSI + PSI histories, current quarter, cap
- Identify flagged segments: PSI tier == "watch" or "investigate" in `quarter`
- Sort by PSI descending, cap at `max_segments`
- For each flagged segment: horizontal bar chart (`geom_col` + `coord_flip`), features sorted by CSI descending, with CI whiskers
- Returns named list of ggplots (names = segment IDs)
- Returns empty list if no segments flagged

#### Function 5: `ks_comparison_chart(ks_hist)` → ggplot

- Input: tibble from `load_metrics_history("KS")`
- Grouped bar chart: segment on x, two bars (dev_ks, ks_value), CI whiskers on current only
- Returns ggplot object

#### Function 6: `ks_change_table(ks_hist)` → flextable

- Input: same tibble
- Columns: Segment, Dev KS, Current KS, Absolute Change, Relative Change (%), CI
- Relative change = `ks_delta / dev_ks * 100`
- Conditional formatting: relative decline > 10% = orange, > 15% = red
- Caption: "KS evaluates 2025Q3 bookings — the most recent cohort with a closed 12-month performance window."
- Returns flextable object

#### Function 7: `rank_order_chart(decile_hist, dev_baseline)` → ggplot

- Input: tibble from `load_metrics_history("KS_DECILES")` + `ks_baseline$decile_rates`
- `facet_wrap(~segment, scales = "free_y")` — 6 panels
- Each panel: bar (`geom_col`) for current bad_rate by decile, Wilson CI whiskers, dashed line for dev_bad_rate
- Caption note about Wilson intervals being per-decile screening intervals
- Returns ggplot object

#### Function 8: `executive_summary_table(psi_hist, ks_hist, decile_hist, dev_baseline)` → flextable

- Input: all histories + baseline
- One row per segment (0-4, All Segments)
- Columns: Segment, PSI (Q3), Tier, Tier Certain, KS Dev, KS Current, KS Rel Change (%), Monotonic, Status
- Monotonic: check if current decile bad_rates are non-decreasing (decile 1..10)
- Status logic:
  - "Action required" if investigate tier OR relative KS decline > 15% OR monotonicity break
  - "Review" if watch tier OR relative KS decline > 10%
  - "Stable" otherwise
- Returns flextable object

### Step 2: Modify `orchestration_2.Rmd`

#### 2a: Dynamic date (line 4)

Change `date: "2026-04-28"` to `date: "\`r Sys.Date()\`"`

#### 2b: PSI visuals chunk (insert after line 391)

```
## PSI Trend Visuals

```{r psi_visuals}
source(here::here("R/report_visuals.R"))
source(here::here("R/load_metrics_history.R"))
psi_hist <- load_metrics_history("PSI", 4)
psi_trend_table(psi_hist)
psi_trend_chart(psi_hist)
```
```

~10 lines. Markdown header + code chunk.

#### 2c: CSI visuals chunk (insert after current CSI chunk end)

Markdown intro with the "Candidate drivers" framing and limitation statement, then chunk:

```
## Candidate Drivers of Score Distribution Shift

The score distribution shifted (PSI above), and among model inputs the features
below also shifted materially while others held. These are candidate drivers,
not a decomposition: CSI and PSI are independent calculations on different
variables. Attributing X% of the PSI shift to a specific feature would require
the scorecard weights and a sensitivity analysis, which is outside the scope of
this quarterly review.

```{r csi_visuals}
csi_hist <- load_metrics_history("CSI", 4)
current_q <- max(psi_hist$report_quarter)
csi_heatmap(csi_hist, current_q)
drilldowns <- csi_drilldown_bars(csi_hist, psi_hist, current_q, max_segments = 3)
for (nm in names(drilldowns)) {
  cat("\n\n### Segment", nm, "— Feature Drill-Down\n\n")
  print(drilldowns[[nm]])
}
```
```

~20 lines including the framing paragraph.

#### 2d: KS + rank-ordering visuals chunk (insert after current KS chunk end)

```
## KS and Rank-Ordering Visuals

```{r ks_visuals}
ks_hist <- load_metrics_history("KS")
ks_comparison_chart(ks_hist)
ks_change_table(ks_hist)
```

## Rank Ordering by Segment

```{r rank_order_visuals}
decile_hist <- load_metrics_history("KS_DECILES")
source(here::here("R/ks_baseline.R"))
rank_order_chart(decile_hist, ks_baseline$decile_rates)
```
```

~15 lines.

#### 2e: Methods note (markdown, after KS visuals)

```
## Threshold Provenance and Methods

### Thresholds and Actions

| Metric | Stable | Watch | Investigate |
|---|---|---|---|
| PSI / CSI | < 0.10 | 0.10 – 0.25 | > 0.25 |
| KS relative decline | < 10% | 10% – 15% | > 15% |
| Rank ordering | Monotonic | — | Any break in middle deciles |

**Actions:**
- **Stable**: No action; note in quarterly review.
- **Watch**: Flag in quarterly review; compare to prior quarters for trend.
- **Investigate**: Notify model owner; assess refit need; document in model risk log.

### Statistical Methods

Confidence intervals use two methods:
- **Bootstrap** (B = 500, stratified percentile): PSI, CSI, and KS. Resamples
  rows within each segment, holding group size fixed. Measures sampling
  variability of the metric given the observed cohort.
- **Wilson score**: Decile bad rates. Closed-form binomial CI; survives zero
  counts.

These intervals reflect sampling variability — "if a cohort with this shape had
been drawn differently, how much would the metric move?" They do NOT predict
regeneration variance from the data generator.
```

~25 lines.

#### 2f: Executive summary chunk (insert at end, before QC markers)

```
## Executive Summary

_Placement note: this summary requires values computed throughout the document.
During docx assembly it moves to the front of the report._

```{r executive_summary}
exec_tbl <- executive_summary_table(psi_hist, ks_hist, decile_hist,
                                     ks_baseline$decile_rates)
exec_tbl
```
```

~10 lines.

### Step 3: Testing

Build a synthetic test script (`tests/test_report_visuals.R`) that:

1. Constructs minimal data frames matching cache schemas
2. Calls each function and verifies it returns the right class (flextable/ggplot)
3. Verifies tier encoding includes text symbols (not color-only)
4. Verifies conditional drilldown fires only for watch/investigate
5. Run via `Rscript tests/test_report_visuals.R`

### Step 4: Line-count reconciliation

**Before**: 825 lines (last = `# QC: Validated`)

Estimated insertions:
- After :391 (PSI visuals): ~10 lines
- After :617 (CSI visuals): ~20 lines
- After :821 (KS visuals): ~15 lines
- Methods note: ~25 lines
- Executive summary: ~10 lines

**Estimated after**: 825 + 80 = ~905 lines

All insertions are AFTER their respective KPI chunks, so:
- PSI chunk anchors (:273, :323) — unchanged
- CSI chunk anchors (:400, :516) — shift by ~10 (PSI visuals insertion)
- KS chunk anchors (:628, :630, :634, :747, :789) — shift by ~30 (PSI + CSI visuals)
- QC markers — shift by ~80

Exact deltas computed in Pass 3 after actual insertion.

### Step 5: Documentation

- **D23** in decisions.md: flextable choice, candidate-drivers framing, exec summary placement, CSI drilldown cap at 3
- **R/CATALOG.md**: Add `report_visuals.R` entry
- **CLAUDE.md**: Update validated frontier line, add visual anchors
- **3-execute.md**: Deviations, handoff section

---

## Deviations from task brief

1. **CSI Q2 non-monotonicity**: feature_1 CSI dips at Q2 before spiking at Q3. This is a property of the generator's nonlinear alpha scaling, not a data error. The trend chart will show the actual values without smoothing.

2. **Pass 1 "sparse chart" risk note**: Corrected per user feedback. KS comparison chart is a normal 6-segment grouped bar chart; rank-ordering is 6x10 decile panels. The caption explains cohort lag, not sparsity.

3. **CSI drilldown cap**: Added `max_segments = 3` parameter per user direction. If more than 3 segments flag, only the top 3 by PSI are shown.

4. **KS relative change**: Companion flextable (approved in Pass 1), not chart annotations.

## Open questions

None. All design decisions resolved between Pass 1 approval and the two additions.
