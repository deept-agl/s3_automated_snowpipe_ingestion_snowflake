----------------------------------------------------------------------
-- STEP 01 — DOWNLOAD THE SAMPLE EARTHQUAKE FILES
----------------------------------------------------------------------
-- Download and extract snowpipe_manual_upload_files.zip.
-- This project uses curated USGS-style event samples for repeatable results.
-- Files are JSON Lines (one earthquake object per line), matching
-- USGS_JSONL_FORMAT. They are NOT the complete live USGS API response.
-- An original API GeoJSON response is a FeatureCollection, not JSONL.
-- Prerequisite: storage integration, stage, pipe and S3 ObjectCreated
-- event notification have already been configured.
-- Do not upload sample files before those components are ready.

----------------------------------------------------------------------
-- STEP 02 — UPLOAD FIRST FILE THROUGH AWS CONSOLE
----------------------------------------------------------------------
-- 1. AWS Console > S3 > select your project bucket.
-- 2. Open earthquakes/incoming/.
-- 3. Click Upload > Add files.
-- 4. Select 01_initial_earthquakes.jsonl and click Upload.
-- 5. Wait for the Snowpipe process to finish; there is no need to
--    execute a COPY INTO command manually.

LIST @EARTHQUAKE_DB.BRONZE.USGS_S3_STAGE;
SELECT SYSTEM$PIPE_STATUS('EARTHQUAKE_DB.BRONZE.USGS_EARTHQUAKE_PIPE');
SELECT SOURCE_FILE, COUNT(*) AS ROW_COUNT
FROM EARTHQUAKE_DB.BRONZE.EARTHQUAKES_RAW
GROUP BY SOURCE_FILE ORDER BY SOURCE_FILE;
-- Expected in a fresh environment: 3 rows from first file.

----------------------------------------------------------------------
-- STEP 03 — SCENARIO 2: FILE UPLOADED TO THE WRONG PREFIX
----------------------------------------------------------------------
-- 1. In S3, create or open earthquakes/wrong-prefix/.
-- 2. Upload 03_recovery_earthquakes.jsonl there.
-- 3. The pipe watches earthquakes/incoming/, so this upload should
--    not trigger that pipe.
-- 4. Correct the mistake by UPLOADING a fresh copy of that file
--    under earthquakes/incoming/ when testing recovery, or leave
--    recovery until STEP 06 below.
-- IMPORTANT: If S3 notification is restricted to incoming/, the
-- wrong-prefix file will not trigger the pipe.

SELECT COUNT(*) AS RAW_COUNT
FROM EARTHQUAKE_DB.BRONZE.EARTHQUAKES_RAW;

----------------------------------------------------------------------
-- STEP 04 — SCENARIO 3: SAME EVENTS IN DIFFERENT S3 FILES
----------------------------------------------------------------------
-- Upload 02_duplicate_snapshot.jsonl to earthquakes/incoming/.
-- This file contains 3 rows: 2 previously seen earthquake IDs and
-- 1 new ID. Snowpipe file tracking does NOT deduplicate event IDs.

SELECT COUNT(*) AS RAW_ROWS,
       COUNT(DISTINCT EVENT_DATA:id::STRING) AS DISTINCT_EVENT_IDS
FROM EARTHQUAKE_DB.BRONZE.EARTHQUAKES_RAW;
-- Expected after files 01 and 02 in a fresh environment:
-- RAW_ROWS = 6, DISTINCT_EVENT_IDS = 4.

SELECT EVENT_DATA:id::STRING AS EVENT_ID, COUNT(*) AS OCCURRENCES
FROM EARTHQUAKE_DB.BRONZE.EARTHQUAKES_RAW
GROUP BY 1 HAVING COUNT(*) > 1 ORDER BY OCCURRENCES DESC;

----------------------------------------------------------------------
-- STEP 05 — SCENARIO 4: MALFORMED JSON FILE
----------------------------------------------------------------------
-- Upload 04_invalid_json.jsonl to earthquakes/incoming/.
-- The file intentionally contains malformed JSON and should fail
-- validation; with ON_ERROR=SKIP_FILE the file should be skipped.
-- Inspect load history and pipe status. Do not assume every
-- uploaded object has been loaded successfully.

SELECT * FROM TABLE(EARTHQUAKE_DB.INFORMATION_SCHEMA.COPY_HISTORY(
 TABLE_NAME => 'BRONZE.EARTHQUAKES_RAW',
 START_TIME => DATEADD('hour', -24, CURRENT_TIMESTAMP())
)) ORDER BY LAST_LOAD_TIME DESC;

----------------------------------------------------------------------
-- STEP 06 — SCENARIO 5: PAUSE AND RESUME THE PIPE
----------------------------------------------------------------------
-- Pause ingestion, then upload 03_recovery_earthquakes.jsonl into
-- earthquakes/incoming/ with a NEW object key if it was previously
-- uploaded to incoming/. Avoid overwriting an already loaded key.

ALTER PIPE EARTHQUAKE_DB.BRONZE.USGS_EARTHQUAKE_PIPE
SET PIPE_EXECUTION_PAUSED = TRUE;

SELECT SYSTEM$PIPE_STATUS('EARTHQUAKE_DB.BRONZE.USGS_EARTHQUAKE_PIPE');

-- After uploading the file, resume the pipe:
ALTER PIPE EARTHQUAKE_DB.BRONZE.USGS_EARTHQUAKE_PIPE
SET PIPE_EXECUTION_PAUSED = FALSE;

SELECT SYSTEM$PIPE_STATUS('EARTHQUAKE_DB.BRONZE.USGS_EARTHQUAKE_PIPE');
SELECT EVENT_DATA:id::STRING AS EVENT_ID, SOURCE_FILE
FROM EARTHQUAKE_DB.BRONZE.EARTHQUAKES_RAW
WHERE EVENT_DATA:id::STRING = 'hv75017371';
-- Confirm a successful load in COPY_HISTORY before concluding that
-- the queued notification was processed. If a notification was lost,
-- investigate S3 notification settings and documented pipe recovery.

----------------------------------------------------------------------
-- STEP 07 — FINAL CHECKS
----------------------------------------------------------------------
SELECT SOURCE_FILE, COUNT(*) AS RECORDS_LOADED
FROM EARTHQUAKE_DB.BRONZE.EARTHQUAKES_RAW
GROUP BY SOURCE_FILE ORDER BY SOURCE_FILE;

SELECT EVENT_DATA:id::STRING AS EVENT_ID,
       EVENT_DATA:properties:mag::FLOAT AS MAGNITUDE,
       EVENT_DATA:properties:place::STRING AS LOCATION,
       SOURCE_FILE
FROM EARTHQUAKE_DB.BRONZE.EARTHQUAKES_RAW
ORDER BY EVENT_ID;

-- Each demonstration starts with a fresh environment or unique S3
-- object keys. Existing load history changes the expected counts.
