# Pass 2 — Plan: clean-ocr-pull-scripts

Spec only. No edits to R/* in this document. Every change below traces to a
numbered finding in 1-explore.md.

---

## R/pull_apps.R — target state

The file will be rewritten in full. Line references below are to the CURRENT
file (pre-edit). The target file structure is:

```
library(dplyr)
library(lubridate)

db_connect <- function() { ... }              # NEW — replaces lines 9-15

get_apps_data <- function(...) {              # line 6-7, signature preserved
  conn <- db_connect()                        # replaces TSYS_TA block
  df <- DBI::dbSendQuery(                     # line 17, odbc:: -> DBI::
    conn = conn,                              # was TSYS_TA
    statement = glue::glue("                  # line 19, unchanged
      ...SQL...                               # lines 20-133, with JC fixes
    ") %>% stringr::str_squish()              # line 137-138
  ) %>% DBI::dbFetch()                        # line 138, odbc:: -> DBI::

  if(write == T){                             # NEW guard — 1-explore MF-PA#7
    data.table::fwrite(...)                   # lines 146-152, with fixes
  }

  return(df)                                  # line 154
}                                             # NEW closing brace — 1-explore MF-PA#3
```

### Edit sequence (order matters for non-overlapping old_string matches)

| # | Source line(s) | Action | Traces to |
|---|---|---|---|
| PA-1 | 4 | Delete `if performance_window <- as.Date('2022-12-01')` | MF-PA#1 |
| PA-2 | 9 | Delete `keyring::keyring_unlock(password = 'keyring')` | MF-PA#2 |
| PA-3 | 11 | Delete `keys <- keyring::key_list()` | MF-PA#2 (orphaned by PA-2) |
| PA-4 | 13-15 | Replace TSYS_TA odbc::dbConnect block with `conn <- db_connect()` | Connection plan |
| PA-5 | 8-15 | Insert `db_connect()` function definition before `get_apps_data` | Connection plan |
| PA-6 | 17-18 | Change `conn = TSYS_TA` to `conn = conn` | Connection plan |
| PA-7 | 52-60 | Replace `logic` CASE with 3-branch reconstruction + comment | JC1 |
| PA-8 | 104 | Add comment after ELEMENT_NAME IN list re: NAVY CUSTOM SCORE 3 | JC3 |
| PA-9 | 114-115 | Fix subquery: `MAX(CHAR(DISPLAY_DT)\|\|CHAR(DISPLAY_TM)) AS DT` (drop `'.'`, wrap in MAX) | JC2 |
| PA-10 | 146-152 | Wrap fwrite in `if(write == T){ ... }` | MF-PA#7 |
| PA-11 | 147 | `'Date/Apps/'` → `'data/apps/'`, `"XYXm"` → `'%Y%m'` | MF-PA#4 |
| PA-12 | 150 | `append = T` → `append = F` | MF-PA#5 |
| PA-13 | 151 | `nclpen = 999` → `scipen = 999` | MF-PA#6 |
| PA-14 | 154+ | Add closing `}` after `return(df)` | MF-PA#3 |
| PA-15 | 157-158 | Delete `(Top Level) =` | MF-PA#8 |
| PA-16 | 95-96 | `"month"` → `'month'` in glue date calls (unescaped `"` terminates string) | MF-PA#9 |
| PA-17 | 17, 138 | `odbc::dbSendQuery` → `DBI::dbSendQuery`, `odbc::dbFetch` → `DBI::dbFetch` | Connection plan (consumer side) |

### Preserved exactly (no edit)

- `library(dplyr)` / `library(lubridate)` at top (lines 1-2)
- Function signature `get_apps_data <- function(performance_window = performance_window, write = T)` (line 6-7) — self-referencing default is a known issue (1-explore Additional Notes) but not in scope
- All SQL table names, column names, DECODE calls (constraint: no dialect conversion)
- `dbSendQuery` + `dbFetch` pattern (no `dbClearResult`/`dbDisconnect` — noted in 1-explore, deferred to flatten). Namespace changes from `odbc::` to `DBI::` per PA-17.
- All commented-out SQL and developer notes (lines 99-103, 131, 132, 139-144)

### JC1 — logic CASE reconstruction (PA-7)

Replace lines 52-60 with:

```sql
  /* OCR RECONSTRUCTION — logic CASE
     Source text (pull_apps.R:52-60): structurally merged, unbalanced parens
     Reading A (applied): 3-branch AUTO/MANUAL/'' based on officer presence
       - OR->AND change in MANUAL branch (see 1-explore.md JC1 disclosure)
     Reading B (discarded): literal OCR with missing WHEN keyword at line 58
     NOTE: logic column is consumed nowhere in orchestration_2.Rmd */
  CASE
    WHEN MAX(A.STATUS_FIELD) NOT IN ('NEWACCOUNT','DECLINE','A2 ERROR','A2 WAIT','APPROVE') THEN ''
    WHEN (MAX(A.DECSN_OFFCR) IS NULL OR MAX(A.DECSN_OFFCR) = '') AND
         (MAX(G.OFFICER_ID) IS NULL OR MAX(G.OFFICER_ID) = '') AND
         MAX(A.STATUS_FIELD) IN ('NEWACCOUNT','DECLINE','A2 ERROR','A2 WAIT','APPROVE') THEN 'AUTO'
    WHEN (MAX(G.OFFICER_ID) IS NOT NULL AND MAX(G.OFFICER_ID) <> '') AND
         MAX(A.STATUS_FIELD) IN ('NEWACCOUNT','DECLINE','A2 ERROR','A2 WAIT','APPROVE') THEN 'MANUAL'
    ELSE ''
  END AS logic,
