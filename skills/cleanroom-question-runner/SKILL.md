---
name: cleanroom-question-runner
description: Use when the user wants to run an existing clean-room question (for example one created by cleanroom-question-builder) and check the results. Selects a READY question, confirms the run, executes it, waits for completion, pulls the result rows, and runs a fixed set of data-quality checks before reporting.
---

# Clean-Room Question Runner

Run a clean-room question and check its output the same way every time. Tools are the `cleanroom_*` tools of `liveramp-cleanroom-mcp`; always pass the same `org_id` from `meta_get_active_org_ids`.

## Non-negotiable rules

1. **Follow the pipeline in order; never skip a step.**
2. **Ask only the fields in `references/run-inputs.md`, in that order, in one batched prompt.**
3. **Only a `READY` question is run.** If it is not READY, stop and route to `cleanroom-question-builder` (unbound datasets) or `cleanroom-setup` (missing datasets).
4. **No run without the Run gate (step 4).** A "yes" covers that exact question, run name and parameters only.
5. **Aggregate output only.** Report counts, rates and summaries. Never echo raw identifier-like or PII-like values from result rows.
6. **Never retry a failed run automatically.** Report `failureReason` and `isRetryable`; a retry is a new Run gate.
7. **Run the checks in `references/result-checks.md`, all of them, and report every result.** Do not drop a check because it passed or because the data looks fine.
8. **Name only tools present in the live tool list.** If one is missing, stop with: "A required tool isn't available on this server: <tool>."

## Pipeline

1. **Check tools and organization.** Confirm `cleanroom_get_all_questions`, `cleanroom_get_question_by_id`, `cleanroom_create_question_run`, `cleanroom_get_question_run_by_id` and `cleanroom_get_question_run_data` are available. Call `meta_get_active_org_ids` (one org: use it and say which; several: ask).
   *Exit:* tools and `org_id` recorded.
2. **Gather inputs.** Read `references/run-inputs.md`. If the question id is in `.cleanroom-ops-cache/<clean_room_id>/question_spec.json`, offer it as the default. Otherwise list questions with `cleanroom_get_all_questions` and let the user pick.
   *Exit:* every required field has a value.
3. **Verify the question.** `cleanroom_get_question_by_id`: status must be `READY`. If the question has date parameters (the Date Parameters toggle), `start_date` and `end_date` are required user inputs; they are submitted under exactly those names, as `YYYY-MM-DD`. One pair applies to every exposure source's date partition (the server fills each source's partition start/end from it), so never ask per source. Any other parameter the question reports also needs a value.
   *Exit:* READY and parameters complete.
3.5. **Partition values.** Read `run-configs/<clean_room_id>/<question_id>.json` if it exists (see `run-configs/README.md`). Partition fields come from the question's bound datasets (`cleanroom_get_all_question_datasets`, `cleanroom_get_dataset_by_id`). With saved values, show them as defaults in one line and ask "Same as last time? (yes / change)". Without, ask once for each non-date partition field. Never save dates. If any value changed or the file is new, write the file (same schema as `run-configs/README.md`), run `python3 scripts/check_run_configs.py`, and after the run tell the user to commit and push the file so teammates get it. Never run `git push` or `git commit` yourself.
   *Exit:* every partition field has a value.
4. **Run gate.** Show question name, run name, `start_date`, `end_date`, the partition values, any other parameters, and organization. Ask exactly: "Run this question now? (yes / change something / stop)".
   *Exit:* yes.
5. **Execute.** `cleanroom_create_question_run` with the run name and parameters. Save the run id to `.cleanroom-ops-cache/<clean_room_id>/last_run.json`.
6. **Wait.** Poll `cleanroom_get_question_run_by_id` until the run reaches a terminal status, with increasing pauses between polls (start at 30 seconds, cap at 5 minutes). On a failed status, report `failureReason`, `runMessage`, `isRetryable` and stop.
   *Exit:* run completed successfully, or failure reported.
7. **Pull results.** `cleanroom_get_question_run_data`, following `nextCursor` until `hasMore` is false. Write rows to `.cleanroom-ops-cache/<clean_room_id>/run_<run id>.json` (gitignored).
8. **Check results.** Apply every check in `references/result-checks.md`.
9. **Finalize (hard gate).** Confirm each item, then print the report:
   - [ ] question was READY
   - [ ] Run gate answered yes
   - [ ] run completed (id, status)
   - [ ] all rows pulled (count)
   - [ ] every check reported

   Report sections, always in this order: Run (question, run id, status, parameters), Rows (count, date range), Checks (one line each, pass / warn / fail), Next step.

## References
- `references/run-inputs.md` - fields asked in step 2.
- `references/result-checks.md` - the fixed check list for step 8.
- The `cleanroom-qa` skill, if installed, can do a deeper null-rate, duplicate, schema-drift and volume-drift pass on the same run; offer it as the next step but do not replace these checks with it.
