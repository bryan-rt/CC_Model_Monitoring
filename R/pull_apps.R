library(dplyr)
library(lubridate)

db_connect <- function() {
  url <- Sys.getenv("SUPABASE_DB_URL")
  m <- regmatches(url, regexec("^postgresql://([^:]+):([^@]+)@([^:]+):(\\d+)/([^?]+)", url))[[1]]
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

get_apps_data <- function(performance_window = performance_window,
                          write = T){

  conn <- db_connect()

  df <- DBI::dbSendQuery(
    conn = conn,
    statement = glue::glue("
                  SELECT
                    *

FROM
  (SELECT A.APP_NUM,
    left(max(b.user_ref_num), 14) as user_ref_num,
    MAX(A.DT_ENTERED) AS DT_ENTERED,
    MAX(A.CLIENT_PRODUCT_CD) AS CLIENT_PRODUCT_CD,
    MAX(A.STRATEGY_VERSION) AS STRATEGY_VERSION,

  TRIM(MAX(A.ASSIGNED_CREDIT_LIM)) AS assigned_credit_lim,

  /* Application status */
  CASE
    WHEN MAX(A.STATUS_FIELD) IN  ('NEWACCOUNT','A2 ERROR','A2 WAIT','APPROVE') THEN 'Approve'
    WHEN MAX(A.STATUS_FIELD) IN  ('DECLINE') THEN 'Decline'
    WHEN MAX(A.STATUS_FIELD) IN  ('VOID APP') THEN 'Void'
    WHEN MAX(A.STATUS_FIELD) IN  ('WITHDRAW') THEN 'Withdraw'
    ELSE 'Pending'
  END AS decision,
  case
    when MAX(A.STATUS_FIELD) IN  ('NEWACCOUNT','A2 ERROR','A2 WAIT','APPROVE','DECLINE') then 1
    else 0
  end as applied,

  CASE WHEN MAX(DD.TS2_ACCOUNT_ID) = '0' THEN NULL ELSE MAX(DD.TS2_ACCOUNT_ID) END AS APPLID,
  MAX(B.COPIED_FROM) AS COPIED_FROM,
  MAX(B.NAVY_CUST_SCR_3) AS NAVY_CUST_SCR_3,
  MAX(B.NAVY_CUST_SCR_2) AS NAVY_CUST_SCR_2,
  MAX(B.NAVY_CUST_SCR) AS NAVY_CUST_SCR,

  /* OCR RECONSTRUCTION — logic CASE
     Source text (pre-edit pull_apps.R:52-60, pre-OCR-cleanup): structurally merged, unbalanced parens
     Reading A (applied): 3-branch AUTO/MANUAL/'' based on officer presence
       - OR->AND change in MANUAL branch (see 1-explore.md JC1 disclosure)
     Reading B (discarded): literal OCR with missing WHEN keyword at pre-edit line 58
     NOTE: logic column is consumed nowhere in orchestration_2.Rmd */
  CASE
    WHEN MAX(A.STATUS_FIELD) NOT IN ('NEWACCOUNT','DECLINE','A2 ERROR','A2 WAIT','APPROVE') THEN ''
    WHEN (MAX(A.DECSN_OFFCR) IS NULL OR MAX(A.DECSN_OFFCR) = '') AND
         (MAX(G.OFFICER_ID) IS NULL OR MAX(G.OFFICER_ID) = '') AND
         MAX(A.STATUS_FIELD) IN ('NEWACCOUNT','DECLINE','A2 ERROR','A2 WAIT','APPROVE') THEN 'AUTO'
    WHEN (MAX(G.OFFICER_ID) IS NOT NULL AND MAX(G.OFFICER_ID) <> '') AND
         MAX(A.STATUS_FIELD) IN ('NEWACCOUNT','DECLINE','A2 ERROR','A2 WAIT','APPROVE') THEN 'MANUAL'
    ELSE ''
  END AS logic,

  MAX(DECODE(TRIM(C.ELEMENT_NAME),'ORG_PAPER_TYPE',C.ALPHA_VALUE)) AS ORG_PAPER_TYPE,
  MAX(DECODE(TRIM(C.ELEMENT_NAME),'CREDIT_LMT',C.NUMERIC_VALUE)) AS LAO_CREDIT_LMT,
  MAX(DECODE(TRIM(C.ELEMENT_NAME),'RISK_SCORE',C.NUMERIC_VALUE)) AS FICO_SCORE,
  MAX(DECODE(TRIM(C.ELEMENT_NAME),'BUREAU_USED',C.ALPHA_VALUE)) AS BUREAU_USED,
  MAX(DECODE(TRIM(C.ELEMENT_NAME),'ACQ_STRAT_CD',C.ALPHA_VALUE)) AS ACQ,
  MAX(case
    when trim(c.element_name) = 'PRIM_SCORE_CARD'
    then trim(c.ALPHA_VALUE)
    end) as prim_score


  FROM TA4236.ADM_APP_INFO A

  LEFT JOIN
  (SELECT A2.APP_NUM,
    MAX(DECODE(TRIM(A2.ELEMENT_NAME),'COPIED_FROM',A2.ALPHA_VALUE)) AS COPIED_FROM,
    MAX(DECODE(TRIM(A2.COMPONENT_NAME),'BURSELCT',
      DECODE(TRIM(A2.ELEMENT_NAME),'NAVY_CUSTOM_SCORE_3',A2.RISK_SCR))) AS NAVY_CUST_SCR_3,
    MAX(DECODE(TRIM(A2.COMPONENT_NAME),'BURSELCT',
      DECODE(TRIM(A2.ELEMENT_NAME),'NAVY_CUSTOM_SCORE_2',A2.RISK_SCR))) AS NAVY_CUST_SCR_2,
    MAX(DECODE(TRIM(A2.COMPONENT_NAME),'CONSUMER',
      DECODE(TRIM(A2.ELEMENT_NAME),'NAVY_CUSTOM_SCORE',A2.RISK_SCR))) AS NAVY_CUST_SCR,
    max(case
      when trim(A2.component_name) = 'BURSELCT'
      then case
        when trim(A2.element_name) = 'CBA REF NUMBER'
        then trim(A2.alpha_value)
        else NULL
      end
    end) as user_ref_num

  FROM TA4236.ADM_GEN_VAL A2
  JOIN TA4236.ADM_APP_INFO B2 ON A2.APP_NUM = B2.APP_NUM
  AND B2.DT_ENTERED >= '{lubridate::floor_date(performance_window[1], 'month')}'
  AND B2.DT_ENTERED <= '{lubridate::ceiling_date(performance_window[1], 'month') - 1}'
  WHERE A2.COMPONENT_NAME IN ('CONSUMER', 'BURSELCT')

  /********************************************************************************************
  NOTE: We also want to pull in the COPIED TO values, but I'm not sure yet how to do this correctly,
  should be a small portion of the population and I suspect it wont fully fix the problem

  ********************************************************************************************/
  AND A2.ELEMENT_NAME IN ('COPIED_FROM','NAVY CUSTOM SCORE 2','NAVY CUSTOM SCORE','RETURN DATE','CBA REF NUMBER')
  /* NOTE: 'NAVY CUSTOM SCORE 3' intentionally absent from IN list.
     Also: underscore vs space mismatch between DECODEs (pre-edit lines 79-83
     pre-OCR-cleanup, now lines 87-92) and this IN list would null all three score
     columns if read literally — see 1-explore.md JC3 */
  GROUP BY A2.APP_NUM) B ON A.APP_NUM = B.APP_NUM

  LEFT JOIN TA4236.ADM_DATA_ELEM C ON A.APP_NUM = C.APP_NUM

  LEFT JOIN TA4236.ADM_TS2_EXTR_OVR DD ON A.APP_NUM = DD.APP_NUM

  LEFT JOIN
  (SELECT e.APP_NUM,e.DISPLAY_DT,e.OFFICER_ID
FROM TA4236.ADM_APP_LOG e
JOIN (SELECT APP_NUM,
MAX(CHAR(DISPLAY_DT)||CHAR(DISPLAY_TM)) AS DT
FROM TA4236.ADM_APP_LOG
WHERE PROD_ID = 'F009'
AND LOG_TYPE = '0001'
AND DISPLAY_DT >= '{lubridate::floor_date(performance_window[1], 'month')}'
AND DISPLAY_DT <= '{lubridate::ceiling_date(performance_window[1], 'month') - 1}'
GROUP BY APP_NUM) F ON e.APP_NUM = F.APP_NUM AND
CHAR(e.DISPLAY_DT)||CHAR(e.DISPLAY_TM) = F.DT
WHERE e.DISPLAY_DT >= '{lubridate::floor_date(performance_window[1], 'month')}'
AND e.DISPLAY_DT <= '{lubridate::ceiling_date(performance_window[1], 'month') - 1}'
AND e.PROD_ID = 'F009'
AND e.LOG_TYPE = '0001') G ON A.APP_NUM = G.APP_NUM


WHERE A.DT_ENTERED >= '{lubridate::floor_date(performance_window[1], 'month')}'
AND A.DT_ENTERED <= '{lubridate::ceiling_date(performance_window[1], 'month') - 1}'
/*AND A.STATUS_FIELD IN ('NEWACCOUNT','A2 ERROR','A2 WAIT','APPROVE')*/
AND A.CLIENT_PRODUCT_CD NOT IN ('EPL',/*'SEC','MSC',*/'BUS','SBM','PUR', 'SBC', 'MBP')
GROUP BY A.APP_NUM)



") %>%
stringr::str_squish()) %>% DBI::dbFetch()
# NOTE: Do we really need to pull apps between this wide of a window, or do we only need to pull apps in the singular month?
# NOTE: We could probably write files with all the apps data for each month to reference rather than re-pulling these.
# AND A.DT_ENTERED <= '{lubridate::floor_date(Sys.Date(), 'month') - 1}'

# WHERE APP_ENTRY_DT >= '{lubridate::floor_date(performance_window[1], 'month')}'
# and <= '{lubridate::ceiling_date(performance_window[1], 'month') - 1}'

if(write == T){
  data.table::fwrite(x = df,
    file = glue::glue(here::here('data/apps/apps_{format(as.Date(min(performance_window)),"%Y%m")}.txt.gz')),
    sep = ',',
    compress = 'auto',
    append = F,
    scipen = 999,
    showProgress = 1)
}

return(df)

}
