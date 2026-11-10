-- =====================================================================
-- 05_monitoring.sql  |  Is the pipe healthy, fast, complete and cheap?
-- =====================================================================
-- A pipe fails quietly: no error pops up anywhere when a file is skipped
-- or a notification never arrives. These are the five checks to run
-- (or schedule) once it's live.
-- =====================================================================

USE ROLE EARTHQUAKE_ENGINEER;
USE WAREHOUSE WH_EARTHQUAKE_INGEST;
USE SCHEMA EARTHQUAKE_DB.BRONZE;


-- ---------------------------------------------------------------------
-- 1. HEALTH: is the pipe running, and is it still hearing from S3?
-- ---------------------------------------------------------------------
WITH s AS (
  SELECT PARSE_JSON(SYSTEM$PIPE_STATUS('EARTHQUAKE_DB.BRONZE.USGS_EARTHQUAKE_PIPE')) AS j
)
SELECT j:executionState::STRING                    AS EXECUTION_STATE,      -- want RUNNING
       j:pendingFileCount::NUMBER                  AS PENDING_FILES,        -- want 0 most of the time
       j:lastReceivedMessageTimestamp::TIMESTAMP_LTZ AS LAST_MESSAGE_FROM_S3, -- too old = notification broken
       j:lastForwardedMessageTimestamp::TIMESTAMP_LTZ AS LAST_FILE_QUEUED,
       j:error::STRING                             AS ERROR
FROM s;


-- ---------------------------------------------------------------------
-- 2. FAILURES: which files did NOT load in the last 24 hours, and why?
-- ---------------------------------------------------------------------
SELECT FILE_NAME, STATUS, FIRST_ERROR_MESSAGE, FIRST_ERROR_LINE_NUMBER, LAST_LOAD_TIME
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
       TABLE_NAME => 'EARTHQUAKE_DB.BRONZE.EARTHQUAKES_RAW',
       START_TIME => DATEADD('hour', -24, CURRENT_TIMESTAMP())))
WHERE STATUS <> 'Loaded'
ORDER BY LAST_LOAD_TIME DESC;
-- Expected after 04: 04_invalid_json.jsonl


-- ---------------------------------------------------------------------
-- 3. LATENCY: how long from "file landed" to "rows queryable"?
-- ---------------------------------------------------------------------
SELECT SOURCE_FILE,
       MIN(FILE_LANDED_AT)                                         AS LANDED_UTC,
       MIN(CONVERT_TIMEZONE('UTC', LOADED_AT))::TIMESTAMP_NTZ      AS LOADED_UTC,
       DATEDIFF('second', MIN(FILE_LANDED_AT),
                MIN(CONVERT_TIMEZONE('UTC', LOADED_AT))::TIMESTAMP_NTZ) AS SECONDS_TO_LOAD
FROM EARTHQUAKES_RAW
GROUP BY SOURCE_FILE
ORDER BY LANDED_UTC DESC;
-- The pause/resume file (03) will show a long wait. That's expected.


-- ---------------------------------------------------------------------
-- 4. COMPLETENESS: is any file in S3 that the pipe never even saw?
--    (a missed notification, or a file that landed before Part C)
-- ---------------------------------------------------------------------
LIST @USGS_S3_STAGE;
SET LIST_QID = LAST_QUERY_ID();

SELECT SPLIT_PART(l."name", '/', -1) AS FILE_IN_S3, l."last_modified"
FROM TABLE(RESULT_SCAN($LIST_QID)) l
WHERE SPLIT_PART(l."name", '/', -1) NOT IN (
  SELECT SPLIT_PART(FILE_NAME, '/', -1)
  FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
         TABLE_NAME => 'EARTHQUAKE_DB.BRONZE.EARTHQUAKES_RAW',
         START_TIME => DATEADD('day', -14, CURRENT_TIMESTAMP())))
);
-- Expected: no rows. If files show up here, queue them (last 7 days only):
--   ALTER PIPE USGS_EARTHQUAKE_PIPE REFRESH;


-- ---------------------------------------------------------------------
-- 5. COST: what has Snowpipe used? (serverless, billed separately from
--    the warehouse; usage can take a while to appear)
--    Needs ACCOUNTADMIN or a role with MONITOR USAGE.
-- ---------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;
SELECT PIPE_NAME,
       SUM(FILES_INSERTED) AS FILES,
       SUM(BYTES_INSERTED) AS BYTES,
       SUM(CREDITS_USED)   AS CREDITS
FROM TABLE(EARTHQUAKE_DB.INFORMATION_SCHEMA.PIPE_USAGE_HISTORY(
       DATE_RANGE_START => DATEADD('day', -1, CURRENT_TIMESTAMP()),
       PIPE_NAME        => 'EARTHQUAKE_DB.BRONZE.USGS_EARTHQUAKE_PIPE'))
GROUP BY PIPE_NAME;


-- ---------------------------------------------------------------------
-- Making it automatic (not built here):
--  * Schedule check 2 as a Snowflake ALERT that emails you when a file
--    fails (alerts are covered in the cost guardrails video).
--  * Or give the pipe an ERROR_INTEGRATION (an SNS notification
--    integration) so Snowpipe pushes load errors to AWS SNS itself.
-- ---------------------------------------------------------------------

-- Next: 06_cleanup.sql when you're done.
