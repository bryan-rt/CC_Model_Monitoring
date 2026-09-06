# Pass 1 — Explore: clean-ocr-pull-scripts

## Files in scope

| File | Lines | Status |
|---|---|---|
| `R/pull_apps.R` | 158 | OCR-RAW |
| `R/function_cc_scorecard_data.R` | 65 | OCR-RAW |

---

## D7 — Fidelity artifact context

**Decision D7**: the Supabase apps source will be a SINGLE FLAT TABLE. The five joined
warehouse tables (ADM_APP_INFO, ADM_GEN_VAL, ADM_DATA_ELEM, ADM_TS2_EXTR_OVR, ADM_APP_LOG)
collapse to one `applications` table. No EAV table, no pivot, no subqueries.
`get_apps_data()` becomes a single SELECT with column aliases and a date filter. Scorecard
is already effectively flat.

Preserve the full output column list, including columns with zero current uses in the Rmd.
Unused columns are retained because the Rmd regions that would consume them (lines 304-508)
carry the heaviest OCR damage — "unused" there means "unreadable", not "absent". Adding a
column later is trivial; discovering a missing one while rehearsing is not. Acknowledged
cost: going flat gives up the DECODE -> MAX(CASE WHEN) dialect conversion as a live
walkthrough example; it survives only in the reconstruction diff.

The SQL repaired in this task will be **deleted by the following task** (flatten rewrite).
This is intended. This task produces a **fidelity artifact**: a faithful, sourceable
reconstruction of the original query, committed so the repo history shows
`OCR-raw → reconstruction → flat rewrite` as three diffs in one file. The cleaning is
required regardless, because `orchestration_2.Rmd:80` sources this file and it must parse
and source cleanly.

**The cleaned file is not the destination — it is a waypoint for traceability.**

---

## Mechanical fixes (apply in Pass 2)

### R/pull_apps.R

1. **Line 4** — stray `if performance_window <- ...`: delete.
2. **Line 9** — hardcoded keyring password `'keyring'`: remove unlock call.
3. **Line 154** — unclosed function brace: `return(df)` is at line 154 with no closing `}` for `get_apps_data`. Add closing `}` after `return(df)`.
4. **Line 147** — `"XYXm"` → `'%Y%m'` (OCR garble); `'Date/Apps/'` → `'data/apps/'` (Rmd reads lowercase `data/apps/`; confirmed via `orchestration_2.Rmd:171`).
5. **Line 150** — `append = T` → `append = F` (scorecard fn uses `F`; appending to gzipped files is wrong).
6. **Line 151** — `nclpen = 999` → `scipen = 999`.
7. **Lines 146-152** — wrap `fwrite` block in `if(write == T){ ... }` to match scorecard fn's guard.
8. **Lines 157-158** — `(Top Level) =`: delete stray OCR artifact.
9. **Lines 95-96** — unescaped `"month"` inside double-quoted glue string terminates the
   string at line 95's first `"`. Every other glue date call (119, 120, 123, 124, 129, 130)
   uses `'month'`; 95-96 are the outliers. Parse error — file cannot source without this fix.
   (Missed in Pass 1 — Pass 1 did semantic review only, not `parse()`.)

### R/function_cc_scorecard_data.R

1. **Line 5** — `library(edlhelper)`: delete.
2. **Line 7** — hardcoded keyring password `'keyring'`: remove unlock call.
3. **Lines 10-12** — Azure host, subscription name, compute cluster path: delete.
4. **Lines 14-18** — `edlhelper::EdlCredentialNew(...)`: delete.
5. **Lines 20-28** — `edl_conn` referencing removed vars: replace (see connection plan below).
6. **Line 26** — `edl_cred$refresh_databricks_token()`: name drift — line 14 assigns `cred`, line 26 references `edl_cred`. Moot once connection block is replaced.
7. **Line 32** — restore `statement = glue::glue("` wrapper (discrepancies.log line 32, Version A correct).
8. **Line 40** — `trim(actdtu)` → `trim(actduty)` (discrepancies.log line 40, Version A correct).
9. **Line 47** — `performance_window[2]` → `performance_window[1]` (pull_apps.R uses `[1]` throughout; `[2]` is inconsistent and the function signature has no multi-element contract).
10. **Line 48** — `/*and trim(segment) != '*'/` → `/*and trim(segment) != '*'*/` (close SQL comment).
11. **Line 53** — `"Data/Scorecard/"` → `"data/scorecard/"` (Rmd reads lowercase; confirmed via `orchestration_2.Rmd:164`).
12. **Line 57** — `nclpen = 999` → `scipen = 999`.
13. **Line 65** — `set_cc_scorecard_data(performance_window_mntc) #`: delete top-level call.

