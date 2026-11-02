
----------------------------------------------------------------------
-- STEP 01 — CONFIGURE LOCAL AWS ACCESS FOR THE PYTHON DATA LOADER
----------------------------------------------------------------------

-- The Snowflake storage integration uses an AWS IAM role to read S3 files.
-- The Python data loader requires separate permission to upload files to S3.
-- For local development, use an AWS IAM Identity Center (SSO) profile.
-- No IAM user access keys are required for this setup.

-- 1. Open Windows Command Prompt (CMD).
-- 2. Verify Python and AWS CLI are installed.

-- Run in CMD:
-- python --version
-- aws --version

-- 3. Install boto3 for uploading files to Amazon S3.

-- Run in CMD:
-- python -m pip install boto3

----------------------------------------------------------------------
-- STEP 02 — CONFIGURE AWS CLI USING IAM IDENTITY CENTER
----------------------------------------------------------------------

-- 1. In AWS Console, open IAM Identity Center.
-- 2. Confirm you have access to the AWS account containing the S3 bucket.
-- 3. Assign an appropriate permission set that allows S3 uploads.
-- 4. Obtain your IAM Identity Center access portal URL.

-- Run in CMD:
-- aws configure sso --profile snowpipe-usgs

-- Follow the prompts to enter:
-- SSO session name: snowpipe-usgs
-- SSO start URL: Your AWS access portal URL
-- SSO region: Region hosting IAM Identity Center
-- AWS account: Select the account containing your bucket
-- Role: Select the assigned uploader permission set
-- Default client Region: ap-southeast-2 (example)
-- Default output format: json

-- Sign in using your AWS account.

-- Run in CMD:
-- aws sso login --profile snowpipe-usgs

----------------------------------------------------------------------
-- STEP 03 — VERIFY AWS CONNECTIVITY
----------------------------------------------------------------------

-- Verify the AWS identity used by your Python loader.

-- Run in CMD:
-- aws sts get-caller-identity --profile snowpipe-usgs

-- Verify access to the S3 incoming folder.

-- Replace <BUCKET_NAME> with your actual S3 bucket name.

-- Run in CMD:
-- aws s3 ls s3://<BUCKET_NAME>/earthquakes/incoming/ --profile snowpipe-usgs

-- An empty result is expected if no files have been uploaded.
-- An AccessDenied error indicates missing IAM or bucket permissions.

----------------------------------------------------------------------
-- STEP 04 — EXECUTE THE PYTHON DATA LOADER
----------------------------------------------------------------------

-- 1. Open CMD.
-- 2. Navigate to the folder containing fetch_upload.py.
-- 3. Run the Python script to fetch the latest one-hour USGS
--    earthquake feed and upload it to S3.

-- Run in CMD:
-- cd <YOUR_PYTHON_SCRIPT_FOLDER>

-- python fetch_upload.py --bucket <BUCKET_NAME> --profile snowpipe-usgs --feed hour

-- The loader should upload a uniquely named JSON file to:
-- s3://<BUCKET_NAME>/earthquakes/incoming/

-- The uploader requires s3:PutObject permission on this prefix.
-- Ensure fetch_upload.py writes to this prefix and uses the
-- snowpipe-usgs boto3 session profile.

----------------------------------------------------------------------
-- STEP 05 — VERIFY FILES IN AMAZON S3
----------------------------------------------------------------------

-- Run in CMD:
-- aws s3 ls s3://<BUCKET_NAME>/earthquakes/incoming/ --profile snowpipe-usgs

-- Verify that the newly uploaded JSON file appears.

----------------------------------------------------------------------
-- STEP 06 — VERIFY FILES ARE VISIBLE TO SNOWFLAKE
----------------------------------------------------------------------

-- Run the following query in your Snowflake SQL worksheet.

LIST @EARTHQUAKE_DB.BRONZE.EARTHQUAKE_S3_STAGE;

-- The LIST command should display the newly uploaded files.
-- This confirms that Snowflake can list objects through
-- the external stage and storage integration.

----------------------------------------------------------------------
-- STEP 07 — VERIFY AUTOMATIC SNOWPIPE INGESTION
----------------------------------------------------------------------

-- Prerequisite:
-- The Snowpipe must already be created with AUTO_INGEST = TRUE.
-- The S3 ObjectCreated event notification must be configured
-- using the pipe's notification channel.

-- Check the pipe execution status.
-- Replace the pipe name if your project uses a different name.

SELECT SYSTEM$PIPE_STATUS(
    'EARTHQUAKE_DB.BRONZE.EARTHQUAKE_PIPE'
);

-- Check the raw table after the pipe has processed the file.

SELECT COUNT(*) AS TOTAL_RECORDS
FROM EARTHQUAKE_DB.BRONZE.EARTHQUAKES_RAW;

-- View recently loaded records.

SELECT *
FROM EARTHQUAKE_DB.BRONZE.EARTHQUAKES_RAW
LIMIT 20;

----------------------------------------------------------------------
-- STEP 08 — RUN THE LOADER AGAIN
----------------------------------------------------------------------

-- Run in CMD:
-- python fetch_upload.py --bucket <BUCKET_NAME> --profile snowpipe-usgs --feed hour

-- Each execution should upload a new uniquely named S3 object.
-- Snowpipe detects new eligible files through S3 notifications.
-- The same USGS events may appear in different hourly snapshots.
-- Snowpipe does not automatically remove duplicate earthquake IDs.
----------------------------------------------------------------------
