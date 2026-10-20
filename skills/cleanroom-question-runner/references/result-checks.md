# Result checks (step 8)

Run every check; report each as pass / warn / fail with one line. Thresholds are starting values, confirm them in the first live trial and edit here.

Generic (any question):
1. **Row count.** 0 rows = fail. Otherwise report the count.
2. **Null rate per column.** Report columns with more than 5% nulls (warn) and columns that are 100% null (fail).
3. **Duplicate rows.** Count fully duplicated rows; any = warn.
4. **Column set.** Compare the columns to the question's declared dimensions and measures; any missing = fail.

Cross-platform exposure mapping question (the builder's template):
5. **VMA mapping coverage.** Share of rows where `channel`, `publisher`, `property` or `creative` is null. Over 10% on any = warn (unmapped ids; check VMA coverage). Report by `exposure_source`.
6. **Exposure totals.** `total_exposures` must be positive in every row; any zero or negative = fail.
7. **Date range.** Report `min_exposure_date` and `max_exposure_date` per source. For Meta, they must fall inside the `START_DATE` / `END_DATE` used; outside = fail.
8. **Source presence.** Every exposure source selected in `question_spec.json` appears in `exposure_source`; a missing source = fail. Label mapping: `digital_pixel` -> `digital_pixel`, `amazon` -> `amazon_direct`, `meta` -> `meta_direct`, `dtv` -> `dtv`, `uber` -> `uber_direct`.
