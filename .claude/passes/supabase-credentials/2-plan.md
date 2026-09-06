# Pass 2 — Plan: supabase-credentials

Spec only. No edits to `R/*`, `.Renviron.example`, or `renv.lock` in this document.
Every change below traces to a finding in `1-explore.md` or a Pass 2 addition from
user review.

---

## 1. Install RPostgres (Pass 3 — mutates `renv.lock`)

```
Rscript -e "renv::install('RPostgres')"
Rscript -e "renv::snapshot()"
```

**System dependency**: RPostgres compiles against libpq (C library). On macOS this is
typically available via Homebrew (`brew install libpq`) or bundled with Postgres.app.
On Linux it requires `libpq-dev` (Debian/Ubuntu) or `postgresql-devel` (RHEL/Fedora) —
without it, the install fails at compile time with a missing `libpq-fe.h` error that
looks like an R/renv problem but is a system package problem. Anticipate this in Pass 3
and check the error message if `renv::install` fails.

Traces to: 1-explore.md "RPostgres status"; Pass 2 addition #4 (libpq system dependency).

---

## 2. Rewrite `db_connect()` — both files

### Current (provisional, 5 vars)

`R/pull_apps.R:4-14`, `R/function_cc_scorecard_data.R:1-11` — byte-identical today.

### Target (single connection string)

```r
db_connect <- function() {
  DBI::dbConnect(
    RPostgres::Postgres(),
    dbname = Sys.getenv("SUPABASE_DB_URL")
  )
}
```

### Design rationale

- **Single source of truth**: one env var, no drift between host/port/user/password.
- **Matches roll_tracker**: same variable name (`SUPABASE_DB_URL`), same value format.
- **`sslmode=require`**: embedded in the URL query string, not a separate R-side param.
  Supabase requires SSL; including it in the URL means the enforcement travels with the
  credential, not with the code.
- **Mechanism**: RPostgres wraps libpq. When libpq receives a `postgresql://` URI via
  the `dbname` parameter, it parses it as a full conninfo string. This is standard libpq
  behavior (PostgreSQL docs §34.1.1). Status: INFERRED — must be VERIFIED with a live
  connection in Pass 3. If it fails, fallback: parse the URL in R and pass individual
  params.

### Why port 5432 (session pooler), not 6543 (transaction pooler)

The binding reason is **prepared statements**. RPostgres uses libpq's extended query
protocol, which creates server-side prepared statements for parameterized queries.
Supabase's transaction pooler (port 6543) explicitly does not support prepared statements
(Supabase docs, verified in Pass 1). This means transaction mode breaks RPostgres as a
*client*, regardless of whether the SQL being sent is DDL or DML.

The prior claim ("session mode supports DDL, transaction mode does not") is imprecise —
Supabase does not document a DDL restriction in transaction mode. But the prepared-
statement restriction is sufficient: transaction mode is incompatible with this client.
Port 5432 is not a preference; it is a requirement.

Source: 1-explore.md "Supabase pooler mode verification"; Pass 2 addition #1.

### Secret handling

The entire conninfo including the password lives in `SUPABASE_DB_URL`. Some RPostgres
connection errors surface the conninfo string in the error message. Rules:

- Do NOT `print()`, `message()`, `cat()`, or `paste()` the value of `SUPABASE_DB_URL`.
- When demonstrating the live connection in Pass 3, paste only the `select 1` result.
- If a connection error must be reported, redact the password from the output first.

Source: Pass 2 addition #3.

### Edit locations

| File | Lines to replace | New content |
|---|---|---|
| `R/pull_apps.R` | 4-14 (entire `db_connect` function) | Target function above |
| `R/function_cc_scorecard_data.R` | 1-11 (entire `db_connect` function) | Target function above — byte-identical |

### Byte-identity verification

After editing, run:
```bash
diff <(sed -n '/^db_connect/,/^}/p' R/pull_apps.R) \
     <(sed -n '/^db_connect/,/^}/p' R/function_cc_scorecard_data.R)
```
Must produce empty output.

---

## 3. Rewrite `.Renviron.example`

### Current (`.Renviron.example:1-11`)

```
# SUPERSEDED — variable names below do NOT match ../roll_tracker.
# roll_tracker uses SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / SUPABASE_DB_URL.
# Checkpoint supabase-credentials will align or justify the divergence.
# Until then, do NOT populate .Renviron from this file.
#
# Provisional variables (will be replaced):
SUPABASE_HOST=
SUPABASE_PORT=5432
SUPABASE_DB=
SUPABASE_USER=
SUPABASE_PWD=
```

