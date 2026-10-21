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

Keys are the exact `<macro>.<field>` names the run API takes (for example `snowplow_exposures.app_id`, `uber.brand`); the runner submits them as-is. Multi-value fields such as `uber.brand` are one string, values joined by a bare comma. Date keys and `vma.bfmt_partition` are not stored here; see `skills/cleanroom-question-runner/references/partition-parameters.md`.

Teammates get changes by `git pull`. After the runner updates a file, commit and push it (the runner reminds the user; it never pushes). Check files with `python3 scripts/check_run_configs.py`.
