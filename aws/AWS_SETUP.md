# AWS setup

Four short trips to the AWS console, each between two Snowflake files.
Use the **same AWS region** as your Snowflake account (Snowflake shows it under your account name, bottom left).

| Part | When | What |
|---|---|---|
| A | after `00_setup.sql` | Bucket, read-only policy, IAM role |
| B | after `01_storage_integration.sql` | Trust policy: let Snowflake assume the role |
| C | after `03_pipe.sql` | S3 event notification to the pipe's queue |
| D | before `04_test_loads.sql` | An uploader profile for your laptop |
| E | optional, before production | Bucket hardening |

Replace every `<PLACEHOLDER>` with your own value. Snowflake itself never gets a key: it reaches S3 only through the role.

---

## Part A: bucket, policy, role

### A1. Bucket
1. **S3 > Buckets > Create bucket**, General purpose.
2. Name it something globally unique, e.g. `earthquake-ingestion-<your-initials>-<digits>`.
3. Keep **ACLs disabled**, **Block all public access ON**, default encryption **SSE-S3**. Create.
4. Open the bucket and **Create folder** `earthquakes`, then inside it `incoming`.

### A2. Read-only policy
1. **IAM > Policies > Create policy > JSON**.
2. Paste [`snowflake_s3_read_policy.json`](snowflake_s3_read_policy.json) and replace `<YOUR_BUCKET_NAME>` (3 places).
3. Name it `EarthquakeS3ReadPolicy`. Create.

It allows exactly three things: read files under `earthquakes/incoming/`, list that folder, and look up the bucket's region. No write, no delete, nothing outside the folder.

### A3. IAM role
1. **IAM > Roles > Create role > AWS account > This account**.
2. Tick **Require external ID** and enter `0000` for now. (Part B replaces both the account and the ID.)
3. Attach `EarthquakeS3ReadPolicy`.
4. Name it `SnowflakeEarthquakeIngestionRole`. Create.
5. Open the role and copy its **ARN**: `arn:aws:iam::<AWS_ACCOUNT_ID>:role/SnowflakeEarthquakeIngestionRole`.

The trust policy at this point looks like [`role_trust_policy_initial.json`](role_trust_policy_initial.json): only your own account can assume it. That's a placeholder.

Paste the ARN into `01_storage_integration.sql` and run it.

---

## Part B: trust policy (the STS handshake)

From `01_storage_integration.sql` you have two values:
- `STORAGE_AWS_IAM_USER_ARN`, e.g. `arn:aws:iam::123456789012:user/abc1-b-xyz2`
- `STORAGE_AWS_EXTERNAL_ID`, e.g. `AB12345_SFCRole=2_abcdefg...`

1. **IAM > Roles > SnowflakeEarthquakeIngestionRole > Trust relationships > Edit trust policy**.
2. Replace everything with [`role_trust_policy.json`](role_trust_policy.json).
3. Put the user ARN in `Principal.AWS` and the external ID in `sts:ExternalId`. Copy them exactly: no spaces, no quotes inside quotes.
4. **Update policy**.

What this says: "Snowflake's AWS identity may call `sts:AssumeRole` on this role, but only when it presents this external ID." STS then hands Snowflake temporary credentials that expire, scoped to the read policy from A2.

Run `02_stage.sql`. `LIST` returning no error means the handshake works.

> **Did the setup trap in `02_stage.sql`?** The integration now has a new external ID. Come back here, paste the new one, save, and `LIST` again.

---

## Part C: event notification

From `03_pipe.sql` you have the `notification_channel`, an SQS queue ARN like
`arn:aws:sqs:<region>:<snowflake-account>:sf-snowpipe-...`. Snowflake owns this queue.

1. **S3 > your bucket > Properties > Event notifications > Create event notification**.
2. Name: `snowpipe-earthquakes`.
3. Prefix: `earthquakes/incoming/`. Suffix: `.jsonl`.
4. Event types: **All object create events**.
5. Destination: **SQS queue > Enter SQS queue ARN**, paste the `notification_channel`. Save.

