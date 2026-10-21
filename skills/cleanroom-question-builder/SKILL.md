---
name: cleanroom-question-builder
description: Use when the user wants to create a new clean-room question from the cross-platform exposure mapping template (unions exposure data from digital pixel, Amazon, Meta, DTV and Uber, then maps creative and property ids to LiveRamp VMA cuts). Collects a fixed set of inputs, generates SQL from the template without touching locked regions, validates it, and creates the question in the clean room only after explicit confirmation.
---

# Clean-Room Question Builder

Turn a fixed set of user inputs into a clean-room question built from `references/cross-platform-exposure-mapping.sql`. The flow is identical for every user: same fields, same order, same gates.

## Non-negotiable rules

1. **Follow the pipeline in order. Never skip, reorder or merge steps.** Each step ends only when its exit condition is true.
2. **Ask only the fields in `references/question-inputs.md`, in that order, worded as written there.** Never invent a field. Never skip a required one. A field gated on another (e.g. field 4, field 6) is asked only when its condition holds.
3. **The template is the only source of SQL.** Start from the template file verbatim, then apply only the edits the input table allows. Never write SQL from memory.
4. **Locked regions are never edited:** the `PivotedCuts` block, the Meta `@START_DATE`/`@END_DATE` filter, and every `@macro` name. Enabling or disabling the commented VMA partition filter (field 5) is a comment toggle, not an edit.
5. **Remove unselected source CTEs and their `UNION ALL` branches; keep selected ones unchanged.** Do not alter source CTE logic.
6. **Validate before showing and before writing.** `scripts/validate_question.py` must print PASS. On FAIL, fix the SQL and re-run; never present SQL that has not passed.
7. **No write without confirmation.** Creating or updating a question in a clean room requires the Review gate (step 5) to be answered "yes" for that exact SQL. A "yes" never carries over to a later change.
8. **Name only tools present in the live tool list** (match the `cleanroom_*` suffix; real names carry a server prefix). If the tool needed in step 6 is absent, stop with the fixed message in step 6; do not improvise another path.
9. **VMA dataset candidates always include datasets whose name starts with `PROD Value Mapping`**, listed first, per `references/question-inputs.md` -> "VMA mapping dataset". Never hardcode a dataset id.
10. **Never ask the user for an id a tool can supply.** The one id that needs a lookup is `organizationID`; resolve it with the ordered steps in `references/question-inputs.md` -> "Organization UUID", and ask only as the last step, once.
11. **Plain output.** Show the user the inputs, the SQL, and results of the checks. Do not narrate internals or offer extras.

## Pipeline

1. **Check tools and organization.** Confirm `cleanroom_create_question`, `cleanroom_configure_question_datasets`, `cleanroom_get_question_by_id` and `cleanroom_get_datasets` are in the live tool list. Call `meta_get_active_org_ids`: one org means use it and say which; more than one means ask which before any other call. Then resolve `organizationID` (UUID) per `references/question-inputs.md`; do it now so a missing UUID never interrupts step 6. If unavailable, continue steps 2-5 and finish with the fixed fallback in step 6.
   *Exit:* tool availability, `org_id` and `organizationID` recorded.
2. **Gather inputs.** Read `references/question-inputs.md`. Ask every applicable field in ONE message (use multiple-choice prompts for enumerable fields). Load any saved answers from `.cleanroom-ops-cache/<clean_room_id>/question_spec.json` as defaults, and say they are defaults.
   *Exit:* every required, applicable field has a value that passes the validation rules.
3. **Write the spec.** Save the answers to `.cleanroom-ops-cache/<clean_room_id>/question_spec.json`.
   *Exit:* file exists and matches the fields in `question-inputs.md`.
