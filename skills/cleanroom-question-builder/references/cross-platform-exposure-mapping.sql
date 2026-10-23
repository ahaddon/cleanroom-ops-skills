/* ============================================================================
   CROSS-PLATFORM EXPOSURE MAPPING TEMPLATE
   ============================================================================
   Unions exposure data from Snowplow/digital pixel, Amazon, Meta, Uber, and TikTok,
   then maps creative + property identifiers to LiveRamp VMA cuts.

   IMPLEMENTATION NOTES FOR NEW CLIENTS
   -------------------------------------------------------------------------

   1. MACRO COLUMNS (clean room config -- do NOT rename)
      Columns are referenced as @table.@macro_name (e.g. @snowplow_exposures.@creative_source_id).
      Map each macro to the correct underlying column inside the clean room's
      dataset configuration UI. Never change the macro name itself -- only
      what it points to.

   2. STANDARD ID NAMING (consistent across all sources)
        creative_source_id  = platform's ad/creative-level identifier - ID used for VMA mapping
        property_source_id  = platform's placement/adset/ad-group-level identifier - ID used for VMA mapping

   3. VMA / bfmt_partition logic is a standardized LiveRamp asset -- identical
      across all clients. Do not modify PivotedCuts.

   4. The Meta date filter (@START_DATE / @END_DATE) is intentionally
      hardcoded. Leave as-is.
   ============================================================================ */

WITH snowplow AS (
    SELECT
        'digital_pixel' AS exposure_source,
        se._ds_ad_name AS creative_source_id,
        se._ds_placement_id AS property_source_id,
        se._ds_publisher_id AS publisher_id,
        se._ds_campaign_id AS campaign_id,
        c_ads.creative AS creative_name,
        p_ads.placement AS placement_name,
        p_ads.campaign AS campaign_name,

        COUNT(*) AS exposures,
        MIN(se._lr_event_date_utc) AS min_date,
        MAX(se._lr_event_date_utc) AS max_date
    FROM @snowplow_exposures se LEFT JOIN @adserver p_ads on se._ds_placement_id = p_ads.placement_id
    LEFT JOIN @adserver c_ads on se._ds_ad_name = c_ads.creative_id
    GROUP BY 1, 2, 3, 4, 5,6,7,8
),
-- -- digital mapping - use this if a client is providing a file with pre-mapped columns
-- digital_mapping AS (
--     -- Example: FROM @digital_mapping  ->  FROM @acme_corp_digital_mapping
--     SELECT
--         @digital_mapping.@creative_source_id AS creative_source_id,
--         @digital_mapping.@creative_name AS creative_name,
--         @digital_mapping.@placement_name AS placement_name,
--         @digital_mapping.@campaign_name AS campaign_name
--     FROM @digital_mapping
-- ),

-- digital_joined AS (
--     SELECT
--         s.exposure_source,
--         s.creative_source_id,
--         s.property_source_id,
--         s.publisher_id,
--         s.campaign_id,
--         dm.creative_name,
--         dm.placement_name,
--         dm.campaign_name,
--         s.exposures,
--         s.min_date,
--         s.max_date
--     FROM snowplow s
--     LEFT JOIN digital_mapping dm
--         ON s.creative_source_id = dm.creative_source_id
--),

-- VMA mapping cuts: standardized LiveRamp asset, identical for every client. Do not modify.

-- Make sure to align source_id's in query for given dataset
PivotedCuts AS (
    SELECT
        map_id,
        MAX(CASE WHEN cut_name = 'campaign'  THEN map_name END) AS campaign,
        MAX(CASE WHEN cut_name = 'channel'   THEN map_name END) AS channel,
        MAX(CASE WHEN cut_name = 'property'  THEN map_name END) AS property,
        MAX(CASE WHEN cut_name = 'publisher' THEN map_name END) AS publisher,
        MAX(CASE WHEN cut_name = 'creative'  THEN map_name END) AS creative,
        MAX(CASE WHEN cut_name = 'custom_cut_1'  THEN map_name END) AS media_type,
        MAX(CASE WHEN cut_name = 'custom_cut_2'  THEN map_name END) AS audience_name
    FROM @vma
    --WHERE @vma.bfmt_partition = (SELECT MAX(@vma_partition.latest_bfmt_partition_value) FROM --@vma_partition -- @vma_partitions = new dataset in /L measurement solutions - XMI
       -- WHERE REPLACE(@vma_partition.cleanroom_id_with_underscores, '_', '-') = '9fa76c78-b478-4860-a8cc-8e00114273c6' )-- UPDATE: cleanroom ID of the cleanroom you are loading this question to. Grab from URL above
    GROUP BY map_id
),

amazon AS (
    SELECT
        'amazon_direct' AS exposure_source,
        @amazon.ad_id AS creative_source_id,
        @amazon.ad_id  AS property_source_id,
        'amazon' AS publisher_id,
        @amazon.order_id AS campaign_id,
        @amazon.creative_name AS creative_name,
        @amazon.ad_name AS placement_name,
        @amazon.campaign_name AS campaign_name,
        COUNT(*) AS exposures,
        MIN(CAST(@amazon.record_date AS date)) AS min_date,
        MAX(CAST(@amazon.record_date AS date)) AS max_date
    FROM @amazon
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
),

dtv AS (
    SELECT
        'dtv' AS exposure_source,
        @dtv.PUBLISHER AS creative_source_id,
        @dtv.PUBLISHER AS property_source_id,
        'dtv' AS publisher_id,
        @dtv.DSP_CAMPAIGN_ID AS campaign_id,
        'dtv' AS creative_name,
        'dtv' AS placement_name,
        'dtv' AS campaign_name,
        COUNT(*) AS exposures,
        MIN(CAST(@dtv.IMP_DATE AS date)) AS min_date,
        MAX(CAST(@dtv.IMP_DATE AS date)) AS max_date
    FROM @dtv
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
 ),

