# Pass 1 — Explore: flatten-apps-query

## Files in scope

| File | Lines | Current state |
|---|---|---|
| `R/pull_apps.R` | 179 | CLEANED — 5-table warehouse SQL, DB2 dialect |
| `R/function_cc_scorecard_data.R` | 57 | CLEANED — single-table SQL, near-Postgres already |
| `R/db.R` | NEW | Extract `db_connect()` here, source from both |

---

## Pre-task verification

Connection tests rerun in housekeeping commit `95aed3c`. All four pass. TRE
engine handles `(?:ql)?` correctly — 6 elements, no index shift. `db_connect()`
is VALIDATED (D5). See `.claude/passes/supabase-credentials/3-execute.md`,
"Post-merge revalidation" section.

No re-run needed — already done this session.

---

## What changes and why

### 1. Extract `db_connect()` to `R/db.R`

Both files contain byte-identical copies of `db_connect()` (verified in
supabase-credentials pass). Extract to `R/db.R`, replace in both files with
`source(here::here("R/db.R"))`. The function body is unchanged.

### 2. Rewrite `R/pull_apps.R` SQL

The current query joins 5 warehouse tables with DB2-dialect SQL:
- `TA4236.ADM_APP_INFO` (A)
- `TA4236.ADM_GEN_VAL` (B) — EAV pivot via DECODE
- `TA4236.ADM_DATA_ELEM` (C) — EAV pivot via DECODE
- `TA4236.ADM_TS2_EXTR_OVR` (DD)
- `TA4236.ADM_APP_LOG` (G) — officer log for logic column

Per D7, all five collapse to one flat `applications` table. The SELECT becomes
a column list with aliases and a date filter. All DECODE/CASE/MAX/GROUP BY
artifacts of the warehouse schema disappear.

### 3. Rewrite `R/function_cc_scorecard_data.R` SQL

Already nearly flat. Changes:
- Table name `crdtplcynl_rstr.ccsrccrddaragen2` → `scorecard`
- Column renamed `priored1` → `primemdt` (D10, resolved by user)
- `left()` and `trim()` may be removable if we store clean values in the flat
  table, but keeping them is harmless and defensive

### 4. Fix query execution pattern

`pull_apps.R` uses `dbSendQuery()` + `dbFetch()` with no `dbClearResult()` or
`dbDisconnect()`. Leaks a result set and connection per call. Replace with
`dbGetQuery()` (scorecard already uses this) + `on.exit(dbDisconnect(conn))`.

### 5. Fix self-referencing defaults

Both files: `performance_window = performance_window` → remove the default.
This only works because callers always pass the argument; if called without
one, R errors on the self-reference. Making it required is more honest.

---

## Column contract: apps

Source table: `applications`. All columns stored directly — no EAV pivot, no
CASE derivation at query time. The sample-data generator (D6) writes the
derived values directly.

### Rmd verification

Grep of `orchestration_2.Rmd` confirms:
- `NAVY`/`navy_cust`/`custom_score`: **zero matches** — renaming is safe
- `user_ref_num`: cast via `as.numeric()` at lines 183, 200, 222, etc.
- `prim_score`: numeric comparisons at lines 188-190, 208-210, 232-234, 239, 268
- `dt_entered`: `zoo::as.yearqtr()` at lines 194, 214
- `priored1`/`primedt`/`primemdt`: **zero matches** — confirms zero downstream use (D10: resolved to `primemdt`)

### Column map and type annotation

