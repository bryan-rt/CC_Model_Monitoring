library(dplyr)
library(lubridate)
source(here::here("R/db.R"))

get_apps_data <- function(performance_window, write = TRUE) {
  conn <- db_connect()
  on.exit(DBI::dbDisconnect(conn))

  # -- Type contract (Postgres DDL source) ---------------------------------
  # app_num            INTEGER      NOT NULL   grain / PK
  # user_ref_num       VARCHAR(14)  NULL       join key -> scorecard (D9)
  # dt_entered         DATE         NOT NULL   Rmd: zoo::as.yearqtr()
  # client_product_cd  TEXT         NOT NULL
  # strategy_version   TEXT         NULL
  # assigned_credit_lim NUMERIC    NULL
  # decision           TEXT         NOT NULL   'Approve'|'Decline'|'Void'|'Withdraw'|'Pending'
  # applied            INTEGER      NOT NULL   0 or 1
  # org_paper_type     TEXT         NULL
  # lao_credit_lmt     NUMERIC     NULL
  # fico_score         NUMERIC     NULL
  # bureau_used        TEXT         NULL
  # acq                TEXT         NULL
  # prim_score         NUMERIC     NULL       D8: score value 100-450
  # -- Dropped (D11): applid, logic, custom_score, custom_score_2, custom_score_3
  # -- Dropped (D12): copied_from

  df <- DBI::dbGetQuery(conn, glue::glue("
    SELECT
      app_num,
      user_ref_num,
      dt_entered,
      client_product_cd,
      strategy_version,
      assigned_credit_lim,
      decision,
      applied,
      org_paper_type,
      lao_credit_lmt,
      fico_score,
      bureau_used,
      acq,
      prim_score
    FROM applications
    WHERE dt_entered >= '{floor_date(performance_window[1], 'month')}'
      AND dt_entered <= '{ceiling_date(performance_window[1], 'month') - 1}'
  "))

  if (write == TRUE) {
    data.table::fwrite(
      x = df,
      file = glue::glue(here::here(
        "data/apps/apps_{format(as.Date(min(performance_window)), '%Y%m')}.txt.gz"
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
