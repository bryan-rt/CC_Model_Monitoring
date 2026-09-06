# Pass 3 — Execute: flatten-apps-query
Date: 2026-09-06  ·  Branch: pass3/flatten-apps-query

## What was implemented

### `R/db.R` (NEW)

Extracted `db_connect()` from both pull files. Body is byte-identical to the
version in the supabase-credentials pass. Single definition, sourced by both
pull files via `source(here::here("R/db.R"))`.

### `R/pull_apps.R`

- Removed inline `db_connect()` definition (lines 4-21)
- Added `source(here::here("R/db.R"))`
- Replaced 5-table warehouse SQL (179 lines) with flat 14-column SELECT
  against `applications` table
- `dbSendQuery()` + `dbFetch()` + `str_squish()` → `dbGetQuery()`
- Added `on.exit(DBI::dbDisconnect(conn))`
- `performance_window = performance_window` → required arg
- `write = T` → `write = TRUE`
- Full type annotation block (14 columns) above SELECT
- Dropped columns per D11 (applid, logic, custom_score/_2/_3) and D12 (copied_from)

### `R/function_cc_scorecard_data.R`

- Removed inline `db_connect()` definition (lines 1-18)
- Added `source(here::here("R/db.R"))`
- Table name `crdtplcynl_rstr.ccsrccrddaragen2` → `scorecard`
- Column `primemdt` per D10 (already in working copy from user edit)
- Removed `left()` and `trim()` wrappers (flat table stores clean values)
- Added `on.exit(DBI::dbDisconnect(conn))`
- `performance_window = performance_window` → required arg
- `write = T` → `write = TRUE`
- Full type annotation block (8 columns) above SELECT

### `R/CATALOG.md`

- Both pull files: `CLEANED` → `FLATTENED`
- Added `db.R` entry

## Deviations from spec

1. **`str_squish()` removal**: The spec's P2 noted this would happen but the
   code block didn't explicitly show the removal. The old code piped the glue
   string through `stringr::str_squish()` before `dbFetch()`. The flat SELECT
   doesn't need squishing — removed entirely. `stringr` is no longer imported.

2. **`left()`/`trim()` removed from scorecard SQL**: The spec said "keeping them
   is harmless and defensive." Removed them instead — with a flat table we
   store clean values, so these are no-ops that add confusion about what the
   source data looks like. The type annotation documents the contract.

## Verification

### source() — both files

```
$ Rscript -e "source('R/pull_apps.R'); cat('pull_apps.R: OK\n')"
pull_apps.R: OK

$ Rscript -e "source('R/function_cc_scorecard_data.R'); cat('function_cc_scorecard_data.R: OK\n')"
function_cc_scorecard_data.R: OK
```

VERIFIED — both files parse and source cleanly. No connection attempted
(SQL is inside function bodies, not called at source time).

### DB2 syntax grep

```
$ grep -nE 'DECODE\(|CHAR\(' R/*.R
R/function_cc_scorecard_data.R:9:  # user_ref_num   VARCHAR(14)  NOT NULL   join key -> apps
R/pull_apps.R:11:  # user_ref_num       VARCHAR(14)  NULL       join key -> scorecard (D9)
```

Only matches are `VARCHAR(14)` in type annotation comments — not DB2 `CHAR()`
function calls. No DECODE anywhere. VERIFIED.

### db_connect() duplication check

```
$ grep -n 'db_connect' R/*.R
R/db.R:1:db_connect <- function() {
R/function_cc_scorecard_data.R:4:  conn <- db_connect()
R/pull_apps.R:6:  conn <- db_connect()
```

Definition only in `R/db.R`. Both pull files call it, neither defines it. VERIFIED.

### Alias list diff against CLAUDE.md contract

Apps SELECT (14 columns):
```
app_num, user_ref_num, dt_entered, client_product_cd, strategy_version,
assigned_credit_lim, decision, applied, org_paper_type, lao_credit_lmt,
fico_score, bureau_used, acq, prim_score
```
CLAUDE.md contract: identical. VERIFIED.

Scorecard SELECT (8 columns):
```
sq_num, user_ref_num, score, segment, actduty, trans_date_ct,
proc_date_ct, primemdt
```
CLAUDE.md contract: identical. VERIFIED.

## Untested

- **Live query execution**: Tables `applications` and `scorecard` do not exist
  yet (create-supabase-tables is the next task). The SELECTs will fail with
  "relation does not exist" until then. This is expected.
- **fwrite/fread round trip**: Deferred to round-trip test task.
- **Rmd knit**: Not possible — tables don't exist, and D12 introduces a known
  break at `orchestration_2.Rmd:179-218` (copied_from references).

## Adjacent text reconciled

- `R/CATALOG.md`: status updated, `db.R` added
- `CLAUDE.md`: contract updated (14 columns, D11/D12 drops noted), D1-D13 ref
- `.claude/docs/decisions.md`: D11, D12, D13 recorded

## git diff --stat

```
 R/CATALOG.md                   |   5 +-
 R/function_cc_scorecard_data.R |  94 ++++++++---------
 R/pull_apps.R                  | 229 ++++++++++-------------------------------
 3 files changed, 102 insertions(+), 226 deletions(-)
```
