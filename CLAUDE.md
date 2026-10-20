# CLAUDE.md

Internal skill package for LiveRamp clean-room operations. Not a software project: no build or test commands. "Development" means editing skill markdown and validating it live against a clean room through the `liveramp-cleanroom-mcp` server.

Modeled on `coreydevin/intelligence-mcp-xmi` (thin `SKILL.md` with numbered rules and a pipeline, lazy-loaded `references/`, per-clean-room cache).

## Planned skills (see `skills/`)

- `cleanroom-question-builder` - builds a clean-room question from user inputs using the general template in `references/cross-platform-exposure-mapping.sql` (SQL with `@macro` columns, a hardcoded Meta date filter, a standardized VMA `PivotedCuts` block that must not be modified).
- `cleanroom-question-runner` - runs the question and checks results. (todo)
- `cleanroom-setup` - create a clean room, invite partner orgs, provision datasets. Hard confirm gate before every outward-facing action. (todo)

`.claude/skills/<name>` should symlink to `skills/<name>`.

## Rules

- Name only MCP tools that are present in the live tool list (match the `cleanroom_*` suffix; names carry a server prefix).
- Never change macro names in the question template; only the underlying column mapping in the clean room config changes.
- Live trial against a sandbox clean room before a change counts as done. Do not simulate.
- Per-clean-room cache and any client data stay gitignored.
