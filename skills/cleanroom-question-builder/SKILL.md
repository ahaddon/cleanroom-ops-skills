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
9. **Plain output.** Show the user the inputs, the SQL, and results of the checks. Do not narrate internals or offer extras.

## Pipeline

1. **Check tools.** Confirm the `liveramp-cleanroom-mcp` question-creation tool is available (step 6 names it). If unavailable, continue steps 2-5 and finish with the fixed fallback in step 6.
   *Exit:* tool availability recorded.
2. **Gather inputs.** Read `references/question-inputs.md`. Ask every applicable field in ONE message (use multiple-choice prompts for enumerable fields). Load any saved answers from `.cleanroom-ops-cache/<clean_room_id>/question_spec.json` as defaults, and say they are defaults.
   *Exit:* every required, applicable field has a value that passes the validation rules.
3. **Write the spec.** Save the answers to `.cleanroom-ops-cache/<clean_room_id>/question_spec.json`.
   *Exit:* file exists and matches the fields in `question-inputs.md`.
4. **Generate and validate SQL.** Copy the template to `.cleanroom-ops-cache/<clean_room_id>/question.sql`, apply the edits from the input table (rule 5), then run:
   ```bash
   python3 scripts/validate_question.py .cleanroom-ops-cache/<clean_room_id>/question.sql
   ```
   *Exit:* output ends with `PASS`. Warnings are shown to the user in step 5.
5. **Review gate.** Present, in this exact order: (a) the inputs table, (b) the final SQL, (c) any validator warnings, (d) the macro-mapping checklist from field 7. Then ask exactly: "Create this question in this clean room? (yes / change something / stop)".
   *Exit:* the user answered yes. "Change something" returns to step 2 for that field, then re-runs steps 3-5.
6. **Create the question.** Use the clean-room MCP question-creation tool with the approved SQL and the title `<client_name> - Cross-Platform Exposure Mapping`.
   *Tool name: TO BE FILLED once `liveramp-cleanroom-mcp` is connected and its tool list is read.* If the tool is absent, say exactly: "The question-creation tool isn't available on this server. The SQL is saved at `.cleanroom-ops-cache/<clean_room_id>/question.sql` for manual loading." and go to step 7.
   *Exit:* creation succeeded and returned an id, or the fallback message was shown.
7. **Finalize (hard gate).** Before the last message, confirm each item and print the completion report:
   - [ ] spec saved
   - [ ] validator PASS
   - [ ] review gate answered yes
   - [ ] question created (id) or fallback shown
   - [ ] macro-mapping checklist given
   - [ ] next step offered: run the question via `cleanroom-question-runner` (once that skill exists)

   Completion report sections, always in this order: Inputs, Question id or file path, Validator result, Macro-mapping checklist, Next step.

## References
- `references/question-inputs.md` - field schema (read in step 2).
- `references/cross-platform-exposure-mapping.sql` - the template (read in step 4).
- `references/examples.md` - worked input -> output examples.