### Connection plan (replaces get_conn() stop-stub)

Both connection blocks are deleted outright: no keyring, no DSN, no Azure
host/subscription/cluster. Replace with a real `db_connect()` helper using RPostgres +
Sys.getenv, per D3:

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

Design notes:
- `RPostgres::Postgres()` namespaced inside the function body — no `library(RPostgres)` at
  file top. `source()` must succeed with no side effects; a function definition is
  side-effect-free even if the package is absent.
- Duplicated in both files for now (one-task scope). Extraction to a shared `R/db.R` belongs
  to the flatten task.
- Until the tables exist, this fails at query time with "relation does not exist" — a more
  honest failure than a `stop()` someone has to remember to remove.
- The exact parameter set is **PROVISIONAL**. Checkpoint `supabase-credentials` (see below)
  may change variable names, port, or sslmode to match the working setup in `../roll_tracker`.

Reference from `../roll_tracker` (READ-ONLY, read during this pass via Explore agent):
- Env vars: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_DB_URL` (connection string)
  — source: `roll_tracker/.env.example:5-12`
- Port 5432 session pooler (NOT direct connection — direct is IPv6-only, fails in Docker)
  — source: `roll_tracker/.env.example:8`
- Host: `aws-1-us-east-1.pooler.supabase.com`
  — source: `roll_tracker/.env.example:9,12`
- dbname: `postgres` (appears in connection string template)
  — source: `roll_tracker/.env.example:9,12`
- Backend uses `psycopg` (Python), not RPostgres — R pattern is new for this project
  — source: `roll_tracker/services/uploader/uploader/database.py:5-6,11`
- Service-role key for backend ops; anon key for frontend only
  — source: `roll_tracker/.env.example:6-7`, `roll_tracker/app_web/.env.example:2`
- Session pooler mode (port 5432, Supavisor) supports DDL; transaction mode (port 6543) does not
  — source: `roll_tracker/.claude/rules/supabase.md:39`

**Discrepancies between roll_tracker and the provisional db_connect() above** (inputs to
supabase-credentials checkpoint — do NOT change db_connect() in this task):
- roll_tracker uses `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` / `SUPABASE_DB_URL`.
  The committed `.Renviron.example` uses `SUPABASE_HOST` / `PORT` / `DB` / `USER` / `PWD`.
  Different scheme. `.Renviron.example` is marked superseded pending the checkpoint.
- Supabase's pooler requires username `postgres.<project_ref>`, NOT `postgres`. A
  `db_connect()` passing `SUPABASE_USER=postgres` against a pooler host fails auth.
  Most common Supabase-from-R failure; invisible until connect time.
- `SUPABASE_DB_URL` is a full connection string. `RPostgres::Postgres()` accepts one
  directly — simpler than five variables that can drift.
- Pooler mode matters for the schema task: session mode (port 5432) supports DDL,
  transaction mode (port 6543) does not. roll_tracker uses session mode (port 5432).
- `psycopg` means there is no R precedent in roll_tracker. The R connection pattern is
  new and must be verified with a live connection test in the credentials checkpoint,
  not assumed.

---

## Judgment calls — DECIDED

### JC1. `logic` CASE expression (pull_apps.R:52-60) — RESOLVED: 3-branch AUTO/MANUAL

Reconstruct as three WHEN branches with a comment recording both OCR readings.

**Disclosure — OR → AND edit in MANUAL branch**: The source text at pull_apps.R:58 reads:

```
(MAX(G.OFFICER_ID) IS NOT NULL OR MAX(G.OFFICER_ID) <> '')
```

The applied reconstruction changes `OR` to `AND`:

```
(MAX(G.OFFICER_ID) IS NOT NULL AND MAX(G.OFFICER_ID) <> '')
```

**Rationale**: With `OR`, a non-NULL empty-string `OFFICER_ID` evaluates TRUE (the `IS NOT
NULL` arm succeeds), classifying the row as `'MANUAL'`. This contradicts branch 2, which
treats `NULL` and `''` equivalently as "no officer present" → `'AUTO'`. The `AND` form
requires the officer ID to be both non-NULL and non-empty, which is consistent with the
`AUTO` branch's logic. This is a **third edit** layered on top of the two OCR readings — it
is an inference about intent, not a transcription.

Applied SQL:

```sql
/* OCR RECONSTRUCTION — logic CASE
   Source text (pull_apps.R:52-60): structurally merged, unbalanced parens
   Reading A (applied): 3-branch AUTO/MANUAL/'' based on officer presence
     - OR→AND change in MANUAL branch (see 1-explore.md JC1 disclosure)
   Reading B (discarded): literal OCR with missing WHEN keyword at line 58
   NOTE: `logic` column is consumed nowhere in orchestration_2.Rmd */
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

