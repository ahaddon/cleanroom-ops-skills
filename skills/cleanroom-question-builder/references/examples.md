# Worked examples

Each example is an input spec and the exact edits expected. Add new confirmed cases here, one per heading.

## Example 1: default four sources, adserver join

Spec:
```json
{
  "clean_room_id": "00000000-0000-0000-0000-000000000000",
  "client_name": "Acme",
  "exposure_sources": ["digital_pixel", "amazon", "meta"],
  "digital_mapping": "adserver",
  "report_date_range": {"start": "2026-01-01", "end": "2026-03-31"}
}
```
Expected SQL: the template unchanged. Validator: PASS, no warnings.
Question title: `Acme - Cross-Platform Exposure Mapping`.
Not in the SQL: the report date range (passed as run parameters) and the dataset bindings (field 7).

## Example 2: Amazon and Meta only

Spec: `exposure_sources = ["amazon", "meta"]`, `digital_mapping` not asked (no `digital_pixel`).
Expected edits: delete the `snowplow` and `dtv` CTEs and their two `UNION ALL` branches; keep `PivotedCuts`, `amazon`, `meta`, `unioned_exposures` (two branches) and the final SELECT unchanged.
Validator: PASS. Bind only the macros left in the SQL.

## Example 3: failure the validator must catch

Spec as example 1, but someone changes `'custom_cut_1'` in `PivotedCuts`.
Expected: `FAIL: LOCKED: PivotedCuts block was modified or removed`. Builder fixes the SQL and re-validates; it never shows the failing SQL as final.

## Example 4: choosing the VMA mapping dataset

Datasets in the clean room: `PROD Value Mapping - Q3`, `PROD Value Mapping - Q4`, `Acme Amazon Exposure`, `Acme Meta Exposure`.
Expected: for the `@vma` row the builder lists both `PROD Value Mapping` datasets first, marked as VMA mapping datasets, and asks the user to choose (two matches, so no default). The other datasets are listed below them.
With a single match, that dataset is offered as the default. With no match, the builder stops and routes to `cleanroom-setup`.

## Example 5: error the builder must prevent and diagnose

Symptom: `Query has the following fields which are not defined in the question: digital_mapping -> creative_source_id, ...; uber -> ...`.
Causes in order of likelihood: (1) commented-out source blocks left in the SQL, because the server reads `@macros` inside comments; (2) column macros not declared (or declared with different spelling) in `dataTypes[].dataSetTypeFields`.
Expected behavior: submit copy has no comments (validator `--submit` PASS); column macros are listed as warnings and shown at the Review gate with the proposed column mapping; on this error the builder does one diagnosis pass and reports, never loops.

## Example 6: setup summary table at the Review gate

Default four sources (the template, comments stripped), datasets chosen. The table the builder shows before the SQL:

| Macro | Dataset name | Dataset ID | Creative join key | Property join key |
|---|---|---|---|---|
| snowplow_exposures | <dataset name> | <full dataset id> | se._ds_ad_name | se._ds_placement_id |
| adserver | <dataset name> | <full dataset id> | - | - |
| vma (VMA mapping) | PROD Value Mapping ... | <full dataset id> | - | - |
| amazon | <dataset name> | <full dataset id> | @amazon.ad_id | @amazon.ad_id |
| dtv | <dataset name> | <full dataset id> | @dtv.PUBLISHER | @dtv.PUBLISHER |
| meta | <dataset name> | <full dataset id> | @meta.ad_id | @meta.placement_type |
| meta_camp / meta_adset / meta_ad | <dataset name> | <full dataset id> | - | - |

Keys come from `scripts/summarize_question.py`. With `uber` or `digital_mapping` selected, their keys show the mapped dataset column (for example `ad_id (mapped)`).

## Example 7: date parameters

Meta selected. Expected create payload: `hasDateParameters: true`, `queryValidation: false`, `parameters: []`. Not expected: any `parameters` entry named `START_DATE` or `END_DATE`, `hasDateFilter`, or `queryValidation: true`.
Why: with validation on, the server rejects the `@START_DATE` / `@END_DATE` macros before the toggle exists. With validation off and the toggle on, the question is created with the Date Parameters toggle on and each date parameter once (confirmed live in the clean room UI). Declaring them in `parameters` instead leaves duplicates in the Parameters panel.
After creation, ask the user to confirm in the clean room UI that each date parameter appears once; the MCP read-back does not list them for this question.

