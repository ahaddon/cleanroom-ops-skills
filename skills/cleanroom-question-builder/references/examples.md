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
  "vma_partition_filter": false,
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

Meta selected. Expected create payload: `hasDateParameters: true`, `parameters: []`. Not expected: any `parameters` entry named `START_DATE` or `END_DATE`.
Why: the toggle already creates `START_DATE` and `END_DATE`; declaring them as well leaves duplicates in the question's Parameters panel (confirmed by a screenshot of a question created that way).
After creation, `cleanroom_get_question_by_id` must show each date parameter once.

## Example 8: dates at run time

Runner asks once for `start_date` = 2026-09-01 and `end_date` = 2026-09-30 and submits `{"start_date": "2026-09-01", "end_date": "2026-09-30"}`. The one pair applies to every exposure source's date partition. The runner does not ask about non-date partition values (such as an app id or brand); those are dataset settings.

