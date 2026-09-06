# Pass 1 — Explore: supabase-credentials

## Files in scope

| File | Lines | Current state | Change needed |
|---|---|---|---|
| `R/pull_apps.R` | 172 | CLEANED, provisional `db_connect()` | Align `db_connect()` |
| `R/function_cc_scorecard_data.R` | 51 | CLEANED, provisional `db_connect()` | Align `db_connect()` |
| `.Renviron.example` | 11 | SUPERSEDED header, 5 provisional vars | Replace with final scheme |
| `renv.lock` | 1570 | No RPostgres | Add RPostgres |
| `CLAUDE.md` | — | Does not exist | Create |

---

## Standing step: parse() verification

| File | parse() | source() | Result |
|---|---|---|---|
| `R/pull_apps.R` | OK | OK (exit 0, no ERROR) | VERIFIED — session output observed |
| `R/function_cc_scorecard_data.R` | OK | OK (exit 0, no ERROR) | VERIFIED — session output observed |

---

## db_connect() current state

Both files contain an identical `db_connect()` — VERIFIED via `diff` (empty output):

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

Source: `R/pull_apps.R:4-14`, `R/function_cc_scorecard_data.R:1-11`

---

## roll_tracker reference (READ-ONLY)

Source: `../roll_tracker/.env.example` (read during this pass, not copied)

### Env vars (lines 5-12)
```
SUPABASE_URL=https://<project_id>.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<JWT service_role key from dashboard>
SUPABASE_DB_URL=postgresql://postgres.<project_ref>:<password>@aws-1-us-east-1.pooler.supabase.com:5432/postgres
```

### Key facts
- **User format**: `postgres.<project_ref>` — NOT `postgres`. The pooler requires the
  project ref suffix. A `db_connect()` passing `user=postgres` against the pooler host
  fails auth with a misleading "password authentication failed" error.
  Source: `roll_tracker/.env.example:9` (URL template shows `postgres.<project_ref>`)
- **Host**: `aws-1-us-east-1.pooler.supabase.com` — this is the Supavisor session pooler.
  Source: `roll_tracker/.env.example:9,12`
- **Port**: 5432 (session pooler, NOT direct connection which is IPv6-only).
  Source: `roll_tracker/.env.example:8` (comment) and `:12` (URL template)
- **dbname**: `postgres`.
  Source: `roll_tracker/.env.example:9,12` (URL template ends `/postgres`)
- **Backend**: Python psycopg — no R precedent in roll_tracker.
  Source: `roll_tracker/services/uploader/uploader/database.py:5-6,11`
- **`SUPABASE_URL`**: the REST API URL, used for PostgREST/JS client. Not needed for
  direct Postgres connections from R.
- **`SUPABASE_SERVICE_ROLE_KEY`**: JWT for PostgREST. Not needed for direct Postgres wire
  protocol (which uses password auth).

### Relevant to this repo
Only `SUPABASE_DB_URL` is needed. `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are
REST API credentials — this repo connects via Postgres wire protocol, not PostgREST.

---

## Discrepancies: provisional db_connect() vs roll_tracker

| # | Provisional (current) | roll_tracker | Impact |
|---|---|---|---|
| 1 | 5 separate env vars (`HOST`, `PORT`, `DB`, `USER`, `PWD`) | Single `SUPABASE_DB_URL` connection string | Five vars can drift out of sync. Brief explicitly suggests single URL. |
| 2 | `SUPABASE_USER` (implies `postgres`) | `postgres.<project_ref>` embedded in URL | Auth failure against pooler — most common Supabase-from-R failure |
| 3 | `sslmode = "require"` as separate param | Not in URL template (but Supabase requires SSL) | Need `?sslmode=require` appended to URL, or passed as separate param |
| 4 | `as.integer(Sys.getenv("SUPABASE_PORT", "5432"))` | Port embedded in URL | Moot if using connection string |

---

## RPostgres status

- **Not in `renv.lock`**: VERIFIED — grep for "RPostgres" returns zero matches
- **Not installed system-wide**: VERIFIED — `library(RPostgres)` exits with error:
  `"there is no package called 'RPostgres'"`
- **Must install**: `renv::install("RPostgres")` then `renv::snapshot()` to update
  `renv.lock`. This will pull `libpq` as a system dependency (C library).

---

## Connection string approach — design decision

The brief suggests: "Consider `SUPABASE_DB_URL` as a single connection string rather than
five variables that can drift out of sync. `RPostgres::Postgres()` accepts one."

**Mechanism**: RPostgres wraps libpq. When libpq receives a connection string
(`postgresql://...`) via the `dbname` parameter, it parses it as a full conninfo string.
This is standard libpq behavior documented in the PostgreSQL manual.

Proposed `db_connect()`:
```r
db_connect <- function() {
  DBI::dbConnect(
    RPostgres::Postgres(),
    dbname = Sys.getenv("SUPABASE_DB_URL")
  )
}
```

Proposed `.Renviron.example`:
```
# Supabase session pooler connection string (port 5432).
# Copy to .Renviron, fill in <project_ref> and <password>.
# Format: postgresql://postgres.<project_ref>:<password>@<host>:5432/postgres?sslmode=require
SUPABASE_DB_URL=
```

