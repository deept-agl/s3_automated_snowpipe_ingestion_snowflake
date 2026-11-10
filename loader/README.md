# File lander: mimic files arriving in S3

`land_files.py` plays the source system. It drops `.jsonl` files into your bucket, one at a time,
so you can watch Snowpipe pick each one up.

## One-time setup (CMD)

1. Install Python 3.9+ and the [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).
2. Install boto3:
   ```bash
   python -m pip install boto3
   ```
3. Create the uploader profile ([`../aws/AWS_SETUP.md`](../aws/AWS_SETUP.md), Part D gives you the keys):
   ```bash
   aws configure --profile snowpipe-uploader
   ```
4. Check it can see the folder (an empty result is fine):
   ```bash
   aws s3 ls s3://<YOUR_BUCKET_NAME>/earthquakes/incoming/ --profile snowpipe-uploader
   ```

## Commands

Run these from the `2_Code` folder.

Land one sample file:
```bash
python loader\land_files.py --bucket <YOUR_BUCKET_NAME> sample_files\01_initial_earthquakes.jsonl
```

Land a file in the wrong folder (test 2):
```bash
python loader\land_files.py --bucket <YOUR_BUCKET_NAME> --prefix earthquakes/wrong-prefix/ sample_files\03_recovery_earthquakes.jsonl
```

Keep landing a new file of 5 made-up earthquakes every 30 seconds (Ctrl+C to stop):
```bash
python loader\land_files.py --bucket <YOUR_BUCKET_NAME> --stream --every 30
```

Land exactly 3 files, one a minute:
```bash
python loader\land_files.py --bucket <YOUR_BUCKET_NAME> --stream --every 60 --batches 3
```

| Option | Default | What it does |
|---|---|---|
| `--bucket` | required | Your bucket |
| `--prefix` | `earthquakes/incoming/` | Folder the file lands in |
| `--stream` | off | Keep generating and landing new files |
| `--every` | `60` | Seconds between files in `--stream` |
| `--rows` | `5` | Earthquakes per generated file |
| `--batches` | `0` (forever) | Stop after this many generated files |
| `--profile` | `snowpipe-uploader` | AWS CLI profile |
| `--region` | profile's region | Override the region |

Sample files keep their own names, so the counts in `04_test_loads.sql` match.
Generated files are named `quakes_<UTC timestamp>.jsonl`, so every one is new to Snowpipe.
Generated events have `"status":"simulated"`.

## Watch them arrive in Snowflake

```sql
USE ROLE EARTHQUAKE_ENGINEER;
SELECT SOURCE_FILE, COUNT(*) AS ROWS_LOADED, MAX(LOADED_AT) AS LOADED_AT
FROM EARTHQUAKE_DB.BRONZE.EARTHQUAKES_RAW
GROUP BY SOURCE_FILE
ORDER BY LOADED_AT DESC;
```

## No Python?

The AWS CLI alone works too:
```bash
aws s3 cp sample_files\01_initial_earthquakes.jsonl s3://<YOUR_BUCKET_NAME>/earthquakes/incoming/ --profile snowpipe-uploader
```
