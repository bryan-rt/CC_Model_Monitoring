# Pass 2 — Plan: flatten-apps-query
Date: 2026-09-06  ·  Grounded in: 1-explore.md

## Objective

After this change, both pull functions issue a single flat SELECT against
Postgres tables (`applications`, `scorecard`) with no DB2 dialect, no EAV
pivots, no warehouse joins. `db_connect()` lives in one file. Connections and
result sets are properly cleaned up. The type annotation block above each SELECT
is the contract from which the DDL task writes CREATE TABLE statements.

## Changes

### `R/db.R` (NEW)

Extract `db_connect()` body verbatim from `R/pull_apps.R:4-21`. No changes to
the function — byte-identical to the current copy in both files.

```r
db_connect <- function() {
  url <- Sys.getenv("SUPABASE_DB_URL")
  m <- regmatches(url, regexec(
    "^postgres(?:ql)?://([^:]+):([^@]+)@([^:]+):(\\d+)/([^?]+)", url
  ))[[1]]
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

### `R/pull_apps.R`

**Before → After** (structural):
- Lines 1-21: `library()` calls + `db_connect()` definition → `library()` calls
  + `source(here::here("R/db.R"))`
- Lines 23-24: `get_apps_data <- function(performance_window = performance_window, write = T)`
  → `get_apps_data <- function(performance_window, write = TRUE)`
- Lines 26-158: `db_connect()` + `dbSendQuery()` + `dbFetch()` with 5-table
  warehouse SQL + inline comments → `db_connect()` + `on.exit()` + `dbGetQuery()`
  with flat SELECT + type annotation block
- Lines 166-177: `if(write)` block + `return(df)` + closing brace — kept,
  minor style normalization

Full replacement for the function body:

```r
get_apps_data <- function(performance_window, write = TRUE) {
  conn <- db_connect()
  on.exit(DBI::dbDisconnect(conn))

  # -- Type contract (Postgres DDL source) ---------------------------------
  # app_num            INTEGER      NOT NULL   grain / PK
  # user_ref_num       VARCHAR(14)  NULL       join key → scorecard (D9)
  # dt_entered         DATE         NOT NULL   Rmd: zoo::as.yearqtr()
  # client_product_cd  TEXT         NOT NULL
  # strategy_version   TEXT         NULL
  # assigned_credit_lim NUMERIC    NULL
  # decision           TEXT         NOT NULL   'Approve'|'Decline'|'Void'|'Withdraw'|'Pending'
  # applied            INTEGER      NOT NULL   0 or 1
  # org_paper_type     TEXT         NULL
  # lao_credit_lmt     NUMERIC     NULL
  # fico_score         NUMERIC     NULL
  # bureau_used        TEXT         NULL
  # acq                TEXT         NULL
  # prim_score         NUMERIC     NULL       D8: score value 100-450
  # -- Dropped (D11): applid, logic, custom_score, custom_score_2, custom_score_3
  # -- Dropped (D12): copied_from

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
      org_paper_type,
      lao_credit_lmt,
      fico_score,
      bureau_used,
      acq,
      prim_score
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

Grounding:
- Column list from 1-explore.md column map, rows 1-20, minus D11/D12 drops (14 remain)
- `dbGetQuery` replaces `dbSendQuery`+`dbFetch` (1-explore §4)
- `on.exit(dbDisconnect)` prevents connection leak (1-explore §4)
- `performance_window` required arg (1-explore §5)
- `write = TRUE` instead of `T` (1-explore §5)
- `floor_date`/`ceiling_date` require `library(lubridate)` — kept at file top

### `R/function_cc_scorecard_data.R`

**Before → After** (structural):
- Lines 1-18: `db_connect()` definition → `source(here::here("R/db.R"))`
- Lines 20-21: `get_cc_scorecard_data <- function(performance_window = performance_window, write = T)`
  → `get_cc_scorecard_data <- function(performance_window, write = TRUE)`
- Lines 23-43: `db_connect()` + `dbGetQuery()` with old table/column name →
  `db_connect()` + `on.exit()` + `dbGetQuery()` with `scorecard` table +
  `primemdt` (D10) + type annotation block
- Lines 45-57: `if(write)` block + `return(df)` — kept, minor style normalization

Full replacement:

```r
source(here::here("R/db.R"))

get_cc_scorecard_data <- function(performance_window, write = TRUE) {
  conn <- db_connect()
  on.exit(DBI::dbDisconnect(conn))

  # -- Type contract (Postgres DDL source) ---------------------------------
  # sq_num         INTEGER      NOT NULL   retained per D7, not grain-defining (D9)
  # user_ref_num   VARCHAR(14)  NOT NULL   join key → apps
  # score          NUMERIC   NULL
  # segment        TEXT      NULL       Rmd: as.character(as.numeric(segment))
  # actduty        TEXT      NULL
  # trans_date_ct  DATE      NOT NULL   date filter column
  # proc_date_ct   DATE      NULL
  # primemdt       TEXT      NULL       D10: name resolved, type deliberately TEXT

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

Grounding:
- Column list from 1-explore.md scorecard contract, rows 1-8
- `primemdt` per D10 (was `priored1`)
- `lubridate::` namespace prefix used because this file does not `library(lubridate)`
- `on.exit(dbDisconnect)` added (1-explore §4)

### `R/CATALOG.md`

Update status for both files from `CLEANED` to `FLATTENED`. Add `R/db.R` entry.

### `CLAUDE.md`

- Update current loop position: `flatten-apps-query` complete
- Confirm contracts match (both already updated with D10)

## Carrying paths verified

| Value | Produced at | Hops | Consumed at |
|---|---|---|---|
| `db_connect()` | `R/db.R` (new) | `source(here::here("R/db.R"))` in both pull files | `conn <- db_connect()` in both function bodies |
| `source('R/pull_apps.R')` | `orchestration_2.Rmd:80` | loads function definition | `get_apps_data()` called at `:147`, `:1275`, `:1939`, `:1944` |
| `source('R/function_cc_scorecard_data.R')` | `orchestration_2.Rmd:81` | loads function definition | `get_cc_scorecard_data()` called at `:129` |
| apps column names (14 cols) | SELECT in `pull_apps.R` | → RPostgres data.frame → fwrite .txt.gz → fread → Rmd | Rmd consumes: `app_num`, `user_ref_num`, `dt_entered`, `prim_score`, `decision`, `applied`, `client_product_cd`. Dropped: applid, logic, custom_score/_2/_3 (D11), copied_from (D12). |
| scorecard column names (8 cols) | SELECT in `function_cc_scorecard_data.R` | → RPostgres data.frame → fwrite .txt.gz → fread → Rmd | Rmd joins on `user_ref_num`, reads `score`, `segment`. `primemdt` has zero Rmd uses (D10). |
| `performance_window` | Rmd caller: `model_input_window` at `:129,:147` | positional arg | Used in glue WHERE clause and fwrite filename |
| `here::here("R/db.R")` | `pull_apps.R`, `function_cc_scorecard_data.R` | `here` resolves from project root | Works because Rmd knits from project root, and `source('R/pull_apps.R')` at Rmd:80 runs in project root context |

## Blast radius

| Thing changed | What reads it |
|---|---|
| `get_apps_data` signature: remove default for `performance_window` | `orchestration_2.Rmd:147` passes explicitly. `:1275,:1939,:1944` pass positionally. All callers supply the argument — no breakage. |
| `get_cc_scorecard_data` signature: remove default for `performance_window` | `orchestration_2.Rmd:129` passes explicitly via `performance_window = model_input_window`. No breakage. |
| `write = T` → `write = TRUE` | All callers pass `write = T` explicitly. `T` evaluates to `TRUE` in standard R. No behavioral change. |
| `dbSendQuery`+`dbFetch` → `dbGetQuery` | Semantically identical — `dbGetQuery` is `dbSendQuery` + `dbFetch` + `dbClearResult`. Return value is the same data.frame. |
| Columns dropped (D11): applid, logic, custom_score/_2/_3 | Zero Rmd matches for any of these names (1-explore Rmd verification). No breakage. |
| Column dropped (D12): copied_from | **KNOWN BREAK.** `orchestration_2.Rmd:184` references `copied_from` directly. `:201-206` uses `str_extract(copied_from, ...)` for user_ref_num remapping. `:224-229` uses it in psi_df. D12 says delete the chunk at `:179-218` and strip `:224-229`. Resolved by `simplify-rmd-psi-region` task immediately following this one. |
| New file `R/db.R` | `orchestration_2.Rmd:80-81` sources the pull files, which in turn source `db.R`. The Rmd does not source `db.R` directly. No change needed in Rmd. |

## Edge cases and how each is handled

1. **`performance_window` is a single date, not a vector**: Callers at `:1275,:1939,:1944`
   pass `cohort_window[1]` or `cohort_window()` — a single Date. `performance_window[1]`
   in the glue string handles this correctly (indexing a scalar returns itself).
   `min(performance_window)` in the fwrite filename also works on a scalar.

2. **`here::here()` resolution when sourced from Rmd**: The Rmd calls
   `source('R/pull_apps.R')` with a relative path (`:80`). Inside `pull_apps.R`,
   `here::here("R/db.R")` resolves from the project root (where `.Rproj` or
   `.here` lives). This is the standard `here` behavior — no issue.

3. **`library(lubridate)` needed in pull_apps.R but not scorecard**: `pull_apps.R`
   uses bare `floor_date`/`ceiling_date` in glue. Scorecard uses
   `lubridate::floor_date` (namespaced). Both work. Keeping `library(lubridate)`
   in pull_apps.R only — no change to scorecard's dependency footprint.

4. **Tables don't exist yet**: Both SELECTs will fail with "relation does not
   exist" until the create-supabase-tables task runs. This is expected and
   documented. `source()` will succeed because the SQL is inside a function
   body that is not called at source time.

## Discovered during planning

**P1.** `orchestration_2.Rmd:1275,1939,1944` call `get_apps_data()` with only
one positional argument and no `write` parameter. The current default `write = T`
means these calls silently write files. Changing the default to `write = TRUE`
preserves this behavior (TRUE ≡ T). Not changing it to `write = FALSE` because
that would alter behavior for these callers. — Does not invalidate any Pass 1
finding.

**P2.** The current `pull_apps.R:157-158` pipes through `stringr::str_squish()`
before passing to `dbFetch()`. The flat SELECT has no multi-line SQL that needs
squishing — the glue string is clean. `str_squish()` is removed with the
rewrite. `library(dplyr)` remains (needed for downstream pipeline); `stringr`
was only used for this one call and is no longer imported.

**P3.** D11/D12 contract change: 20 → 14 columns. Drops applid, logic,
custom_score/_2/_3 (D11) and copied_from (D12). copied_from has active Rmd
consumers at `:184,:201-206,:224-229` — this is a **known break**, resolved
by the simplify-rmd-psi-region task immediately following.

## Unresolved

None. All open questions from Pass 1 are resolved:
- `priored1` → `primemdt` (D10)
- `prim_score` typed NUMERIC (D8)
- `primemdt` typed TEXT (D10)

## Definition of done

- [ ] `R/db.R` created with `db_connect()`, byte-identical to current
- [ ] Both files `source()` cleanly: `Rscript -e "source('R/pull_apps.R')"`
- [ ] Every alias in the contract present and unchanged — diff the alias list
      from the SELECT against CLAUDE.md, paste the comparison
- [ ] Type annotation block above each SELECT, complete (14 apps, 8 scorecard)
- [ ] No DB2-only syntax remains: `grep -E 'DECODE|CHAR\(' R/*.R` returns
      zero matches
- [ ] No `db_connect()` duplication: function exists only in `R/db.R`
- [ ] `on.exit(DBI::dbDisconnect(conn))` in both functions
- [ ] `R/CATALOG.md` updated (both files → FLATTENED, `db.R` added)
- [ ] `CLAUDE.md` updated (loop position, contracts confirmed)
- [ ] `git diff --stat` in the Pass 3 summary