4. **Generate and validate SQL.** Copy the template to `.cleanroom-ops-cache/<clean_room_id>/question.sql`, apply the edits from the input table (rule 5), then run:
   ```bash
   python3 scripts/validate_question.py .cleanroom-ops-cache/<clean_room_id>/question.sql
   ```
   Then make the submit copy and validate it too:
   ```bash
   python3 scripts/prepare_submit_sql.py .cleanroom-ops-cache/<clean_room_id>/question.sql .cleanroom-ops-cache/<clean_room_id>/question.submit.sql
   python3 scripts/validate_question.py .cleanroom-ops-cache/<clean_room_id>/question.submit.sql --submit
   ```
   The server reads `@macros` inside SQL comments, so commented-out blocks (an unused `digital_mapping`, `uber`, the VMA partition filter) make creation fail with "fields not defined in the question". Only `question.submit.sql` (no comments) is shown at the gate and sent in step 6. Build the dataset-bindings list (field 7) and any column-macro fields from the submit copy, never from the annotated copy.
   *Exit:* both validator runs end with `PASS`. Warnings (including any column macros needing declared fields) are shown to the user in step 5.
5. **Review gate.** Present, in this exact order: (a) the inputs table, (b) the final submit SQL, (c) any validator warnings, (d) the dataset bindings from field 7. Then ask exactly: "Create this question in this clean room? (yes / change something / stop)".
   *Exit:* the user answered yes. "Change something" returns to step 2 for that field, then re-runs steps 3-5.
6. **Create and bind the question** (tools are the `cleanroom_*` tools of `liveramp-cleanroom-mcp`; always pass the same `org_id` from `meta_get_active_org_ids`).
   a. `cleanroom_create_question` with the approved SQL, title `<client_name> - Cross-Platform Exposure Mapping`, the fixed values from `question-inputs.md`, and `dataTypes` built from field 7 (each entry needs `macro`, `importDataType`, `datasetID`). The question lands in `MISSING_DATASETS`; it is not runnable yet.
   b. `cleanroom_configure_question_datasets` with one entry per macro (`macro`, `datasetId`, plus `fields` if the question's data types declare fields). Leave `darForce` false; if analysis-rule validation rejects the binding, show the error and stop. Never retry with `darForce` true without the user asking.
   c. `cleanroom_get_question_by_id` and confirm `status` is `READY`. If it is `MISSING_OWNER_DATASET_FIELDS` or similar, run `cleanroom_get_all_question_datasets`, show which fields are unmapped, and stop.
   **Column macros.** If the validator warned about `@table.@column` macros, that table's `dataTypes` entry must declare each column as `dataSetTypeFields` (see `references/question-inputs.md` -> "Column macros"). If `cleanroom_create_question` returns "fields which are not defined in the question", stop after one diagnosis pass: (1) confirm the submit copy has no comments, (2) compare the declared field names to the error text character for character, (3) read-only: look at how an existing question in this clean room declares them. Do not retry blindly more than once, and never loop. Report what was tried and the exact error.
   If `cleanroom_create_question` is absent from the tool list, say exactly: "The question-creation tool isn't available on this server. The SQL is saved at `.cleanroom-ops-cache/<clean_room_id>/question.sql` for manual loading." and go to step 7.
   Save the returned question id to `question_spec.json`.
   *Exit:* status is `READY`, or the fallback message was shown, or a stop condition above was reported.
7. **Finalize (hard gate).** Before the last message, confirm each item and print the completion report:
   - [ ] spec saved
   - [ ] validator PASS
   - [ ] review gate answered yes
   - [ ] question created and `READY` (id) or fallback shown
   - [ ] dataset bindings listed
   - [ ] next step offered: run the question via `cleanroom-question-runner` (once that skill exists)

   Completion report sections, always in this order: Inputs, Question id and status or file path, Validator result, Dataset bindings, Next step.

## References
- `references/question-inputs.md` - field schema (read in step 2).
- `references/cross-platform-exposure-mapping.sql` - the template (read in step 4).
- `references/examples.md` - worked input -> output examples.
