-- =====================================================================
-- 01_storage_integration.sql  |  Snowflake's half of the trust
-- =====================================================================
-- Before this: AWS Part A is done and you have copied the role ARN.
-- The integration stores WHICH role Snowflake may assume and WHERE it
-- may read. No keys, no secrets.
-- =====================================================================

-- Creating an integration is an account-level privilege.
USE ROLE ACCOUNTADMIN;

CREATE STORAGE INTEGRATION IF NOT EXISTS S3_EARTHQUAKE_INT
  TYPE                      = EXTERNAL_STAGE
  STORAGE_PROVIDER          = 'S3'
  ENABLED                   = TRUE
  STORAGE_AWS_ROLE_ARN      = 'arn:aws:iam::<AWS_ACCOUNT_ID>:role/SnowflakeEarthquakeIngestionRole'
  STORAGE_ALLOWED_LOCATIONS = ('s3://<YOUR_BUCKET_NAME>/earthquakes/incoming/')
  COMMENT = 'Snowflake assumes this AWS role through STS to read the earthquake files';

-- Snowflake generated two values for AWS. Copy both.
--   STORAGE_AWS_IAM_USER_ARN : the Snowflake identity that will call sts:AssumeRole
--   STORAGE_AWS_EXTERNAL_ID  : the secret handshake that proves it's THIS integration
DESC INTEGRATION S3_EARTHQUAKE_INT;

SELECT "property", "property_value"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "property" IN ('STORAGE_AWS_IAM_USER_ARN', 'STORAGE_AWS_EXTERNAL_ID');

-- Let the project role build stages on top of it.
GRANT USAGE ON INTEGRATION S3_EARTHQUAKE_INT TO ROLE EARTHQUAKE_ENGINEER;

-- Never CREATE OR REPLACE this integration once AWS trusts it.
-- To change the role ARN or the allowed paths, use:
--   ALTER STORAGE INTEGRATION S3_EARTHQUAKE_INT SET STORAGE_ALLOWED_LOCATIONS = (...);
-- 02_stage.sql shows what happens if you replace it.

-- Next: aws/AWS_SETUP.md, Part B (paste both values into the trust policy).
