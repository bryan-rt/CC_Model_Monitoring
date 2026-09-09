# Pass 2: Plan — resolve-questions-and-add-narrative

## Corrections from Pass 1 review

### Correction 1 (BLOCKING): Hardcoded quarters in prose

**Sweep results — all quarter/date references in the Rmd:**

| Line | Type | Text | Verdict |
|---|---|---|---|
| :69 | code comment | `# Available quarters (generated data): 2025Q4, 2026Q1, 2026Q2, 2026Q3` | OK — documents available data, not report output |
| :70 | code comment | `# cohort_date <- as.Date('2026-07-01')` | OK — example override, commented out |
| :97 | prose | "calculates PSI, CSI, KS, bad rate, and approval rate metrics" | REPLACE (part of N1 rewrite; also drops false "approval rate" claim — see correction 3) |
| :618 | prose | "PSI/CSI evaluate Q3 2026... KS evaluate Q3 2025..." | **BLOCKING** — hardcoded quarters |
| :649 | code comment | `# Pull Q3 2025 apps + scorecard for score and segment` | FIX — make relative ("performance-quarter apps") |

No other prose lines contain hardcoded quarters or metric values.

**Fix plan for :618:** Rewrite to use relative phrasing: "the current quarter's through-the-door applications" and "bookings from twelve months prior." The specific quarters are already computable from `cohort_date` and `perf_date`; the prose does not need to repeat them. This also future-proofs the document for any `cohort_date` override.

**Fix plan for :649:** Change comment to `# Pull performance-quarter apps + scorecard for score and segment` (perf_date is defined at :626, one screen above).

### Correction 2: Reconcile overlapping prose

Pass 1 finding "No existing prose duplicates the planned narrative blocks" was incorrect. The plan correctly replaces :97-99 (N1) and :103 (N2), but the finding implied nothing needed reconciling.

Corrected finding: Lines :97-99 and :103 overlap with N1 and N2 respectively. The plan REPLACES both, so no duplication survives in the output. Specifically:
- :97 ("This section processes scorecard...") — deleted, replaced by N1
- :99 ("PSI and CSI evaluate the most recent window of TTD...") — deleted, replaced by N1
- :103 ("PSI and CSI evaluate the current quarter's... see the KS section for the two-cohort rationale") — deleted, replaced by N2

The execute step must delete these lines as part of the N1/N2 insertions, not leave them in place.

### Correction 3: "approval rate" is not a reported KPI

Grep confirms: `approval_rate` appears only in `R/generate_cohort.R` as a generator parameter (per-segment approval rates for synthesizing decisions). The Rmd never computes or displays an approval rate metric. Line :97's claim is false.

N1 will NOT mention approval rate. The metrics the report actually computes: PSI, CSI, KS, and decile bad rates (rank ordering).

## Execution plan

### Step 1: Q1 — R/build_dev_population.R:61

Replace:
```r
  # QUESTION: What is invisible and why don't we use rm()?
  invisible(dev_pop)
```

With:
```r
  # invisible(): return the data for callers who want it, without printing
  # 120 rows to the console/report on every run.
  invisible(dev_pop)
```

### Step 2: Q2 — R/compute_si.R:26-36 (refactor)

Replace lines 26-36:
```r
      # QUESTION: Why not have these two if_else statements as a singular case statement so the variable is defined once?
      percent_current = dplyr::if_else(
        segment_total == 0,
        epsilon,
        counts / segment_total
      ),
      percent_current = dplyr::if_else(
        percent_current == 0,
        epsilon,
        percent_current
      ),
```

With:
```r
      percent_current = dplyr::case_when(
        segment_total == 0          ~ epsilon,  # segment absent entirely
        counts / segment_total == 0 ~ epsilon,  # bin empty within a populated segment
        TRUE                        ~ counts / segment_total
      ),
```

### Step 3: Q3 — R/compute_si.R:57

Replace:
```r
  # QUESTION: What would cause these NaN or Inf occurances?
```

With:
```r
  # Should be unreachable — the epsilon floor blocks NaN/-Inf and the dev
  # reference is uniform by construction. This is a tripwire: if it fires,
  # the epsilon floor or the dev population file has broken.
```

### Step 4: Q4 — R/bootstrap_ci.R:10

Replace:
```r
# QUESTION: Do I call this the 95% percentile confidence window because conf = 0.95? When and why would we change the value?
```

With:
```r
# conf sets the interval width. 95% is convention. Raise to 0.99 when a false
# escalation is expensive (wider interval, fewer flags, more confidence in
# each). Lower to 0.90 for an early-warning screen where a missed shift costs
# more than a second look. The level is a policy dial on how much ambiguity is
# tolerated before escalating — it directly changes which segments come back
# tier_certain = FALSE.
```

