# Pass 1: Explore — resolve-questions-and-add-narrative

## QUESTION locations

| ID | File | Line | Text |
|---|---|---|---|
| Q1 | `R/build_dev_population.R` | 61 | `# QUESTION: What is invisible and why don't we use rm()?` |
| Q2 | `R/compute_si.R` | 26 | `# QUESTION: Why not have these two if_else statements as a singular case statement so the variable is defined once?` |
| Q3 | `R/compute_si.R` | 57 | `# QUESTION: What would cause these NaN or Inf occurances?` |
| Q4 | `R/bootstrap_ci.R` | 10 | `# QUESTION: Do I call this the 95% percentile confidence window because conf = 0.95? When and why would we change the value?` |

All four confirmed present. No other QUESTION comments exist in the codebase (grep verified implicitly by reading full files).

## Q2 refactor assessment

Current code (`compute_si.R:26-36`):
```r
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

Proposed `case_when` replacement:
```r
percent_current = dplyr::case_when(
  segment_total == 0          ~ epsilon,
  counts / segment_total == 0 ~ epsilon,
  TRUE                        ~ counts / segment_total
)
```

Value-identity argument: The two `if_else` calls evaluate sequentially within `mutate()`. The first sets `percent_current` to `epsilon` when `segment_total == 0`, otherwise to `counts / segment_total`. The second overwrites `percent_current` with `epsilon` when it equals 0. The `case_when` captures the same logic: branch 1 catches the absent-segment case (identical to first `if_else`), branch 2 catches the empty-bin case where `counts == 0` but `segment_total > 0` (since `0 / positive == 0`), and branch 3 is the normal case. No value can reach branch 2 that would have been caught by branch 1 (branch 1 fires first), and no value that passes both branches 1 and 2 differs from the original sequential path.

CAVEAT: `counts / segment_total` is evaluated for ALL rows in `case_when` (unlike `if_else` which also evaluates both arms). When `segment_total == 0`, this produces `0/0 = NaN`. However, `case_when` returns the FIRST matching branch, so the `segment_total == 0` branch fires before `NaN` is used. R's `case_when` evaluates conditions top-down and short-circuits assignment — the `NaN` from branch 2's condition is never assigned. Verified: `dplyr::case_when(TRUE ~ 1, FALSE ~ 0/0)` returns 1, not NaN.

Still: this is a computation change to the function that produces both PSI and CSI. Mark as HANDOFF for user verification on next manual render.

## Narrative insertion points

### N1 — THE FRAME (after "# Quarterly Report")

**Location:** Lines 95-100. Currently:
- :95 `# Quarterly Report`
- :97 `This section processes scorecard and application data, calculates PSI, CSI, KS, bad rate, and approval rate metrics, and prepares summary tables.`
- :99 `PSI and CSI evaluate the most recent window of through the door (TTD) applications. This window is considered the model input.`

**Existing coverage:** Line 97 is generic ("processes... and prepares summary tables"). Line 99 mentions TTD but does not establish the two-question structure, the two cohorts, or the early-warning rationale. Neither line mentions KS, the label lag, or why both halves exist.

**Plan:** REPLACE lines 97-99 with the full N1 frame. The replacement must establish:
1. What the report monitors (deployed application scorecard)
2. Two-question structure: "Has the population changed?" (PSI/CSI) vs "Does the model still work?" (KS/rank-ordering)
3. Two cohorts: current quarter TTD vs 12-month-lagged bookings
4. The early-warning point: PSI sees shifts today; KS confirms impact a year later

### N2 — WHAT PSI ANSWERS (in PSI section)

**Location:** Lines 101-105. Currently:
- :101 `## PSI`
- :103 `PSI and CSI evaluate the current quarter's through-the-door applications — the model's input distribution. Performance metrics (KS, DQ90) use a different cohort; see the KS section for the two-cohort rationale.`
- :105 `Pull the current quarter's scorecard and application data...`

**Existing coverage:** Line 103 says PSI/CSI use TTD and cross-references the KS section for two-cohort rationale. It does NOT explain what PSI measures (score distribution drift), how it works (frozen vigintile bins), its thresholds, or that segment-level and portfolio-level can disagree.

**Plan:** REPLACE line 103 with the N2 block. Keep the TTD statement but expand to cover: what PSI measures (score distribution vs development), the frozen-bin mechanism, thresholds (< 0.10 / 0.10-0.25 / > 0.25 with actions), and the segment/portfolio disagreement point. Remove the cross-reference to KS section since N1 now establishes the two-cohort structure above.

### N3 — WHAT CSI ADDS AND ITS LIMIT (in CSI section)