| # | Output alias | Source column | Postgres type | Nullable | Notes |
|---|---|---|---|---|---|
| 1 | app_num | app_num | INTEGER | NOT NULL | Grain / PK |
| 2 | user_ref_num | user_ref_num | TEXT | NULL | Join key to scorecard. Rmd casts `as.numeric()`. 14 chars max (left(...,14) in original). Store pre-truncated. |
| 3 | dt_entered | dt_entered | DATE | NOT NULL | Rmd calls `zoo::as.yearqtr()`. Must survive fread → as.yearqtr round trip. |
| 4 | client_product_cd | client_product_cd | TEXT | NOT NULL | Filter: NOT IN ('EPL','BUS','SBM','PUR','SBC','MBP') applied at generation time. |
| 5 | strategy_version | strategy_version | TEXT | NULL | Zero Rmd uses in readable region. Retained per D7. |
| 6 | assigned_credit_lim | assigned_credit_lim | NUMERIC | NULL | Original: TRIM(MAX(...)). Store as numeric. |
| 7 | decision | decision | TEXT | NOT NULL | Values: 'Approve','Decline','Void','Withdraw','Pending'. Stored directly, not derived at query time. |
| 8 | applied | applied | INTEGER | NOT NULL | Values: 0 or 1. Stored directly. |
| 9 | applid | applid | TEXT | NULL | TS2 account ID. NULL when original was '0'. |
| 10 | copied_from | copied_from | TEXT | NULL | Rmd parses via regex: `str_extract(copied_from, "(?<=FROM ) \\d+")`. Free text like "FROM 12345678901234 TO 12345678901234". |
| 11 | org_paper_type | org_paper_type | TEXT | NULL | Zero Rmd uses. Retained per D7. |
| 12 | lao_credit_lmt | lao_credit_lmt | NUMERIC | NULL | Zero Rmd uses. Retained per D7. |
| 13 | fico_score | fico_score | NUMERIC | NULL | Zero Rmd uses in readable region. Retained per D7. |
| 14 | bureau_used | bureau_used | TEXT | NULL | Zero Rmd uses. Retained per D7. |
| 15 | acq | acq | TEXT | NULL | Zero Rmd uses. Retained per D7. |
| 16 | prim_score | prim_score | NUMERIC | NULL | D8: score value 100-450. NOT text. |
| 17 | logic | logic | TEXT | NULL | Values: 'AUTO','MANUAL',''. Zero Rmd uses. Retained per D7. |
| 18 | custom_score | custom_score | NUMERIC | NULL | Renamed from NAVY_CUST_SCR. Zero Rmd matches for either name. |
| 19 | custom_score_2 | custom_score_2 | NUMERIC | NULL | Renamed from NAVY_CUST_SCR_2. Zero Rmd matches. |
| 20 | custom_score_3 | custom_score_3 | NUMERIC | NULL | Renamed from NAVY_CUST_SCR_3. Zero Rmd matches. |

**Source = output for all columns.** The flat table stores final values under
the names the Rmd expects. The SELECT is `SELECT <columns> FROM applications
WHERE ...` with no transformations except the date filter.

---

## Column contract: scorecard

Source table: `scorecard`. Grain: one row per user_ref_num (D9).

| # | Output alias | Source column | Postgres type | Nullable | Notes |
|---|---|---|---|---|---|
| 1 | sq_num | sq_num | INTEGER | NOT NULL | Retained per D7. Not grain-defining (D9). |
| 2 | user_ref_num | user_ref_num | TEXT | NOT NULL | Join key to apps. Store pre-truncated (14 chars). |
| 3 | score | score | NUMERIC | NULL | |
| 4 | segment | segment | TEXT | NULL | Rmd: `as.character(as.numeric(segment))` at line 275. Numeric-as-text. |
| 5 | actduty | actduty | TEXT | NULL | |
| 6 | trans_date_ct | trans_date_ct | DATE | NOT NULL | Date filter column. |
| 7 | proc_date_ct | proc_date_ct | DATE | NULL | |
| 8 | primemdt | primemdt | TEXT | NULL | D10: resolved by user review of original source. Name resolved, type deliberately deferred — zero Rmd uses, and TEXT round-trips safely through fwrite/fread regardless. |

---

## Dialect conversion inventory

