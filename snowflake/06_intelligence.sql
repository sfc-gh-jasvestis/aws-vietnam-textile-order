-- ============================================================================
-- 06_INTELLIGENCE.SQL - search, anomaly detection, semantic view, agent,
-- live order-status alert and on-demand refresh DAG.
-- Run with snowflake/run_intelligence.py (substitutes validated __DEMO_DB__ /
-- __DEMO_WH__ / __ALERT_EMAIL__). Requires 00-05, plus 08 (Snowflake only) or
-- aws/setup_aws.py (AWS build) for RAW.LIVE_ORDERS.
-- Alerts and tasks are created SUSPENDED; run them with EXECUTE ALERT / EXECUTE TASK.
-- ============================================================================
USE DATABASE __DEMO_DB__;
CREATE SCHEMA IF NOT EXISTS SEARCH;
CREATE SCHEMA IF NOT EXISTS APP;

-- ---------- Synthetic order-risk follow-up SOPs (clearly synthetic, not buyer compliance guidance) ----------
CREATE OR REPLACE TABLE SEARCH.ORDER_SOP_DOCS AS
WITH signals AS (
  SELECT DISTINCT r.RISK_SIGNAL, f.CATEGORY
  FROM RAW.FACTORY_DAILY r JOIN RAW.FACTORIES f ON f.ID = r.ENTITY_ID
  WHERE r.CONFIRMED_COUNT > 0
)
SELECT
  'SOP-' || LPAD(ROW_NUMBER() OVER (ORDER BY CATEGORY, RISK_SIGNAL)::VARCHAR, 3, '0') AS DOC_ID,
  'SOP' AS DOC_TYPE,
  CATEGORY,
  RISK_SIGNAL,
  CATEGORY || ' - ' || RISK_SIGNAL || ' order follow-up' AS TITLE,
  'Synthetic demo SOP for a fictional network of Vietnam garment factories; not buyer compliance or audit guidance. Product category: ' || CATEGORY || '. Order-risk signal: ' || RISK_SIGNAL || '. '
  || 'Step 1: list the open buyer purchase orders at the factory with an ex-factory date in the next 14 days, and notify the merchandiser and the factory production manager within 1 business day. '
  || 'Step 2: ' || CASE
       WHEN RISK_SIGNAL = 'Fabric delivery late' THEN 'confirm the revised fabric in-house date with the mill, and re-plan the cutting sequence so the earliest ex-factory orders are cut first.'
       WHEN RISK_SIGNAL = 'Shade band rejected' THEN 'request a new shade band from the mill, and keep cutting on hold for the affected colourways until the buyer approves it.'
       WHEN RISK_SIGNAL = 'Trims not in-house' THEN 'chase the trims supplier for labels, buttons and zips by order number, and move sewing lines to orders whose trims are complete.'
       WHEN RISK_SIGNAL = 'Line efficiency below plan' THEN 'compare the daily sewing output with the line plan, and add overtime or a second line if the gap exceeds one day of output.'
       WHEN RISK_SIGNAL = 'Wash recipe rework' THEN 'rerun the wash trial against the approved wash standard, and confirm the recipe with the buyer before bulk washing restarts.'
       WHEN RISK_SIGNAL = 'PP sample not approved' THEN 'send the corrected pre-production sample to the buyer by courier, and hold bulk cutting until written approval is on file.'
       WHEN RISK_SIGNAL = 'Subcontract capacity cut' THEN 'ask the subcontractor for the revised weekly capacity in writing, and check whether another approved subcontractor can take the balance.'
       WHEN RISK_SIGNAL = 'Inline inspection fail' THEN 'review the inline inspection defects with the line supervisor, and re-inspect the next 2 hours of output before the order continues.'
       ELSE 'review the order against the buyer purchase order and escalate if unexplained.'
     END
  || ' Step 3: if the WIP gap exceeds 6% of plan or more than a quarter of the pieces are expected to miss the ex-factory date, ask the buyer for a revised ship date or an air-freight decision. '
  || 'Step 4: record the outcome and the evidence; release the order for booking only with sign-off from the merchandising lead.' AS CONTENT
FROM signals;

CREATE OR REPLACE CORTEX SEARCH SERVICE SEARCH.ORDER_SOP_SEARCH
  ON CONTENT
  ATTRIBUTES CATEGORY, RISK_SIGNAL
  WAREHOUSE = __DEMO_WH__
  TARGET_LAG = '7 days'
AS (SELECT DOC_ID, TITLE, CATEGORY, RISK_SIGNAL, CONTENT FROM SEARCH.ORDER_SOP_DOCS);

