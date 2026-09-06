# Pass 1 — Explore: scrub-rmd-credentials
Date: 2026-09-06  ·  Commit: 66b106d

## Scope

Scrub all credential and infrastructure identifiers from `*.Rmd` files. Delete
`orchestration.Rmd` (superseded). Replace `orchestration_2.Rmd` CSI connection
block with a D13 stub. Confirm zero hits from the definition-of-done grep.

## Findings

### orchestration.Rmd — DELETE (2,381 lines)

F1. `orchestration.Rmd:476` — `keyring::keyring_unlock(password = "keyring")`
F2. `orchestration.Rmd:478` — `keyring::key_list()`
F3. `orchestration.Rmd:480` — `host <- "svb-20890728103416-01.cl.svrconnection.net"`
F4. `orchestration.Rmd:481` — `subscription_name <- "AAANA-01-PROD-SVS"`
F5. `orchestration.Rmd:484-498` — full `odbc::dbConnect()` block with DSN, PWD,
    Auth_AccessToken, AuthMech, compute_cluster references

All 5 hits eliminated by deleting the file. The file is marked SUPERSEDED in
CATALOG.md. Its OCR-comparison value is banked in `scripts/discrepancies.log`.

### orchestration_2.Rmd — CSI connection block (:519-546)

F6. `:523` — `keyring::keyring_unlock(password = 'keyring')`
F7. `:525` — `keys <- keyring::key_list()`
F8. `:527` — `host <- 'adv-2496822760[UNCLEAR].ll.azuredatabricks.net'`
F9. `:528` — `subscription_name <- 'SPACE-IT-PROD-BI'`
F10. `:529` — compute cluster path `'ascii-clust[UNCLEAR]/...'`
F11. `:530-534` — `DBI::dbConnect(drv, ...)` with host, password via `key_get('BI')`
F12. `:539-546` — `odbc::dbConnect(odbc::odbc(), DSN='BI', UID=..., PWD=keyring::key_get('BI'), Auth_Client_id=..., Host=host, HTTPPATH=compute_cluster, Token...)`

All credential material is in lines 523-546 (24 lines). The chunk opens at
`:512` with prose at `:513-518`. Lines `:519-522` are commented model-input-window
stubs. Lines `:548+` are non-connection CSI logic (damaged but retainable per D13).

### orchestration_2.Rmd — keyring prose section (:42-54)

F13. `:42` — `### 1) Creating the Keyring File` section header
F14. `:44` — prose paragraph describing keyring setup for 8 database connections
     (names EDWPROD, PRODODBC, Impala64, TSYS_DV_DB2, ASL, cpspace,
     MySQL_CPSpace, edu_lending)
F15. `:46-54` — commented-out code block with `source('R/set_keyring.R')` and
     `set_keyring()` call

These are informational prose + commented code, not executable credentials. The
DSN names in the prose paragraph are database identifiers. The code is all
commented out. **But** the grep will match `keyring` at `:42,:44,:47,:48,:51`.

### Grep-invisible connection patterns

F16. `:530` — `DBI::dbConnect(drv, ...)` — matched by secondary grep but would
     not be caught by the definition-of-done grep (no keyring/DSN/PWD keyword
     on that exact line). However, it's inside the :523-546 block being replaced,
     so it's covered.

F17. `:553` — `# odbc::dbGetQuery(` — commented out, no credentials, inside
     the post-connection CSI logic. Not a credential concern.

## Contradictions with the Task Brief

None. The brief's hit count ("5 of 13") matches: 5 hits in orchestration.Rmd
(F1-F5), 8 in orchestration_2.Rmd (F6-F15 collapse to 8 grep-matching lines).
The keyring prose section (F13-F15) was not explicitly mentioned in the brief
but will trigger the definition-of-done grep.

## Existing contracts touched

None. No function signatures, return values, or column names change.
`orchestration.Rmd` is consumed by nothing (CATALOG.md: "Read by: Nothing").

## Defects observed (not fixed)

D1. `orchestration_2.Rmd:509` — line reads `?` (likely OCR artifact for `}`
    or end-of-chunk marker). This is outside the credential block and not
    in scope.

## Not examined

- `orchestration_2.Rmd` lines outside :42-54 and :509-634 — not credential-related.
- `renv/activate.R` — excluded per brief (GITHUB_TOKEN is renv bootstrap, not embedded creds).
- `scripts/` — Python tooling, no R connection code.

## Open questions for Pass 2

None.

## Assumptions

None — all findings cited.

## Scope assessment
- Files edited: 2 (orchestration.Rmd deleted, orchestration_2.Rmd edited)
- Contract changes: no
- New Supabase tables or migrations: no
- Single verification run sufficient: yes (grep)
- Spec fits on one page: yes
- **Verdict: SINGLE** — two localized edits, no contract changes, grep verification