### Target

```
# Supabase session pooler connection string (port 5432, Supavisor).
# Copy this file to .Renviron, fill in <project_ref> and <password>, restart R.
#
# Format: postgresql://postgres.<project_ref>:<password>@<host>:5432/postgres?sslmode=require
#
# IMPORTANT:
#   - The username MUST be postgres.<project_ref>, not just "postgres".
#     The pooler uses the project ref for routing; omitting it produces
#     "password authentication failed" even with the correct password.
#   - The password MUST be percent-encoded if it contains @ / ? # : or
#     other URI-special characters. Supabase-generated passwords routinely
#     include these. An unencoded @ splits the URI authority section,
#     producing a host-resolution error that looks nothing like an auth failure.
#     In R: utils::URLencode("your-password", reserved = TRUE)
SUPABASE_DB_URL=
```

Traces to: 1-explore.md discrepancy #1-#3; Pass 2 additions #2 (percent-encoding),
#3 (secret handling — the variable name signals it's a URL, not a bare password).

---

## 4. Replace dangling commit SHAs in R file

Git history was reset to a single commit (`d93fbbf`). Two comments in `R/pull_apps.R`
reference the now-dangling SHA `b59d6c8`:

| Line | Current text | Replacement |
|---|---|---|
| 56 | `Source text (pre-edit pull_apps.R:52-60 @ b59d6c8):` | `Source text (pre-edit pull_apps.R:52-60, pre-OCR-cleanup):` |
| 116 | `@ b59d6c8, now lines 87-92)` | `pre-OCR-cleanup, now lines 87-92)` |

Pass artifact files (`.claude/passes/clean-ocr-pull-scripts/*.md`) retain their original
SHA references. Those SHAs are dangling and cannot be resolved — they serve as ordering
markers within the pass narrative, not as pointers into live history.

Traces to: 1-explore.md "Dangling commit SHAs"; user correction on wording.

---

## 5. Create `CLAUDE.md`

New file at repo root. Pointer document, not a copy of the task brief.

```markdown
# CC Model Monitoring

Quarterly monitoring pipeline for a custom credit card application scorecard.
Rebuilds production pipeline (DB2/Databricks) from OCR screenshots, rewired to
Supabase (Postgres) with generic tables.

Primary orchestrator: `orchestration_2.Rmd` (~2,800 lines, ~40 chunks).
Validated frontier: line 300 (`# QC: Validated`) — but "validated" means reviewed,
not run. Code is validated only once it has run (D5).

## Current loop position

Completed: OCR cleanup of `R/pull_apps.R` and `R/function_cc_scorecard_data.R`.
Current: `supabase-credentials` — wiring `db_connect()` to Supabase, installing
RPostgres, live connection test.

Next sequence: prim_score/grain resolution (user) -> flatten-apps-query ->
create-supabase-tables -> round-trip test -> sample-data-generator ->
fix-orchestration-rmd.

## Pull function contracts

| Function | File | Returns |
|---|---|---|
| `get_apps_data(performance_window, write)` | `R/pull_apps.R` | data.frame: application-level, one row per APP_NUM. Key columns: user_ref_num, dt_entered, decision, applied, navy_cust_scr_*, prim_score. Writes `data/apps/apps_YYYYMM.txt.gz` if `write=T`. |
| `get_cc_scorecard_data(performance_window, write)` | `R/function_cc_scorecard_data.R` | data.frame: scorecard-level, one row per sq_num. Key columns: user_ref_num, score, segment, actduty, trans_date_ct, priored1. Writes `data/scorecard/scorecard_YYYYMM.txt.gz` if `write=T`. |

## Where things live

| What | Where |
|---|---|
| Decisions (D1-D7) | `.claude/docs/decisions.md` |
| Pass artifacts | `.claude/passes/<task-name>/` |
| R script catalog | `R/CATALOG.md` |
| Project catalog | `CATALOG.md` |

## Evidence discipline

- Cite `path:line` for load-bearing claims.
- Distinguish VERIFIED (ran it, output observed) from INFERRED (reasoning).
- `source()` proves a file parses and defines. It does NOT evaluate function bodies.
- Corrections need more verification than original work.
- Reconcile, do not append: if a change makes adjacent text wrong, fix both.
- Confirm the carrying path: a change correct in one file while the path that
  carries the value silently drops it is the recurring failure mode.

