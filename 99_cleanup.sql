-- ============================================================
--  Drop everything at once
-- ============================================================
DROP SCHEMA IF EXISTS EARTHQUAKE_DB.RAW;
DROP DATABASE IF EXISTS EARTHQUAKE_DB;

-- ============================================================
--  Or Drop Individual Objects
-- ============================================================

DROP PIPE IF EXISTS
EARTHQUAKE_DB.RAW.USGS_EARTHQUAKE_PIPE;

DROP STAGE IF EXISTS
EARTHQUAKE_DB.RAW.USGS_S3_STAGE;

DROP FILE FORMAT IF EXISTS
EARTHQUAKE_DB.RAW.USGS_JSONL_FORMAT;

DROP TABLE IF EXISTS
EARTHQUAKE_DB.RAW.EARTHQUAKES_RAW;

DROP WAREHOUSE IF EXISTS EVENTS_WH;

-- ============================================================
--VERIFY SNOWFLAKE CLEANUP
-- ============================================================

SHOW PIPES ;
SHOW STAGES ;
SHOW FILE FORMATS ;

-- ============================================================
--  AWS CLEANUP (MANUAL)
-- ============================================================
-- Delete S3 Bucket
-- Delete IAM User
-- Delete IAM Policy