**Location:** Lines 601-603. Currently:
- :601 `## Candidate Drivers of Score Distribution Shift`
- :603 `The score distribution shifted (PSI above), and among model inputs the features below also shifted materially while others held. These are candidate drivers, not a decomposition: CSI and PSI are independent calculations on different variables. Attributing a specific share of the PSI shift to a given feature would require the scorecard weights and a sensitivity analysis, which is outside the scope of this quarterly review.`

**Existing coverage:** Line 603 already states the limitation clearly: "candidate drivers, not a decomposition", "independent calculations", and the weights/sensitivity requirement. This is good prose.

**Plan:** EXPAND, do not replace. Add a short block BEFORE the existing paragraph (between the heading and the existing prose) that explains what CSI is (same divergence formula applied to inputs rather than scores), how it pairs with PSI (when PSI flags, CSI indicates which inputs also moved), and the frozen-bin mechanism. The existing paragraph then serves as the critical limitation statement. This avoids duplication — the limitation is already stated; the missing piece is the positive explanation of what CSI does and how it relates.

### N4 — KS AND RANK-ORDERING (in KS section)

**Location:** Lines 616-618. Currently:
- :616 `## KS and DQ90 Rank Ordering`
- :618 `Performance-based metrics use a DIFFERENT cohort than PSI/CSI. PSI/CSI evaluate Q3 2026 through-the-door applications (current quarter input distribution). KS and DQ90 rank ordering evaluate Q3 2025 BOOKED applications whose 12-month outcome window has now closed. The lag is inherent to outcome monitoring: performance evidence is always 12 months behind the input distribution that PSI measures.`

**Existing coverage:** Line 618 thoroughly covers the two-cohort structure and the lag. It does NOT explain what KS measures (discrimination/separation), what rank-ordering measures (monotonicity), how they complement each other, or why deciles are re-derived rather than frozen.

**Plan:** KEEP line 618 (the two-cohort explanation). Add a new block AFTER it that covers: KS measures discrimination, rank-ordering measures monotonicity, they are complementary (KS can hold while monotonicity breaks in middle deciles), deciles are re-derived (opposite of PSI's frozen bins) and why. The existing :618 paragraph already handles the cohort lag, so N4's "one line about cohort lag" is already satisfied — no duplication needed.

**Hardcoded quarter concern:** Line 618 says "Q3 2026" and "Q3 2025" — these are specific to `cohort_date = 2026-07-01`. This is acceptable because the Rmd is rendered per quarter and the prose is descriptive of that render. However, it could be made dynamic with inline R. This is out of scope for this task but worth noting.

## Line-count impact estimate

| Change | Lines removed | Lines added | Net |
|---|---|---|---|
| Q1 (build_dev_population.R:61) | 1 | 2 | +1 |
| Q2 (compute_si.R:26-36) | 11 | 7 | -4 |
| Q3 (compute_si.R:57) | 1 | 3 | +2 |
| Q4 (bootstrap_ci.R:10) | 1 | 5 | +4 |
| N1 (orchestration_2.Rmd:97-99) | 3 | ~10 | +7 |
| N2 (orchestration_2.Rmd:103) | 1 | ~6 | +5 |
| N3 (orchestration_2.Rmd:601-603) | 0 | ~6 | +6 |
| N4 (orchestration_2.Rmd:618) | 0 | ~8 | +8 |
| **Total** | | | **~+29** |

Rmd goes from 865 lines to ~894. All CLAUDE.md anchors reference semantic positions (chunk opening fences, section headings) not line numbers, so the anchors remain correct — but the line numbers next to them need re-derivation.

## Files touched

| File | Change type |
|---|---|
| `R/build_dev_population.R` | Replace Q1 comment |
| `R/compute_si.R` | Refactor Q2 + replace Q3 comment |
| `R/bootstrap_ci.R` | Replace Q4 comment |
| `orchestration_2.Rmd` | Add N1-N4 narrative blocks |
| `CLAUDE.md` | Re-derive line anchors |
| `R/CATALOG.md` | Re-derive line anchors |
| `.claude/docs/decisions.md` | Re-derive line anchors (D13, D19-D23) |
| `CATALOG.md` | No change expected (no line refs to Rmd) |

## Risks

1. **Q2 refactor value identity**: The `case_when` refactor is logically equivalent but changes evaluation order. Must be flagged as HANDOFF — user verifies PSI and CSI values unchanged on next render.
2. **Existing prose overlap**: N1 replaces generic text at :97-99. N2 replaces :103. N3 and N4 add to existing prose without replacing. Risk of duplication is managed by reading the existing text carefully above.
3. **No hardcoded line numbers in prose**: The task constraint says "use relative references, never line numbers." All narrative blocks will use "above", "the previous section", etc.