Now every new `.jsonl` file in `earthquakes/incoming/` sends a message to Snowflake, and the pipe loads it. Do Part D, then `04_test_loads.sql`.

---

## Part D: an uploader for your laptop

`loader/land_files.py` plays the source system and needs to upload files. That's a different job from Snowflake's read role, so it gets its own small identity.

1. **IAM > Users > Create user** `earthquake-uploader` (no console access).
2. **Add permissions > Create inline policy > JSON**: paste [`s3_uploader_policy.json`](s3_uploader_policy.json), replace `<YOUR_BUCKET_NAME>` (2 places). It can only upload to and list `earthquakes/incoming/`.
3. Open the user > **Security credentials > Create access key > Command Line Interface (CLI)**. Copy both values.
4. In CMD:
   ```bash
   aws configure --profile snowpipe-uploader
   ```
   Paste the two keys, your bucket's region, and `json`.

The uploader can't read anything, and Snowflake can't upload anything. Delete the key when you're done (see Cleanup).
If your company uses IAM Identity Center, use `aws configure sso --profile snowpipe-uploader` instead.

Then follow [`../loader/README.md`](../loader/README.md).

---

## Part E (optional): hardening the bucket for production

Not needed for the demo. Do these before real data lands here.

1. **HTTPS only.** Bucket > Permissions > Bucket policy: paste [`bucket_policy_tls_only.json`](bucket_policy_tls_only.json) (replace the bucket name, 2 places). Any request without TLS is denied.
2. **Keep the landed files, but not forever.** Snowpipe never deletes files, and you don't want it to: S3 is your replay source. Add a lifecycle rule on `earthquakes/incoming/`: move to a cheaper storage class after 30 days, expire after 90 (pick what your retention rules say). Keep them at least as long as you might need `ALTER PIPE … REFRESH` (7 days) or a manual reload.
3. **Versioning** (Properties > Bucket Versioning) protects against overwritten or deleted files. The read policy already allows `s3:GetObjectVersion`.
4. **Your own KMS key?** If the bucket uses SSE-KMS, add `kms:Decrypt` on that key to `EarthquakeS3ReadPolicy`, and allow the role in the key policy.
5. **One integration and role per environment.** Separate dev and prod buckets, roles and integrations, so a dev mistake can't read or break prod.
6. **Compress real files.** gzip cuts S3 and transfer cost; Snowflake detects it (`COMPRESSION = AUTO`). Change the notification suffix to `.jsonl.gz` if you do.

---

## Troubleshooting

| You see | Usually means |
|---|---|
| `LIST` error mentioning the role or `AssumeRole` | Trust policy principal or external ID doesn't match `DESC INTEGRATION`. Did someone `CREATE OR REPLACE` the integration? |
| `LIST` Access Denied | Read policy bucket name or prefix is wrong, or the stage URL isn't inside `STORAGE_ALLOWED_LOCATIONS`. |
| `LIST` works, files never load | Event notification missing, wrong prefix/suffix, or wrong queue ARN. Check `SYSTEM$PIPE_STATUS`. |
| "Configuration overlaps" when saving the notification | Another notification on this bucket already covers the same prefix. S3 allows one per overlapping prefix. |
| STS error in an unusual region | **IAM > Account settings > STS endpoints**: the region must be active. |
| Your company account still denies `AssumeRole` | An AWS Organizations SCP or RCP may block cross-account access. Ask your admin for a narrow exception; don't remove org-wide denies. |

---

## Cleanup (after `06_cleanup.sql`)

1. Bucket > Properties > delete the `snowpipe-earthquakes` notification.
2. Empty the bucket, then delete it.
3. IAM > Roles > delete `SnowflakeEarthquakeIngestionRole`.
4. IAM > Policies > delete `EarthquakeS3ReadPolicy`.
5. IAM > Users > delete `earthquake-uploader` (this deletes its access key too).
