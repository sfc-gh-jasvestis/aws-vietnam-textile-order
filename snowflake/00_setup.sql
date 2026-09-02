-- Generated from generator/demo_specs/aws-vietnam-textile-order.json
-- Regenerate with: python3 generator/gen_repo_docs.py aws-vietnam-textile-order
-- This is the schema that is actually deployed for VIETNAM_TEXTILE_ORDER.

-- VIETNAM_TEXTILE_ORDER  (Order Management)
-- generated from generator/demo_specs/aws-vietnam-textile-order.json - do not hand-edit
CREATE DATABASE IF NOT EXISTS VIETNAM_TEXTILE_ORDER;
CREATE SCHEMA IF NOT EXISTS VIETNAM_TEXTILE_ORDER.RAW;
CREATE SCHEMA IF NOT EXISTS VIETNAM_TEXTILE_ORDER.CURATED;
CREATE SCHEMA IF NOT EXISTS VIETNAM_TEXTILE_ORDER.APP;
USE DATABASE VIETNAM_TEXTILE_ORDER;

-- 5 real regions; entity names carry their region so the two always agree
