# Pulling and analyzing run results with cleanroom-intelligence-mcp

Use this server for step 7/8 of the runner when the row pull from `cleanroom_get_question_run_data` is not usable (it returned only `count` / `nextCursor` / `hasMore`, no rows, 20 rows per page, ~250 calls for 5k rows). Server: `cleanroom-intelligence-mcp` (tool names end in `cleanroom_*`; not the client-labeled variants such as `citi-...`). Pass the same `org_id` from its own `meta_get_active_org_ids`.

The server queries a Snowflake copy of the results, so every check in `result-checks.md` can be a read-only aggregate query. Report aggregates only, never raw rows.

## Prerequisite: the run must be loaded

A COMPLETED run loads automatically only when all of these hold (from the server's `domain-concepts` guide):
- the org has the Habu Intelligence product,
- the clean room has Intelligence enabled (`provisionStatus` ENABLED),
- the question is not a List question,
- the question's output format is REPORT.

Check with `cleanroom_get_question_result_tables` (`cleanRoomId`, `cleanRoomQuestionId`): `status` must be `ready` and `loadStatus` `LOADED`. Confirmed: CRQ-234358 (Citibank) stayed `unavailable` / `NOT_LOADED` more than 90 minutes after its run completed, and querying `CRQ_234358` failed with "does not exist or not authorized". If that happens, stop and report it; do not retry the query. Cause: that question had `outputFormat` `CODE_OUTPUT` and no declared dimensions or measures. The builder now creates questions with `REPORT` and the declared output fields (`cleanroom-question-builder/references/question-inputs.md`). A question built before that change must be recreated; updating a definition deletes its dataset bindings. Whether a question built the new way loads after a run is not yet confirmed.

## Steps

1. `cleanroom_get_guide` with `topic: "domain-concepts"` (once per session) for table and run semantics.
2. `cleanroom_get_cleanroom_query_lookup_ids` (`cleanRoomId`): record `analyticsDatabaseId` (used as `databaseId` below) and `warehouseDatabase`.
3. `cleanroom_get_question_result_tables`: record `warehouseReportTable` (for example `CRQ_234358`) and `warehouseMetadataTable`. Never derive table names yourself.
4. Confirm the run is present: `SELECT RUN_ID, COUNT(*) FROM <report table> GROUP BY RUN_ID`. Runs stack in one table; always filter to the run id under test (`WHERE RUN_ID = '<run id>'`). `<table>_METADATA` has one row per run (`RUN_ID`, `RUN_NAME`, `SUBMIT_TIME`, `IS_RECENT`, `START_DATE` / `END_DATE` when the question has date parameters).
5. Optional shape check: `cleanroom_list_result_tables` (to confirm the table exists), `cleanroom_describe_result_columns` (`tableId`), `cleanroom_get_results_table_profile` (`databaseId`, `tableId`; row count, nulls, cardinality, flags).
6. Run the checks with `cleanroom_query_results` (`cleanRoomId`, `databaseId`, `sql`). Use bare table names; they auto-qualify. SELECT only, auto-LIMIT 10000. Soft-delete filter if you use it: `(IS_DELETED IS NULL OR IS_DELETED = FALSE)`.

## Checks as queries (cross-platform exposure mapping; `T` = report table, `:run` = run id)

Untested against live data until a loaded run is available; treat as templates.

- Row count: `SELECT COUNT(*) FROM T WHERE RUN_ID = :run`
- Null rate and 100%-null columns: use `cleanroom_get_results_table_profile`, or `SELECT COUNT(*) - COUNT(col) ... FROM T WHERE RUN_ID = :run` per column.
- Duplicate rows: `SELECT COUNT(*) FROM (SELECT <all columns>, COUNT(*) c FROM T WHERE RUN_ID = :run GROUP BY ALL HAVING c > 1)`
- VMA mapping coverage by source: `SELECT exposure_source, AVG(IFF(channel IS NULL,1,0)), AVG(IFF(publisher IS NULL,1,0)), AVG(IFF(property IS NULL,1,0)), AVG(IFF(creative IS NULL,1,0)) FROM T WHERE RUN_ID = :run GROUP BY exposure_source`
- Exposure totals: `SELECT COUNT(*) FROM T WHERE RUN_ID = :run AND total_exposures <= 0`
- Date range per source: `SELECT exposure_source, MIN(min_exposure_date), MAX(max_exposure_date) FROM T WHERE RUN_ID = :run GROUP BY exposure_source`
- Source presence: `SELECT DISTINCT exposure_source FROM T WHERE RUN_ID = :run`

Column-name case in Snowflake may be upper case; match what `cleanroom_describe_result_columns` returns.

## Rules
- Read-only. Never use the dashboard, card, folder or curated-dataset tools for result checks.
- Do not echo identifier-like values from rows; report counts and rates.
- Use the same org for every call; changing org needs the user's confirmation.