## Update rule

This file MUST be updated whenever a connection, table, or frontier changes.
```

Traces to: task brief "CLAUDE.md — new deliverable".

---

## 6. Verification steps (Pass 3, after all edits)

### 6a. parse() + source() — both R files
```
Rscript -e "parse('R/pull_apps.R'); cat('parse OK\n')"
Rscript -e "parse('R/function_cc_scorecard_data.R'); cat('parse OK\n')"
Rscript -e "source('R/pull_apps.R'); cat('source OK\n')"
Rscript -e "source('R/function_cc_scorecard_data.R'); cat('source OK\n')"
```

### 6b. db_connect() byte-identity
```bash
diff <(sed -n '/^db_connect/,/^}/p' R/pull_apps.R) \
     <(sed -n '/^db_connect/,/^}/p' R/function_cc_scorecard_data.R)
```

### 6c. Live connection test

**GATE**: requires user to populate `.Renviron` with a real `SUPABASE_DB_URL` first.
Pass 3 cannot complete this step without it. Flag to user before beginning execution
so the value is ready and execution does not stall with code changed but unverified.

```r
result <- DBI::dbGetQuery(db_connect(), "SELECT 1 AS ok")
print(result)
```

Expected output: `ok` column, value `1`. Paste only this result — do NOT paste the
connection string or any error output containing it without first redacting the password.

If `dbname`-as-conninfo fails (RPostgres does not parse the URI), fallback:
```r
db_connect <- function() {
  url <- Sys.getenv("SUPABASE_DB_URL")
  m <- regmatches(url, regexec("^postgresql://([^:]+):([^@]+)@([^:]+):(\\d+)/(.+?)(?:\\?(.*))?$", url))[[1]]
  params <- list()
  if (length(m) >= 7 && nzchar(m[7])) {
    pairs <- strsplit(strsplit(m[7], "&")[[1]], "=")
    for (p in pairs) params[[p[1]]] <- p[2]
  }
  DBI::dbConnect(
    RPostgres::Postgres(),
    host     = m[4],
    port     = as.integer(m[5]),
    dbname   = m[6],
    user     = m[2],
    password = utils::URLdecode(m[3]),
    sslmode  = params[["sslmode"]] %||% "require"
  )
}
```

This is heavier and introduces URL parsing, so it is the fallback, not the primary
approach. If needed, it replaces the primary in both files (still byte-identical).

### 6d. Grep for superseded content
- `SUPERSEDED` in `.Renviron.example` — must return zero
- `SUPABASE_HOST|SUPABASE_PORT|SUPABASE_DB[^_]|SUPABASE_USER|SUPABASE_PWD` in R files
  — must return zero (old var names gone)

### 6e. No secrets in diff
```bash
git diff --cached  # inspect before committing — no passwords, keys, or .Renviron content
```

---

## 7. Commit and push

Branch: to be determined with user. The task brief says "committed to a branch and PUSHED,
reviewed before merge to main."

---

## Execution order (Pass 3)

1. **Ask user**: "Please populate `.Renviron` with your `SUPABASE_DB_URL`. I need this
   before the live connection test. Format is in the updated `.Renviron.example`."
2. Install RPostgres (`renv::install` + `renv::snapshot`)
3. Edit `db_connect()` in both files
4. Edit `.Renviron.example`
5. Replace dangling SHAs in `R/pull_apps.R`
6. Create `CLAUDE.md`
7. Verify: parse, source, byte-identity diff, grep for old vars
8. Verify: live connection (`SELECT 1`) — paste result
9. `git diff --stat`, commit to branch, push
10. Write `3-execute.md`

Steps 2-6 can proceed before the user provides `.Renviron`. Step 8 blocks on it.
If the user has not provided `.Renviron` by step 8, pause and ask.

---

## What this plan does NOT do

- Touch SQL (dialect conversion belongs to flatten task)
- Create Supabase tables
- Resolve `priored1` vs `primedt` (schema task)
- Extract `db_connect()` to shared `R/db.R` (flatten task)
- Add `dbClearResult()` / `dbDisconnect()` (flatten task)
- Scrub git history of infrastructure identifiers (separate operation)

---

**Awaiting user approval before executing Pass 3.**
