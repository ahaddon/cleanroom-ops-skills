# Worked examples

Each example is an input spec and the exact edits expected. Add new confirmed cases here, one per heading.

## Example 1: default four sources, adserver join

Spec:
```json
{
  "clean_room_id": "00000000-0000-0000-0000-000000000000",
  "client_name": "Acme",
  "exposure_sources": ["digital_pixel", "amazon", "meta", "dtv"],
  "digital_mapping": "adserver",
  "vma_partition_filter": false,
  "meta_date_range": {"start": "2026-01-01", "end": "2026-03-31"}
}
```
Expected SQL: the template unchanged. Validator: PASS, no warnings.
Question title: `Acme - Cross-Platform Exposure Mapping`.
Not in the SQL: the meta date range (passed as run parameters) and the dataset bindings (field 7).

## Example 2: Amazon and Meta only

Spec: `exposure_sources = ["amazon", "meta"]`, `digital_mapping` not asked (no `digital_pixel`).
Expected edits: delete the `snowplow` and `dtv` CTEs and their two `UNION ALL` branches; keep `PivotedCuts`, `amazon`, `meta`, `unioned_exposures` (two branches) and the final SELECT unchanged.
Validator: PASS. Bind only the macros left in the SQL.

## Example 3: failure the validator must catch

Spec as example 1, but someone changes `'custom_cut_1'` in `PivotedCuts`.
Expected: `FAIL: LOCKED: PivotedCuts block was modified or removed`. Builder fixes the SQL and re-validates; it never shows the failing SQL as final.
