-- ============================================================================
-- 08_AGENT.SQL — Cortex Agent for Order Management
-- ============================================================================
USE DATABASE TEXTILE_ORDERS;
USE SCHEMA APP;

CREATE OR REPLACE CORTEX AGENT APP.TEXTILE_ORDERS_AGENT
  COMMENT = 'Order Management AI Assistant'
  MODEL = 'claude-opus-4-8'
  TOOLS = (
    SEMANTIC_VIEW_TOOL(SEMANTIC_VIEW => 'TEXTILE_ORDERS.APP.TEXTILE_ORDERS_ANALYTICS'),    CORTEX_SEARCH_TOOL(CORTEX_SEARCH_SERVICE => 'TEXTILE_ORDERS.SEARCH.TEXTILE_ORDERS_SEARCH', TOOL_DESCRIPTION => 'Search documents for Textile & Garment information')
  )
  SYSTEM_PROMPT = 'You are the Order Management Agent for Vietnamese textile & garment operations in Hanoi & Ho Chi Minh City.';
