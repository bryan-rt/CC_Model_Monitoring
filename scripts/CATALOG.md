# scripts/ Catalog

Python tooling for the project.

| File | Status | Purpose | Key functions | Read by |
|---|---|---|---|---|
| `image_to_rmd_pipeline.py` | VALIDATED | OCR + Claude Vision pipeline to transcribe screenshots into R/Rmd files | `main()`, `process_image()`, `detect_and_merge_overlap()` | User (CLI) |
| `pipeline.log` | REFERENCE | Most recent pipeline run log | — | User (debug) |
| `discrepancies.log` | REFERENCE | Overlap discrepancies from most recent pipeline run | — | User (QC review) |
