# Pass 2 — Plan: scrub-rmd-credentials
Date: 2026-09-06  ·  Grounded in: 1-explore.md

## Objective

After this change, zero credential or infrastructure identifiers remain in
`*.Rmd` or `*.R` files (excluding `renv/`). `orchestration.Rmd` is deleted.
`orchestration_2.Rmd` retains its structure with the CSI connection block
replaced by a D13 stub and institution-specific references genericized.

## Line number reconciliation

The working copy of `orchestration_2.Rmd` has pre-existing user edits that
shifted line numbers versus the committed version. The credential block is at
**:520-543** in the working copy (was :523-546 in Pass 1's grep against the
committed version). All line references below use the working-copy numbering.

## Changes

### 1. DELETE `orchestration.Rmd` (2,381 lines)

Removes F1-F5 (5 credential hits). File is SUPERSEDED in CATALOG.md, consumed
by nothing. OCR-comparison value banked in `scripts/discrepancies.log`.

### 2. `orchestration_2.Rmd` — keyring prose :42-44 (REWRITE)

**Before** (:42-44):
```
### 1) Creating the Keyring File

The set_keyring function is an internal designed function which will set up a keyring file in the posit environment for the user. This keyring file will handle user credentials when connecting with databases (e.g. 'EDWPROD', 'PRODODBC', 'Impala64', 'TSYS_DV_DB2', 'ASL', 'cpspace', 'MySQL_CPSpace', 'edu_lending'). The function has three inputs ...
```

**After** (:42-44):
```
### 1) Credential Setup

Database credentials are supplied via environment variables from `.Renviron`;
see `.Renviron.example`. In the production environment this section configured
a keyring for the internal warehouses.
```

Removes 8 internal database aliases while preserving narrative structure.
3 lines replace 3 lines — zero line-count delta.

### 3. `orchestration_2.Rmd` — DELETE chunk :46-53

