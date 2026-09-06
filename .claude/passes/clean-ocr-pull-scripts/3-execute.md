# Pass 3 — Execute: clean-ocr-pull-scripts

Execution commit: `7793038` (main). This document records what was done, what
was observed, and what was not achieved.

---

## Edits applied

### R/pull_apps.R — 17 edits (PA-1 through PA-17)

| # | Action | Traces to |
|---|---|---|
| PA-1 | Deleted stray `if performance_window <- ...` at line 4 | MF-PA#1 |
| PA-2 | Deleted `keyring::keyring_unlock(password = 'keyring')` | MF-PA#2 |
| PA-3 | Deleted orphaned `keys <- keyring::key_list()` | MF-PA#2 |
| PA-4 | Replaced TSYS_TA odbc::dbConnect block with `conn <- db_connect()` | Connection plan |
| PA-5 | Inserted provisional `db_connect()` definition (RPostgres + Sys.getenv) | Connection plan |
| PA-6 | Changed `conn = TSYS_TA` to `conn = conn` | Connection plan |
| PA-7 | Replaced logic CASE (pre-edit lines 52-60 @ b59d6c8) with 3-branch AUTO/MANUAL reconstruction + disclosure comment | JC1 |
| PA-8 | Added comment after ELEMENT_NAME IN list re: NAVY CUSTOM SCORE 3 absence and underscore/space mismatch | JC3 |
| PA-9 | Fixed officer-log subquery: `MAX(CHAR(DISPLAY_DT)\|\|CHAR(DISPLAY_TM)) AS DT` — dropped `'.'`, wrapped in MAX | JC2 |
| PA-10 | Wrapped fwrite in `if(write == T){ ... }` | MF-PA#7 |
| PA-11 | Fixed path `'Date/Apps/'` → `'data/apps/'`, format `"XYXm"` → `"%Y%m"` | MF-PA#4 |
| PA-12 | `append = T` → `append = F` | MF-PA#5 |
| PA-13 | `nclpen = 999` → `scipen = 999` | MF-PA#6 |
| PA-14 | Added closing `}` after `return(df)` | MF-PA#3 |
| PA-15 | Deleted `(Top Level) =` EOF artifact | MF-PA#8 |
| PA-16 | Fixed `"month"` → `'month'` at pre-edit lines 95-96 (unescaped `"` inside double-quoted glue string) | MF-PA#9 |
| PA-17 | `odbc::dbSendQuery` → `DBI::dbSendQuery`, `odbc::dbFetch` → `DBI::dbFetch` | Connection plan (consumer side) |

**PA-16 note**: This was a Pass 3 addition not present in the approved 2-plan.md. The parse
error was discovered during pre-execution review: line 19 opens a double-quoted glue string,
and lines 95-96 contained unescaped `"month"` that terminated the string. Every other glue
date call in the file already used `'month'`. Without this fix, verification step 1 would
have failed. Added to 1-explore.md as MF-PA#9 and to 2-plan.md as PA-16 before execution.

### R/function_cc_scorecard_data.R — 16 edits (SC-1 through SC-16)

| # | Action | Traces to |
|---|---|---|
| SC-1 | Deleted `# ---- EDL Connection ----` and `library(edlhelper)` | MF-SC#1 |
| SC-2 | Deleted `keyring::keyring_unlock(password = 'keyring')` | MF-SC#2 |
| SC-3 | Deleted orphaned `keys <- keyring::key_list()` | MF-SC#2 |
| SC-4 | Deleted Azure host, subscription_name, crdtplcy_compute | MF-SC#3 |
| SC-5 | Deleted `edlhelper::EdlCredentialNew(...)` block | MF-SC#4 |
| SC-6 | Deleted compute_cluster assignment and edl_conn dbConnect block | MF-SC#5, MF-SC#6 |
| SC-7 | Inserted provisional `db_connect()` definition | Connection plan |
| SC-8 | Changed `conn = edl_conn` to `conn = conn` | Connection plan |
| SC-9 | Restored `statement = glue::glue("` wrapper around SQL | MF-SC#7 |
| SC-10 | `trim(actdtu)` → `trim(actduty)` | MF-SC#8 |
| SC-11 | `performance_window[2]` → `performance_window[1]` | MF-SC#9 |
| SC-12 | Fixed SQL comment close: `'*'/` → `'*'*/` | MF-SC#10 |
| SC-13 | `"Data/Scorecard/"` → `"data/scorecard/"` | MF-SC#11 |
| SC-14 | `nclpen = 999` → `scipen = 999` | MF-SC#12 |
| SC-15 | Deleted top-level call `set_cc_scorecard_data(performance_window_mntc) #` | MF-SC#13 |
| SC-16 | `odbc::dbGetQuery` → `DBI::dbGetQuery` | Connection plan (consumer side) |

