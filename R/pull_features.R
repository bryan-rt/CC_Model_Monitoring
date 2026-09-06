source(here::here("R/db.R"))

get_features_data <- function(performance_window, write = TRUE) {
  conn <- db_connect()
  on.exit(DBI::dbDisconnect(conn))

  # -- Type contract (Postgres DDL source) ---------------------------------
  # user_ref_num  VARCHAR(14)  NOT NULL  PK, join key -> apps/scorecard (D9)
  # feature_date  DATE         NOT NULL  pull filter column
  # feature_1     NUMERIC      NULL      continuous, 10 quantile bins
  # feature_2     NUMERIC      NULL      continuous, 8 quantile bins
  # feature_3     NUMERIC      NULL      continuous, 5 quantile bins
  # feature_4     TEXT         NULL      categorical, 4 levels (A/B/C/D)
  # feature_5     TEXT         NULL      categorical, 3 levels (X/Y/Z)

  df <- DBI::dbGetQuery(conn, glue::glue("
    SELECT
      user_ref_num,
      feature_date,
      feature_1,
      feature_2,
      feature_3,
      feature_4,
      feature_5
    FROM features
    WHERE feature_date >= '{lubridate::floor_date(performance_window[1], 'month')}'
      AND feature_date <= '{lubridate::ceiling_date(performance_window[1], 'month') - 1}'
  "))

  if (write == TRUE) {
    data.table::fwrite(
      x = df,
      file = glue::glue(here::here(
        "data/features/features_{format(as.Date(min(performance_window)), '%Y%m')}.txt.gz"
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