**Advantages**:
- Matches roll_tracker's variable name
- Single source of truth — no drift between host/port/user/password
- `sslmode=require` embedded in URL, not a separate R-side param
- Simpler `db_connect()` (3 lines vs 8)

**Risk**: The `dbname`-as-conninfo approach is standard libpq but UNVERIFIED in RPostgres
from R. Must be confirmed with a live connection in Pass 3 before committing. If it fails,
fallback is individual params parsed from the URL in R.

**Status**: INFERRED (libpq behavior) — not VERIFIED until Pass 3 live test.

---

## Supabase pooler mode verification (DDL claim)

**Claim** (from `roll_tracker/.claude/rules/supabase.md:39`): "Session pooler URL
(port 5432, Supavisor) — not direct connection (IPv6-only fails in Docker)."

**Broader claim** (from `1-explore.md` of prior task): "Session mode supports DDL,
transaction mode does not."

**Verification against Supabase docs** (`supabase.com/docs/guides/database/connecting-to-postgres`):
- Session mode: port 5432, Supavisor — CONFIRMED
- Transaction mode: port 6543, Supavisor — CONFIRMED
- Transaction mode restriction: "does not support prepared statements" — CONFIRMED
- DDL restriction in transaction mode: **NOT explicitly documented**. The docs do not
  mention DDL as a transaction-mode limitation. DDL statements are regular SQL and work
  in both modes. The real restriction is session-level state (prepared statements,
  `SET`, `LISTEN/NOTIFY`, temp tables).
- IPv6-only for direct connection: confirmed by roll_tracker comment, not tested

**Conclusion**: The DDL claim is IMPRECISE but the practical recommendation is correct —
use session mode (port 5432) as roll_tracker does. This is what the `SUPABASE_DB_URL`
template already specifies. For this project, DDL (schema task) and DML (query time) both
go through port 5432. No action needed beyond using the correct URL.

---

## .gitignore verification

`.Renviron` IS listed in `.gitignore:35` — VERIFIED by reading the file.
`.env` IS listed in `.gitignore:4` — VERIFIED.

No secret material will be committed if `.Renviron` is used for credentials.

---

## Git state

- Single commit: `d93fbbf Clean initial commit: CC Model Monitoring project`
- Working tree clean (VERIFIED — `git status -s` returned empty)
- No `CLAUDE.md` at root (VERIFIED)

---

## Dangling commit SHAs

Git history was reset to a single commit. The following files reference now-dangling SHAs:

| File | Lines | SHAs | Action |
|---|---|---|---|
| `R/pull_apps.R` | 56, 116 | `b59d6c8` | Replace with "pre-OCR-cleanup" in Pass 3 |
| `.claude/passes/clean-ocr-pull-scripts/1-explore.md` | 287 | `5bd4ed8` | Leave as-is (historical pass artifact) |
| `.claude/passes/clean-ocr-pull-scripts/3-execute.md` | 3, 20, 87, 108, 129, 130 | `7793038`, `5bd4ed8`, `b59d6c8` | Leave as-is (historical pass artifact) |

Only the R file references need updating — they appear in SQL comments that would be
visible during an interview walkthrough. Pass artifact files are internal records and
retain their original references for traceability.

---

## CLAUDE.md requirements

The brief specifies a pointer document covering:
- What the project is
- Current loop position
- Return contract of both pull functions
- Where decisions and pass artifacts live
- Evidence discipline
- Update rule (must be updated when a connection, table, or frontier changes)

This is a new file. Content will be drafted in Pass 2.

---

## Task brief hypotheses — verified

| Hypothesis | Verified? | Finding |
|---|---|---|
| `.Renviron.example` carries SUPERSEDED header | YES | `.Renviron.example:1` |
| `R/pull_apps.R` and `R/function_cc_scorecard_data.R` need `db_connect()` aligned | YES | Both contain provisional 5-var version |
| `renv.lock` needs RPostgres | YES | Not present in lockfile or installed |
| `CLAUDE.md` needs to be created | YES | Does not exist |

---

## Changes required (inputs to Pass 2)

1. **Install RPostgres** via `renv::install("RPostgres")` + `renv::snapshot()` — updates
   `renv.lock`. This is a Pass 3 action (mutates lockfile).

2. **Rewrite `db_connect()`** in both files — from 5-var approach to single
   `SUPABASE_DB_URL` connection string. Must remain byte-identical across both files.

3. **Rewrite `.Renviron.example`** — remove SUPERSEDED header, replace 5 provisional vars
   with single `SUPABASE_DB_URL` template. Include format comment showing
   `postgres.<project_ref>` user pattern.

4. **Replace dangling SHAs** in `R/pull_apps.R:56,116` — `@ b59d6c8` becomes
   `(pre-OCR-cleanup)`.

5. **Create `CLAUDE.md`** at repo root.

6. **Live connection test**: `DBI::dbGetQuery(db_connect(), "select 1")` — requires user
   to populate `.Renviron` with real values first.

7. **Create `.claude/passes/supabase-credentials/3-execute.md`** after execution.

### What this task does NOT do
- Touch SQL (dialect conversion belongs to flatten task)
- Create Supabase tables
- Resolve `priored1` vs `primedt` (schema task)
- Extract `db_connect()` to shared `R/db.R` (flatten task)
- Scrub git history of infrastructure identifiers (separate operation)

---

**Awaiting user approval before proceeding to Pass 2.**
