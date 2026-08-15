-- ============================================================================
-- 05_SEARCH.SQL — Cortex Search for Order Management
-- ============================================================================
USE DATABASE TEXTILE_ORDERS;
USE SCHEMA SEARCH;

CREATE OR REPLACE CORTEX SEARCH SERVICE SEARCH.TEXTILE_ORDERS_SEARCH
  ON CONTENT
  ATTRIBUTES DOC_TYPE, CATEGORY
  WAREHOUSE = TEXTILE_WH
  TARGET_LAG = '1 hour'
AS (
  SELECT * FROM RAW.DOCUMENTS
);
