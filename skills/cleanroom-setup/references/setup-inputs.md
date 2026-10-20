# Setup inputs

Ask exactly these, in this order, in one message. Gated fields are asked only when their condition holds.

| # | Field | Type | Required | Allowed values / source | Default |
|---|---|---|---|---|---|
| 1 | `name` | string | yes | free text | none |
| 2 | `type` | single-select | yes | `Hybrid`, `Snowflake`, `Databricks`, `Google`, `AWS`, `Facebook`, `AMC`, `ADH`, `LinkedIn`, `HabuConfidentialComputing` | `Hybrid` |
| 3 | `cloud` | single-select | yes | `CLOUD_AWS`, `CLOUD_GCP`, `CLOUD_AZURE` | none |
| 4 | `region` | single-select | yes | `REGION_US`, `REGION_EU`, `REGION_APAC`, `REGION_AFRICA`, `REGION_UAE` | none |
| 5 | `sub_region` | single-select | only if the user wants to pick one | valid pairs: AWS+US -> `SUB_REGION_EAST2`; AWS+UAE -> `SUB_REGION_ME_CENTRAL1`; GCP+US -> `SUB_REGION_EAST1` or `SUB_REGION_CENTRAL1`; GCP+APAC -> `SUB_REGION_SOUTHEAST1`; GCP+EU -> `SUB_REGION_EU_WEST4` | omit (server picks) |
| 6 | `start_date`, `end_date` | dates | start yes, end optional | `YYYY-MM-DD` | none |
| 7 | `flags` | multi-select | yes | `ENABLE_HABU_INTELLIGENCE`, `ENABLE_EXPORT`, `ENABLE_VIEW_QUERY`, `ENABLE_PAIR`, `ENABLE_OPJA` (sent as `"true"`/`"false"` strings) | all false |
| 8 | `crowd_size`, `data_decibel` | numeric strings | no | positive integers | omit |
| 9 | `users` | list | no | `email` (must be an org user) + `role` chosen from `cleanroom_get_roles` | none |
| 10 | `partners` | list | no | `partnerAdminEmail`, optional `invitationNote`. Emails must be given by the user | none |
| 11 | `datasets` | list | no | per item: data connection (from `cleanroom_get_all_data_connections`, stage must be `CONFIGURATION_COMPLETE`), `rampIDConsent` (yes/no), excluded or renamed fields, row filters (`EQUALS`, `NOT_EQUALS`, `IN`, `NOT_IN`), `partnerCanAssign` (yes/no) | consent no, partnerCanAssign no |

Validation: end date on or after start date; sub-region only from the valid pairs; a data connection with stage `MAPPING_REQUIRED` cannot be provisioned (tell the user to finish its field mapping first); `ENABLE_HABU_INTELLIGENCE` is needed for the Intelligence dashboards to work in this clean room.

Unconfirmed until a live trial: which flags are standard for the internal use case, and default role names. Record confirmed values here.
