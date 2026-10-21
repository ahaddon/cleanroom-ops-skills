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
| 7 | `dataset_bindings` | table | yes, one row per `@macro` in the final SQL | `macro`, `dataset` (pick from the clean room's CONFIGURED datasets), `importDataType` (default `Generic`) | none | Not written into the SQL. Becomes `dataTypes` on create and the bindings on `configure_question_datasets`. Macros are listed from the final SQL by the builder, never typed by the user |

## VMA mapping dataset (field 7, the `@vma` macro)

The VMA mapping dataset's name always starts with `PROD Value Mapping`. When listing candidate datasets for the `@vma` row:
- Always include every dataset whose name starts with `PROD Value Mapping` (case-insensitive match on that prefix), read from `cleanroom_get_datasets`.
- List those first and mark them as the VMA mapping datasets. Other CONFIGURED datasets may still appear below them, since the user may need a different one.
- If exactly one dataset matches the prefix, offer it as the default for `@vma`. If several match, ask the user to choose and do not pick one. If none match, say so plainly and stop; route to `cleanroom-setup` to provision it.
- A match must still have `configurationStatus = CONFIGURED`. A prefix match that is not CONFIGURED is shown with its status and cannot be selected.
- Never hardcode a dataset id or the full dataset name; only the prefix is fixed.

Fixed values, never asked: category `Analytics`, outputFormat `CODE_OUTPUT`, queryLanguage `SQL`, cleanRoomType `Hybrid`, `queryValidation` true, `hasDateParameters` true when `meta` is selected (parameters `START_DATE` and `END_DATE`, type date).

## Pre-flight facts to confirm for the clean room (ask once, store in the cache)
- Datasets for each selected source are already in the clean room with `configurationStatus = CONFIGURED` (read with `cleanroom_get_datasets`). If not, stop and route to `cleanroom-setup`.
- VMA dataset (`@vma`, and `@vma_partition` if field 5 = yes) is present. See "VMA mapping dataset" above.
- The working organization (`meta_get_active_org_ids`); never switch mid-task without the user confirming.

## Unconfirmed until the first live trial
- Which `importDataType` each macro needs (`Generic` is the starting default).
- Whether the question-level date parameters need extra settings beyond `hasDateParameters`.
Record confirmed answers in `examples.md` after the trial.

## Validation rules
- Field 3 must contain at least one source.
- Field 4 only asked when `digital_pixel` is selected.
- Field 6 only asked when `meta` is selected; end date must be on or after start date.
- Field 1 must match a UUID pattern.
