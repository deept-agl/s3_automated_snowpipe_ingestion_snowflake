-- STEP 1 - CREATE S3 BUCKET (AWS console)
-- S3 > Create bucket; choose globally unique name.
-- Keep Block Public Access ON, ACLs disabled, SSE-S3 encryption.
-- Example path: s3://<YOUR_UNIQUE_BUCKET>/earthquakes/incoming/
--Create these folders eartquakes/incoming/
-- Do NOT upload any events yet. Configure the pipe first.


-- STEP 2 - CREATE A DEDICATED IAM USER AND POLICY
-- IAM > Users > Create user: snowpipe-usgs-user, no console access.
-- IAM > Policies > Create policy (JSON): use aws_iam_policy.json in project.
-- IMPORTANT: replace <YOUR_UNIQUE_BUCKET> in that policy.
-- Attach that policy to the user. Generate one access key(chooose third party).
-- Save key securely, never in a Git-connected SQL file.


