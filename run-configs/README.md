# Saved run configs (shared, committed)

One JSON file per question: `run-configs/<clean_room_id>/<question_id>.json`. The runner (`cleanroom-question-runner`) reads it for default partition values and writes it when a user changes them.

Contains only the non-date partition values that stay the same run over run (for example a source's `app_id` or `brand`). Never put dates, result rows, run ids, credentials or personal data here. The repo is private; keep it that way.

Format:
```json
{
  "clean_room_id": "<uuid>",
  "clean_room_name": "<name>",
  "question_id": "<uuid>",
  "question_title": "<title>",
  "partitions": { "<macro>.<field>": "<value>" },
  "updated_at": "YYYY-MM-DD"
}
```

Teammates get changes by `git pull`. After the runner updates a file, commit and push it (the runner reminds the user; it never pushes). Check files with `python3 scripts/check_run_configs.py`.
