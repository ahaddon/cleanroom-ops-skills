# Run inputs

Ask exactly these, in this order, in one message. Field 3 is asked only when the question has date parameters or other parameters.

| # | Field | Type | Required | Format / source | Default |
|---|---|---|---|---|---|
| 1 | `clean_room_id` | string | yes | UUID | from `question_spec.json` if present |
| 2 | `question` | single-select | yes | list from `cleanroom_get_all_questions`; show title and status only | `question_id` in `question_spec.json` if present |
| 3 | `start_date`, `end_date` | dates | yes when the question has date parameters | `YYYY-MM-DD`; submitted as `start_date` and `end_date`; one pair for all exposure sources | none |
| 4 | `run_name` | string | yes | free text | `<question title> - <YYYY-MM-DD>` |

Validation: field 2 must be `READY`; dates must be valid, end on or after start. Partition values that are not dates (for example an app id or brand on a source dataset) are dataset settings, not run inputs; do not ask for them.
