-- =============================================================================
-- P3 — Provider Aberrant Billing Pattern Detection
-- 00_setup_database.sql
--
-- Purpose : Create the database, virtual warehouse, schemas, and file format
--           required to load CMS DE-SynPUF data into Snowflake.
--
-- Pre-reqs: Active Snowflake account (free trial: signup.snowflake.com)
--           SYSADMIN or ACCOUNTADMIN role
--
-- Notes   : The free trial provides 30 days + $400 in credits.
--           Use X-SMALL warehouse to conserve credits during development.
--           All DDL output should be captured (screenshot or query history
--           export) and committed to the repository before the trial expires.
-- =============================================================================

-- -------------------------------------------------------
-- 1. Set role and create the virtual warehouse
-- -------------------------------------------------------
USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS FWA_WH
    WITH WAREHOUSE_SIZE = 'X-SMALL'
    AUTO_SUSPEND = 120          -- suspend after 2 min idle (save credits)
    AUTO_RESUME  = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'P3 Provider Aberrant Billing Detection — development warehouse';

-- -------------------------------------------------------
-- 2. Create the database
-- -------------------------------------------------------
CREATE DATABASE IF NOT EXISTS MEDICARE_FWA
    COMMENT = 'CMS DE-SynPUF Medicare claims data for FWA detection portfolio project';

USE DATABASE MEDICARE_FWA;

-- -------------------------------------------------------
-- 3. Create schemas
-- -------------------------------------------------------

-- RAW: landing zone for CSV files — all VARCHAR, no transformations
CREATE SCHEMA IF NOT EXISTS RAW
    COMMENT = 'Raw staging schema — CSV landing zone, all columns VARCHAR';

-- ANALYTICS: dimensional model — typed columns, star schema
CREATE SCHEMA IF NOT EXISTS ANALYTICS
    COMMENT = 'Dimensional model — DIM/FACT tables with proper data types';

-- DATA_QUALITY: profiling and validation views
CREATE SCHEMA IF NOT EXISTS DATA_QUALITY
    COMMENT = 'Data quality assessment views — completeness, referential integrity, temporal consistency';

-- -------------------------------------------------------
-- 4. Create file format for CSV loading
-- -------------------------------------------------------
USE SCHEMA RAW;

CREATE FILE FORMAT IF NOT EXISTS CSV_DESYNPUF
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    RECORD_DELIMITER = '\n'
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('', 'NA', 'NULL')
    EMPTY_FIELD_AS_NULL = TRUE
    TRIM_SPACE = TRUE
    ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
    COMMENT = 'File format for CMS DE-SynPUF CSV files';

-- -------------------------------------------------------
-- 5. Create internal stage for file upload
-- -------------------------------------------------------
CREATE STAGE IF NOT EXISTS DESYNPUF_STAGE
    FILE_FORMAT = CSV_DESYNPUF
    COMMENT = 'Internal stage for uploading DE-SynPUF CSV files via PUT or Snowsight UI';

-- -------------------------------------------------------
-- 6. Verify setup
-- -------------------------------------------------------
SHOW DATABASES LIKE 'MEDICARE_FWA';
SHOW SCHEMAS IN DATABASE MEDICARE_FWA;
SHOW STAGES IN SCHEMA MEDICARE_FWA.RAW;
SHOW FILE FORMATS IN SCHEMA MEDICARE_FWA.RAW;

-- -------------------------------------------------------
-- IMPORTANT: Screenshot or export the output of the SHOW
-- commands above. Commit to repository as evidence of
-- successful Snowflake setup.
-- -------------------------------------------------------
