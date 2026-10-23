---
name: cleanroom-ops-router
description: Use when the user asks for any clean-room operations task (build a question, run a question, set up a clean room, invite partners, provision datasets) and it is not yet clear which workflow applies. Presents a fixed menu and hands off to the matching skill.
---

# Clean-Room Ops Router

Single entry point so everyone starts the same way.

## Rules

1. Always present the same menu, in the same order, then hand off. Never answer an ops request directly without routing.
2. One workflow per request. A compound request is split into sequential workflows; confirm the order with the user.
3. Hand off by name; do not restate the target skill's steps.
4. State handed between skills lives on disk in `.cleanroom-ops-cache/<clean_room_id>/`, never in chat memory.
5. Freshness first. Step 0 must print `FRESH` before anything else. On `STALE` or `UNVERIFIED`, stop and show the script's message verbatim; never continue, and never offer to skip the check.

## Pipeline

0. Run `bash scripts/check_latest.sh` from the repo root first. It must print `FRESH`; on `STALE` or `UNVERIFIED` (non-zero exit), stop and show its message verbatim. Do not route or continue.
1. If the user's request clearly names one workflow, confirm it in one line and go to step 2. Otherwise ask, with a multiple-choice prompt, exactly:
   - Build a question (`cleanroom-question-builder`)
   - Run a question and check results (`cleanroom-question-runner`)
   - Set up a clean room, invite partners, provision datasets (`cleanroom-setup`)
2. Invoke the chosen skill.
