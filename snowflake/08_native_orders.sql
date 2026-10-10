-- ============================================================================
-- 08_native_orders.sql - Snowflake-only build: live order-status feed without AWS.
-- Creates RAW.LIVE_ORDERS (same columns as the Snowpipe target created by
-- aws/setup_aws.py) and APP.SIMULATE_ORDERS(N), which inserts synthetic
-- buyer order-status events with the same value ranges and ~10% FLAG
-- rate (order whose WIP gap is out of tolerance) as aws/publish_orders.py.
-- Rows are inserted directly; this simulates a factory order-status feed and is not
-- Snowpipe Streaming.
-- Run before 06_intelligence.sql (the alert reads RAW.LIVE_ORDERS).
-- Idempotent: safe to run in the AWS build too.
-- ============================================================================
CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS APP;

CREATE TABLE IF NOT EXISTS RAW.LIVE_ORDERS (
  FACTORY_ID VARCHAR, EVENT_TS TIMESTAMP_NTZ, SHIPMENT_KUNITS FLOAT, WIP_GAP_PCT FLOAT,
  STATUS VARCHAR, SENT_TS TIMESTAMP_NTZ, SOURCE_FILE VARCHAR,
  LOADED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP());

CREATE OR REPLACE PROCEDURE APP.SIMULATE_ORDERS(N NUMBER)
RETURNS NUMBER
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
BEGIN
  IF (N < 1 OR N > 1000) THEN
    RETURN 0;
  END IF;
  INSERT INTO RAW.LIVE_ORDERS (FACTORY_ID, EVENT_TS, SHIPMENT_KUNITS, WIP_GAP_PCT, STATUS, SENT_TS, SOURCE_FILE)
    WITH g AS (
      SELECT 'FAC-' || LPAD(UNIFORM(0, 39, RANDOM())::VARCHAR, 4, '0') AS FACTORY_ID,
             UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.1 AS IS_FLAG,
             SYSDATE() AS TS, SEQ4() AS I
      FROM TABLE(GENERATOR(ROWCOUNT => 1000))
    )
    -- NORMAL() needs a constant mean, so the flag offset is added outside it.
    SELECT FACTORY_ID, TS,
           ROUND(IFF(IS_FLAG, 6.5, 8.8) * EXP(NORMAL(0, 0.15, RANDOM())), 2),
           ROUND(GREATEST(0, IFF(IS_FLAG, 9.1, 1.6) + NORMAL(0, 0.9, RANDOM())), 2),
           IFF(IS_FLAG, 'FLAG', 'OK'), TS, 'APP.SIMULATE_ORDERS'
    FROM g
    WHERE I < :N;
  RETURN SQLROWCOUNT;
END;
$$;

-- Optional continuous feed for longer demos (suspended; RESUME to start, SUSPEND after).
CREATE OR REPLACE TASK APP.TASK_SIMULATE_ORDERS
  WAREHOUSE = __DEMO_WH__
  SCHEDULE = '1 MINUTE'
AS
  CALL APP.SIMULATE_ORDERS(5);
