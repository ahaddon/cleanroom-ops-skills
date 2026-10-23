# Question inputs (single source of truth)

The builder asks for exactly these fields, in this order, worded as shown. It never invents fields and never skips a required one. Any new per-client variable must be added HERE first, then to `SKILL.md` if it changes the pipeline.

Template: `cross-platform-exposure-mapping.sql`. Locked regions (never edited): `PivotedCuts` block, the Meta `@START_DATE`/`@END_DATE` filter, all `@macro` names.

| # | Field | Type | Required | Allowed values / format | Default | Effect on the SQL |
|---|---|---|---|---|---|---|
| 1 | `clean_room_id` | string | yes | UUID of the clean room the question will be loaded into | none | Not written into the SQL. Identifies the clean room the question is created in |
| 2 | `client_name` | string | yes | free text, used for the question name only | none | Question title: `<client_name> - Cross-Platform Exposure Mapping` |
| 3 | `exposure_sources` | multi-select | yes (at least 1) | `digital_pixel`, `amazon`, `dtv`, `meta`, `uber`, `tiktok`, `other` (a platform not listed; asked for in field 8) | `digital_pixel`, `amazon`, `meta`, `dtv` | Keep the CTE and its `UNION ALL` branch for each selected source; remove (not just comment) the rest. `uber` and `tiktok` are commented blocks in the template; uncomment each (CTE and union branch) only when selected |
| 4 | `digital_mapping` | single-select | yes if `digital_pixel` selected | `adserver` (default join) or `premapped_file` | `adserver` | `premapped_file` enables the commented `digital_mapping` and `digital_joined` CTEs and unions `digital_joined` instead of `snowplow` |
| 5 | `adserver_data` | boolean | yes if `digital_pixel` selected | yes / no. Prompt text, exactly: "Are you currently using ad server data (an ad server data connection) for your digital pixel exposures?" | yes | no = remove the ad server joins from the `snowplow` CTE with `python3 scripts/remove_adserver.py <question.sql> <question.sql>` (never by hand): both `LEFT JOIN @adserver` clauses go and `creative_name`, `placement_name` and `campaign_name` become `CAST(NULL AS STRING)`. The `@adserver` macro is then absent, so field 7 never asks for an ad server dataset. A "no" overrides field 4's `adserver` choice. yes = no change |
| 6 | (reserved) | - | no | Dates are NOT asked at build time. They are entered when the question is run (`cleanroom-question-runner` field 3) as `start_date` and `end_date`, one pair for all exposure sources | - | Nothing. The Date Parameters toggle is on when `meta` is selected |
| 7 | `dataset_bindings` | table | yes, one row per `@macro` in the final SQL | `macro`, `dataset` (pick from the clean room's CONFIGURED datasets), `importDataType` (default `Generic`) | none | Not written into the SQL. Becomes `dataTypes` on create and the bindings on `configure_question_datasets`. Macros are listed from the final SQL by the builder, never typed by the user |
| 8 | `custom_sources` | table | yes if field 3 includes `other` | one row per platform: `name` (free text, for example "Snapchat") and `dataset` (a CONFIGURED dataset). Prompt text, exactly: "Which exposure source is it, and which dataset holds its exposures?" The column mapping is proposed from the dataset's fields and confirmed at the Review gate | none | Each row is added with `python3 scripts/add_exposure_source.py` from the generic template, never by hand. Rules, mapping table and date handling: `references/new-exposure-source.md` |


The VMA `bfmt_partition` is not a build-time input: it is a run-time partition parameter (`vma.bfmt_partition`) that `cleanroom-question-runner` asks for at every run (see its `references/partition-parameters.md`). The commented partition filter inside `PivotedCuts` stays commented and is never enabled.

## VMA mapping dataset (field 7, the `@vma` macro)

The VMA mapping dataset's name always starts with `PROD Value Mapping`. When listing candidate datasets for the `@vma` row:
- Always include every dataset whose name starts with `PROD Value Mapping` (case-insensitive match on that prefix), read from `cleanroom_get_datasets`.
- List those first and mark them as the VMA mapping datasets. Other CONFIGURED datasets may still appear below them, since the user may need a different one.
- If exactly one dataset matches the prefix, offer it as the default for `@vma`. If several match, ask the user to choose and do not pick one. If none match, say so plainly and stop; route to `cleanroom-setup` to provision it.
- A match must still have `configurationStatus = CONFIGURED`. A prefix match that is not CONFIGURED is shown with its status and cannot be selected.
- Never hardcode a dataset id or the full dataset name; only the prefix is fixed.

Fixed values, never asked: category `Analytics`, outputFormat **`REPORT`**, queryLanguage `SQL`, cleanRoomType `Hybrid`, `queryValidation` **false**, `hasDateParameters` true when `meta` is selected or any custom source uses the `sql` date filter, plus the dimensions and measures below.

- **outputFormat `REPORT` is required for results to load into Clean Room Intelligence.** `CODE_OUTPUT` questions never load (CRQ-234358 stayed `NOT_LOADED`).
- **`queryValidation` false is required when `@START_DATE` / `@END_DATE` are in the SQL.** With it true, the server's pre-save check rejects the question ("Query has the following dataset type which are not part of the question: END_DATE,START_DATE"), and neither `hasDateParameters` nor `hasDateFilter` avoids that. Confirmed live. Local validation (`scripts/validate_question.py`, both runs) is the guard instead, so it must pass before the Review gate.
- **Do not send `hasDateFilter`**; it made no difference.

## Output fields (dimensions and measures): always declared

The server builds the report table from the declared output fields, so a question with none has nothing to load. The UI's Extract Output Fields button fills them; through the MCP, send them explicitly in `cleanroom_create_question` as `dimensions` and `measures` (`name`, `type`). The template's final `SELECT` is the same for every source selection, so the list is fixed:

| Kind | Name | Type |
|---|---|---|
| dimension | `exposure_source`, `creative_source_id`, `property_source_id`, `publisher_id`, `campaign_id`, `creative_name`, `placement_name`, `campaign_name`, `audience_name`, `channel`, `property`, `publisher`, `media_type`, `campaign`, `creative` | `STRING` |
| dimension | `min_exposure_date`, `max_exposure_date` | `DATE` |
| measure | `total_exposures` | `LONG` |

Rules: date columns are always dimensions, never measures; measures are numeric only; names are the output column aliases exactly as written in the final `SELECT` (lower case). If the final `SELECT` ever changes, update this table in the same commit. Confirmed live: the question was created with this list, the UI's Extract Output Fields matched it, and `cleanroom_configure_question_datasets` (no `fields`, `darForce` false) bound all 9 plain macros and moved the status from `MISSING_DATASETS` to `READY`.

**Date parameters: only set the toggle (`hasDateParameters: true`). Never add `START_DATE` or `END_DATE` to the `parameters` array.** The server creates `START_DATE` and `END_DATE` itself when the toggle is on; declaring them again produces duplicate parameters in the question editor. Send `parameters` as an empty array (the default) for the exposure mapping template.

## Column macros (`@table.@column`)

Active SQL that uses `@table.@column` (the template's `digital_mapping` and `uber` blocks) needs more than a dataset binding: every column macro must be declared as a field on that table's `dataTypes` entry (`dataSetTypeFields`: `name` = the column macro name, `type` = the column type), and mapped to a real dataset column in `configure_question_datasets` `fields` (`name` = the macro name, `value` = the dataset column).

- Propose the mapping from the dataset's own field names (`cleanroom_get_dataset_by_id`), show it at the Review gate, and let the user correct it. Never apply a guessed mapping without showing it.
- Template macros per source: `digital_mapping` -> `creative_source_id`, `creative_name`, `placement_name`, `campaign_name`; `uber` -> `creative_source_id`, `property_source_id`.
- Plain table macros like `@snowplow_exposures`, `@amazon` or `@tiktok` (with ordinary columns after the dot) need no fields.
- `tiktok` uses plain column names (`ad_id`, `adgroup_id`, `adgroup_name`, `ad_name`, `campaign_id`, `campaign_name`, `exposure_date`), written for the KDP `tiktok_habu_lcr-tiktok_kdp_xmi_exposures_v1` dataset. They are dataset-specific: the non-v1 TikTok dataset names the ad group id `ad_group_id`, so binding it needs the column name changed and the validator re-run. Compare the bound dataset's fields (`cleanroom_get_dataset_by_id`) with the CTE before the Review gate.
- Not yet confirmed: how the server wants these declared. A first attempt that declared them as `dataSetTypeFields` was rejected with "fields which are not defined in the question: digital_mapping -> ..., uber -> ...". That attempt also sent SQL with comments, so retest with the comment-free submit copy first. Record the working shape here after a live trial.

## Organization UUID (`organizationID` on create): never ask for it first

`cleanroom_create_question` needs `organizationID`, the UUID of the working organization (the org named by `meta_get_active_org_ids`). That tool returns only a ULID (`org_id`) and a name, so the UUID must be looked up. Users are never asked for it unless every step below fails. Resolve in this order and stop at the first hit:
1. **Cache.** `.cleanroom-ops-cache/org.json`, keyed by the active `org_id`.
2. **Partner list.** `cleanroom_get_all_partners` for the clean room; use the entry whose `name` equals the active org's name; its `organizationId` is the UUID. This call needs the PartnerManagement permission and returns 403 without it, which is not an error for the user: go to the next step.
3. **Owner shortcut.** Only if `cleanroom_get_by_id` shows `ownerOrganization` equals the active org's name: take `ownerOrganizationId` from `cleanroom_get_question_by_id` on any existing question in that clean room (read it from the first page of `cleanroom_get_all_questions`).
4. **Ask once, in plain words.** "I couldn't look up your organization's UUID automatically. Please paste it once (your LiveRamp admin can provide it) and I'll remember it." Save the answer to `org.json`.

Never use the clean room owner's UUID unless the owner is the active org (step 3). Existing questions in a clean room owned by another organization carry that owner's UUID, not yours. Record the result in the cache with the org name, and never show the UUID back to the user beyond one confirmation line.

## Pre-flight facts to confirm for the clean room (ask once, store in the cache)
- Datasets for each selected source are already in the clean room with `configurationStatus = CONFIGURED` (read with `cleanroom_get_datasets`). If not, stop and route to `cleanroom-setup`.
- VMA dataset (`@vma`) is present. See "VMA mapping dataset" above.
- The working organization (`meta_get_active_org_ids`); never switch mid-task without the user confirming.

## Unconfirmed until the first live trial
- Which `importDataType` each macro needs (`Generic` is the starting default).
- Run-time dates are the runner's job, not the builder's. The server does not derive each source's date partition from the run dates; the runner submits every `<macro>.<field>_start` / `_end` key itself. See `skills/cleanroom-question-runner/references/partition-parameters.md`.
Record confirmed answers in `examples.md` after the trial.

## Validation rules
- Field 3 must contain at least one source.
- Field 4 only asked when `digital_pixel` is selected.
- Field 1 must match a UUID pattern.
