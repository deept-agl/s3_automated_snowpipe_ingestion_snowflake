-- =====================================================================
-- 04_test_loads.sql  |  Drop files in S3, watch them arrive
-- =====================================================================
-- Before this: AWS Part C is done (event notification -> pipe queue).
-- Before this: AWS Part D is done (uploader profile on your laptop).
-- Files land with loader/land_files.py, run in CMD from the 2_Code folder.
-- (S3 console > Upload works too.) Never run COPY INTO yourself: the pipe does it.
-- Expected counts assume a fresh run (cleanup + 00 -> 03).
-- =====================================================================

USE ROLE EARTHQUAKE_ENGINEER;
USE WAREHOUSE WH_EARTHQUAKE_INGEST;
USE SCHEMA EARTHQUAKE_DB.BRONZE;


-- ---------------------------------------------------------------------
-- TEST 1: the happy path
--   python loader\land_files.py --bucket <YOUR_BUCKET_NAME> sample_files\01_initial_earthquakes.jsonl
-- Give it about a minute.
-- ---------------------------------------------------------------------
LIST @USGS_S3_STAGE;

SELECT SOURCE_FILE, FILE_ROW,
       EVENT_DATA:id::STRING               AS EVENT_ID,
       EVENT_DATA:properties:mag::FLOAT    AS MAGNITUDE,
       EVENT_DATA:properties:place::STRING AS PLACE,
       LOADED_AT
FROM EARTHQUAKES_RAW
ORDER BY LOADED_AT DESC;
-- Expected: 3 rows, all from 01_initial_earthquakes.jsonl


-- ---------------------------------------------------------------------
-- TEST 2: a file in the wrong folder
--   python loader\land_files.py --bucket <YOUR_BUCKET_NAME> --prefix earthquakes/wrong-prefix/ sample_files\03_recovery_earthquakes.jsonl
-- The notification only fires for earthquakes/incoming/, and the stage
-- only points there, so nothing should load.
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS RAW_ROWS FROM EARTHQUAKES_RAW;
-- Expected: still 3


-- ---------------------------------------------------------------------
-- TEST 3: the same earthquakes in a new file
--   python loader\land_files.py --bucket <YOUR_BUCKET_NAME> sample_files\02_duplicate_snapshot.jsonl
-- 2 of its 3 events were already in file 01. Snowpipe tracks FILES,
-- not rows, so a new file name means a new load.
-- ---------------------------------------------------------------------
SELECT COUNT(*)                               AS RAW_ROWS,
       COUNT(DISTINCT EVENT_DATA:id::STRING)  AS DISTINCT_EVENTS
FROM EARTHQUAKES_RAW;
-- Expected: RAW_ROWS = 6, DISTINCT_EVENTS = 4

SELECT EVENT_DATA:id::STRING AS EVENT_ID,
       COUNT(*)              AS COPIES,
       ARRAY_AGG(SOURCE_FILE) AS FILES
FROM EARTHQUAKES_RAW
GROUP BY 1
HAVING COUNT(*) > 1;

-- Bronze keeps every copy on purpose. Readers get one row per event:
CREATE OR REPLACE VIEW EARTHQUAKES_LATEST AS
SELECT *
FROM EARTHQUAKES_RAW
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY EVENT_DATA:id::STRING
  ORDER BY LOADED_AT DESC, SOURCE_FILE DESC
) = 1;

SELECT COUNT(*) AS LATEST_ROWS FROM EARTHQUAKES_LATEST;
-- Expected: 4


-- ---------------------------------------------------------------------
-- TEST 4: a broken file
--   python loader\land_files.py --bucket <YOUR_BUCKET_NAME> sample_files\04_invalid_json.jsonl
-- ON_ERROR = SKIP_FILE: the whole file is skipped and the pipe moves on.
-- ---------------------------------------------------------------------
SELECT FILE_NAME, STATUS, ROW_COUNT, FIRST_ERROR_MESSAGE, LAST_LOAD_TIME
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
       TABLE_NAME => 'EARTHQUAKE_DB.BRONZE.EARTHQUAKES_RAW',
       START_TIME => DATEADD('hour', -24, CURRENT_TIMESTAMP())))
ORDER BY LAST_LOAD_TIME DESC;
-- Expected: 04_invalid_json.jsonl with STATUS = Load failed

-- The exact parse errors the pipe hit:
SELECT *
FROM TABLE(VALIDATE_PIPE_LOAD(
       PIPE_NAME  => 'EARTHQUAKE_DB.BRONZE.USGS_EARTHQUAKE_PIPE',
       START_TIME => DATEADD('hour', -24, CURRENT_TIMESTAMP())));


-- ---------------------------------------------------------------------
-- TEST 5: pause, upload, resume
-- Pause the pipe, land file 03 in the RIGHT folder, check nothing
-- loads, then resume.
-- ---------------------------------------------------------------------
ALTER PIPE USGS_EARTHQUAKE_PIPE SET PIPE_EXECUTION_PAUSED = TRUE;
SELECT SYSTEM$PIPE_STATUS('EARTHQUAKE_DB.BRONZE.USGS_EARTHQUAKE_PIPE');
-- "executionState":"PAUSED"

--   python loader\land_files.py --bucket <YOUR_BUCKET_NAME> sample_files\03_recovery_earthquakes.jsonl
-- (wait a minute)
SELECT COUNT(*) AS RAW_ROWS FROM EARTHQUAKES_RAW;
-- Expected: still 6

ALTER PIPE USGS_EARTHQUAKE_PIPE SET PIPE_EXECUTION_PAUSED = FALSE;
SELECT SYSTEM$PIPE_STATUS('EARTHQUAKE_DB.BRONZE.USGS_EARTHQUAKE_PIPE');

-- About a minute later the queued file loads:
SELECT EVENT_DATA:id::STRING AS EVENT_ID, SOURCE_FILE, LOADED_AT
FROM EARTHQUAKES_RAW
WHERE EVENT_DATA:id::STRING = 'hv75017371';
-- Expected: 1 row from 03_recovery_earthquakes.jsonl
-- Still missing? Files that landed with no notification can be queued
-- by hand (it only looks back 7 days):
--   ALTER PIPE USGS_EARTHQUAKE_PIPE REFRESH;


-- ---------------------------------------------------------------------
-- FINAL CHECK
-- ---------------------------------------------------------------------
SELECT SOURCE_FILE, COUNT(*) AS ROWS_LOADED
FROM EARTHQUAKES_RAW
GROUP BY SOURCE_FILE
ORDER BY SOURCE_FILE;
-- Expected: 01 -> 3, 02 -> 3, 03 -> 1 (04 skipped, wrong-prefix ignored)

-- ---------------------------------------------------------------------
-- TEST 6: files keep landing
--   python loader\land_files.py --bucket <YOUR_BUCKET_NAME> --stream --every 30 --batches 4
-- Re-run this every 30 seconds and watch a new file appear each time.
-- ---------------------------------------------------------------------
SELECT SOURCE_FILE, COUNT(*) AS ROWS_LOADED, MAX(LOADED_AT) AS LOADED_AT
FROM EARTHQUAKES_RAW
GROUP BY SOURCE_FILE
ORDER BY LOADED_AT DESC;
-- Expected: one quakes_<timestamp>.jsonl per batch, 5 rows each
