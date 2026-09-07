source(here::here("R/db.R"))

get_performance_data <- function(performance_window, write = TRUE) {
  conn <- db_connect()
  on.exit(DBI::dbDisconnect(conn))

  # -- Type contract (Postgres DDL source) ---------------------------------
  # user_ref_num     VARCHAR(14) NOT NULL  PK, join key -> apps/scorecard (D9)
  # origination_date DATE        NOT NULL  = apps.dt_entered for approved apps
  # dq90             INTEGER     NOT NULL  0/1, past-90-days delinquent within
  #                                        12 months of origination

  df <- DBI::dbGetQuery(conn, glue::glue("
    SELECT
      user_ref_num,
      origination_date,
      dq90
    FROM performance
    WHERE origination_date >= '{lubridate::floor_date(performance_window[1], 'month')}'
      AND origination_date <= '{lubridate::ceiling_date(performance_window[1], 'month') - 1}'
  "))

  if (write == TRUE) {
    data.table::fwrite(
      x = df,
      file = glue::glue(here::here(
        "data/dq_12_mos/dq_12_mos_{format(as.Date(min(performance_window)), '%Y%m')}.txt.gz"
      )),
      sep = ",",
      compress = "auto",
      append = FALSE,
      scipen = 999,
      showProgress = TRUE
    )
  }

  return(df)
}
