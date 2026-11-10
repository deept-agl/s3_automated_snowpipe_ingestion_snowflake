-- =====================================================================
-- 03_pipe.sql  |  Snowpipe with auto-ingest
-- =====================================================================
-- Don't upload any files yet. The S3 event notification (AWS Part C)
-- comes after this, and it needs the queue ARN this file prints.
-- =====================================================================

USE ROLE EARTHQUAKE_ENGINEER;
USE WAREHOUSE WH_EARTHQUAKE_INGEST;
USE SCHEMA EARTHQUAKE_DB.BRONZE;

-- AUTO_INGEST = TRUE: S3 tells Snowflake about new files; nobody polls.
-- The COPY inside is the whole pipe: what to load, from where, and which
-- metadata to keep.
--
-- Choices worth knowing:
--   * Fully qualified names: the COPY runs later, outside your session.
--   * Lineage columns: every row says which file, which line, and when
--     that file landed in S3.
--   * ON_ERROR = SKIP_FILE: one bad line rejects the whole file, so a file
--     is either fully loaded or not at all. (CONTINUE would load the good
--     lines and silently drop the bad ones.)
--   * No transformations beyond column picks: keep bronze as-is and clean
--     it downstream, so a parsing bug never means re-ingesting from S3.
--   * Never CREATE OR REPLACE a live pipe: a new pipe has no load history,
--     and a REFRESH could load old files again.
CREATE PIPE IF NOT EXISTS USGS_EARTHQUAKE_PIPE
  AUTO_INGEST = TRUE
  COMMENT     = 'Loads each new earthquake file from S3 into BRONZE.EARTHQUAKES_RAW'
AS
COPY INTO EARTHQUAKE_DB.BRONZE.EARTHQUAKES_RAW
     (EVENT_DATA, SOURCE_FILE, FILE_ROW, FILE_LANDED_AT)
FROM (
  SELECT $1,
         METADATA$FILENAME,
         METADATA$FILE_ROW_NUMBER,
         METADATA$FILE_LAST_MODIFIED
  FROM @EARTHQUAKE_DB.BRONZE.USGS_S3_STAGE
)
ON_ERROR = SKIP_FILE;

-- The queue S3 must notify. Copy the notification_channel value.
SHOW PIPES LIKE 'USGS_EARTHQUAKE_PIPE';
SELECT "notification_channel"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- Healthy pipe: "executionState":"RUNNING", "pendingFileCount":0
SELECT SYSTEM$PIPE_STATUS('EARTHQUAKE_DB.BRONZE.USGS_EARTHQUAKE_PIPE');

-- Next: aws/AWS_SETUP.md, Part C (S3 event notification -> this queue).
