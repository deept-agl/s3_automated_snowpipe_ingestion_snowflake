

-- STEP 01 — CREATE YOUR TRIAL ACCOUNTS
-- 1. Open https://aws.amazon.com/free/ and create or sign in to an AWS account.
--    Complete  verification and enable MFA on the root account.

-- 2. Open https://signup.snowflake.com/ and create a Snowflake trial account,
--    or sign in to an existing account.

----------------------------------------------------------------------

-- STEP 02 — CREATE THE S3 BUCKET IN AWS
-- 1. In AWS Console, open Amazon S3 > General purpose buckets > Create bucket.
-- 2. Select the AWS Region you will use for this project.
-- 3. Choose a globally unique bucket name, such as:
--      earthquake-ingestion-<unique-suffix>
-- 4. Keep ACLs disabled (Bucket owner enforced), Block all public access ON,
--    and default encryption SSE-S3. Create the bucket.

----------------------------------------------------------------------

-- STEP 03 — CREATE A READ-ONLY AWS IAM POLICY
-- 1. AWS Console > IAM > Policies > Create policy > JSON.
-- 2. Paste the JSON from file :- aws/snowflake_s3_read_policy.json
-- 3. Replace <BUCKET_NAME> twice with your real bucket name.
-- 4. Save the policy as EarthquakeS3ReadPolicy.

----------------------------------------------------------------------

-- STEP 04 — CREATE THE AWS IAM ROLE
-- 1. AWS Console > IAM > Roles > Create role.
-- 2. Choose AWS account > Another AWS account (cross-account access).
-- 3. Enter YOUR AWS account ID temporarily to create the role. If prompted for
--    an external ID, use a temporary placeholder '0000'; it will be replaced in STEP 06.
-- 4. Attach the EarthquakeS3ReadPolicy policy created in STEP 03.
-- 5. Name the role SnowflakeEarthquakeIngestionRole and create it.
-- 6. Copy the role ARN, for example:
--      arn:aws:iam::<AWS_ACCOUNT_ID>:role/SnowflakeEarthquakeIngestionRole
-- 7. Do NOT create an IAM user or long-lived access keys for Snowflake.

----------------------------------------------------------------------

-- STEP 05 — CREATE SNOWFLAKE database and STORAGE INTEGRATION

--Go to 02_db_setup and create database, schema and storage integration
--and then come back here

----------------------------------------------------------------------

-- STEP 06 — UPDATE THE AWS IAM ROLE TRUST POLICY
-- 1. AWS Console > IAM > Roles > SnowflakeEarthquakeIngestionRole.
-- 2. Open Trust relationships > Edit trust policy.
-- 3. Replace the temporary policy with the JSON in aws/role_trust_template.json
-- 4. Replace the principal and external ID with STEP 05 property_value values.
-- 5. Save the trust policy. The principal must be the exact full IAM user ARN.

----------------------------------------------------------------------

-- Continue to 03_stage_and_pipe.sql file

----------------------------------------------------------------------

-- NOTE: If the account belongs to an AWS Organization, applicable SCPs or RCPs can
-- still deny cross-account sts:AssumeRole, even with this trust policy. Do not
-- remove organization-wide Deny rules to get this working; ask the
-- organization administrator to review narrowly scoped access if necessary.
