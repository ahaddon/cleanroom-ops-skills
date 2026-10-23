---
name: cleanroom-setup
description: Use when the user wants to set up a clean room - create it, invite partner organizations, add internal users, and provision datasets from data connections. Collects a fixed set of inputs, shows a full plan, and performs each outward-facing step only after explicit confirmation. Invitations stay pending until the partner accepts.
---

# Clean-Room Setup

Create a clean room and get it ready for questions. Tools are the `cleanroom_*` tools of `liveramp-cleanroom-mcp`; always pass the same `org_id` from `meta_get_active_org_ids`. These steps are outward-facing (partners receive emails, datasets are shared, consents are recorded), so the gates below are hard stops.

## Non-negotiable rules

1. **Follow the pipeline in order; never skip, reorder or merge steps.**
2. **Ask only the fields in `references/setup-inputs.md`, in that order, in one batched prompt.**
3. **Plan first, act second.** Step 4 prints the complete plan and makes no changes. Nothing is created before the Plan gate is answered yes.
4. **One gate per outward-facing action group, with fixed wording** (steps 5, 6, 7, 8). A yes covers exactly the items shown, not later ones.
5. **Never decide consents or permissions for the user.** `rampIDConsent` is asked as its own explicit yes/no per dataset and defaults to false. Partner assignment (`partnerCanAssign`) defaults to false.
6. **Never invite an email the user did not give in this session.** Never infer partner admin emails.
7. **Read before replace.** `cleanroom_update_dataset_by_id` replaces the whole field configuration. Always read the dataset first and resend every field.
8. **Stay in one organization.** Never switch `org_id` mid-task without the user confirming.
9. **Stop on error.** Report the error and the state reached so far (what exists, what does not). Never roll back or retry a write automatically.
10. **Name only tools present in the live tool list.** If one is missing, stop with: "A required tool isn't available on this server: <tool>."
11. **Freshness first.** Step 0 must print `FRESH` before anything else. On `STALE` or `UNVERIFIED`, stop and show the script's message verbatim; never continue, and never offer to skip the check.

## Pipeline

0. **Freshness gate.** Run `bash scripts/check_latest.sh` from the repo root. *Exit:* it prints `FRESH`. On `STALE` or `UNVERIFIED` (non-zero exit), stop and show its message verbatim; do not continue, retry in a loop, or offer a way around it. The user fixes the checkout (usually `git pull --ff-only origin main`) and starts again.
1. **Check tools and organization.** Confirm `cleanroom_create`, `cleanroom_add_partner`, `cleanroom_add_user`, `cleanroom_get_roles`, `cleanroom_get_all_data_connections`, `cleanroom_configure_dataset`, `cleanroom_update_dataset_by_id`, `cleanroom_get_datasets` and `cleanroom_list_partner_invitations_for_inviter` are available. Call `meta_get_active_org_ids` (one org: use it and say which; several: ask).
   *Exit:* tools and `org_id` recorded.
2. **Gather inputs.** Read `references/setup-inputs.md`. Ask every applicable field in one message. Read `cleanroom_get_roles` and `cleanroom_get_all_data_connections` first so role and data-connection choices are real options, not free text.
   *Exit:* every required field passes validation.
3. **Write the spec.** Save to `.cleanroom-ops-cache/setup/<name-slug>/setup_spec.json`.
4. **Plan gate.** Print the full plan in this order: clean room settings, users and roles, partner invitations (emails), datasets (data connection, filters, consent, partner-assignable), then what will NOT happen (partners are not added until they accept). Ask exactly: "Proceed with this plan? (yes / change something / stop)". No changes are made at this step.
   *Exit:* yes.
5. **Create the clean room.** Gate text: "Create clean room <name> (<type>, <cloud>/<region>)? (yes / stop)". On yes, `cleanroom_create`. Save the id to the spec.
6. **Add internal users.** One gate listing every email and role. On yes, `cleanroom_add_user` once per user, with `role` exactly as `cleanroom_get_roles` returned it.
7. **Provision datasets.** One gate per dataset: data connection, the `rampIDConsent` value, and filters. On yes: `cleanroom_configure_dataset`, then if fields or filters were requested read the dataset (`cleanroom_get_dataset_by_id`) and apply them with `cleanroom_update_dataset_by_id`, then read it back and confirm. Then `cleanroom_update_dataset_partner_assignment` only for datasets where the user said partners may assign.
8. **Invite partners.** One gate listing every email and the note text. On yes, `cleanroom_add_partner` once per partner. Then `cleanroom_list_partner_invitations_for_inviter` and report each status; `PENDING` is expected.
9. **Finalize (hard gate).** Confirm each item, then print the report:
   - [ ] Plan gate answered yes
   - [ ] clean room created (id)
   - [ ] users added (count)
   - [ ] datasets provisioned and read back (count, configurationStatus)
   - [ ] invitations sent (count, statuses)
   - [ ] nothing outside the plan was changed

   Report sections, always in this order: Clean room, Users, Datasets, Invitations, What happens next (partners accept in their own org; then build questions with `cleanroom-question-builder`).

## References
- `references/setup-inputs.md` - fields asked in step 2.
