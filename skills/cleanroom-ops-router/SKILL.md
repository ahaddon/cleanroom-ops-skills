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

## Pipeline

1. If the user's request clearly names one workflow, confirm it in one line and go to step 3. Otherwise ask, with a multiple-choice prompt, exactly:
   - Build a question (`cleanroom-question-builder`)
   - Run a question and check results (`cleanroom-question-runner`)
   - Set up a clean room, invite partners, provision datasets (`cleanroom-setup`)
2. Invoke the chosen skill.
