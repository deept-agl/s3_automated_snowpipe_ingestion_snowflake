-- =====================================================================
-- 06_cleanup.sql  |  Remove everything this project created
-- =====================================================================
-- Destructive. Run only when you're done with the demo.
-- =====================================================================

-- Pipe first, so no new loads start while we drop the rest.
USE ROLE EARTHQUAKE_ENGINEER;
DROP PIPE IF EXISTS EARTHQUAKE_DB.BRONZE.USGS_EARTHQUAKE_PIPE;
DROP SCHEMA IF EXISTS EARTHQUAKE_DB.BRONZE;   -- table, view, stage, file format

USE ROLE SYSADMIN;
DROP DATABASE  IF EXISTS EARTHQUAKE_DB;
DROP WAREHOUSE IF EXISTS WH_EARTHQUAKE_INGEST;

USE ROLE ACCOUNTADMIN;
DROP STORAGE INTEGRATION IF EXISTS S3_EARTHQUAKE_INT;

USE ROLE USERADMIN;
DROP ROLE IF EXISTS EARTHQUAKE_ENGINEER;

-- In AWS (aws/AWS_SETUP.md, "Cleanup"): delete the event notification,
-- the files, the bucket, the IAM role and its policy.
