# Question inputs (single source of truth)

The builder asks for exactly these fields, in this order, worded as shown. It never invents fields and never skips a required one. Any new per-client variable must be added HERE first, then to `SKILL.md` if it changes the pipeline.

Template: `cross-platform-exposure-mapping.sql`. Locked regions (never edited): `PivotedCuts` block, the Meta `@START_DATE`/`@END_DATE` filter, all `@macro` names.

| # | Field | Type | Required | Allowed values / format | Default | Effect on the SQL |
|---|---|---|---|---|---|---|
| 1 | `clean_room_id` | string | yes | UUID of the clean room the question will be loaded into | none | Goes in the commented VMA partition filter's clean-room-id line only if the partition filter is enabled (field 5) |
| 2 | `client_name` | string | yes | free text, used for the question name only | none | Question title: `<client_name> - Cross-Platform Exposure Mapping` |
| 3 | `exposure_sources` | multi-select | yes (at least 1) | `digital_pixel`, `amazon`, `dtv`, `meta`, `uber` | `digital_pixel`, `amazon`, `meta`, `dtv` | Keep the CTE and its `UNION ALL` branch for each selected source; remove (not just comment) the rest. `uber` is a commented block in the template; uncomment it only when selected |
| 4 | `digital_mapping` | single-select | yes if `digital_pixel` selected | `adserver` (default join) or `premapped_file` | `adserver` | `premapped_file` enables the commented `digital_mapping` and `digital_joined` CTEs and unions `digital_joined` instead of `snowplow` |
| 5 | `vma_partition_filter` | boolean | yes | yes / no | no | yes = enable the `bfmt_partition` filter in `PivotedCuts` using `clean_room_id`. This is a comment toggle, not an edit to `PivotedCuts` logic |
| 6 | `meta_date_range` | start/end date | yes if `meta` selected | `YYYY-MM-DD` | none | Not written into the SQL. The `@START_DATE`/`@END_DATE` macros stay as-is; values are set as date parameters in the question editor |
| 7 | `macro_mappings` | table | yes per selected source | macro -> underlying dataset column, per source | none | Not written into the SQL. Handed to the user as a checklist for the clean room's dataset configuration UI |

## Pre-flight facts to confirm for the clean room (ask once, store in the cache)
- Datasets for each selected source are already provisioned in the clean room. If not, stop and route to `cleanroom-setup`.
- VMA dataset (`@vma`, and `@vma_partition` if field 5 = yes) is present.

## Validation rules
- Field 3 must contain at least one source.
- Field 4 only asked when `digital_pixel` is selected.
- Field 6 only asked when `meta` is selected; end date must be on or after start date.
- Field 1 must match a UUID pattern.
