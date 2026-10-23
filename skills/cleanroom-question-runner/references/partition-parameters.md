# Partition parameters (how a run is submitted)

`cleanroom_create_question_run` takes `name` and a flat string map `parameters`. The server does **not** derive per-source partition values from the run dates. Every source's partition values must be submitted explicitly, or the dataset is read with empty bounds and the run fails (confirmed: Amazon failed after ~50 min with `record_date >= '' AND record_date <= ''`, "Could not cast literal "" to type TIMESTAMP").

These keys are the same for every client; only the values change. Key format: `<macro>.<field>`; date partitions add `_start` / `_end`. Include a source's keys only if its macro is bound to the question (`cleanroom_get_all_question_datasets`).

## Runtime parameters (always, when the question has the Date Parameters toggle)

| Key | Value |
|---|---|
| `START_DATE` | `YYYY-MM-DD` |
| `END_DATE` | `YYYY-MM-DD` |

Upper case. The run read-back shows `START_DATE` / `END_DATE`.

## Per exposure source

| Source (macro) | Key | Value format | Per run or saved |
|---|---|---|---|
| `amazon` | `amazon.record_date_start` | `YYYY-MM-DD 00:00:00` | dates: every run |
| | `amazon.record_date_end` | `YYYY-MM-DD 23:59:59` | dates: every run |
| `snowplow_exposures` (digital pixel) | `snowplow_exposures._lr_event_date_utc_start` | `YYYY-MM-DD` | dates: every run |
| | `snowplow_exposures._lr_event_date_utc_end` | `YYYY-MM-DD` | dates: every run |
| | `snowplow_exposures.app_id` | client's app id | saved in `run-configs/` |
| `uber` | `uber.event_date_start` | `YYYY-MM-DD` | dates: every run |
| | `uber.event_date_end` | `YYYY-MM-DD` | dates: every run |
| | `uber.brand` | brands joined by a bare comma, no space: `A,B,C` | saved in `run-configs/` |
| `tiktok` | `tiktok.exposure_date_start` | `YYYY-MM-DD` | dates: every run (unconfirmed) |
| | `tiktok.exposure_date_end` | `YYYY-MM-DD` | dates: every run (unconfirmed) |
| | `tiktok.brand` | brands joined by a bare comma, no space: `A,B,C` | saved in `run-configs/` (unconfirmed) |
| `vma` | `vma.bfmt_partition` | the user's whole number, as a string (for example `"141"`) | asked at every run (`vma_bfmt_partition` in `run-inputs.md`), never saved or defaulted; needed whenever the `vma` dataset is bound |
| a custom source (`question_spec.json` -> `custom_sources`) with `date_filter: partition` | `<macro>.<date_column>_start` / `_end` | `YYYY-MM-DD` for DATE, `YYYY-MM-DD 00:00:00` / `23:59:59` for TIMESTAMP (unconfirmed) | dates: every run; any non-date partition field is asked once and saved in `run-configs/` |
| a custom source with `date_filter: sql` | none | filtered in the SQL by `@START_DATE` / `@END_DATE` | the question's Date Parameters toggle supplies them |
| `meta`, `dtv` | not yet confirmed | | Meta is filtered in the SQL by `@START_DATE` / `@END_DATE`; read a UI run's Partition Parameters before adding keys |

Amazon timestamps must be `YYYY-MM-DD HH:MM:SS`. The UI's display format `2026-09-01, 12:00:00 AM` is rejected by the API ("unable to parse date"). The API validates formats before creating the run, so a bad format fails instantly and costs nothing.

## Example (run 2026-10-01 to 2026-10-10)

```json
{
  "START_DATE": "2026-10-01",
  "END_DATE": "2026-10-10",
  "amazon.record_date_start": "2026-10-01 00:00:00",
  "amazon.record_date_end": "2026-10-10 23:59:59",
  "snowplow_exposures._lr_event_date_utc_start": "2026-10-01",
  "snowplow_exposures._lr_event_date_utc_end": "2026-10-10",
  "snowplow_exposures.app_id": "<client app id>",
  "uber.event_date_start": "2026-10-01",
  "uber.event_date_end": "2026-10-10",
  "uber.brand": "<brand 1>,<brand 2>",
  "vma.bfmt_partition": "<user's partition, e.g. 141>"
}
```

## Build rules
- Ask for one `start_date` / `end_date` pair; fan it out to every `_start` / `_end` key above (Amazon with the time suffixes).
- Non-date values (`app_id`, `brand`) come from `run-configs/`; `vma.bfmt_partition` is asked from the user at every run.
- After the run is created, read it back with `cleanroom_get_question_run_by_id` and confirm every key submitted appears in `parameters`. A missing key means it was not applied.
- Confirm a new source's keys by running once and reading the run's Partition Parameters in the UI, then add them here.
