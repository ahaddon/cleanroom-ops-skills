# Tester guide: clean-room ops skills in Claude Desktop

Time: about 45 minutes for a first full pass (setup 15, build a question 15, run it 15).
You will: get the repo, connect the clean-room server, build a question, run it, and tell us what broke.

## What you need before you start

- Claude Desktop, signed in.
- Access to the private GitHub repo `ahaddon/cleanroom-ops-skills` (ask the owner if you can't open it).
- A LiveRamp login that can use `liveramp-cleanroom-mcp` and can work in a **sandbox** clean room that has your test datasets, including a dataset whose name starts with `PROD Value Mapping`.
- Python 3 on your computer (macOS usually has it).
- Git on your computer, with GitHub access set up (SSH key or GitHub sign-in).

Do the first pass in a sandbox clean room, not a client clean room. Building a question and running it create real records.

## Part 1: One-time setup

1. **Connect the clean-room server.** In Claude Desktop connector settings, connect `liveramp-cleanroom-mcp` and sign in. If you belong to more than one organization, you will be asked which one to use later.
2. **Get the repo.** In a terminal (or GitHub Desktop):
   ```bash
   git clone git@github.com:ahaddon/cleanroom-ops-skills.git
   ```
   Note the folder it creates.
3. **Open it in the Code tab.** In Claude Desktop, open the **Code** tab and choose the `cleanroom-ops-skills` folder as the working folder. Always work from this folder.
4. **Check the skills loaded.** In the Code tab, type: `What skills do you have?`
   Pass: you see `cleanroom-ops-router`, `cleanroom-question-builder`, `cleanroom-question-runner` and `cleanroom-setup`.
   Fail: you don't. Confirm the working folder is the repo root, not a parent or subfolder.
5. **Check the safeguards work.** Type: `Run bash scripts/test_validate.sh`.
   Pass: the last line is `PASS`. Approve the command if asked.
6. **Check the server connection.** Type: `List my clean rooms.`
   Pass: you see your sandbox clean room. If you have more than one organization, Claude asks which one; choose your sandbox organization.

Before every session after this one, ask Claude to run `git pull` (or run it yourself) so you have the latest skills and saved values.

## Part 2: Build a question

Start by typing: `Build a new exposure mapping question.`

Claude follows a fixed flow. Expect these, in this order:

1. **One message asking for all inputs.** Typical answers:
   - Clean room: your sandbox clean room.
   - Client name: a test name (it becomes the question title: `<client> - Cross-Platform Exposure Mapping`).
   - Exposure sources: pick the ones your sandbox has data for.
   - Digital mapping: answer as asked.
2. **Dataset choices.** For each data source Claude lists your datasets. For the VMA mapping, the datasets starting with `PROD Value Mapping` appear first and are marked. Pick the right one.
3. **Setup summary table.** Check every row before saying yes: macro, dataset name, dataset ID, creative join key, property join key. A row showing `NOT MAPPED` means a column mapping is missing; Claude will not continue until it is fixed.
4. **The final SQL**, plus any warnings.
5. **The confirmation:** "Create this question in this clean room? (yes / change something / stop)". Nothing is created until you answer yes.
6. **Result:** the question is created, its datasets are bound, and its status becomes `READY`. Claude then prints a completion report.

Checkpoints:
- The SQL has no comment lines in it (the server reads text inside comments).
- Date parameters are switched on in the question, once each: one `START_DATE` and one `END_DATE`, no duplicates. Open the question in the clean-room UI and look at its Parameters panel.
- The question's status in the UI is `READY`.

You never need to look up an organization ID or paste an ID. If Claude asks you for one, that is a bug: report it.

## Part 3: Run the question

Start by typing: `Run the question I just built.`

1. Claude lists your questions or offers the one you just built. Choose it.
2. **Dates.** Enter a start date and an end date (`YYYY-MM-DD`). One pair applies to all exposure sources.
3. **Partition values.** These are the non-date values that rarely change, such as a source's app id or brand. First time: you enter them. After that: Claude shows saved values and asks "Same as last time? (yes / change)".
4. **Run confirmation.** Claude shows the question, dates, partition values and organization, then asks "Run this question now? (yes / change something / stop)". Nothing runs until you say yes.
5. **Wait.** Claude checks the run until it finishes. Large runs can take several minutes.
6. **Results report.** You get row counts, the date range, and a pass / warn / fail line for each data check. Raw rows are not printed.

Checkpoint: every check has a result line, and the run's start and end dates match what you entered.

## Part 4: Share partition values with the team

If Claude created or changed a file in `run-configs/`, it will tell you at the end. Commit and push it so teammates get the same defaults:
```bash
git add run-configs && git commit -m "Update run config" && git push
```
Only partition values are stored there. Never add dates, results or credentials.

## Things that should never happen

Report any of these immediately:
- Claude creates, runs or sends something before you answered yes.
- Claude asks you for an ID it should look up itself (organization ID, dataset ID).
- Claude edits the locked parts of the SQL (the value-mapping block or the Meta date filter).
- Claude invites someone or changes a clean room without a plan and confirmation (setup skill).
- A step is skipped or the flow order differs from this guide.

## If something goes wrong

| Symptom | What to do |
|---|---|
| Skills don't appear | Working folder is not the repo root; reopen it. Run `git pull`. |
| `test_validate.sh` doesn't print PASS | Python 3 missing or repo out of date. Run `git pull`, install Python 3, retry. |
| Clean rooms don't list | Reconnect `liveramp-cleanroom-mcp`, restart the session, make sure you chose the right organization. |
| Error: fields not defined in the question | Copy the full error text and send it. Do not retry more than once. |
| A dataset you expect is missing from the list | It is not configured in that clean room yet. Ask whoever owns the datasets. |
| Question status is not `READY` | Copy the message Claude shows and send it. Don't run it. |
| Run fails | Copy the failure reason Claude shows; Claude will not retry on its own. |

## What to send back

For each part, tell us: did it pass, what you typed, and anything that surprised you. Include screenshots of any confusing prompt, and full text of any error. Also tell us:
- Time each part took.
- Any question Claude asked that you didn't understand.
- Any step where you weren't sure what to do next.