```

### JC2 — officer-log join key (PA-9)

Replace line 115:
```
MAX(CHAR(DISPLAY_DT))||'.'||CHAR(DISPLAY_TM)) AS DT
```
with:
```
MAX(CHAR(DISPLAY_DT)||CHAR(DISPLAY_TM)) AS DT
```

The `MAX()` wraps the full concatenation (fixes unaggregated `DISPLAY_TM` under `GROUP BY`).
The `'.'` separator is dropped to match the ON clause at line 122.

### JC3 — NAVY CUSTOM SCORE 3 comment (PA-8)

After line 104, add:
```sql
  /* NOTE: 'NAVY CUSTOM SCORE 3' intentionally absent from IN list.
     Also: underscore vs space mismatch between DECODEs (lines 79-83) and
     this IN list would null all three score columns if read literally —
     see 1-explore.md JC3 */
```

---

## R/function_cc_scorecard_data.R — target state

```
db_connect <- function() { ... }              # NEW — replaces lines 4-28

get_cc_scorecard_data <- function(...) {       # line 1-2, signature preserved
  conn <- db_connect()                         # replaces edl_conn block

  df <- DBI::dbGetQuery(                       # line 31, odbc:: -> DBI::
    conn = conn,                               # was edl_conn
    statement = glue::glue("                   # RESTORED — 1-explore MF-SC#7
      select
        sq_num,
        left(user_ref_num, 14) as user_ref_num,
        score,
        trim(segment) as segment,
        trim(actduty) as actduty,              # FIXED actdtu -> actduty — MF-SC#8
        trans_date_ct,
        proc_date_ct,
        priored1                               # KEPT as-is — JC4 UNRESOLVED
      from crdtplcynl_rstr.ccsrccrddaragen2
      where trans_date_ct >= '{lubridate::floor_date(performance_window[1], \"month\")}'
        AND trans_date_ct <= '{lubridate::ceiling_date(performance_window[1], \"month\") - 1}'
        /*and trim(segment) != '*'*/           # FIXED comment close — MF-SC#10
    "))                                        # line 49

  if(write == T){                              # line 51
    data.table::fwrite(x = df,
      file = glue::glue(here::here("data/scorecard/scorecard_{format(as.Date(min(performance_window)), '%Y%m')}.txt.gz")),
      sep = ',',                               # FIXED path case — MF-SC#11
      compress = 'auto',
      append = F,
      scipen = 999,                            # FIXED nclpen -> scipen — MF-SC#12
      showProgress = T)
  }

  return(df)
}
                                               # line 65 DELETED — MF-SC#13
```

### Edit sequence

| # | Source line(s) | Action | Traces to |
|---|---|---|---|
| SC-1 | 4-5 | Delete `# ---- EDL Connection ----` and `library(edlhelper)` | MF-SC#1 |
| SC-2 | 7 | Delete `keyring::keyring_unlock(password = 'keyring')` | MF-SC#2 |
| SC-3 | 8 | Delete `keys <- keyring::key_list()` | MF-SC#2 (orphaned) |
| SC-4 | 10-12 | Delete host, subscription_name, crdtplcy_compute | MF-SC#3 |
| SC-5 | 14-18 | Delete `edlhelper::EdlCredentialNew(...)` block | MF-SC#4 |
| SC-6 | 20-28 | Delete compute_cluster assignment and `edl_conn` dbConnect block | MF-SC#5, MF-SC#6 |
| SC-7 | before fn | Insert `db_connect()` function definition | Connection plan |
| SC-8 | 31 | Change `conn = edl_conn` to `conn = conn` | Connection plan |
| SC-9 | 31-32 | Restore `statement = glue::glue("` wrapper around SQL | MF-SC#7 |
| SC-10 | 40 | `trim(actdtu)` → `trim(actduty)` | MF-SC#8 |
| SC-11 | 47 | `performance_window[2]` → `performance_window[1]` | MF-SC#9 |
| SC-12 | 48 | `/*and trim(segment) != '*'/` → `/*and trim(segment) != '*'*/` | MF-SC#10 |
| SC-13 | 53 | `"Data/Scorecard/"` → `"data/scorecard/"` | MF-SC#11 |
| SC-14 | 57 | `nclpen = 999` → `scipen = 999` | MF-SC#12 |
| SC-15 | 65 | Delete `set_cc_scorecard_data(performance_window_mntc) #` | MF-SC#13 |
| SC-16 | 31 | `odbc::dbGetQuery` → `DBI::dbGetQuery` | Connection plan (consumer side) |

### Preserved exactly

- Function signature (line 1-2) — self-referencing default noted, deferred
- All SQL table/column names (constraint: no dialect conversion)
- `priored1` unchanged (JC4 — UNRESOLVED, handoff to schema task)
- `if(write == T)` guard and fwrite structure (lines 51-60)

---

## db_connect() — provisional, duplicated in both files

```r
db_connect <- function() {
  DBI::dbConnect(
    RPostgres::Postgres(),
    host     = Sys.getenv("SUPABASE_HOST"),
    port     = as.integer(Sys.getenv("SUPABASE_PORT", "5432")),
    dbname   = Sys.getenv("SUPABASE_DB"),
    user     = Sys.getenv("SUPABASE_USER"),
    password = Sys.getenv("SUPABASE_PWD"),
    sslmode  = "require"
  )
}
```

Traces to: 1-explore.md Connection plan. PROVISIONAL — known not to match
roll_tracker's scheme (1-explore.md Discrepancies). Not aligned in this task.

---

## R/CATALOG.md update

Change status for both files from `OCR-RAW` to `CLEANED`.

---

## Verification steps (after all edits)

1. `Rscript -e "source('R/pull_apps.R')"` — must exit 0 with no ERROR on stderr.
   (dplyr masking messages on stderr are expected and acceptable.)
2. `Rscript -e "source('R/function_cc_scorecard_data.R')"` — must exit 0 with no ERROR
   on stderr.
3. Grep for credential/infrastructure strings:
   - `keyring` (should appear nowhere in R/*.R)
   - `adb-` (Azure host prefix)
   - `SPOKE` (subscription name)
   - `0126-152005` (cluster ID)
   - `edlhelper`
   - `password.*=.*'` (hardcoded password pattern)
4. Confirm no top-level code other than `library()` calls and function definitions; no
   connection attempted, no query executed, no file written at source time.
5. Grep R/*.R for `odbc::` — must return zero matches. (All call sites changed to `DBI::`.
   CRITICAL: these calls are inside function bodies, so `source()` only defines the function
   and never evaluates them. A green source() is NOT evidence the DBI:: rewire is complete —
   this grep is the only check that catches a missed `odbc::` consumer.)

---

## What this plan does NOT do

- Align db_connect() to roll_tracker env var scheme (supabase-credentials checkpoint)
- Convert SQL dialect (flatten task)
- Fix self-referencing default in function signatures (flatten task)
- Add dbClearResult/dbDisconnect (flatten task)
- Resolve priored1 vs primedt (schema task)
- Resolve prim_score typing (schema task)
- Clean git history of infrastructure identifiers (separate security operation)
- Install RPostgres: `renv.lock` has DBI but NOT RPostgres. `RPostgres::Postgres()`
  namespaced inside a function body will not break `source()`, so the gate stays green while
  the first real connection fails with "there is no package called 'RPostgres'". Either
  `renv::install("RPostgres")` + `renv::snapshot()` in the supabase-credentials checkpoint,
  or verify it is already available outside renv. This is a credentials-checkpoint item.

---

**Awaiting user approval before executing Pass 2 edits.**