| DB2/Oracle pattern | Current location | Postgres equivalent | Disposition |
|---|---|---|---|
| `DECODE(x,'k',v)` | pull_apps.R:78-86, 93-99 | `CASE WHEN x = 'k' THEN v END` | **Disappears** — EAV pivot eliminated by flat table. Narrated in this doc as walkthrough artifact. |
| `CHAR(x)` | pull_apps.R:135, 142 | `x::text` | **Disappears** — officer log join eliminated. |
| `MAX(...)` + `GROUP BY` | pull_apps.R throughout | Direct column reference | **Disappears** — aggregation was artifact of joins. |
| `TRIM(x)` | Both files | `trim(x)` — same in Postgres | Removable if stored clean. Keep in scorecard defensively. |
| `left(x, 14)` | Both files | Same in Postgres | Removable if stored pre-truncated. |
| `||` concatenation | pull_apps.R:135, 142 | Same in Postgres | **Disappears** with officer log join. |
| `'{glue}'` date literals | Both files, WHERE clauses | Same — glue interpolation is R-side | **Kept**. Verify DATE comparison works: `dt_entered >= '2026-01-01'` is valid Postgres (implicit cast from text literal to date). |

**Net result**: No DB2-specific syntax survives in the flat rewrite. The only
SQL constructs are SELECT, FROM, WHERE with date comparisons, and column aliases.

---

## Key risks and things to verify in Pass 3

### R1. Date filter comparison

The WHERE clause uses glue-interpolated R date values:
```r
dt_entered >= '{lubridate::floor_date(performance_window[1], 'month')}'
```

`floor_date()` returns a Date object. `glue()` calls `as.character()`, producing
`"2026-01-01"`. Postgres compares this text literal against a DATE column via
implicit cast. This works, but is fragile — an unexpected format would silently
return zero rows, not error. Consider explicit cast: `dt_entered >= $1::date`
with parameterized query. **Decision**: keep glue interpolation for now (matches
existing pattern, no parameterized-date precedent in the codebase), but note for
round-trip test.

### R2. fread type inference on DATE columns

When `fwrite` writes a DATE column and `fread` reads it back, fread may type it
as character. `zoo::as.yearqtr("2026-01-15")` works (returns `2026 Q1`), so
this is safe — but must be verified in the round-trip test, not assumed.

### R3. user_ref_num join key type consistency

Path: Postgres TEXT → RPostgres character → fwrite → fread character → Rmd
`as.numeric()`. Both sides of the left_join cast to numeric. 14-digit integers
are exact in double precision (max exact integer: 2^53 ≈ 9e15, 14 digits max
9.99e13). Safe, but verify no leading zeros exist in sample data (leading zeros
would be lost in numeric cast and break the join).

### R4. ~~Working copy has uncommitted `priored1` → `primemdt` change~~ RESOLVED

User confirmed `primemdt` is correct (D10). The working-copy change is the
user's edit. Commit it rather than overwriting it. The rewrite will use
`primemdt` per the updated contract.

---

## Proposed file structure after changes

### R/db.R (NEW)
```r
db_connect <- function() {
  url <- Sys.getenv("SUPABASE_DB_URL")
  m <- regmatches(url, regexec("^postgres(?:ql)?://([^:]+):([^@]+)@([^:]+):(\\d+)/([^?]+)", url))[[1]]
  if (length(m) == 0) {
    stop("SUPABASE_DB_URL is unset or malformed. Expected ",
         "postgresql://user:password@host:port/dbname — see .Renviron.example",
         call. = FALSE)
  }
  DBI::dbConnect(
    RPostgres::Postgres(),
    host     = m[4],
    port     = as.integer(m[5]),
    dbname   = m[6],
    user     = m[2],
    password = utils::URLdecode(m[3]),
    sslmode  = "require"
  )
}
```