### JC2. Officer-log join key (pull_apps.R:114-122) — RESOLVED: wrap MAX, drop '.'

The unaggregated `DISPLAY_TM` under `GROUP BY APP_NUM` is invalid SQL regardless of
separator choice. Fix: `MAX(CHAR(DISPLAY_DT)||CHAR(DISPLAY_TM)) AS DT`. Drop `'.'` from
subquery to match the ON clause (either separator works if both sides match; the mismatch
is the only error).

### JC3. 'NAVY CUSTOM SCORE 3' in ELEMENT_NAME IN list — RESOLVED: do NOT add, comment

Preserve the current IN list and add a comment.

**Underscore-vs-space mismatch**: the DECODEs (lines 79-83) use underscored names
(`'NAVY_CUSTOM_SCORE_3'`, `'NAVY_CUSTOM_SCORE_2'`, `'NAVY_CUSTOM_SCORE'`) while the IN list
(line 104) uses spaced names (`'NAVY CUSTOM SCORE 2'`, `'NAVY CUSTOM SCORE'`). If read
literally in DB2, the DECODE predicates would never match rows filtered by the IN list,
nulling **all three** score columns — not just `NAVY_CUST_SCR_3`.

Treating the underscores in the DECODEs as OCR artifacts (should be spaces) is an
**inference** supported by line 87 (`'CBA REF NUMBER'` with spaces in the same subquery),
not a confirmed fact. This is recorded here but not acted on in this task — the flatten
rewrite (D7) will replace the entire subquery.

### JC4. `priored1` vs `primedt` — RESOLVED: keep `priored1`, UNRESOLVED

Keep `priored1` as-is. Mark as unresolved — zero uses in 2,802 lines of Rmd.

**Corrected rationale**: Under D1/D7, the Supabase table schema is designed to match whatever
the SELECT names, so neither `priored1` nor `primedt` will fail at runtime — the table will
simply be created with whichever column name we choose. The risk is not a runtime error but
**silent permanence**: the moment the Supabase table is created with one name, the ambiguity
becomes invisible. If the wrong name is baked in, no downstream code will surface the
discrepancy because nothing currently consumes this column.

**Handoff**: `priored1` vs `primedt` remains UNRESOLVED and **must be carried into the
schema design task** as an open question. If it is not explicitly revisited when the
`applications` / scorecard tables are created, the unknown becomes permanently invisible.

---

## Checkpoint: supabase-credentials (partially executed — read done, wiring deferred)

`../roll_tracker` was read READ-ONLY during this pass. The reference data is recorded in the
connection plan section above with file-level citations. What remains for the checkpoint:
- Align `.Renviron.example` variable names to match roll_tracker's scheme (or justify divergence)
- Decide: five separate env vars vs single `SUPABASE_DB_URL` connection string
- Verify `RPostgres::Postgres()` connects successfully (no R precedent in roll_tracker)
- Confirm session pooler (port 5432) works for both DDL (schema task) and DML (query time).
  NOTE: the claim "session mode supports DDL, transaction mode does not" is cited to
  `roll_tracker/.claude/rules/supabase.md:39` — a Claude-authored note in another repo,
  not ground truth. Verify against Supabase's own documentation during this checkpoint.
- Write `.Renviron` with real values by hand (never committed, never copied from roll_tracker)

**DO NOT** copy `.Renviron`, keys, passwords, or any file containing secret material into
this repo. Write `.Renviron.example` with correct variable names and EMPTY values; the user
pastes real values into `.Renviron` by hand, once, outside version control. Copying secrets
across repos puts live keys in two places that must both stay gitignored forever, in a repo
that has already leaked infrastructure identifiers into public history once.

