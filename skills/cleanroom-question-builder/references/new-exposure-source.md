# Adding a new exposure source

Use this when the user has an exposure source that is not a built-in option of field 3 in `question-inputs.md` (built-ins: `digital_pixel`, `amazon`, `dtv`, `meta`, `uber`, `tiktok`). A built-in is selected normally; never add it as a custom source (`scripts/add_exposure_source.py` refuses it). The user picks `other` in field 3 and gives each custom source in field 8.

Never write a new source's SQL from memory. Fill the generic template (`references/exposure-source-template.sql`) with `scripts/add_exposure_source.py`, which inserts the CTE and the `UNION ALL` branch and refuses anything unsafe.

## Output contract (why the template is fixed)

Every source CTE emits exactly these 11 columns, in this order, because the sources are combined with `UNION ALL` and then joined to the VMA cuts:
`exposure_source, creative_source_id, property_source_id, publisher_id, campaign_id, creative_name, placement_name, campaign_name, exposures, min_date, max_date`.
- `creative_source_id` and `property_source_id` are the ids the VMA mapping uses (creative / ad level and placement / ad group level). They must match the ids in the client's VMA map, as strings.
- `exposure_source` is `<macro>_direct`; `publisher_id` is the macro as a literal.
- `exposures` is `COUNT(*)`; `min_date` / `max_date` are DATE.

## What to ask (field 8, once per custom source, in the same batched message)

1. **Platform name** (free text, for example "Snapchat"). The macro is its snake_case form (`snapchat`), the label `snapchat_direct`. If it matches a built-in, tell the user to select the built-in instead.
2. **Dataset** holding its exposures, picked from the CONFIGURED datasets (`cleanroom_get_datasets`).

Do not ask for column names. Read the dataset's fields (`cleanroom_get_dataset_by_id`), **propose** the mapping below, and show it at the Review gate for the user to correct. Never apply a guessed mapping without showing it.

| Spec key | Meaning | Required | If absent |
|---|---|---|---|
| `creative_id` | column with the creative / ad id (the id VMA maps) | yes | stop and ask; without it nothing can map to VMA |
| `property_id` | column with the placement / ad group id | no | defaults to `creative_id` |
| `campaign_id` | column with the campaign id | yes | stop and ask |
| `creative_name`, `placement_name`, `campaign_name` | name columns | no | `CAST(NULL AS STRING)` |
| `date_column` | the exposure date column | yes | stop and ask |
| `date_kind` | `date`, `timestamp` or `epoch_seconds` (read from the column's type: DATE, TIMESTAMP, LONG seconds) | yes | ask |
| `date_filter` | how the date range is applied, see below | no | `sql` |

If the names live in a separate metadata dataset (as Meta's do), the generic template cannot express the join. Stop, say so, and ask the user how to proceed; a hand-written source must still follow the output contract and pass the validator.

## Date handling (decide per source)

- `sql` (default): the CTE gets `WHERE <date> BETWEEN '@START_DATE' AND '@END_DATE'`, like Meta. Always works, because the Date Parameters toggle provides the two parameters. Set `hasDateParameters` to true when any source uses it.
- `partition`: choose it only when the user confirms the dataset has a date partition parameter and the partition field is `date_column`. The CTE gets no date filter; the runner submits `<macro>.<date_column>_start` / `_end` (see the runner's `partition-parameters.md`). If the dataset has no such partition, the run fails with empty bounds after a long wait, so never guess. An `epoch_seconds` column cannot be a partition (the script rejects it).

## Steps

1. Save each custom source's spec under `custom_sources` in `.cleanroom-ops-cache/<clean_room_id>/question_spec.json` (the runner reads `macro`, `date_column`, `date_kind`, `date_filter` from it).
2. After the other template edits, run once per source:
   `python3 scripts/add_exposure_source.py <question.sql> <question.sql> <spec.json>`
3. Validate (`scripts/validate_question.py`, then the submit copy with `--submit`). A warning "macro @<macro> is not in the template" is expected for a custom source; show it at the Review gate.
4. The new macro appears in field 7 (dataset bindings) and in the setup summary table automatically, because both are read from the SQL.
5. The results label for the new source is `<macro>_direct`; `result-checks.md` check 8 (source presence) must expect it.

## Status

Generated and validated locally; not yet live-trialed. After the first live run with a custom source, confirm in the run's Partition Parameters (UI) that the keys match what the runner submitted, and record the result here.
