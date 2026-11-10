r"""Mimic files landing in S3, the way a source system would drop them.

Run from the 2_Code folder in CMD:

  Land one sample file:
    python loader\land_files.py --bucket <YOUR_BUCKET_NAME> sample_files\01_initial_earthquakes.jsonl

  Land it in the wrong folder (test 2):
    python loader\land_files.py --bucket <YOUR_BUCKET_NAME> --prefix earthquakes/wrong-prefix/ sample_files\03_recovery_earthquakes.jsonl

  Keep landing new files every 30 seconds (Ctrl+C to stop):
    python loader\land_files.py --bucket <YOUR_BUCKET_NAME> --stream --every 30
"""
import argparse
import datetime as dt
import json
import pathlib
import random
import time
import uuid

import boto3

# Region name -> rough (longitude, latitude) centre, so the points look plausible.
REGIONS = {
    "Southern Alaska": (-150.0, 61.0),
    "Central California": (-120.5, 36.5),
    "Island of Hawaii": (-155.5, 19.5),
    "Honshu, Japan": (140.0, 37.0),
    "Northern Chile": (-69.5, -21.0),
    "Sumatra, Indonesia": (100.0, -1.0),
    "Central Italy": (13.0, 42.5),
    "Nevada": (-117.0, 39.0),
}


def land_file(s3, bucket, prefix, name, body):
    """Upload one file to s3://bucket/prefix/name. This is the 'file landing'."""
    key = prefix.rstrip("/") + "/" + name
    s3.put_object(Bucket=bucket, Key=key, Body=body, ContentType="application/x-ndjson")
    print(f"{dt.datetime.now():%H:%M:%S}  landed  s3://{bucket}/{key}")


def make_earthquakes(rows):
    """A small batch of made-up earthquakes, same shape as the USGS feed, one per line."""
    now_ms = int(time.time() * 1000)
    lines = []
    for _ in range(rows):
        place = random.choice(list(REGIONS))
        lon, lat = REGIONS[place]
        quake = {
            "type": "Feature",
            "id": "sim" + uuid.uuid4().hex[:10],
            "properties": {
                "mag": round(random.uniform(0.5, 6.5), 1),
                "place": place,
                "time": now_ms - random.randint(0, 3_600_000),
                "type": "earthquake",
                "status": "simulated",
            },
            "geometry": {
                "type": "Point",
                "coordinates": [
                    round(lon + random.uniform(-1.5, 1.5), 3),
                    round(lat + random.uniform(-1.5, 1.5), 3),
                    round(random.uniform(0, 300), 1),
                ],
            },
        }
        lines.append(json.dumps(quake, separators=(",", ":")))
    return ("\n".join(lines) + "\n").encode("utf-8")


def main():
    ap = argparse.ArgumentParser(description="Mimic files landing in S3.")
    ap.add_argument("files", nargs="*", help="Local .jsonl files to land as they are")
    ap.add_argument("--bucket", required=True, help="Your S3 bucket name")
    ap.add_argument("--prefix", default="earthquakes/incoming/", help="Folder in the bucket")
    ap.add_argument("--profile", default="snowpipe-uploader", help="AWS CLI profile")
    ap.add_argument("--region", default=None, help="Defaults to the profile's region")
    ap.add_argument("--stream", action="store_true", help="Keep landing new generated files")
    ap.add_argument("--every", type=int, default=60, help="Seconds between files in --stream")
    ap.add_argument("--rows", type=int, default=5, help="Earthquakes per generated file")
    ap.add_argument("--batches", type=int, default=0, help="Stop after N files (0 = until Ctrl+C)")
    args = ap.parse_args()

    if not args.files and not args.stream:
        ap.error("give one or more files, or use --stream")

    s3 = boto3.Session(profile_name=args.profile, region_name=args.region).client("s3")

    # Sample files keep their own names, so the counts in 04_test_loads.sql match.
    for path in map(pathlib.Path, args.files):
        land_file(s3, args.bucket, args.prefix, path.name, path.read_bytes())

    # Generated files get a timestamp in the name: every file is new to Snowpipe.
    sent = 0
    try:
        while args.stream and (args.batches == 0 or sent < args.batches):
            name = f"quakes_{dt.datetime.now(dt.timezone.utc):%Y%m%dT%H%M%SZ}.jsonl"
            land_file(s3, args.bucket, args.prefix, name, make_earthquakes(args.rows))
            sent += 1
            if args.batches == 0 or sent < args.batches:
                time.sleep(args.every)
    except KeyboardInterrupt:
        print(f"\nStopped after {sent} file(s).")


if __name__ == "__main__":
    main()