---

## `scipen` verification

`scipen` was confirmed as a valid `data.table::fwrite` argument by running
`formals(data.table::fwrite)` in a live R session and observing `scipen` in the returned
list. Session output:

```
$ Rscript -e 'cat(names(formals(data.table::fwrite)), sep="\n")'
x
file
append
quote
sep
...
scipen        # <-- present
dateTimeAs
buffMB
nThread
showProgress
compress
yaml
bom
verbose
```

This is live session output, not inference.

---

## Additional notes

- Table name `crdtplcynl_rstr.ccsrccrddaragen2` vs Version A `crdtplcy_rstr.ctrscrcdatagon2`:
  both look OCR-garbled. Per constraint, NOT changing table names in this task.
- `glue::glue()` `{...}` syntax inside SQL strings: correct glue interpolation behavior.
- `pull_apps.R` uses `dbSendQuery()` + `dbFetch()` with no `dbClearResult()` / `dbDisconnect()`.
  This leaks the result set and connection. Not fixed in this task (the flatten rewrite will
  replace the entire query execution path).
- Both functions use a self-referencing default `performance_window = performance_window`,
  which only works because callers always pass the argument explicitly. If called without an
  argument, R will error on the self-reference. Not fixed in this task — the flatten rewrite
  will replace the function signatures.

---

## Security — history contains infrastructure identifiers

Commit `5bd4ed8` (public repo) contains in `R/*.R`:
- Azure workspace host `adb-298282276613203...azuredatabricks.net`
- Subscription name `SPOKE-01-PROD-EUS`
- Compute cluster path with cluster ID `0126-152005-wb9gqhrm`
- `keyring::keyring_unlock(password = ...)`

Removing them in a new commit does NOT remove them from git history. These are infrastructure
identifiers (not credentials), so attacker risk is low — but this is a public repo carrying
an employer's internal identifiers and the URL is going to an interview panel.

**Recommended**: delete the GitHub repo, `rm -rf .git`, re-init with one clean initial
commit, push to a new remote. Only 3 commits exist and none are precious. Alternative:
`git filter-repo` + force push + ask GitHub Support to purge cached views.

**This is a separate operation — do NOT mix into a code diff.**

---

## Handoff to flatten task

The pull scripts double as the contract from which the Supabase DDL is written. A SELECT
alone is a weak contract: it fixes column names and order but not types, nullability, or
keys. The flatten task must add a type annotation block above each SELECT specifying, per
column, the Postgres type, nullable Y/N, and which column is the join key.

The binding surface is NOT the Postgres schema. The path is:
`Postgres → RPostgres → fwrite .txt.gz → fread → Rmd`

So the Rmd sees fread's inferred types from gzipped CSV. Three columns to specify carefully
and then TEST through a full write/read round trip:

- **`dt_entered`**: `orchestration_2.Rmd:194,214` calls `zoo::as.yearqtr()` on it. If fread
  types it as character, `as.yearqtr()` may return NA for every row and silently collapse the
  QC grouping. Verify by round trip, not by reading.
- **`user_ref_num`**: SQL does `left(...,14)`, R does `as.numeric()`. 14 digits is exact in
  a double. Recommend text in Postgres, cast in R. This is the join key — a silent mismatch
  breaks everything downstream.
- **`prim_score`**: still UNRESOLVED (score value vs scorecard identifier). Do not type this
  column until that question is answered — choosing numeric silently resolves a question we
  have not answered.

Also carry forward: `priored1` vs `primedt` remains UNRESOLVED and must be revisited when
the scorecard table is created.

---

## Pass 2 plan

1. Replace connection blocks in both files with `db_connect()` helper (RPostgres + Sys.getenv)
2. Apply all mechanical fixes listed above
3. Apply JC1-JC4 resolutions
4. Verify both files source cleanly: `Rscript -e "source('R/pull_apps.R')"` and same for
   scorecard. (`source()`, not `parse()` — parsing does not execute top-level code, and the
   definition of done requires "sources cleanly with no side effects", which proves the
   deleted line-65 top-level call is gone and no connection is attempted at source time.)
5. Grep for any remaining credential/host/cluster/subscription strings
6. Commit `.Renviron.example` with SUPABASE_* variable names, no values
7. Update `R/CATALOG.md` status

**Awaiting user approval before executing Pass 2.**
