-- ============================================================================
-- 07_SEMANTIC_VIEW.SQL — Semantic View for Order Management
-- ============================================================================
USE DATABASE TEXTILE_ORDERS;
USE SCHEMA APP;

CREATE OR REPLACE SEMANTIC VIEW APP.TEXTILE_ORDERS_ANALYTICS
  COMMENT = 'Textile & Garment order management analytics'
AS
  TABLES (
    CURATED.PERFORMANCE_DASHBOARD AS performance_dashboard,CURATED.TREND_ANALYTICS AS trend_analytics,CURATED.FORECAST_INPUT AS forecast_input,CURATED.OPERATIONAL_RISK AS operational_risk
  );