### R/pull_apps.R (sketch)
```r
library(dplyr)
library(lubridate)
source(here::here("R/db.R"))

get_apps_data <- function(performance_window, write = TRUE) {
  conn <- db_connect()
  on.exit(DBI::dbDisconnect(conn))

  # -- Type contract (Postgres → R via fwrite/fread) ----------------------
  # app_num          INTEGER  NOT NULL  grain/PK
  # user_ref_num     TEXT     NULL      join key → scorecard
  # dt_entered       DATE     NOT NULL
  # client_product_cd TEXT    NOT NULL
  # ... (full block in execute)

  df <- DBI::dbGetQuery(conn, glue::glue("
    SELECT
      app_num,
      user_ref_num,
      dt_entered,
      client_product_cd,
      strategy_version,
      assigned_credit_lim,
      decision,
      applied,
      applid,
      copied_from,
      org_paper_type,
      lao_credit_lmt,
      fico_score,
      bureau_used,
      acq,
      prim_score,
      logic,
      custom_score,
      custom_score_2,
      custom_score_3
    FROM applications
    WHERE dt_entered >= '{floor_date(performance_window[1], 'month')}'
      AND dt_entered <= '{ceiling_date(performance_window[1], 'month') - 1}'
  "))

  if (write == TRUE) {
    data.table::fwrite(
      x = df,
      file = glue::glue(here::here(
        "data/apps/apps_{format(as.Date(min(performance_window)), '%Y%m')}.txt.gz"
      )),
      sep = ",",
      compress = "auto",
      append = FALSE,
      scipen = 999,
      showProgress = TRUE
    )
  }

  return(df)
}
```

### R/function_cc_scorecard_data.R (sketch)
```r
source(here::here("R/db.R"))

get_cc_scorecard_data <- function(performance_window, write = TRUE) {
  conn <- db_connect()
  on.exit(DBI::dbDisconnect(conn))

  # -- Type contract (Postgres → R via fwrite/fread) ----------------------
  # sq_num           INTEGER  NOT NULL
  # user_ref_num     TEXT     NOT NULL  join key → apps
  # ... (full block in execute)

  df <- DBI::dbGetQuery(conn, glue::glue("
    SELECT
      sq_num,
      user_ref_num,
      score,
      segment,
      actduty,
      trans_date_ct,
      proc_date_ct,
      primemdt
    FROM scorecard
    WHERE trans_date_ct >= '{lubridate::floor_date(performance_window[1], 'month')}'
      AND trans_date_ct <= '{lubridate::ceiling_date(performance_window[1], 'month') - 1}'
  "))

  if (write == TRUE) {
    data.table::fwrite(
      x = df,
      file = glue::glue(here::here(
        "data/scorecard/scorecard_{format(as.Date(min(performance_window)), '%Y%m')}.txt.gz"
      )),
      sep = ",",
      compress = "auto",
      append = FALSE,
      scipen = 999,
      showProgress = TRUE
    )
  }

  return(df)
}
```

---

## Deferred items NOT in this task

| Item | Destination |
|---|---|
| CREATE TABLE DDL | create-supabase-tables task (next) |
| Sample data with drift parameters | sample-data-generator (D6) |
| orchestration_2.Rmd fixes (line 209 `< 100 < -1` is OCR damage) | fix-orchestration-rmd |
| ~~`priored1` vs `primedt`~~ | Resolved: `primemdt` (D10) |
| Git history scrub of infrastructure identifiers | Separate operation |

---

## Pass 2 plan

1. Create `R/db.R` with extracted `db_connect()`
2. Rewrite `R/pull_apps.R`:
   - Remove `db_connect()` definition
   - Add `source(here::here("R/db.R"))`
   - Remove `library(lubridate)` from top if not needed outside glue (it IS
     needed — `floor_date`/`ceiling_date` in glue string)
   - Replace entire SQL with flat SELECT
   - Add full type annotation block
   - Replace `dbSendQuery`+`dbFetch` with `dbGetQuery`
   - Add `on.exit(DBI::dbDisconnect(conn))`
   - Fix `performance_window = performance_window` → required arg
   - Fix `write = T` → `write = TRUE` (style, not semantic — T can be masked)
3. Rewrite `R/function_cc_scorecard_data.R`:
   - Remove `db_connect()` definition
   - Add `source(here::here("R/db.R"))`
   - Replace table name, use `primemdt` (D10)
   - Add full type annotation block
   - Add `on.exit(DBI::dbDisconnect(conn))`
   - Fix `performance_window = performance_window` → required arg
   - Fix `write = T` → `write = TRUE`
4. Verify both files `source()` cleanly
5. Diff alias lists against CLAUDE.md contract
6. Grep for residual DB2 syntax (DECODE, CHAR())
7. Update `R/CATALOG.md` and `CLAUDE.md`

**Awaiting user approval before executing Pass 2.**
