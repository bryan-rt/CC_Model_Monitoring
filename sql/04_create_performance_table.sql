-- Schema for 12-month DQ90 performance outcomes.
-- Approved applications only. Grain: one row per user_ref_num.

CREATE TABLE performance (
  user_ref_num     VARCHAR(14) PRIMARY KEY,
  origination_date DATE        NOT NULL,
  dq90             INTEGER     NOT NULL
);
