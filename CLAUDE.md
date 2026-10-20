# CLAUDE.md

Internal skill package for LiveRamp clean-room operations. Not a software project: no build or test commands. "Development" means editing skill markdown and validating it live against a clean room through the `liveramp-cleanroom-mcp` server.

Modeled on `coreydevin/intelligence-mcp-xmi` (thin `SKILL.md` with numbered rules and a pipeline, lazy-loaded `references/`, per-clean-room cache).

## Skills (see `skills/`)

- `cleanroom-ops-router` - fixed-menu entry point that hands off to the skills below.

- `cleanroom-question-builder` - written against the real tools (create question, bind datasets, verify READY); not yet live-trialed. Inputs live in `references/question-inputs.md`; `scripts/validate_question.py` enforces the locked regions; worked cases in `references/examples.md`. Builds a clean-room question from user inputs using the general template in `references/cross-platform-exposure-mapping.sql` (SQL with `@macro` columns, a hardcoded Meta date filter, a standardized VMA `PivotedCuts` block that must not be modified).
- `cleanroom-question-runner` - runs a READY question, polls, pulls rows, applies `references/result-checks.md`. Not yet live-trialed.
- `cleanroom-setup` - create a clean room, add users, provision datasets, invite partners. Plan gate plus a gate per outward-facing step; consent and partner-assignable default to no. Not yet live-trialed.

`.claude/skills/<name>` symlinks to `skills/<name>`.

## Consistency design (copy this for new skills)

- One field schema per skill (`references/<x>-inputs.md`); the skill asks exactly those fields, in order, in one batched prompt.
- Numbered pipeline with an explicit exit condition per step, and a Finalize checklist with a fixed completion report.
- Output built from a template file, with locked regions enforced by a script, not by prose.
- Review gate with fixed wording before every write.
- State passed between skills as files in `.cleanroom-ops-cache/<clean_room_id>/`.
- `scripts/test_validate.sh` must print PASS after any change to the template or validator.

## Rules

- Server: `liveramp-cleanroom-mcp` (`cleanroom_*`, plus `meta_get_active_org_ids`; pass the same `org_id` on every call).
- Name only MCP tools that are present in the live tool list (match the `cleanroom_*` suffix; names carry a server prefix).
- Never change macro names in the question template; only the underlying column mapping in the clean room config changes.
- Live trial against a sandbox clean room before a change counts as done. Do not simulate.
- Per-clean-room cache and any client data stay gitignored.
