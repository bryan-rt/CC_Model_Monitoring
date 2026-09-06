source(here::here("R/db.R"))

setup_supabase <- function() {
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

  DBI::dbExecute(conn, "DROP TABLE IF EXISTS applications CASCADE")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS scorecard CASCADE")

  execute_sql_file(conn, here::here("sql/01_create_tables.sql"))
  execute_sql_file(conn, here::here("sql/02_seed_minimal.sql"))

  message("Setup complete: applications + scorecard created and seeded.")
}
