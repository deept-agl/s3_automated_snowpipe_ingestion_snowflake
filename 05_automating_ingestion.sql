
USE WAREHOUSE EVENTS_WH;
USE DATABASE EARTHQUAKE_DB;
USE SCHEMA RAW;

--check pipe status
SELECT SYSTEM$PIPE_STATUS(
    'EARTHQUAKE_DB.RAW.USGS_EARTHQUAKE_PIPE'
);

LIST @USGS_S3_STAGE;

ALTER PIPE EARTHQUAKE_DB.RAW.USGS_EARTHQUAKE_PIPE REFRESH;

SELECT SYSTEM$PIPE_STATUS(
    'EARTHQUAKE_DB.RAW.USGS_EARTHQUAKE_PIPE'
);

SELECT *
FROM EARTHQUAKE_DB.RAW.EARTHQUAKES_RAW;

---Enable S3 Event Notification (Automation)

-- Copy the notification_channel ARN from the DESC PIPE result.

DESC PIPE EARTHQUAKE_DB.RAW.USGS_EARTHQUAKE_PIPE;

-- AWS S3 > bucket > Properties > Event notifications > Create:
-- Name: usgs-snowpipe-autoload
-- Prefix: earthquakes/incoming/
-- Suffix: .jsonl
-- Event types: All object create events
-- Destination: SQS queue > Enter SQS queue ARN > paste ARN above.
-- Save. Do not create your own SQS queue.
-- If AWS rejects event notification due to overlapping prefixes,
-- review existing notifications and use a separate dedicated prefix.


-- TEST USING LOCAL SCRIPT
-- python fetch_upload.py --bucket earthquake-live-data-feed --profile snowpipe-usgs --feed hour
-- Run the command a second time to upload a new snapshot file.
-- The bucket path is automatically earthquakes/incoming/<unique>.jsonl


SELECT SYSTEM$PIPE_STATUS('EARTHQUAKE_DB.RAW.USGS_EARTHQUAKE_PIPE');

SELECT COUNT(*) AS LOADED_ROWS FROM EARTHQUAKE_DB.RAW.EARTHQUAKES_RAW;

SELECT EVENT_DATA:id::VARCHAR AS EVENT_ID,
       EVENT_DATA:properties:mag::FLOAT AS MAGNITUDE,
       EVENT_DATA:properties:place::VARCHAR AS LOCATION,
       DATEADD('MILLISECOND', EVENT_DATA:properties:time::NUMBER,
               '1970-01-01'::TIMESTAMP_NTZ) AS EVENT_TIME_UTC,
       SOURCE_FILE
FROM EARTHQUAKE_DB.RAW.EARTHQUAKES_RAW
ORDER BY EVENT_TIME_UTC DESC
LIMIT 20;

