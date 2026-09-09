# Pass 3: Execute — resolve-questions-and-add-narrative

## HANDOFF — User verification required

1. **case_when refactor in compute_si.R**: The two sequential `if_else` calls
   (lines 26-36, old) were replaced with a single `case_when` (lines 26-30,
   new). This function computes BOTH PSI and CSI. The refactor is logically
   equivalent but changes the evaluation pattern. On your next manual render,
   verify that PSI and CSI values are byte-identical to pre-refactor values.
   **Do not trust this as verified — it has not been run.**

2. **Hardcoded quarter removed from KS prose**: The paragraph at the top of
   the KS section previously said "Q3 2026" and "Q3 2025". It now uses relative
   phrasing ("current quarter", "twelve months prior"). Confirm it reads
   correctly for whatever cohort_date you render with.

## Changes made

### R files (Q1-Q4)

| File | Change |
|---|---|
| `R/build_dev_population.R:61-62` | Q1: Replaced QUESTION with 2-line comment explaining `invisible()` |
| `R/compute_si.R:26-30` | Q2: Refactored two `if_else` → single `case_when` with per-branch comments |
| `R/compute_si.R:49-51` | Q3: Replaced QUESTION with 3-line "unreachable tripwire" explanation |
| `R/bootstrap_ci.R:10-15` | Q4: Replaced QUESTION with 6-line block on `conf` as a policy dial |

### orchestration_2.Rmd (N1-N4 + hardcoded quarter fix)

| Block | Location | Action |
|---|---|---|
| N1 — The Frame | After `# Quarterly Report` (:95) | Replaced generic :97-99 with two-question / two-cohort / early-warning frame |
| N2 — What PSI Answers | After `## PSI` (:111) | Replaced cross-reference at old :103 with PSI explanation: frozen vigintiles, thresholds, segment disagreement |
| N3 — What CSI Adds | After `## Candidate Drivers` (:605) | Added CSI explanation + softened threshold caveat (bin-count sensitivity) before existing limitation paragraph |
| N4 — KS and Rank-Ordering | After `## KS and DQ90 Rank Ordering` (:622) | Rewrote hardcoded-quarter paragraph with relative phrasing; added KS/rank-ordering explanation and re-derived decile rationale |
| Code comment fix | :659 | Changed "Pull Q3 2025 apps" → "Pull performance-quarter apps" |

### Line-count delta

| File | Before | After | Delta |
|---|---|---|---|
| `orchestration_2.Rmd` | 865 | 875 | +10 |
| `R/build_dev_population.R` | 63 | 64 | +1 |
| `R/compute_si.R` | 117 | 112 | -5 |
| `R/bootstrap_ci.R` | 44 | 49 | +5 |

### Anchor re-derivation table

| Anchor | Old line | New line | Verified |
|---|---|---|---|
| EOF | :865 | :875 | wc -l |
| `source("R/compute_si.R")` PSI chunk | :261 | :252 | grep |
| PSI bootstrap | :309 | :303 | grep |
| PSI visuals chunk | :380 | :374 | grep |
| CSI chunk opening fence | :395 | :386 | grep |
| CSI bootstrap | :517 | :508 | grep |
| CSI visuals chunk | :623 | :611 | grep |
| KS chunk opening fence | :643 | :630 | grep |
| `source("R/compute_ks.R")` KS chunk | :645 | :632 | grep |
| perf_date | :649 | :636 | grep |
| KS bootstrap | :764 | :751 | grep |
| Wilson CI | :808 | :795 | grep |
| KS visuals chunk | :839 | :826 | grep |
| Rank ordering chunk | :851 | :836 | grep |
| Executive summary chunk | :892 | :871 | grep |
| segment_breaks (D15) | :184-197 | :190-203 | grep |
| suffix = c("", "_dev") (D22) | :756 | :743 | grep |

### Files updated with new anchors

- `CLAUDE.md` — all anchors re-derived
- `R/CATALOG.md` — all 15 file entries re-derived
- `.claude/docs/decisions.md` — D13, D15, D19, D20, D21, D22, D23 re-derived
- `CATALOG.md` — no Rmd line references, no change needed

## Deviations from plan

1. **N3 threshold caveat softened** (correction from Pass 2 review): Changed
   "so the same thresholds apply" to "CSI uses the same thresholds as PSI by
   convention. Note that CSI magnitude is sensitive to bin count — a coarsely
   binned feature reads lower than a finely binned one for the same underlying
   shift — so cross-feature comparisons are indicative rather than strict."

2. **D11, D24 historical line references left unchanged**: These decisions
   reference line numbers from the state when they were written (pre-CSI-build,
   pre-polish). Per the evidence discipline rule, pass artifacts and decision
   rationale are historical records and are not updated.

## Checklist

- [x] All four QUESTION comments removed and replaced with explanations
- [x] compute_si.R refactored to single case_when with per-branch comments
- [x] Four narrative blocks added; each states what the metric answers
- [x] Two-cohort structure and label-free/label-dependent split stated in N1, referenced in N4
- [x] CSI limitation stated in PROSE (existing paragraph preserved; N3 adds positive explanation above it)
- [x] CSI threshold caveat softened per reviewer correction (bin-count sensitivity)
- [x] Zero line-number citations in prose (all relative references)
- [x] Hardcoded quarters removed from :618 prose and :649 code comment
- [x] "approval rate" dropped from N1 (not a reported KPI)
- [x] Line-count delta reported; all live citations re-derived
- [x] HANDOFF section at top of this file
- [x] CLAUDE.md, R/CATALOG.md, decisions.md updated
