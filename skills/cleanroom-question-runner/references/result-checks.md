# Result checks (step 8)

Run every check; report each as pass / warn / fail with one line. Thresholds are starting values, confirm them in the first live trial and edit here.

Generic (any question):
1. **Row count.** 0 rows = fail. Otherwise report the count.
2. **Null rate per column.** Report columns with more than 5% nulls (warn) and columns that are 100% null (fail).
3. **Duplicate rows.** Count fully duplicated rows; any = warn.
4. **Column set.** Compare the columns to the question's declared dimensions and measures; any missing = fail.

Cross-platform exposure mapping question (the builder's template):
5. **VMA mapping coverage.** Share of rows where each of the question's cut columns is null: `channel`, `property` and `publisher` always, plus the standard and custom cuts the user selected (`standard_cuts` and `custom_cuts` in `question_spec.json`; read the column names from the question's dimensions). Over 10% on any = warn (unmapped ids; check VMA coverage). A custom cut that is 100% null = warn: check that its `custom_cut_N` slot exists in the VMA map. Report by `exposure_source`.
6. **Exposure totals.** `total_exposures` must be positive in every row; any zero or negative = fail.
7. **Date range.** Report `min_exposure_date` and `max_exposure_date` per source. Every source's dates must fall inside the `start_date` / `end_date` used for the run; outside = fail.
8. **Source presence.** Every exposure source selected in `question_spec.json` appears in `exposure_source`; a missing source = fail. Label mapping: `digital_pixel` -> `digital_pixel`, `amazon` -> `amazon_direct`, `meta` -> `meta_direct`, `dtv` -> `dtv`, `uber` -> `uber_direct`. A custom source (`question_spec.json` -> `custom_sources`) appears as `<macro>_direct`.
