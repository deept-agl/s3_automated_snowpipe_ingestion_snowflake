"""Fetch live USGS earthquakes, convert FeatureCollection to JSON Lines,
and upload a uniquely named S3 object to trigger Snowpipe auto-ingest.

Dependencies: pip install boto3
Credentials: AWS CLI profile (aws configure --profile snowpipe-usgs)
Example: python fetch_upload.py --bucket my-unique-bucket --profile snowpipe-usgs
"""
import argparse
import datetime as dt
import json
import pathlib
import urllib.request
import uuid

import boto3

FEEDS = {
    "hour": "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_hour.geojson",
    "day": "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_day.geojson",
    "week": "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_week.geojson",
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bucket", required=True, help="Existing S3 bucket name")
    ap.add_argument("--profile", default="snowpipe-usgs", help="AWS CLI profile name")
    ap.add_argument("--feed", choices=FEEDS, default="hour")
    ap.add_argument("--prefix", default="earthquakes/incoming/")
    ap.add_argument("--save-local", action="store_true", help="Keep a copy of the JSONL file")
    args = ap.parse_args()
    with urllib.request.urlopen(urllib.request.Request(FEEDS[args.feed], headers={"User-Agent": "snowpipe-usgs-educational-demo/1.0"}), timeout=25) as resp:
        doc = json.load(resp)
    features = doc.get("features", [])
    if not features:
        print("USGS feed contains zero earthquake events at this time; no file uploaded.")
        return
    payload = ("\n".join(json.dumps(feature, separators=(",", ":")) for feature in features) + "\n").encode("utf-8")
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    key = args.prefix.rstrip("/") + f"/usgs_{args.feed}_{stamp}_{uuid.uuid4().hex[:8]}.jsonl"
    if args.save_local:
        path = pathlib.Path(key.rsplit("/", 1)[-1])
        path.write_bytes(payload)
        print(f"Local file: {path.resolve()}")
    session = boto3.Session(profile_name=args.profile, region_name="ap-southeast-2")
    session.client("s3").put_object(Bucket=args.bucket, Key=key, Body=payload, ContentType="application/x-ndjson")
    print(f"Uploaded {len(features)} REAL USGS events: s3://{args.bucket}/{key}")
    print("NOTE: USGS hourly snapshots overlap, so duplicate EVENT_IDs across files are expected.")


if __name__ == "__main__":
    main()
