--  CONFIGURE LOCAL AWS CREDENTIALS FOR UPLOADER
-- Open command prompt
python -m pip install boto3
aws --version
-- Install AWS CLI if needed; 
aws configure --profile snowpipe-usgs
-- Enter the new IAM access key and secret, region <your cloud region>.
AWS Access Key ID: YOUR_ACCESS_KEY_ID
AWS Secret Access Key: YOUR_SECRET_ACCESS_KEY
Default region name: ap-southeast-2
Default output format: json
--Verify AWS connectivity
aws sts get-caller-identity --profile snowpipe-usgs
-- Alternative: upload generated JSON files in the AWS S3 console.

--Verify S3 access
aws s3 ls s3://earthquake-live-data-feed/ --profile snowpipe-usgs


--Run your python script top fetch the last 1 hour earthquake data and then upload it to s3
--cd <your script location>
python fetch_upload.py --bucket earthquake-live-data-feed --profile snowpipe-usgs --feed hour


--This will upload event json file to your s3 location.