### Step 5: N1 — The Frame (orchestration_2.Rmd)

DELETE lines :97-99. INSERT after `# Quarterly Report` (:95):

```markdown
This report monitors a deployed application scorecard. It answers two questions:

**Has the population changed?** PSI and CSI compare the current quarter's
through-the-door applications to the development population. These use only
inputs and scores — no outcome labels required — so they are available as soon
as applications arrive.

**Does the model still work?** KS and rank-ordering compare predicted risk
to realized outcomes. Because outcomes require a 12-month performance window,
these metrics necessarily lag by one year.

The report therefore draws on two cohorts: PSI and CSI use the current quarter's
applications; KS and rank-ordering use bookings from twelve months prior whose
outcome window has closed. The label-free half is the early warning system: if
the population shifts today, PSI sees it today. KS cannot confirm a performance
impact for another year. That lag is why both halves exist.
```

### Step 6: N2 — What PSI Answers (orchestration_2.Rmd)

DELETE line :103 (the old "PSI and CSI evaluate the current quarter's..." cross-reference). INSERT after `## PSI`:

```markdown
Population Stability Index measures how far the current score distribution has
moved from the development population. Scores are binned into frozen development
vigintiles — the reference is uniform by construction (5% per bin), so any
departure is drift. Thresholds: below 0.10 is stable (note in review), 0.10 to
0.25 is watch (flag and compare to prior quarters), above 0.25 is investigate
(notify model owner, assess refit). Segment-level and portfolio-level PSI can
disagree; that disagreement is the reason for segment-level monitoring.
```

### Step 7: N3 — What CSI Adds (orchestration_2.Rmd)

INSERT between the `## Candidate Drivers` heading (:601) and the existing limitation paragraph (:603). Do NOT touch the existing paragraph.

```markdown
Characteristic Stability Index applies the same divergence calculation to each
model input rather than the score. When PSI flags a segment, CSI indicates
which inputs also shifted. The bins are frozen development breaks (analogous to
PSI's vigintiles), so the same thresholds apply.
```

### Step 8: N4 — What KS and Rank-Ordering Answer (orchestration_2.Rmd)

REWRITE line :618 to remove hardcoded quarters (correction 1). Then ADD a new block after it.

Replace :618 with:
```markdown
Performance-based metrics use a different cohort than PSI and CSI. PSI and CSI
evaluate the current quarter's through-the-door applications. KS and rank-
ordering evaluate bookings from twelve months prior whose outcome window has
closed. The lag is inherent: performance evidence is always one year behind
the input distribution that PSI measures.
```

Add after it:
```markdown
KS (Kolmogorov-Smirnov) measures discrimination — how well the score separates
accounts that went bad from those that did not. Rank-ordering asks whether bad
rates decline monotonically across score deciles: whether the score is still
ordered correctly. They are complementary: KS can hold while monotonicity
breaks in the middle deciles, meaning overall separation looks acceptable while
the score is inverted over part of its range.

Unlike PSI's frozen vigintile bins, KS deciles are re-derived from the booked
cohort. The distinction is intentional: PSI asks whether the population moved
relative to development; KS asks whether the score still separates within this
population.
```

### Step 9: Fix code comment at :649

Replace:
```r
# Pull Q3 2025 apps + scorecard for score and segment
```
With:
```r
# Pull performance-quarter apps + scorecard for score and segment
```

### Step 10: Re-derive line anchors

After all edits, count the new Rmd line total and re-derive every anchor in:
- `CLAUDE.md`
- `R/CATALOG.md`
- `.claude/docs/decisions.md`

Report a before/after table.

### Step 11: Write 3-execute.md

Include:
- HANDOFF section at top: user must verify PSI and CSI values unchanged after case_when refactor
- Deviations section
- Line-count delta and anchor re-derivation table

## Execution order

Steps 1-4 (Q comments) are independent of each other and of steps 5-9 (Rmd narrative). Steps 5-9 are sequential within the Rmd (edits from top to bottom to avoid line-shift confusion). Step 10 depends on all prior steps completing. Step 11 is last.

## Handoff items (for 3-execute.md)

1. **Q2 case_when refactor**: User must render the Rmd and confirm PSI and CSI values are byte-identical to pre-refactor values. The refactor is logically equivalent but changes evaluation pattern in a function shared by both metrics.
2. **Hardcoded quarter in :649 code comment**: Changed to relative phrasing. User should confirm it reads clearly in context on next review.
