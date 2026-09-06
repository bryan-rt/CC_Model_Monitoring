# Pass 2: Plan — create-supabase-tables

Date: 2026-09-06

## Deliverables

### 1. `sql/01_create_tables.sql`

```sql
CREATE TABLE applications (
  app_num             INTEGER       NOT NULL PRIMARY KEY,
  user_ref_num        VARCHAR(14)   NULL,
  dt_entered          DATE          NOT NULL,
  client_product_cd   TEXT          NOT NULL,
  strategy_version    TEXT          NULL,
  assigned_credit_lim NUMERIC       NULL,
  decision            TEXT          NOT NULL,
  applied             INTEGER       NOT NULL,
  org_paper_type      TEXT          NULL,
  lao_credit_lmt      NUMERIC       NULL,
  fico_score          NUMERIC       NULL,
  bureau_used         TEXT          NULL,
  acq                 TEXT          NULL,
  prim_score          NUMERIC       NULL
);

CREATE TABLE scorecard (
  sq_num          INTEGER       NOT NULL,
  user_ref_num    VARCHAR(14)   NOT NULL PRIMARY KEY,
  score           NUMERIC       NULL,
  segment         TEXT          NULL,
  actduty         TEXT          NULL,
  trans_date_ct   DATE          NOT NULL,
  proc_date_ct    DATE          NULL,
  primemdt        TEXT          NULL
);
```

Source: `R/pull_apps.R:9-25`, `R/function_cc_scorecard_data.R:7-15`.

PK on `scorecard.user_ref_num` per D9: grain is one row per user_ref_num.
This makes a grain violation fail loudly at INSERT rather than silently fanning
out the left_join months later. `sq_num` is retained as a column but is not
grain-defining.

No CHECK constraints on `decision` or `applied`. See "Inherited vs invented
values" below.

### 2. `sql/02_seed_minimal.sql`

~50 apps rows, ~30 scorecard rows, across three months (2026-07, 2026-08,
2026-09).

**user_ref_num values: 14-digit numeric strings.**

Why: The Rmd does `as.numeric(user_ref_num)` on both sides before joining.
Alphabetic content would produce NA with coercion warnings, making both frames
go all-NA on the join key. 14-digit values (~1e13) are inside a double's
exact-integer range (2^53 ≈ 9e15), so no precision loss.

This is also why `scipen = 999` is set in the fwrite calls at
`pull_apps.R:57` and `function_cc_scorecard_data.R:42` — without it, a
14-digit value round-trips through scientific notation (e.g., "1e+13") and the
join silently breaks on reload.

Seed values: `10000000000001` through `10000000000050` (roughly).

**Required edge cases:**

| Requirement | How satisfied |
|---|---|
| prim_score spread 100-450 | Values: 105, 150, 200, 250, 300, 350, 400, 445, plus NULLs |
| segments '0'-'4' with varying volumes | seg 0: ~3, seg 1: ~8, seg 2: ~6, seg 3: ~5, seg 4: ~3, NULL: ~5 |
| NULL prim_score | ~5 apps rows with NULL prim_score |
| NULL segment | ~5 scorecard rows with NULL segment |
| Unmatched apps rows (no scorecard) | ~8 apps rows whose user_ref_num has no scorecard match — left_join produces real NAs |
| SEC and MSC product codes | ~3 rows with 'SEC', ~2 with 'MSC' — Rmd filters these out |
| 14-digit user_ref_num | All values are exactly 14 digits |
| One row per user_ref_num in scorecard | PK enforces this; no duplicates seeded |

**Month distribution:**

| Month | apps rows | scorecard rows |
|---|---|---|
| 2026-07 | ~18 | ~12 |
| 2026-08 | ~17 | ~10 |
| 2026-09 | ~15 | ~8 |

**Inherited vs invented annotation values:**

These column constraints come from the original DB2 CASE/DECODE expressions
that no longer exist in the flat table. The annotations are design decisions,
not database-enforced constraints. The seed makes them real for the first time:

- `decision`: Five values ('Approve', 'Decline', 'Void', 'Withdraw', 'Pending')
  inherited from the original `CASE WHEN DEC_CODE IN (...)` at the warehouse
  layer. The flat table has no CHECK; the seed uses a realistic mix weighted
  toward 'Approve' and 'Decline'.
- `applied`: 0 or 1, inherited from the original `CASE WHEN APPLIED_IND = 'Y'
  THEN 1 ELSE 0` conversion. The flat table stores it as INTEGER with no
  CHECK; the seed uses only 0 and 1.
- `segment`: '0' through '4', inherited from the scorecard model's segment
  assignment. TEXT in Postgres (the Rmd does `as.character(as.numeric(segment))`
  which is a no-op on these values). Seed includes NULLs.

### 3. `R/setup_supabase.R`

```r
# Idempotent setup: drops and recreates both tables, seeds minimal data.
source(here::here("R/db.R"))

setup_supabase <- function() {
  conn <- db_connect()
  on.exit(DBI::dbDisconnect(conn))

  create_sql <- readLines(here::here("sql/01_create_tables.sql"))
  seed_sql   <- readLines(here::here("sql/02_seed_minimal.sql"))

  DBI::dbExecute(conn, "DROP TABLE IF EXISTS applications CASCADE")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS scorecard CASCADE")
  DBI::dbExecute(conn, paste(create_sql, collapse = "\n"))
  DBI::dbExecute(conn, paste(seed_sql, collapse = "\n"))

  message("Setup complete: applications + scorecard created and seeded.")
}
```

Idempotent: DROP IF EXISTS before CREATE. CASCADE in case future FKs exist.
Uses `readLines()` + `paste()` to execute the SQL files through `dbExecute()`.

