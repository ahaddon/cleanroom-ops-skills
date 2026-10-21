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