meta AS (
    SELECT
        'meta_direct' AS exposure_source,
        @meta.ad_id AS creative_source_id,
        @meta.placement_type AS property_source_id,
        'meta' AS publisher_id,
        @meta.campaign_id AS campaign_id,
        mad.ad_name AS creative_name,
        mads.adset_name AS placement_name,
        mc.campaign_name,
        COUNT(*) AS exposures,
        MIN(TO_DATE(TIMESTAMP_SECONDS(INT(@meta.ts)))) AS min_date,
        MAX(TO_DATE(TIMESTAMP_SECONDS(INT(@meta.ts)))) AS max_date
    FROM @meta
    LEFT JOIN @meta_camp mc ON @meta.campaign_id = mc.campaign_id
    LEFT JOIN @meta_adset mads ON @meta.adset_id = mads.adset_id
    LEFT JOIN @meta_ad mad ON @meta.ad_id = mad.ad_id
    -- Hardcoded date filter -- leave as-is for every client
    -- Enable date parameters in question editor
    WHERE TO_DATE(TIMESTAMP_SECONDS(INT(@meta.ts))) BETWEEN '@START_DATE' AND '@END_DATE'
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
),

--remove any exposure sources you do not require
-- uber AS (
--     SELECT
--         'uber_direct' AS exposure_source,
--         @uber.@creative_source_id AS creative_source_id,
--         @uber.@property_source_id AS property_source_id,
--         'uber' AS publisher_id,
--         @uber.campaign_id AS campaign_id,
--         @uber.creative_name AS creative_name,
--         @uber.placement_name AS placement_name,
--         @uber.campaign_name AS campaign_name,
--         COUNT(*) AS exposures,
--         MIN(@uber.event_date) AS min_date,
--         MAX(@uber.event_date) AS max_date
--     FROM @uber
--     GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
-- ),

-- tiktok AS (
--     SELECT
--         'tiktok_direct' AS exposure_source,
--         @tiktok.ad_id AS creative_source_id,
--         @tiktok.adgroup_id AS property_source_id,
--         'tiktok' AS publisher_id,
--         @tiktok.campaign_id AS campaign_id,
--         @tiktok.ad_name AS creative_name,
--         @tiktok.adgroup_name AS placement_name,
--         @tiktok.campaign_name AS campaign_name,
--         COUNT(*) AS exposures,
--         MIN(@tiktok.new_date) AS min_date,
--         MAX(@tiktok.new_date) AS max_date
--     FROM @tiktok
--     GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
-- ),

unioned_exposures AS (
    SELECT exposure_source, creative_source_id, property_source_id, publisher_id, campaign_id,
           creative_name, placement_name, campaign_name, exposures, min_date, max_date,
           creative_source_id AS vma_creative_join_key
    FROM snowplow
    UNION ALL
    SELECT exposure_source, creative_source_id, property_source_id, publisher_id, campaign_id,
           creative_name, placement_name, campaign_name, exposures, min_date, max_date,
           creative_source_id AS vma_creative_join_key
    FROM amazon
    UNION ALL
    SELECT exposure_source, creative_source_id, property_source_id, publisher_id, campaign_id,
           creative_name, placement_name, campaign_name, exposures, min_date, max_date,
           creative_source_id AS vma_creative_join_key
    FROM meta
    UNION ALL
    SELECT exposure_source, creative_source_id, property_source_id, publisher_id, campaign_id,
           creative_name, placement_name, campaign_name, exposures, min_date, max_date,
           creative_source_id AS vma_creative_join_key
    FROM dtv
    -- UNION ALL (Comment out any unions for exposure sources not required)
    -- SELECT exposure_source, creative_source_id, property_source_id, publisher_id, campaign_id,
    --        creative_name, placement_name, campaign_name, exposures, min_date, max_date,
    --        creative_source_id AS vma_creative_join_key
    -- FROM uber
    -- UNION ALL
    -- SELECT exposure_source, creative_source_id, property_source_id, publisher_id, campaign_id,
    --        creative_name, placement_name, campaign_name, exposures, min_date, max_date,
    --        creative_source_id AS vma_creative_join_key
    -- FROM tiktok
)

-- Final union + VMA mapping join
SELECT /*+ BROADCAST(vma_prop, vma_cr) */
    u.exposure_source,
    u.creative_source_id,
    u.property_source_id,
    u.publisher_id,
    u.campaign_id,
    u.creative_name,
    u.placement_name,
    u.campaign_name,
    SUM(u.exposures) AS total_exposures,
    MIN(u.min_date) AS min_exposure_date,
    MAX(u.max_date) AS max_exposure_date,
    case when u.exposure_source = 'meta' then ANY_VALUE(vma_cr.audience_name) else ANY_VALUE(vma_prop.audience_name) end AS audience_name,
    ANY_VALUE(vma_prop.channel) AS channel,
    ANY_VALUE(vma_prop.property) AS property,
    ANY_VALUE(vma_prop.publisher) AS publisher,
    ANY_VALUE(vma_prop.media_type) AS media_type,
    case when u.exposure_source = 'meta' then ANY_VALUE(vma_cr.campaign) else ANY_VALUE(vma_prop.campaign) END AS campaign,
    ANY_VALUE(vma_cr.creative) AS creative
FROM unioned_exposures u
LEFT JOIN PivotedCuts vma_prop ON u.property_source_id = vma_prop.map_id
LEFT JOIN PivotedCuts vma_cr ON u.vma_creative_join_key = vma_cr.map_id
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
