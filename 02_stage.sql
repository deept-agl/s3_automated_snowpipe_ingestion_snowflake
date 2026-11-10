-- =====================================================================
-- 02_stage.sql  |  The stage, the handshake test, and the trap
-- =====================================================================
-- Before this: AWS Part B is done (trust policy has the Snowflake user
-- ARN and external ID).
-- =====================================================================

USE ROLE EARTHQUAKE_ENGINEER;
USE WAREHOUSE WH_EARTHQUAKE_INGEST;
USE SCHEMA EARTHQUAKE_DB.BRONZE;

-- The stage points at the folder and borrows the integration's access.
CREATE STAGE IF NOT EXISTS USGS_S3_STAGE
  URL                 = 's3://<YOUR_BUCKET_NAME>/earthquakes/incoming/'
  STORAGE_INTEGRATION = S3_EARTHQUAKE_INT
  FILE_FORMAT         = USGS_JSONL_FORMAT;

-- The handshake test. Snowflake calls sts:AssumeRole, gets temporary
-- credentials and lists the folder.
--   Empty result      -> it worked (the folder is just empty).
--   Error about role  -> trust policy ARN or external ID doesn't match.
--   Access Denied     -> the role's S3 policy, or the bucket/prefix path.
LIST @USGS_S3_STAGE;


-- =====================================================================
-- THE TRAP: "I'll just re-run it with CREATE OR REPLACE"
-- Run this section only in the demo. It's why 01 says never replace.
-- =====================================================================

USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE STORAGE INTEGRATION S3_EARTHQUAKE_INT
  TYPE                      = EXTERNAL_STAGE
  STORAGE_PROVIDER          = 'S3'
  ENABLED                   = TRUE
  STORAGE_AWS_ROLE_ARN      = 'arn:aws:iam::<AWS_ACCOUNT_ID>:role/SnowflakeEarthquakeIngestionRole'
  STORAGE_ALLOWED_LOCATIONS = ('s3://<YOUR_BUCKET_NAME>/earthquakes/incoming/');

-- Same name, new object: its grants are gone and it has a NEW external ID.
GRANT USAGE ON INTEGRATION S3_EARTHQUAKE_INT TO ROLE EARTHQUAKE_ENGINEER;

DESC INTEGRATION S3_EARTHQUAKE_INT;
SELECT "property", "property_value"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "property" = 'STORAGE_AWS_EXTERNAL_ID';
-- Compare with the external ID in your AWS trust policy: they differ.

-- Stages link to an integration by an internal ID, not by name, so the
-- old stage lost its link too. Recreate it.
USE ROLE EARTHQUAKE_ENGINEER;
CREATE OR REPLACE STAGE USGS_S3_STAGE
  URL                 = 's3://<YOUR_BUCKET_NAME>/earthquakes/incoming/'
  STORAGE_INTEGRATION = S3_EARTHQUAKE_INT
  FILE_FORMAT         = USGS_JSONL_FORMAT;

LIST @USGS_S3_STAGE;   -- fails: AWS no longer trusts this integration

-- FIX: AWS Part B again with the NEW external ID, save, then:
LIST @USGS_S3_STAGE;   -- works again

-- In production the stage would also have a pipe on top of it, and that
-- pipe would need recreating too. That's why we break it BEFORE the pipe.

-- Next: 03_pipe.sql
