-- =====================================================================
-- 00_setup.sql  |  Project role, warehouse, database, raw table
-- =====================================================================
-- Use case: a seismic network sends earthquake events (USGS format) as
-- small JSON Lines files, one every few minutes, into S3. We want each
-- file in Snowflake about a minute after it lands, with nobody running
-- a COPY. Snowflake reaches S3 through a storage integration.
--
-- AWS setup: Follow AWS_SETUP.md guide
-- =====================================================================

-- 1. A project role. It will own every object except the storage
--    integration (only ACCOUNTADMIN creates that, in 01).
USE ROLE USERADMIN;

CREATE ROLE IF NOT EXISTS EARTHQUAKE_ENGINEER
  COMMENT = 'Owns the S3 -> Snowpipe earthquake ingestion objects';

-- Hang it under SYSADMIN so admins can still see and manage its objects.
GRANT ROLE EARTHQUAKE_ENGINEER TO ROLE SYSADMIN;

-- Give the role to whoever is running this script.
SET MY_USER = CURRENT_USER();
GRANT ROLE EARTHQUAKE_ENGINEER TO USER IDENTIFIER($MY_USER);


-- 2. Compute and database: SYSADMIN creates them, the project role uses them.
USE ROLE SYSADMIN;

-- Snowpipe runs on serverless compute. This warehouse is only for our
-- own checks, so it stays tiny and sleeps after 60 seconds.
CREATE WAREHOUSE IF NOT EXISTS WH_EARTHQUAKE_INGEST
  WAREHOUSE_SIZE      = XSMALL
  AUTO_SUSPEND        = 60
  AUTO_RESUME         = TRUE
  INITIALLY_SUSPENDED = TRUE;

CREATE DATABASE IF NOT EXISTS EARTHQUAKE_DB;

GRANT USAGE ON WAREHOUSE WH_EARTHQUAKE_INGEST TO ROLE EARTHQUAKE_ENGINEER;
GRANT USAGE, CREATE SCHEMA ON DATABASE EARTHQUAKE_DB TO ROLE EARTHQUAKE_ENGINEER;


-- 3. Bronze layer, created and owned by the project role.
USE ROLE EARTHQUAKE_ENGINEER;
USE WAREHOUSE WH_EARTHQUAKE_INGEST;

CREATE SCHEMA IF NOT EXISTS EARTHQUAKE_DB.BRONZE;
USE SCHEMA EARTHQUAKE_DB.BRONZE;

-- One row per earthquake, kept exactly as USGS sent it.
CREATE TABLE IF NOT EXISTS EARTHQUAKES_RAW (
  EVENT_DATA      VARIANT,          -- the whole USGS feature
  SOURCE_FILE     VARCHAR,          -- S3 object it came from
  FILE_ROW        NUMBER,           -- line number in that file
  FILE_LANDED_AT  TIMESTAMP_NTZ,    -- when the file landed in S3 (UTC)
  LOADED_AT       TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()   -- when Snowpipe loaded it
)
COMMENT = 'Bronze: one row per earthquake event, exactly as received from S3';

-- JSON Lines: one JSON object per line, no outer [ ] array to strip.
CREATE FILE FORMAT IF NOT EXISTS USGS_JSONL_FORMAT
  TYPE = JSON;

-- Next: aws/AWS_SETUP.md, Part A (bucket, read policy, IAM role).
