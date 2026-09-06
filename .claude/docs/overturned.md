# Overturned Conclusions

Conclusions we reached and later killed, so they don't get quietly re-derived.

---

### O1 — "OCR output can be validated by reading it."
**Date overturned:** 2026-09-05
**What we believed:** Careful visual review of transcribed code is sufficient to confirm correctness.
**What overturned it:** Two errors were found behind the `# QC: Validated` marker in `orchestration_2.Rmd`: `%m+` missing its closing `%` (line ~178), and `prim_score < 100 < -1` where R chains the comparisons — `prim_score < 100` evaluates to a logical, which is then compared to `-1`, silently returning `FALSE` so the `case_when` branch never fires (lines 203, 248). It won't error; it just quietly drops the condition. Both bugs are syntactically valid and survived human review. Live execution is the only real gate.
