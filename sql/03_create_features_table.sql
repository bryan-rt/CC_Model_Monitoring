-- Features table: one row per user_ref_num (D9 grain, D17).
-- 3 continuous features (quantile bins), 2 categorical features (level sets).
-- feature_date matches the application's dt_entered for monthly pull filtering.

CREATE TABLE features (
  user_ref_num VARCHAR(14) PRIMARY KEY,
  feature_date DATE        NOT NULL,
  feature_1    NUMERIC,
  feature_2    NUMERIC,
  feature_3    NUMERIC,
  feature_4    TEXT,
  feature_5    TEXT
);
