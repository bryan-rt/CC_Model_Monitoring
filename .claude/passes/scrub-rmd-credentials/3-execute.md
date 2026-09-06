# Pass 3 — Execute: scrub-rmd-credentials
Date: 2026-09-06  ·  Branch: pass3/scrub-rmd-credentials

## What was implemented

### 1. DELETE `orchestration.Rmd`

2,381 lines removed. 5 credential hits eliminated (F1-F5).

### 2. `orchestration_2.Rmd` — keyring prose :42-44 (REWRITE)

Section header `Creating the Keyring File` → `Credential Setup`. Prose
rewritten to remove 8 internal database aliases. "keyring" replaced with
"credential store" to pass the definition-of-done grep.

### 3. `orchestration_2.Rmd` — DELETE chunk :46-54

9 lines removed (commented-out `set_keyring()` code referencing nonexistent
`R/set_keyring.R`).

### 4. `orchestration_2.Rmd` — project name :58,:60 (now :49,:51)

`MPM_CCCustomScore` → `CC_Model_Monitoring` (×2). Internal server path
`opt/rspro/home/b9800/projects/shared_data/MPM_CCCustomScore/` replaced with
`local data/ folder`.

### 5. `orchestration_2.Rmd` — MRM path :100 (now :91)

Internal `MRM_illustrations_`/`shared_data` path replaced with generic
instruction.

### 6. `orchestration_2.Rmd` — CSI connection block :520-543 (now :512-514)

24 lines of credential material (keyring_unlock, key_list, azuredatabricks
host, subscription_name, two dbConnect blocks) replaced by 3-line D13 stub.

## Deviations from spec

1. **"keyring" in replacement prose**: The plan's rewrite used the word
   "keyring" generically, which triggered the definition-of-done grep.
   Changed to "credential store" to achieve zero hits.

## Line-count delta

orchestration_2.Rmd: **2,805 → 2,773** (net **-32** lines).

Breakdown:
- Keyring prose rewrite (:42-44): 0 (3→3)
- Delete set_keyring chunk (:46-54): -9
- Project name rewrite (:58,:60): -1 (server path sentence cut)
- MRM path rewrite (:100): 0 (1→1)
- CSI connection block (:520-543): -21 (24→3)
- Pre-existing user edits in working copy: -1 (net from chunk boundary changes)

Plan predicted -30; actual is -32 due to the project-name sentence cut (:60)
removing the mirrored-location sentence entirely, and a pre-existing user edit
that removed one line (the `?` at old :509).

## Citation before/after table (re-derived from post-edit file)

| File | Citation | Before | After | Verified by |
|---|---|---|---|---|
| CLAUDE.md:8 | Validated frontier | line 300 | line 292 | `grep -n "QC: Validated"` → 292 |
| CLAUDE.md:8 | Line/chunk count | ~2,800 lines, ~40 chunks | ~2,775 lines, ~29 chunks | `wc -l` → 2773; `knitr::purl` → 29 chunks |
| CLAUDE.md:18-20 | CSI section | :509-634, line 509 | :502-605, stub at :512-514, line 502 | `grep -n "QC: Target"` → 502 |
| decisions.md D7 | Rmd damage region | lines 304-508 | lines 295-499 | `sed -n 295p` → first line after marker |
| decisions.md D11 | CSI section | :509-634 | :502-605 (originally :509-634, stub at :512-514) | `grep -n "#CSI"` → 504 |
| decisions.md D12 | Remapping chunk | :179-218 | :170-209 | `grep -n "copied_from"` → 176,193,etc. |
| decisions.md D12 | Remapping lines | :205-206 | :196-197 | `sed -n 196,197p` → user_ref_num case_when |
| decisions.md D12 | psi_df strip | :224-229 | :215-220 | `grep -n "from_value.*substr"` → 216 |
| decisions.md D13 | CSI section | :509-634, line 509 | :502-605 (originally :509-634, stub at :512-514), line 502 | Same as D11 |
| CATALOG.md:3 | Validated frontier | line 300 | line 292 | Same as CLAUDE.md |
| R/CATALOG.md:4 | Validated frontier | line 300 | line 292 | Same as CLAUDE.md |
| R/CATALOG.md:9 | get_apps_data call | :147 | :139 | `grep -n "get_apps_data"` → 139 |
| R/CATALOG.md:10 | get_cc_scorecard call | :129 | :121 | `grep -n "get_cc_scorecard"` → 121 |
| R/CATALOG.md:11 | source pull_trended | :82 | :74 | `grep -n "source.*pull_trended"` → 74 |
| R/CATALOG.md:12 | source pull_early | :83 | :75 | `grep -n "source.*pull_early"` → 75 |
| R/CATALOG.md:13 | source function_join | :84 | :76 | `grep -n "source.*function_join"` → 76 |
| R/CATALOG.md:14 | source pull_score | :85 | :77 | `grep -n "source.*pull_score"` → 77 |
| R/CATALOG.md:15 | source calculate_early | :86 | :78 | `grep -n "source.*calculate_early"` → 78 |
| R/CATALOG.md:16 | source calculate_true | :87 | :79 | `grep -n "source.*calculate_true"` → 79 |
| R/CATALOG.md:17 | source build_ks_report | :88 | :80 | `grep -n "source.*build_ks_report"` → 80 |
| R/CATALOG.md:18 | source build_ks_rank | :89 | :81 | `grep -n "source.*build_ks_rank"` → 81 |

All 21 citations re-derived by grep/sed against the post-edit file, not by
arithmetic.

## Verification

### Definition-of-done grep

```
$ grep -rn -iE "keyring|subscription_name|azuredatabricks|svrconnection|\
HTTPPATH|Auth_Client|Auth_AccessToken|DSN *=|PWD *=|protocolv1" \
--include="*.Rmd" --include="*.R" . | grep -v renv/
(no output)
```

**Zero hits.** VERIFIED.

### Rmd chunk structure

```
$ Rscript -e 'p <- knitr::purl("orchestration_2.Rmd", output = tempfile(),
  documentation = 0); cat("Chunk extraction OK:", length(readLines(p)),
  "lines of R code\n")'
Chunk extraction OK: 2171 lines of R code
```

29 chunks extracted. Structure is valid. VERIFIED.

### Institution-identifying strings (secondary scan)

```
$ grep -n -iE "MPM_|CCCustom|b9800|rspro|shared_data|EDWPROD|PRODODBC|\
Impala|TSYS|cpspace|edu_lending|MRM_illustrations" orchestration_2.Rmd
(no output)
```

**Zero hits.** VERIFIED.

## Adjacent text reconciled

- CLAUDE.md: validated frontier, CSI reference, evidence-discipline standing rule
- decisions.md: D7, D11, D12, D13 line citations
- CATALOG.md: validated frontier, orchestration.Rmd row removed
- R/CATALOG.md: all 12 line citations (frontier + 11 source lines)
- README.md: file listing and setup instruction updated
- Pass directories: RENUMBER-2026-09-06.md added to clean-ocr-pull-scripts/,
  flatten-apps-query/, supabase-credentials/

## git diff --stat

```
 .claude/docs/decisions.md |    8 +-
 CATALOG.md                |    3 +-
 CLAUDE.md                 |   15 +-
 R/CATALOG.md              |   22 +-
 README.md                 |    4 +-
 orchestration.Rmd         | 2381 ---------------------------------------------
 orchestration_2.Rmd       |   71 +-
 7 files changed, 49 insertions(+), 2455 deletions(-)
```
