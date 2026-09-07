source(here::here("R/db.R"))

setup_supabase <- function(mode = c("minimal", "generated")) {
  mode <- match.arg(mode)
  conn <- db_connect()
  on.exit(DBI::dbDisconnect(conn))

  # NB: semicolon-split breaks if a seeded TEXT value contains a semicolon.
  # Current seed data does not; if future seeds do, switch to single-statement
  # files or use a SQL parser.
  execute_sql_file <- function(conn, path) {
    sql <- paste(readLines(path), collapse = "\n")
    statements <- strsplit(sql, ";\\s*\n")[[1]]
    statements <- trimws(statements)
    statements <- statements[nchar(statements) > 0]
    for (stmt in statements) {
      DBI::dbExecute(conn, stmt)
    }
  }

  DBI::dbExecute(conn, "DROP TABLE IF EXISTS performance CASCADE")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS applications CASCADE")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS scorecard CASCADE")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS features CASCADE")

  execute_sql_file(conn, here::here("sql/01_create_tables.sql"))
  execute_sql_file(conn, here::here("sql/03_create_features_table.sql"))
  execute_sql_file(conn, here::here("sql/04_create_performance_table.sql"))

  if (mode == "minimal") {
    execute_sql_file(conn, here::here("sql/02_seed_minimal.sql"))
    message("Setup complete: minimal seed loaded (50 apps, 40 scorecard, 40 features).")
  } else {
    source(here::here("R/generate_cohort.R"))
    result <- generate_cohort()
    DBI::dbAppendTable(conn, "applications", result$apps)
    DBI::dbAppendTable(conn, "scorecard", result$scorecard)
    DBI::dbAppendTable(conn, "features", result$features)
    DBI::dbAppendTable(conn, "performance", result$performance)
    message("Setup complete: generated cohorts loaded (",
            nrow(result$apps), " apps, ",
            nrow(result$scorecard), " scorecard, ",
            nrow(result$features), " features, ",
            nrow(result$performance), " performance rows).")
  }
}
