source(here::here("R/db.R"))

get_cc_scorecard_data <- function(performance_window, write = TRUE) {
  conn <- db_connect()
  on.exit(DBI::dbDisconnect(conn))

  # -- Type contract (Postgres DDL source) ---------------------------------
  # sq_num         INTEGER      NOT NULL   retained per D9, not grain-defining
  # user_ref_num   VARCHAR(14)  NOT NULL   join key -> apps
  # score          NUMERIC      NULL
  # segment        TEXT         NULL       Rmd: as.character(as.numeric(segment))
  # actduty        TEXT         NULL
  # trans_date_ct  DATE         NOT NULL   date filter column
  # proc_date_ct   DATE         NULL
  # primemdt       TEXT         NULL       D10: name resolved, type deliberately TEXT

  df <- DBI::dbGetQuery(conn, glue::glue("
    SELECT
      sq_num,
      user_ref_num,
      score,
      segment,
      actduty,
      trans_date_ct,
      proc_date_ct,
      primemdt
    FROM scorecard
    WHERE trans_date_ct >= '{lubridate::floor_date(performance_window[1], 'month')}'
      AND trans_date_ct <= '{lubridate::ceiling_date(performance_window[1], 'month') - 1}'
  "))

  if (write == TRUE) {
    data.table::fwrite(
      x = df,
      file = glue::glue(here::here(
        "data/scorecard/scorecard_{format(as.Date(min(performance_window)), '%Y%m')}.txt.gz"
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
