# Clean-room ops skills

Claude Code skills that walk you through clean-room operations the same way every time: build a question, run it and check the results, and set up a clean room. Internal use only.

| Skill | What it does |
|---|---|
| `cleanroom-ops-router` | Entry point. Shows a fixed menu and hands off to the skill below |
| `cleanroom-question-builder` | Collects a fixed set of inputs, generates SQL from the cross-platform exposure mapping template, validates it, and creates and binds the question after you confirm |
| `cleanroom-question-runner` | Runs a READY question, waits for it, pulls the rows and applies a fixed set of result checks |
| `cleanroom-setup` | Creates a clean room, adds users, provisions datasets and invites partners, with a plan first and a confirmation before each outward-facing step |

## Setup

1. Install [Claude Code](https://claude.com/claude-code) (CLI, desktop app or IDE extension).
2. Connect the `liveramp-cleanroom-mcp` server in your Claude connector settings. Each person connects their own; the skills never hardcode an organization or clean room.
3. Clone this repo and open Claude Code inside the folder:
   ```bash
   git clone git@github.com:ahaddon/cleanroom-ops-skills.git
   cd cleanroom-ops-skills
   ```
   The skills are picked up from `.claude/skills/` (symlinks to `skills/`). Python 3 is needed for the validator.
4. Check the validator works; it should print `PASS`:
   ```bash
   bash scripts/test_validate.sh
   ```

## Using it

Ask in plain language, for example "build a new exposure mapping question for <client>", "run the question I just built", or "set up a new clean room". Claude asks for the inputs in one message, shows what it will do, and waits for a yes before anything is created, run or sent.

- If you work in more than one LiveRamp organization, Claude asks which one at the start and keeps it for the whole task.
- Setup never invites an email you didn't give it, and consent and partner-assign settings default to no.
- Partner invitations stay pending until the partner accepts in their own organization.

## Where things are saved

Working files go in `.cleanroom-ops-cache/<clean-room-id>/` (the question spec and SQL, last run id, and result rows). This folder is gitignored. Do not commit it or result data.

Shared across the team (committed): `run-configs/<clean-room-id>/<question-id>.json` holds each question's non-date partition values (for example a source's app id or brand), so the next person to run the question gets them as defaults and only confirms them. Dates are never saved; the runner asks for them every run. After the runner updates a file, commit and push it, and `git pull` before running so you have the latest values. See `run-configs/README.md`.

## For people editing this repo

- `CLAUDE.md` describes the layout and the rules for changing skills.
- Each skill has a `SKILL.md` (rules and a numbered pipeline) and a `references/` folder (input schema, template, checks, examples). Add a new per-client variable to the skill's input schema first.
- Locked SQL regions (`PivotedCuts`, the Meta date filter, macro names) are enforced by `scripts/validate_question.py`. Run `bash scripts/test_validate.sh` after any change to the template or validator.
- A change is not done until it passes a live trial against a sandbox clean room. Record confirmed values in the skill's `examples.md` or inputs file.
