-- ============================================================================
-- Order Management
-- Order Management for Vietnam - ML.FORECAST and Dynamic Tables power real-time order management intelligence for textile & garment in Hanoi & Ho Chi Minh City.
-- ============================================================================
USE ROLE ACCOUNTADMIN;
CREATE DATABASE IF NOT EXISTS TEXTILE_ORDERS;
CREATE WAREHOUSE IF NOT EXISTS TEXTILE_WH WAREHOUSE_SIZE = 'MEDIUM' AUTO_SUSPEND = 120 AUTO_RESUME = TRUE;
USE DATABASE TEXTILE_ORDERS;
CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS CURATED;
CREATE SCHEMA IF NOT EXISTS ML;
CREATE SCHEMA IF NOT EXISTS AI;
CREATE SCHEMA IF NOT EXISTS SEARCH;
CREATE SCHEMA IF NOT EXISTS APP;

USE WAREHOUSE TEXTILE_WH;
