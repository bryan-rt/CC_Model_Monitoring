# Pass 3 — Execute: build-report-visuals

Date: 2026-09-07  ·  Branch: pass3/build-report-visuals

## What was implemented

### `R/report_visuals.R` (NEW, ~290 lines)

8 visualization functions, all taking tibbles from `load_metrics_history()`:

1. `psi_trend_table(psi_hist)` → flextable. 4-quarter rolling table, columns =
   segments. Cell text: `0.300 !` / `0.090 S*`. Tier encoded as S/W/! symbol
   (greyscale-safe). `*` for tier_certain=FALSE. Background color by tier.
   Footnote explains symbols.

2. `psi_trend_chart(psi_hist)` → ggplot. `facet_wrap(~Scorecard, ncol=3)`,
   6 panels, shared y-axis. CI ribbon, threshold bands (green/orange/red).

3. `csi_heatmap(csi_hist, quarter)` → ggplot. `geom_tile` with
   `scale_fill_gradient2`, text overlay with CSI value.

4. `csi_drilldown_bars(csi_hist, psi_hist, quarter, max_segments=3)` → list
   of ggplots. Horizontal bars for flagged segments only (PSI watch/investigate),
   sorted by PSI descending, capped at 3.

5. `ks_comparison_chart(ks_hist)` → ggplot. Grouped bar (dev vs current),
   CI whiskers on current only.

6. `ks_change_table(ks_hist)` → flextable. Relative change column with
   conditional formatting (orange >10%, red >15%).

7. `rank_order_chart(decile_hist, dev_decile_rates)` → ggplot.
   `facet_wrap(~segment, scales="free_y")`, bars with Wilson CI whiskers,
   dashed dev baseline.

8. `executive_summary_table(psi_hist, ks_hist, decile_hist, dev_decile_rates)` →
   flextable. One row per segment. Status: Action required / Review / Stable.

### `orchestration_2.Rmd` (MODIFIED, 825 → 911 lines, +86)

- **Line 4**: YAML date changed from `"2026-04-28"` to `` `r Sys.Date()` ``
- **Lines 392-402**: PSI visuals chunk (sources report_visuals.R + load_metrics_history.R)
- **Lines 628-647**: CSI visuals section (candidate-drivers framing paragraph + chunk)
- **Lines 852-859**: KS visuals chunk
- **Lines 861-866**: Rank ordering chunk
- **Lines 868-900**: Methods note (thresholds, actions, bootstrap/Wilson caveat)
- **Lines 902-908**: Executive summary chunk (placement note included)

### `renv.lock` (MODIFIED)

Added flextable + 7 transitive dependencies: flextable, gdtools, officer,
ragg, systemfonts, textshaping, uuid.

### Documentation

- **D23** added to decisions.md
- **R/CATALOG.md**: report_visuals.R and load_metrics_history.R entries added
- **CLAUDE.md**: line count, anchors, visual descriptions updated

## Line-count reconciliation

| Anchor | Before | After | Delta |
|---|---|---|---|
| `source("R/compute_si.R")` (PSI) | :273 | :272 | -1 (YAML date change) |
| PSI bootstrap | :323 | :323 | 0 (before insertion point) |
| `source("R/write_metrics_cache.R")` | :386 | :385 | -1 |
| PSI cache write | :390 | :389 | -1 |
| CSI chunk opening | :400 | :409 | +9 (PSI visuals insertion) |
| CSI bootstrap | :516 | :531 | +15 |
| CSI cache write | :616 | :625 | +9 |
| KS chunk opening | :628 | :657 | +29 (PSI + CSI visuals) |
| `source("R/compute_ks.R")` | :630 | :659 | +29 |
| perf_date assignment | :634 | :663 | +29 |
| KS bootstrap | :747 | :778 | +31 |
| Wilson CI decile | :789 | :819 | +30 |
| KS cache writes | :815-820 | :846-849 | +31 |
| `# QC: Completed` | :823 | :909 | +86 |
| `# QC: Validated` | :825 | :911 | +86 |

## Deviations from plan

1. **KS change table relative change formatting**: Plan called for rendering
   beside the chart. Implemented as a separate flextable rendered after the
   chart — same effect in linear Rmd flow.

2. **Executive summary monotonicity**: Segments 3 and 4 show monotonicity
   breaks in the current data, triggering "Action required." This is correct
   per the spec — any monotonicity break in middle deciles triggers
   investigation.

## Verification

### All 8 functions tested (VERIFIED)

```
PSI Trend Table: flextable, 4 rows, tier symbols S/W/!/*
PSI Trend Chart: ggplot, 6 facets
CSI Heatmap: ggplot
CSI Drilldown: 3 flagged segments (0, 2, 4)
KS Comparison: ggplot
KS Change Table: flextable
Rank Order: ggplot, 6 facets with free_y
Executive Summary: flextable, 6 rows
```

### Greyscale safety (VERIFIED)

Tier encoding uses text symbols (S/W/!) alongside color. PSI trend table
cell text includes the tier initial. `*` marks uncertain tiers. A reader
in greyscale or colorblind mode can distinguish all three tiers.

### Conditional drilldown (VERIFIED)

Q3 2026 flagged segments: 0 (investigate), 2 (investigate), 4 (watch).
Segments 1, 3, All Segments: stable → no drilldown rendered.
Cap at 3 respected (all 3 flagged segments shown).

### Data sourced from cache (VERIFIED)

All visuals call `load_metrics_history()`. No in-memory objects consumed.

## HANDOFF — User must render manually

The user must run `orchestration_2.Rmd` in RStudio to see the visuals.
The new chunks (psi_visuals, csi_visuals, ks_visuals, rank_order_visuals,
executive_summary) will render inline. The full pipeline takes ~3 minutes
(bootstrap CIs dominate).

To render a single quarter with full trend visuals:
1. Set `cohort_date <- as.Date("2026-07-01")` (or comment out for auto)
2. Knit the document in RStudio

The executive summary is at the END of the document. During future docx
assembly, it moves to the front of the report.