### R/CATALOG.md

Both files changed from `OCR-RAW` to `CLEANED`.

---

## Verification results (observed)

| Step | Command / Check | Result |
|---|---|---|
| 1 | `Rscript -e "source('R/pull_apps.R')"` | Exit 0. stderr: dplyr masking messages, lubridate version warning. No ERROR. |
| 2 | `Rscript -e "source('R/function_cc_scorecard_data.R')"` | Exit 0. stderr: renv out-of-sync note. No ERROR. |
| 3 | Grep R/*.R for `keyring\|adb-\|SPOKE\|0126-152005\|edlhelper\|password.*=.*'` | Zero matches. |
| 4 | Top-level code inspection | `pull_apps.R`: `library(dplyr)`, `library(lubridate)`, `db_connect` definition, `get_apps_data` definition. `function_cc_scorecard_data.R`: `db_connect` definition, `get_cc_scorecard_data` definition. No connections, queries, or file writes at source time. |
| 5 | Grep R/*.R for `odbc::` | Zero matches. |

---

## What was achieved

- Both `R/pull_apps.R` and `R/function_cc_scorecard_data.R` parse and `source()` cleanly
  with no side effects and no errors.
- No credential, host, cluster ID, or subscription name remains in `R/*.R`.
- Judgment-call reconstructions (JC1-JC4) are documented in 1-explore.md with competing
  readings, decisions, and disclosure of inferences beyond transcription.
- `db_connect()` provides a real connection seam using `RPostgres` + `Sys.getenv()`,
  provisional pending the supabase-credentials checkpoint.
- The cleaned files are a fidelity artifact: the repo history now shows
  `OCR-raw (5bd4ed8) → reconstruction (7793038) → [future flat rewrite]` as traceable diffs.

## What was NOT achieved

- **The Rmd does not knit.** `orchestration_2.Rmd` has its own defects behind the validated
  marker (backward `seq()` at lines 125/143, dead `copied_from` regex at 201/224, unattached
  `glue()` at 73, `data/apps` and `data/scorecard` directories never created by the
  folder-init chunk). These are outside this task's scope.
- **No Supabase connection exists.** There are no tables, no `.Renviron` with real values,
  and `RPostgres` is not in `renv.lock`. The `db_connect()` function defines correctly but
  will fail at call time until the supabase-credentials checkpoint is completed.
- **The original Task Brief's DoD** ("Rmd knits clean to the validated marker against live
  Supabase") cannot be met by this task. What was met: both scripts parse, source cleanly
  with no side effects, and carry no credential or infrastructure material.

---

## Deferred items

| Item | Destination |
|---|---|
| Git history scrub — commit 5bd4ed8 contains Azure host, subscription, cluster ID on public repo | Standalone operation (delete repo, re-init, push clean) |
| Align `db_connect()` env vars to roll_tracker scheme (`SUPABASE_DB_URL` connection string vs 5 separate vars) | supabase-credentials checkpoint |
| Install `RPostgres` (`renv.lock` has DBI but not RPostgres) | supabase-credentials checkpoint |
| Verify `RPostgres::Postgres()` connects to Supabase session pooler (no R precedent in roll_tracker) | supabase-credentials checkpoint |
| Verify session pooler (port 5432) supports DDL — cited from Claude-authored note, not Supabase docs | supabase-credentials checkpoint |
| Align `.Renviron.example` variable names (currently marked SUPERSEDED) | supabase-credentials checkpoint |
| `priored1` vs `primedt` — UNRESOLVED, zero downstream uses | Schema design task |
| `prim_score` typing — UNRESOLVED (score value vs scorecard identifier) | Schema design task |
| Type annotations for `dt_entered`, `user_ref_num`, `prim_score` — round-trip testing through fwrite/fread | Flatten task |
| SQL dialect conversion (DECODE → CASE, DB2 → Postgres) | Flatten task |
| Self-referencing default `performance_window = performance_window` | Flatten task |
| `dbClearResult()` / `dbDisconnect()` — result set and connection leak | Flatten task |
| Extract `db_connect()` to shared `R/db.R` | Flatten task |
| Underscore vs space mismatch in DECODE element names (JC3 — inference, not confirmed) | Flatten task (moot — entire subquery replaced) |

---

## Post-edit line reference corrections

Reconstruction comments in `pull_apps.R` reference pre-edit line numbers. Fixed in this
commit to qualify as pre-edit with commit hash:
- JC1 comment: "pre-edit pull_apps.R:52-60 @ b59d6c8"
- JC3 comment: "pre-edit lines 79-83 @ b59d6c8, now lines 87-92"
