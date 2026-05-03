-- Unified Attribution Dashboard Query
-- Run this directly in Looker Studio as a Custom Query data source,
-- or create a view in your BigQuery project and connect Looker to it.
--
-- Output: one row per (model, channel) with attributed conversions and percentage.
-- Models included: Last Click, First Click, Last Non-Direct, Linear, Time Decay, Position-Based.
-- Uses the public GA4 sample — to use with your own data, replace the dataset name below.

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

-- ============================================================================
-- Shared base: all touchpoints within 30-day lookback of each conversion
-- ============================================================================
WITH all_events AS (
  SELECT
    user_pseudo_id,
    user_id,
    event_name,
    event_timestamp,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS medium,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'campaign') AS campaign
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
),
user_stitching AS (
  SELECT DISTINCT
    user_pseudo_id,
    LAST_VALUE(user_id IGNORE NULLS) OVER (
      PARTITION BY user_pseudo_id ORDER BY event_timestamp
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS blended_user_id
  FROM all_events
),
conversions AS (
  SELECT
    e.user_pseudo_id,
    u.blended_user_id,
    e.session_id,
    e.event_timestamp AS conversion_timestamp,
    ROW_NUMBER() OVER (PARTITION BY u.blended_user_id ORDER BY e.event_timestamp) AS conversion_number,
    LAG(e.event_timestamp) OVER (PARTITION BY u.blended_user_id ORDER BY e.event_timestamp) AS prev_conversion_timestamp
  FROM all_events e
  JOIN user_stitching u ON e.user_pseudo_id = u.user_pseudo_id
  WHERE e.event_name = 'purchase'
),
touchpoints AS (
  SELECT
    e.user_pseudo_id,
    u.blended_user_id,
    e.event_timestamp,
    CONCAT(e.source, ' / ', e.medium) AS channel,
    e.source,
    e.medium,
    e.campaign
  FROM all_events e
  JOIN user_stitching u ON e.user_pseudo_id = u.user_pseudo_id
  WHERE e.source IS NOT NULL
),
touchpoint_window AS (
  SELECT
    c.blended_user_id,
    c.conversion_timestamp,
    c.conversion_number,
    t.channel,
    t.event_timestamp,
    t.source,
    t.medium,
    t.campaign,
    ROW_NUMBER() OVER (PARTITION BY c.blended_user_id, c.conversion_number ORDER BY t.event_timestamp ASC)  AS touch_asc,
    ROW_NUMBER() OVER (PARTITION BY c.blended_user_id, c.conversion_number ORDER BY t.event_timestamp DESC) AS touch_desc,
    COUNT(*) OVER (PARTITION BY c.blended_user_id, c.conversion_number) AS total_touches
  FROM conversions c
  JOIN touchpoints t
    ON c.blended_user_id = t.blended_user_id
    AND t.event_timestamp <= c.conversion_timestamp
    AND (c.prev_conversion_timestamp IS NULL OR t.event_timestamp > c.prev_conversion_timestamp)
    AND t.event_timestamp >= c.conversion_timestamp - (30 * 24 * 60 * 60 * 1000000)
),

-- ============================================================================
-- Model 1: Last Click
-- ============================================================================
last_click AS (
  SELECT 'Last Click' AS model, channel, COUNT(*) AS conversions
  FROM touchpoint_window WHERE touch_desc = 1
  GROUP BY 2
),

-- ============================================================================
-- Model 2: First Click
-- ============================================================================
first_click AS (
  SELECT 'First Click' AS model, channel, COUNT(*) AS conversions
  FROM touchpoint_window WHERE touch_asc = 1
  GROUP BY 2
),

-- ============================================================================
-- Model 3: Last Non-Direct Click (falls back to last click if no non-direct)
-- ============================================================================
last_non_direct AS (
  SELECT 'Last Non-Direct' AS model, channel, COUNT(*) AS conversions
  FROM (
    SELECT channel, blended_user_id, conversion_number,
      ROW_NUMBER() OVER (
        PARTITION BY blended_user_id, conversion_number
        ORDER BY CASE WHEN NOT (source = '(direct)' OR medium = '(none)') THEN 0 ELSE 1 END, event_timestamp DESC
      ) AS rn
    FROM touchpoint_window
  ) WHERE rn = 1
  GROUP BY 2
),

-- ============================================================================
-- Model 4: Linear (equal credit to all touchpoints)
-- ============================================================================
linear AS (
  SELECT 'Linear' AS model, channel, SUM(1.0 / total_touches) AS conversions
  FROM touchpoint_window
  GROUP BY 2
),

-- ============================================================================
-- Model 5: Time Decay (half-life = 7 days)
-- ============================================================================
time_decay AS (
  SELECT
    'Time Decay' AS model, channel,
    SUM(POWER(0.5, (conversion_timestamp - event_timestamp) / (7.0 * 24 * 60 * 60 * 1000000))) AS conversions
  FROM touchpoint_window
  GROUP BY 2
),

-- ============================================================================
-- Model 6: Position-Based (U-Shaped: 40/40/20)
-- ============================================================================
position_based AS (
  SELECT 'Position-Based' AS model, channel,
    SUM(CASE
      WHEN total_touches = 1 THEN 1.0
      WHEN total_touches = 2 THEN 0.5
      WHEN touch_asc = 1 THEN 0.4
      WHEN touch_desc = 1 THEN 0.4
      ELSE 0.2 / (total_touches - 2)
    END) AS conversions
  FROM touchpoint_window
  GROUP BY 2
),

-- ============================================================================
-- Union all models + compute percentage within each model
-- ============================================================================
unified AS (
  SELECT * FROM last_click
  UNION ALL SELECT * FROM first_click
  UNION ALL SELECT * FROM last_non_direct
  UNION ALL SELECT * FROM linear
  UNION ALL SELECT * FROM time_decay
  UNION ALL SELECT * FROM position_based
)

SELECT
  model,
  channel,
  ROUND(conversions, 4) AS attributed_conversions,
  ROUND(conversions * 100.0 / SUM(conversions) OVER (PARTITION BY model), 2) AS attribution_pct,
  SUM(conversions) OVER (PARTITION BY model) AS model_total_conversions
FROM unified
ORDER BY model, attributed_conversions DESC;