-- ---------- WIP gap anomaly detection (train first 75 days, detect last 15) ----------
CREATE OR REPLACE VIEW ML.WIP_GAP_SERIES AS
SELECT ENTITY_ID, EVENT_DATE::TIMESTAMP_NTZ AS TS, WIP_GAP_PCT::FLOAT AS WIP_GAP
FROM RAW.FACTORY_DAILY;
CREATE OR REPLACE VIEW ML.WIP_GAP_TRAIN AS
SELECT * FROM ML.WIP_GAP_SERIES WHERE TS < (SELECT DATEADD(day, -15, MAX(TS)) FROM ML.WIP_GAP_SERIES);
CREATE OR REPLACE VIEW ML.WIP_GAP_DETECT AS
SELECT * FROM ML.WIP_GAP_SERIES WHERE TS >= (SELECT DATEADD(day, -15, MAX(TS)) FROM ML.WIP_GAP_SERIES);

CREATE OR REPLACE SNOWFLAKE.ML.ANOMALY_DETECTION ML.WIP_GAP_ANOMALY_MODEL(
  INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ML.WIP_GAP_TRAIN'),
  SERIES_COLNAME => 'ENTITY_ID', TIMESTAMP_COLNAME => 'TS', TARGET_COLNAME => 'WIP_GAP',
  LABEL_COLNAME => '');

CREATE OR REPLACE TABLE ML.WIP_GAP_ANOMALIES AS
SELECT SERIES::VARCHAR AS ENTITY_ID, TS::DATE AS EVENT_DATE, Y AS WIP_GAP, FORECAST AS EXPECTED,
       LOWER_BOUND, UPPER_BOUND, IS_ANOMALY, PERCENTILE
FROM TABLE(ML.WIP_GAP_ANOMALY_MODEL!DETECT_ANOMALIES(
  INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ML.WIP_GAP_DETECT'),
  SERIES_COLNAME => 'ENTITY_ID', TIMESTAMP_COLNAME => 'TS', TARGET_COLNAME => 'WIP_GAP'));

-- ---------- Semantic view ----------
CREATE OR REPLACE SEMANTIC VIEW APP.ORDER_ANALYTICS
  TABLES (
    factories AS CURATED.PERFORMANCE_SUMMARY PRIMARY KEY (ENTITY_ID)
      WITH SYNONYMS = ('entities', 'garment factories', 'sewing factories')
      COMMENT = 'One row per factory (city or province x product category), 90-day totals',
    risk AS ML.LATE_RISK_SCORES PRIMARY KEY (ENTITY_ID)
      COMMENT = 'Latest next-7-day probability of a confirmed late shipment per factory',
    signals AS CURATED.SIGNAL_SUMMARY PRIMARY KEY (RISK_SIGNAL)
      COMMENT = 'Order risk flags, confirmed late shipments and lots held at final inspection by order-risk signal, 90 days',
    daily AS CURATED.TREND_ANALYSIS PRIMARY KEY (METRIC_DATE)
      COMMENT = 'Network-wide totals per day'
  )
  RELATIONSHIPS (risk_factory AS risk (ENTITY_ID) REFERENCES factories)
  FACTS (
    factories.shipments_f AS SHIPMENT_COUNT,
    factories.ontime_f AS ONTIME_KUNITS,
    factories.shipped_f AS SHIPPED_KUNITS,
    factories.flags_f AS FLAG_COUNT,
    factories.confirmed_f AS CONFIRMED_COUNT,
    factories.held_f AS QUARANTINED_COUNT,
    factories.review_due_f AS REVIEW_DUE,
    factories.review_done_f AS REVIEW_DONE,
    risk.late_prob_f AS LATE_PROB_7D,
    signals.sig_flags_f AS FLAG_COUNT,
    signals.sig_confirmed_f AS CONFIRMED_COUNT,
    signals.sig_held_f AS QUARANTINED_COUNT,
    daily.day_shipments_f AS SHIPMENT_COUNT,
    daily.day_ontime_f AS ONTIME_KUNITS,
    daily.day_shipped_f AS SHIPPED_KUNITS,
    daily.day_flags_f AS FLAG_COUNT
  )
  DIMENSIONS (
    factories.factory_id AS ENTITY_ID WITH SYNONYMS = ('entity', 'factory', 'factory id'),
    factories.factory_name AS ENTITY_NAME,
    factories.city AS REGION WITH SYNONYMS = ('city', 'province', 'region', 'factory location') COMMENT = 'Vietnamese city or province of the factory',
    factories.product_category AS CATEGORY WITH SYNONYMS = ('product category', 'factory type', 'category'),
    factories.risk_tier AS RISK_TIER COMMENT = 'Order risk tier 1 (low) to 3 (high)',
    risk.risk_band AS RISK_BAND COMMENT = 'High >= 0.5, Medium >= 0.25, else Low',
    risk.scored_as_of AS SCORED_AS_OF,
    signals.risk_signal AS RISK_SIGNAL WITH SYNONYMS = ('signal', 'order-risk signal', 'order risk'),
    daily.metric_date AS METRIC_DATE
  )
  METRICS (
    factories.factory_count AS COUNT(factories.factory_id) WITH SYNONYMS = ('number of entities', 'number of factories'),
    factories.on_time_pieces_pct AS 100 * SUM(factories.ontime_f) / NULLIF(SUM(factories.shipped_f), 0)
      COMMENT = 'Pieces shipped by the buyer ex-factory date / pieces shipped',
    factories.total_shipments AS SUM(factories.shipments_f) WITH SYNONYMS = ('order shipments', 'buyer order shipments'),
    factories.total_ontime_kpieces AS SUM(factories.ontime_f) WITH SYNONYMS = ('on-time pieces', 'thousand pieces on time'),
    factories.total_shipped_kpieces AS SUM(factories.shipped_f) WITH SYNONYMS = ('pieces shipped', 'thousand pieces shipped'),
    factories.total_flags AS SUM(factories.flags_f) WITH SYNONYMS = ('order risk flags', 'flags'),
    factories.total_confirmed AS SUM(factories.confirmed_f) WITH SYNONYMS = ('confirmed late shipments', 'late shipments'),
    factories.total_held AS SUM(factories.held_f) WITH SYNONYMS = ('lots held at final inspection', 'held lots'),
    factories.flag_precision_pct AS 100 * SUM(factories.confirmed_f) / NULLIF(SUM(factories.flags_f), 0)
      COMMENT = 'Confirmed late shipments / order risk flags',
    factories.review_rate_pct AS 100 * SUM(factories.review_done_f) / NULLIF(SUM(factories.review_due_f), 0)
      COMMENT = 'WIP status reviews completed / reviews due',
    risk.avg_late_prob AS AVG(risk.late_prob_f),
    signals.signal_flags AS SUM(signals.sig_flags_f),
    signals.signal_confirmed AS SUM(signals.sig_confirmed_f),
    signals.signal_held AS SUM(signals.sig_held_f),
    signals.signal_precision_pct AS 100 * SUM(signals.sig_confirmed_f) / NULLIF(SUM(signals.sig_flags_f), 0),
    daily.daily_shipments AS SUM(daily.day_shipments_f),
    daily.daily_shipped_kpieces AS SUM(daily.day_shipped_f),
    daily.daily_on_time_pct AS 100 * SUM(daily.day_ontime_f) / NULLIF(SUM(daily.day_shipped_f), 0),
    daily.daily_flags AS SUM(daily.day_flags_f)
  )
  COMMENT = 'Synthetic Vietnam garment buyer-order late-shipment analytics (demo)';

