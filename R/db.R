db_connect <- function() {
  url <- Sys.getenv("SUPABASE_DB_URL")
  m <- regmatches(url, regexec(
    "^postgres(?:ql)?://([^:]+):([^@]+)@([^:]+):(\\d+)/([^?]+)", url
  ))[[1]]
  if (length(m) == 0) {
    stop("SUPABASE_DB_URL is unset or malformed. Expected ",
         "postgresql://user:password@host:port/dbname — see .Renviron.example",
         call. = FALSE)
  }
  DBI::dbConnect(
    RPostgres::Postgres(),
    host     = m[4],
    port     = as.integer(m[5]),
    dbname   = m[6],
    user     = m[2],
    password = utils::URLdecode(m[3]),
    sslmode  = "require"
  )
}