**Issue: `dbExecute()` with multiple statements.** RPostgres sends the entire
string as one query. Postgres accepts multiple statements in a single query
string, so this works — but only via the session pooler (port 5432), not the
transaction pooler (port 6543) which breaks multi-statement. The `.Renviron`
is already configured for 5432 per the project setup.

However, the seed SQL will have many INSERT statements. Safer approach: split
on semicolons and execute individually, OR use a single multi-row INSERT per
table. **Decision: use multi-row INSERT (one per table) in the seed SQL.**
This avoids the multi-statement concern entirely and is cleaner.

For the CREATE SQL, the two CREATE TABLE statements need to be executed
separately. Split approach:

```r
DBI::dbExecute(conn, "DROP TABLE IF EXISTS applications CASCADE")
DBI::dbExecute(conn, "DROP TABLE IF EXISTS scorecard CASCADE")

# Read and execute SQL files statement by statement
execute_sql_file <- function(conn, path) {
  sql <- paste(readLines(path), collapse = "\n")
  statements <- strsplit(sql, ";\\s*\n")[[1]]
  statements <- trimws(statements)
  statements <- statements[nchar(statements) > 0]
  for (stmt in statements) {
    DBI::dbExecute(conn, stmt)
  }
}

execute_sql_file(conn, here::here("sql/01_create_tables.sql"))
execute_sql_file(conn, here::here("sql/02_seed_minimal.sql"))
```

This handles both files uniformly and is robust to any number of statements.

### 4. `data/apps/.gitkeep` and `data/scorecard/.gitkeep`

Create both directories with `.gitkeep` files so they're tracked by git.
fwrite needs these directories to exist.

### 5. `.gitignore` update

Add to `.gitignore`:

```
# Pull function output (gzipped CSV)
data/**/*.txt.gz
```

This covers `data/apps/*.txt.gz`, `data/scorecard/*.txt.gz`, and any future
subdirectory data files. The `.gitkeep` files are not matched.

### 6. Validation script

Run in R (not in the Rmd). Three months, all six checks.

```r
source(here::here("R/pull_apps.R"))
source(here::here("R/function_cc_scorecard_data.R"))

# Pull all three months
for (mo in c("2026-07-01", "2026-08-01", "2026-09-01")) {
  get_apps_data(as.Date(mo), write = TRUE)
  get_cc_scorecard_data(as.Date(mo), write = TRUE)
}

# Round-trip checks on July (representative)
a <- data.table::fread("data/apps/apps_202607.txt.gz")
s <- data.table::fread("data/scorecard/scorecard_202607.txt.gz")

# Check 1: column count and names
stopifnot(ncol(a) == 14, ncol(s) == 8)
cat("Check 1 — ncol(a):", ncol(a), " ncol(s):", ncol(s), "\n")
cat("  names(a):", paste(names(a), collapse=", "), "\n")
cat("  names(s):", paste(names(s), collapse=", "), "\n")

# Check 2: dt_entered class
cat("Check 2 — class(a$dt_entered):", class(a$dt_entered), "\n")

# Check 3: zoo::as.yearqtr on dt_entered
yq <- zoo::as.yearqtr(a$dt_entered)
cat("Check 3 — yearqtr NAs:", sum(is.na(yq)), "of", length(yq), "\n")
cat("  values:", paste(unique(yq), collapse=", "), "\n")

# Check 4: prim_score class
cat("Check 4 — class(a$prim_score):", class(a$prim_score), "\n")

# Check 5: user_ref_num numeric conversion — check CLASS first
cat("Check 5 — class(a$user_ref_num):", class(a$user_ref_num), "\n")
cat("  class(s$user_ref_num):", class(s$user_ref_num), "\n")
a_urns <- as.numeric(a$user_ref_num)
s_urns <- as.numeric(s$user_ref_num)
matched <- intersect(a_urns, s_urns)
cat("  NAs in as.numeric(a$user_ref_num):", sum(is.na(a_urns)), "\n")
cat("  NAs in as.numeric(s$user_ref_num):", sum(is.na(s_urns)), "\n")
cat("  Matching user_ref_nums:", length(matched), "\n")

# Check 6: left_join row count and NA segments
joined <- dplyr::left_join(a, s, by = "user_ref_num")
cat("Check 6 — joined rows:", nrow(joined), " (apps rows:", nrow(a), ")\n")
cat("  NA segments in joined:", sum(is.na(joined$segment)), "\n")
```

**Check 5 class note:** fread may infer 14-digit values as `integer64`
(from the `bit64` package) rather than `numeric` or `character`. At 1e13
magnitude, `as.numeric()` on integer64 is exact (well within 2^53), so the
join still works — but the check must verify this rather than assume it.
If fread returns them as character (due to VARCHAR in the CSV header), that's
also fine since `as.numeric("10000000000001")` is exact.

### File change summary

| File | Action |
|---|---|
| `sql/01_create_tables.sql` | CREATE |
| `sql/02_seed_minimal.sql` | CREATE |
| `R/setup_supabase.R` | CREATE |
| `data/apps/.gitkeep` | CREATE |
| `data/scorecard/.gitkeep` | CREATE |
| `.gitignore` | EDIT (add `data/**/*.txt.gz`) |

No changes to: `orchestration_2.Rmd`, `R/pull_apps.R`,
`R/function_cc_scorecard_data.R`, `R/db.R`.

### Post-validation

- Update `CLAUDE.md`: tables exist, loop position advanced.
- Update `data/CATALOG.md`: subdirectories now exist (no longer STUB).
- Update `R/CATALOG.md`: add `setup_supabase.R`.
- Write `3-execute.md`.
- Branch `pass3/create-supabase-tables`, commit, push.
