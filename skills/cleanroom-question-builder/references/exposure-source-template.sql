-- GENERIC EXPOSURE SOURCE TEMPLATE (used by scripts/add_exposure_source.py; not a question by itself)
--
-- Two fragments, separated by the "@@" marker lines. The script fills every <PLACEHOLDER>,
-- inserts the CTE before `unioned_exposures` and the branch at the end of `unioned_exposures`.
-- Never hand-edit these in a question; change the spec and re-run the script.
-- Output columns, their order and their types are fixed: every source must emit exactly the
-- 11 columns below, or the UNION ALL breaks.
--
-- Placeholders:
--   <MACRO>               dataset macro / CTE name, snake_case (tiktok)
--   <SOURCE_LABEL>        value of exposure_source in the results (tiktok_direct)
--   <PUBLISHER>           literal publisher_id (tiktok)
--   <CREATIVE_ID_COLUMN>  dataset column holding the creative/ad id (the id VMA maps)
--   <PROPERTY_ID_COLUMN>  dataset column holding the placement/ad group id (the id VMA maps)
--   <CAMPAIGN_ID_COLUMN>  dataset column holding the campaign id
--   <CREATIVE_NAME_EXPR>, <PLACEMENT_NAME_EXPR>, <CAMPAIGN_NAME_EXPR>
--                         CAST(@<MACRO>.col AS STRING), or CAST(NULL AS STRING) when the dataset has none
--   <DATE_EXPR>           the date column as a DATE (see date_kind in references/new-exposure-source.md)
--   <DATE_FILTER>         `WHERE <DATE_EXPR> BETWEEN '@START_DATE' AND '@END_DATE'` when date_filter = sql, else removed
--
-- @@ CTE
<MACRO> AS (
    SELECT
        '<SOURCE_LABEL>' AS exposure_source,
        CAST(@<MACRO>.<CREATIVE_ID_COLUMN> AS STRING) AS creative_source_id,
        CAST(@<MACRO>.<PROPERTY_ID_COLUMN> AS STRING) AS property_source_id,
        '<PUBLISHER>' AS publisher_id,
        CAST(@<MACRO>.<CAMPAIGN_ID_COLUMN> AS STRING) AS campaign_id,
        <CREATIVE_NAME_EXPR> AS creative_name,
        <PLACEMENT_NAME_EXPR> AS placement_name,
        <CAMPAIGN_NAME_EXPR> AS campaign_name,
        COUNT(*) AS exposures,
        MIN(<DATE_EXPR>) AS min_date,
        MAX(<DATE_EXPR>) AS max_date
    FROM @<MACRO>
    <DATE_FILTER>
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
)
-- @@ UNION
    UNION ALL
    SELECT exposure_source, creative_source_id, property_source_id, publisher_id, campaign_id,
           creative_name, placement_name, campaign_name, exposures, min_date, max_date,
           creative_source_id AS vma_creative_join_key
    FROM <MACRO>