## Example 9: output format and output fields

Expected create payload: `outputFormat: "REPORT"`, 17 `dimensions` (15 `STRING`, then `min_exposure_date` and `max_exposure_date` as `DATE`) and 1 `measures` entry (`total_exposures`, `LONG`). Not expected: `CODE_OUTPUT`, empty `dimensions` / `measures`, or the date columns as measures.
Why: a `CODE_OUTPUT` question with no declared output fields never loaded into Clean Room Intelligence (`NOT_LOADED`), and a run on it returned a row count but no columns. After creation, `cleanroom_get_question_by_id` must list all 17 dimensions and the metric.

## Example 8: dates at run time

Runner asks once for `start_date` = 2026-09-01 and `end_date` = 2026-09-30 and fans the one pair out to `START_DATE` / `END_DATE` plus every source's own `_start` / `_end` partition key (for example `amazon.record_date_start` = `2026-09-01 00:00:00`). Non-date values (app id, brand) come from `run-configs/`, and `vma.bfmt_partition` is asked from the user at every run. The server does not derive any of these. Full list: `skills/cleanroom-question-runner/references/partition-parameters.md`.


## Example 10: no ad server data

Spec: `digital_pixel` selected, `adserver_data`: no.
Expected edits: `python3 scripts/remove_adserver.py` is run on the SQL. In the `snowplow` CTE both `LEFT JOIN @adserver` clauses are gone and `creative_name`, `placement_name`, `campaign_name` are `CAST(NULL AS STRING)`; nothing else changes. Validator: PASS. The submit SQL contains no `@adserver`, so the setup summary table has no `adserver` row and the user is never asked for an ad server dataset.
Not expected: leaving `@adserver` in the SQL and binding a dummy dataset, or hand-editing the joins.

## Example 11: TikTok source

Spec: `exposure_sources = ["digital_pixel", "amazon", "meta", "uber", "tiktok"]`.
Expected edits: uncomment the `tiktok` CTE and its `UNION ALL` branch in `unioned_exposures`; everything else as for the other selected sources. Validator: PASS, no column-macro warning for `tiktok` (plain `@tiktok.<column>` references).
Setup summary row: `tiktok | <dataset name> | <full dataset id> | @tiktok.ad_id | @tiktok.adgroup_id`.
Column names are written for `tiktok_habu_lcr-tiktok_kdp_xmi_exposures_v1` (`adgroup_id`, `adgroup_name`). The non-v1 dataset calls the id `ad_group_id`, so compare the bound dataset's fields with the CTE before the Review gate. Not yet live-trialed.

## Example 11: a source that is not built in (Snapchat)

Spec: field 3 includes `other`; field 8: `name` Snapchat, `dataset` a CONFIGURED dataset. The builder reads the dataset's fields and proposes `creative_id` = `ad_id`, `property_id` = `adgroup_id`, `campaign_id` = `campaign_id`, `creative_name` = `ad_name`, `date_column` = `impression_ts` (LONG epoch seconds, so `date_kind: epoch_seconds`, `date_filter: sql`); the user confirms it at the Review gate.
Expected edit: `python3 scripts/add_exposure_source.py question.sql question.sql spec.json` adds a `snapchat` CTE (label `snapchat_direct`, publisher `'snapchat'`, ids cast to STRING, missing name columns `CAST(NULL AS STRING)`, `WHERE ... BETWEEN '@START_DATE' AND '@END_DATE'`) before `unioned_exposures` and one `UNION ALL` branch at its end. Validator: PASS with one expected warning, `macro @snapchat is not in the template`. `@snapchat` then appears in the dataset-bindings table and the setup summary; `hasDateParameters` is true.
Not expected: hand-written SQL for the source, a guessed mapping applied without showing it, or `TikTok` added this way (it is built in: select it in field 3).
Same example with a DATE column that is a configured date partition: `date_filter: partition`; the CTE has no date filter and the runner submits `snapchat.<date_column>_start` / `_end`.