-- ---------- Cortex Agent ----------
CREATE OR REPLACE AGENT APP.ORDER_AGENT
  COMMENT = 'Buyer-order late-shipment assistant over a synthetic network of Vietnam garment factories'
  FROM SPECIFICATION
$$
models:
  orchestration: claude-sonnet-4-5
instructions:
  response: "Answer only from tool results. State that data is synthetic and that order risk flags are demo signals, not buyer compliance or audit verdicts. Give factory IDs and numbers with units (thousand pieces, percent)."
  orchestration: "Use order_analyst for buyer-order shipments, pieces shipped and pieces on time, on-time shipment, order risk flags, confirmed late shipments, lots held at final inspection, WIP status reviews, cities, product categories, order-risk signals and late-shipment risk. Use sop_search for follow-up procedures."
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: order_analyst
      description: "Buyer-order shipments, pieces shipped, on-time shipment, order risk flags, confirmed late shipments, lots held at final inspection, flag precision, WIP review completion, order-risk signals and late-shipment risk scores by factory"
  - tool_spec:
      type: cortex_search
      name: sop_search
      description: "Synthetic order-risk follow-up SOPs for garment factories by product category and order-risk signal"
tool_resources:
  order_analyst:
    semantic_view: __DEMO_DB__.APP.ORDER_ANALYTICS
    execution_environment:
      type: warehouse
      warehouse: __DEMO_WH__
  sop_search:
    name: __DEMO_DB__.SEARCH.ORDER_SOP_SEARCH
    max_results: 3
    id_column: DOC_ID
    title_column: TITLE
$$;

-- ---------- Live order-status alert ----------
CREATE TABLE IF NOT EXISTS APP.ALERT_LOG (
  ALERTED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(), FACTORY_ID VARCHAR,
  EVENT_TS TIMESTAMP_NTZ, SHIPMENT_KUNITS FLOAT, WIP_GAP_PCT FLOAT, SOP_HINT VARCHAR);

CREATE OR REPLACE NOTIFICATION INTEGRATION VN_TEXTILE_ORDER_EMAIL_INT
  TYPE = EMAIL ENABLED = TRUE ALLOWED_RECIPIENTS = ('__ALERT_EMAIL__');

