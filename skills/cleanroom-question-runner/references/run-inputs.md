# Run inputs

Ask exactly these, in this order, in one message. Fields 3 is asked only when the question defines parameters.

| # | Field | Type | Required | Format / source | Default |
|---|---|---|---|---|---|
| 1 | `clean_room_id` | string | yes | UUID | from `question_spec.json` if present |
| 2 | `question` | single-select | yes | list from `cleanroom_get_all_questions`; show title and status only | `question_id` in `question_spec.json` if present |
| 3 | `parameters` | key/value | only if the question defines parameters | one value per parameter; dates `YYYY-MM-DD` | none |
| 4 | `run_name` | string | yes | free text | `<question title> - <YYYY-MM-DD>` |

Validation: field 2 must be `READY`; date parameters must be valid dates and end must be on or after start.
