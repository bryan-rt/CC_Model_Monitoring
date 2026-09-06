# Pass 3 — Execute: supabase-credentials

Branch: `pass3/supabase-credentials`

---

## Edits applied

### R/pull_apps.R — 3 edits

| # | Action | Traces to |
|---|---|---|
| PA-1 | Replaced provisional 5-var `db_connect()` (lines 4-14) with URL-parsing fallback using single `SUPABASE_DB_URL` | 2-plan.md §2, fallback activated |
| PA-2 | `@ b59d6c8` → `pre-OCR-cleanup` at line 56 | 2-plan.md §4 |
| PA-3 | `@ b59d6c8` → `pre-OCR-cleanup` at line 116 | 2-plan.md §4 |

### R/function_cc_scorecard_data.R — 1 edit

| # | Action | Traces to |
|---|---|---|
| SC-1 | Replaced provisional 5-var `db_connect()` (lines 1-11) with URL-parsing fallback — byte-identical to pull_apps.R | 2-plan.md §2 |

### .Renviron.example — full rewrite

Removed SUPERSEDED header and 5 provisional variables. Replaced with single
`SUPABASE_DB_URL=` template with percent-encoding warning and pooler-user
(`postgres.<project_ref>`) warning.

### renv.lock — 1 addition

`RPostgres 1.4.10` — only package added. `renv::snapshot()` output confirmed
no other changes. `git diff renv.lock` verified: only the RPostgres block was
inserted (VERIFIED — diff output observed).

### CLAUDE.md — new file

Pointer document at repo root. Content corrections from user review:
- Scorecard grain marked UNRESOLVED (no GROUP BY in query)
- Apps key columns corrected: app_num, client_product_cd, copied_from instead
  of navy_cust_scr_*
- Open questions section added: prim_score typing, priored1 vs primedt,
  scorecard grain

---

## Primary approach failure

The `dbname`-as-conninfo approach (Pass 1 INFERRED, Pass 2 primary) failed.
RPostgres does not pass a `postgresql://` URI in the `dbname` parameter through
to libpq's conninfo parser. It treats it as a literal database name, producing
a local socket connection attempt:

```
Error: connection to server on socket "/tmp/.s.PGSQL.5432" failed:
  No such file or directory
```

The fallback (regex URL parsing in R) was activated per 2-plan.md §6c. The
single `SUPABASE_DB_URL` env var is preserved — only the R-side mechanism
changed from one-line passthrough to URL decomposition.

---

## Verification results (observed)

### parse() + source()

| File | parse() | source() | Result |
|---|---|---|---|
| `R/pull_apps.R` | OK | OK (exit 0, no ERROR) | VERIFIED |
| `R/function_cc_scorecard_data.R` | OK | OK (exit 0, no ERROR) | VERIFIED |

### db_connect() byte-identity

```
$ diff <(sed -n '/^db_connect/,/^}/p' R/pull_apps.R) \
       <(sed -n '/^db_connect/,/^}/p' R/function_cc_scorecard_data.R)
```
Empty output — VERIFIED.

### Grep for superseded content

| Pattern | Scope | Matches |
|---|---|---|
| `SUPERSEDED` | `.Renviron.example` | 0 |
| `SUPABASE_HOST\|SUPABASE_PORT\|SUPABASE_DB[^_]\|SUPABASE_USER\|SUPABASE_PWD` | `R/` | 0 |
| `b59d6c8` | `R/` | 0 |

### Live connection test (VERIFIED — session output)

```
--- Test 1: SELECT 1 ---
  ok
1  1

--- Test 2: current_user, current_database ---
  current_user current_database
1     postgres         postgres

--- Test 3: parameterized query ---
  ok
1  1

--- Test 4: temp table create/drop ---
CREATE TEMP TABLE: OK
DROP TABLE: OK

All connection tests passed.
```

Test 3 (parameterized `$1::int`) exercises libpq's extended query protocol,
which creates server-side prepared statements. This confirms session pooler
mode (port 5432) — transaction mode (port 6543) would fail here.

Test 4 (`CREATE TEMP TABLE`) exercises session-level state, a second
confirmation of session mode.

Connection properly disconnected via `on.exit(DBI::dbDisconnect(conn))`.

---

## git diff --stat (branch vs main)

```
 .Renviron.example              | 24 ++++++++++++++----------
 CLAUDE.md                      | 62 +++++++++++++++++++++++++++++++++++++++++++
 R/function_cc_scorecard_data.R | 12 +++++++-----
 R/pull_apps.R                  | 16 +++++++++-------
 renv.lock                      | 18 ++++++++++++++++++
 5 files changed, 109 insertions(+), 22 deletions(-)
```

---

## Definition of done — checklist

- [x] `DBI::dbGetQuery(db_connect(), "select 1")` returns 1 — live session output above
- [x] Actual session output pasted, not a description
- [x] `.Renviron.example` SUPERSEDED header removed, variable names final
- [x] `.Renviron` confirmed gitignored; no secret material in diff
- [x] `renv.lock` includes RPostgres
- [x] `db_connect()` byte-identical across both files — diff pasted
- [x] Both files source() cleanly
- [x] `CLAUDE.md` created
- [x] `3-execute.md` written
- [x] `git diff --stat` in this summary
- [ ] Committed to branch and PUSHED, reviewed before merge to main

---

## Deferred items

| Item | Destination |
|---|---|
| Extract `db_connect()` to shared `R/db.R` | flatten task |
| SQL dialect conversion (DECODE → CASE, DB2 → Postgres) | flatten task |
| `dbClearResult()` / `dbDisconnect()` in pull functions | flatten task |
| `priored1` vs `primedt` | schema task |
| `prim_score` typing | schema task |
| Scorecard grain resolution | schema task |
| Scrub git history of infrastructure identifiers | separate operation |
