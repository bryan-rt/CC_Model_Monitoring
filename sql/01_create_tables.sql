-- Schema derived from R/pull_apps.R:9-25 and R/function_cc_scorecard_data.R:7-15.
-- Do not add columns that are not in those annotation blocks.

CREATE TABLE applications (
  app_num             INTEGER       NOT NULL PRIMARY KEY,
  user_ref_num        VARCHAR(14)   NULL,
  dt_entered          DATE          NOT NULL,
  client_product_cd   TEXT          NOT NULL,
  strategy_version    TEXT          NULL,
  assigned_credit_lim NUMERIC       NULL,
  decision            TEXT          NOT NULL,
  applied             INTEGER       NOT NULL,
  org_paper_type      TEXT          NULL,
  lao_credit_lmt      NUMERIC       NULL,
  fico_score          NUMERIC       NULL,
  bureau_used         TEXT          NULL,
  acq                 TEXT          NULL,
  prim_score          NUMERIC       NULL
);

CREATE TABLE scorecard (
  sq_num          INTEGER       NOT NULL,
  user_ref_num    VARCHAR(14)   NOT NULL PRIMARY KEY,
  score           NUMERIC       NULL,
  segment         TEXT          NULL,
  actduty         TEXT          NULL,
  trans_date_ct   DATE          NOT NULL,
  proc_date_ct    DATE          NULL,
  primemdt        TEXT          NULL
);