CREATE OR REPLACE PROCEDURE APP.LOG_LIVE_FLAGS()
RETURNS NUMBER
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
  n NUMBER;
BEGIN
  INSERT INTO APP.ALERT_LOG (FACTORY_ID, EVENT_TS, SHIPMENT_KUNITS, WIP_GAP_PCT, SOP_HINT)
    SELECT c.FACTORY_ID, c.EVENT_TS, c.SHIPMENT_KUNITS, c.WIP_GAP_PCT,
           'Check ' || m.CATEGORY || ' order SOPs; current risk band ' || COALESCE(r.RISK_BAND, 'n/a')
    FROM RAW.LIVE_ORDERS c
    JOIN RAW.FACTORIES m ON m.ID = c.FACTORY_ID
    LEFT JOIN ML.LATE_RISK_SCORES r ON r.ENTITY_ID = c.FACTORY_ID
    WHERE c.STATUS = 'FLAG'
      AND NOT EXISTS (SELECT 1 FROM APP.ALERT_LOG l WHERE l.FACTORY_ID = c.FACTORY_ID AND l.EVENT_TS = c.EVENT_TS);
  n := SQLROWCOUNT;
  IF (n > 0) THEN
    CALL SYSTEM$SEND_EMAIL('VN_TEXTILE_ORDER_EMAIL_INT', '__ALERT_EMAIL__',
      '[Demo] Buyer order risk alert',
      'New flagged live order-status events logged in APP.ALERT_LOG: ' || :n || '. Data is synthetic.');
  END IF;
  RETURN n;
END;
$$;

CREATE OR REPLACE ALERT APP.LIVE_ORDER_ALERT
  WAREHOUSE = __DEMO_WH__
  SCHEDULE = '5 MINUTE'
  IF (EXISTS (
    SELECT 1 FROM RAW.LIVE_ORDERS c
    WHERE c.STATUS = 'FLAG'
      AND NOT EXISTS (SELECT 1 FROM APP.ALERT_LOG l WHERE l.FACTORY_ID = c.FACTORY_ID AND l.EVENT_TS = c.EVENT_TS)))
  THEN CALL APP.LOG_LIVE_FLAGS();

-- ---------- On-demand refresh DAG (suspended; run with EXECUTE TASK APP.TASK_REFRESH_CURATED) ----------
CREATE OR REPLACE PROCEDURE APP.REFRESH_CURATED()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
BEGIN
  ALTER DYNAMIC TABLE CURATED.PERFORMANCE_SUMMARY REFRESH;
  ALTER DYNAMIC TABLE CURATED.TREND_ANALYSIS REFRESH;
  ALTER DYNAMIC TABLE CURATED.SIGNAL_SUMMARY REFRESH;
  ALTER DYNAMIC TABLE CURATED.KPI_SUMMARY REFRESH;
  RETURN 'refreshed';
END;
$$;

CREATE OR REPLACE TASK APP.TASK_REFRESH_CURATED
  WAREHOUSE = __DEMO_WH__
AS
  CALL APP.REFRESH_CURATED();

CREATE OR REPLACE TASK APP.TASK_RESCORE_RISK
  WAREHOUSE = __DEMO_WH__
  AFTER APP.TASK_REFRESH_CURATED
AS
  CREATE OR REPLACE TABLE ML.LATE_RISK_SCORES COPY GRANTS AS
  WITH latest AS (
    SELECT * FROM ML.LATE_FEATURES QUALIFY ROW_NUMBER() OVER (PARTITION BY ENTITY_ID ORDER BY EVENT_DATE DESC) = 1
  ), p AS (
    SELECT ENTITY_ID, EVENT_DATE,
           ML.LATE_RISK_MODEL!PREDICT(INPUT_DATA => OBJECT_CONSTRUCT(
             'CATEGORY', CATEGORY, 'RISK_TIER', RISK_TIER, 'PROGRAM_YEARS', PROGRAM_YEARS,
             'WIP_GAP_PCT', WIP_GAP_PCT, 'LATE_PCT', LATE_PCT,
             'WIP_GAP_7D', WIP_GAP_7D, 'CONFIRMED_30D', CONFIRMED_30D,
           'DAYS_SINCE_REVIEW', DAYS_SINCE_REVIEW, 'REVIEW_RATE_30D', REVIEW_RATE_30D)) AS PRED
    FROM latest
  )
  SELECT ENTITY_ID, EVENT_DATE AS SCORED_AS_OF, ROUND(PRED:probability:LATE::FLOAT, 4) AS LATE_PROB_7D,
         CASE WHEN PRED:probability:LATE::FLOAT >= 0.5 THEN 'High'
              WHEN PRED:probability:LATE::FLOAT >= 0.25 THEN 'Medium' ELSE 'Low' END AS RISK_BAND,
         CURRENT_TIMESTAMP() AS SCORED_AT
  FROM p;