The `set_keyring()` code chunk is fully commented out, references
`R/set_keyring.R` which does not exist, and is dead under D3. Delete the
entire chunk (lines 46-54, including the closing ` ``` `).

9 lines removed. Lines after :54 shift up by 9.

### 4. `orchestration_2.Rmd` — project name :58,:60 → :49,:51 (after shift)

**:58** (becomes :49): Replace `MPM_CCCustomScore` with `CC_Model_Monitoring`.
**:60** (becomes :51): Replace `MPM_CCCustomScore` repo reference and the
internal server path `opt/rspro/home/b9800/projects/shared_data/MPM_CCCustomScore/`.

Before (:60):
```
Code and reference files are sourced within the `MPM_CCCustomScore` repo. Data is written in this directory as well as a mirrored location at opt/rspro/home/b9800/projects/shared_data/MPM_CCCustomScore/. This location will house data for collaboration without allowing contributors to edit original data sets.
```

After (:51):
```
Code and reference files are sourced within the `CC_Model_Monitoring` repo. Data is written in this directory as well as a local `data/` folder.
```

The mirrored-location sentence is cut entirely — it names an internal server
path with user ID `b9800` and the internal project name.

### 5. `orchestration_2.Rmd` — MRM path :100 → :91 (after shift)

**:100** (becomes :91): Contains internal shared_data path with
`MRM_illustrations_` and `MRM_[UNCLEAR]`. Replace the entire bold instruction:

Before:
```
**MRM** - after folder creation, copy all data from the mirrored shared directory into the cloned repo to preserve file pointers and code like: cp -r /mnt/c/sp/custom/path/AAAA/projects/shared_data/MRM_illustrations_/MRM_[UNCLEAR]/monitor/ to move files into the needed locations
```

After:
```
**Note** — after folder creation, copy any required data files into the local `data/` directory to preserve file pointers.
```

### 6. `orchestration_2.Rmd` — CSI connection block :520-543 → :511-534 (after shift)

Replace lines :520-543 (24 lines of credential material) with a D13 stub
comment (3 lines). This is inside the `{r}` chunk that opens at :516 (→:507).

Before (:520-543): keyring_unlock, key_list, host, subscription_name,
compute_cluster, two dbConnect blocks.

After (:511-513):
```r
# CSI data pull — OUT OF SCOPE this iteration (D13).
# Production connected to a separate BI warehouse. Will be replaced by a
# Supabase table and its own pull function once the validated marker reaches this section.
```

24 lines replaced by 3 lines. Net: -21 lines from this edit.

Lines :544+ (non-connection CSI logic) are preserved and shift up by 21.

### 7. `CATALOG.md` — remove orchestration.Rmd row

### 8. `README.md` — remove orchestration.Rmd reference at :18,:27

### 9. `CLAUDE.md` — update loop position, note orchestration.Rmd deletion

## Institution-identifying strings scan (non-grep)

Manual read of orchestration_2.Rmd for strings the identifier grep would miss:

| Line (working copy) | Content | Action |
|---|---|---|
| :44 | 8 database aliases (EDWPROD, etc.) | Rewrite prose (change 2) |
| :51 | `set_keyring(#db = c("EDWPROD", "PRODODBC", "ASL")` | Delete chunk (change 3) |
| :58 | `MPM_CCCustomScore` project name (×1) | Rename (change 4) |
| :60 | `MPM_CCCustomScore` (×1) + `opt/rspro/home/b9800/...` server path | Rewrite (change 4) |
| :100 | `MRM_illustrations_`, `shared_data`, internal cp path | Rewrite (change 5) |
| :525 | `SPACE-IT-PROD-BI` subscription | Replace block (change 6) |

**Not found** (scanned and clean): No team names, division names, product codes,
or institution identifiers beyond the above. DSN alias `'BI'` at :537 is generic
enough to keep — but it's inside the block being replaced anyway.

## Line-count delta

| Edit | Lines removed | Lines added | Net |
|---|---|---|---|
| Keyring prose rewrite (:42-44) | 3 | 3 | 0 |
| Delete set_keyring chunk (:46-54) | 9 | 0 | -9 |
| Project name rewrite (:58,:60) | 2 | 2 | 0 |
| MRM path rewrite (:100) | 1 | 1 | 0 |
| CSI connection block (:520-543) | 24 | 3 | -21 |
| **Total** | | | **-30** |

orchestration_2.Rmd: 2,805 → ~2,775 lines.

**Impact on cited line numbers:** Lines before :42 are unchanged. Lines :42-44
are rewritten in-place. Lines :55+ shift up by 9. Lines :520+ shift up by 9+21=30.
The most-cited lines are in the PSI region (:179-300) which shifts by 9 to
:170-291. The `# QC: Validated` marker moves from :301 to :292.

This shift affects citations in CLAUDE.md, decisions.md, and pass artifacts.
**Do NOT update historical citations** (pass artifacts record what was true at
the time). **Do** update CLAUDE.md's validated-frontier reference.

## Blast radius

| Thing changed | What reads it |
|---|---|
| `orchestration.Rmd` deleted | Nothing (CATALOG.md: "Read by: Nothing") |
| `:42-54` prose + chunk rewritten/deleted | No code depends on prose |
| `:58,:60` project name rewritten | No code reads prose |
| `:100` MRM path rewritten | No code reads prose |
| `:520-543` connection block → stub | D13: CSI out of scope. No downstream code in the current loop depends on this connection. |

## Definition of done

- [ ] Definition-of-done grep returns zero hits
- [ ] `orchestration.Rmd` deleted
- [ ] `orchestration_2.Rmd` parses as Rmd (knitr chunk structure readable)
- [ ] Line-count delta reported
- [ ] `CLAUDE.md` validated-frontier line number updated
- [ ] `CATALOG.md`, `README.md` updated
- [ ] 3-execute.md written
- [ ] Committed to branch `pass3/scrub-rmd-credentials`, pushed
