# Project Catalog

**Validated frontier:** `orchestration_2.Rmd` line 300 (`# QC: Validated`)

## Folder index

| Folder | Catalog | Purpose |
|---|---|---|
| `/` (root) | this file | Project root — orchestration notebooks and config |
| `R/` | `R/CATALOG.md` | Sourced R scripts (pull functions, KS calculations) |
| `scripts/` | `scripts/CATALOG.md` | Python tooling (image-to-code pipeline) |
| `data/` | `data/CATALOG.md` | Generated/pulled data files (gitignored contents) |
| `docs/` | `docs/CATALOG.md` | Project documentation |
| `.claude/docs/` | `.claude/docs/CATALOG.md` | Workflow decisions and overturned conclusions |
| `.claude/passes/` | — | Working artifacts from three-pass workflow runs |

## Root files

| File | Status | Purpose | Key exports | Read by |
|---|---|---|---|---|
| `orchestration_2.Rmd` | CLEANED | Main orchestration notebook — PSI/CSI/KS quarterly report | Knitted HTML report | User (primary deliverable) |
| `orchestration.Rmd` | SUPERSEDED | Original orchestration notebook (pre-cleanup) | — | Nothing (reference only) |
| `CC_Model_Monitoring.Rproj` | CURRENT | RStudio project file | — | RStudio |
| `.Rprofile` | CURRENT | R session profile | — | R session startup |
| `renv.lock` | CURRENT | Package dependency lockfile | — | `renv::restore()` |
| `README.md` | STUB | Project readme | — | GitHub |
| `.gitignore` | CURRENT | Git ignore rules | — | Git |
