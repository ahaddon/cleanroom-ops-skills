# Run inputs

Ask exactly these, in this order, in one message. Field 3 is asked only when the question has date parameters or other parameters.

| # | Field | Type | Required | Format / source | Default |
|---|---|---|---|---|---|
| 1 | `clean_room_id` | string | yes | UUID | from `question_spec.json` if present |
| 2 | `question` | single-select | yes | list from `cleanroom_get_all_questions`; show title and status only | `question_id` in `question_spec.json` if present |
| 3 | `start_date`, `end_date` | dates | yes when the question has date parameters | `YYYY-MM-DD`; submitted as `start_date` and `end_date`; one pair for all exposure sources | none |
| 4 | `partition_values` | key/value, one per non-date partition field | yes for each partition field the datasets expose | defaults from `run-configs/<clean_room_id>/<question_id>.json`; first run: ask once per field | saved values, else none |
| 5 | `vma_bfmt_partition` | integer | yes when the question binds a `vma` dataset | digits only; submitted as `vma.bfmt_partition`. Prompt text, exactly: "Which BFMT partition should this run use? The latest BFMT partition can be found in measurement-enablement-prod bigquery project or from your latest XMI flow run" | none; never saved, never defaulted, because the latest partition changes |
| 6 | `run_name` | string | yes | free text | `<question title> - <YYYY-MM-DD>` |

Validation: field 2 must be `READY`; dates must be valid, end on or after start; `vma_bfmt_partition` must be a whole number (reject anything else and ask again, do not guess). Non-date partition values (for example a source's app id or brand) are run inputs, saved per question in `run-configs/` and shown as defaults at every run. Dates and `vma_bfmt_partition` are never saved; ask for them at every run.

Submission: dates and partition values go in the `parameters` map under fixed, source-specific keys (for example `amazon.record_date_start`). The server does not derive them from the run dates. The full key list, value formats and an example are in `partition-parameters.md`; build the map from that file.
