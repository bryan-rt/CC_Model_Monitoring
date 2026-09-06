db_connect <- function() {
  url <- Sys.getenv("SUPABASE_DB_URL")
  m <- regmatches(url, regexec("^postgres(?:ql)?://([^:]+):([^@]+)@([^:]+):(\\d+)/([^?]+)", url))[[1]]
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

get_cc_scorecard_data <- function(performance_window = performance_window,
                                   write = T){

  conn <- db_connect()

  df <- DBI::dbGetQuery(conn = conn,
    statement = glue::glue("

                   select

                   sq_num,
                   left(user_ref_num, 14) as user_ref_num,
                   score,
                   trim(segment) as segment,
                   trim(actduty) as actduty,
                   trans_date_ct,
                   proc_date_ct,
                   priored1

                   from crdtplcynl_rstr.ccsrccrddaragen2
                   where trans_date_ct >= '{lubridate::floor_date(performance_window[1], \"month\")}'
                     AND trans_date_ct <= '{lubridate::ceiling_date(performance_window[1], \"month\") - 1}'
                     /*and trim(segment) != '*'*/
                   "))

if(write == T){
  data.table::fwrite(x = df,
             file = glue::glue(here::here("data/scorecard/scorecard_{format(as.Date(min(performance_window)), '%Y%m')}.txt.gz")),
             sep = ',',
             compress = 'auto',
             append = F,
             scipen = 999,
             showProgress = T)

}

  return(df)
}
