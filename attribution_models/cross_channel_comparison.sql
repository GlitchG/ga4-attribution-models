-- Cross-Channel Attribution Comparison
-- Compares 6 models side by side: Last Click, First Click, Last Non-Direct,
-- Linear, Time Decay, and Position-Based
-- All models use the same 30-day lookback and conversion cycle boundaries
-- Features: user stitching, multi-conversion cycles

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

WITH all_events AS (
  SELECT
    user_pseudo_id,
    user_id,
    event_name,
    event_timestamp,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS medium
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
    e.medium
  FROM all_events e
  JOIN user_stitching u ON e.user_pseudo_id = u.user_pseudo_id
  WHERE e.source IS NOT NULL
),
-- Touchpoints within conversion cycle + 30-day lookback
touchpoint_window AS (
  SELECT
    c.blended_user_id,
    c.conversion_timestamp,
    c.conversion_number,
    t.channel,
    t.event_timestamp,
    t.source,
    t.medium,
    -- Exclude direct/none for last non-direct model
    NOT (t.source = '(direct)' OR t.medium = '(none)') AS is_non_direct,
    ROW_NUMBER() OVER (
      PARTITION BY c.blended_user_id, c.conversion_number 
      ORDER BY t.event_timestamp ASC
    ) AS touch_order_asc,
    ROW_NUMBER() OVER (
      PARTITION BY c.blended_user_id, c.conversion_number 
      ORDER BY t.event_timestamp DESC
    ) AS touch_order_desc,
    COUNT(*) OVER (
      PARTITION BY c.blended_user_id, c.conversion_number
    ) AS total_touchpoints
  FROM conversions c
  JOIN touchpoints t
    ON c.blended_user_id = t.blended_user_id
    AND t.event_timestamp <= c.conversion_timestamp
    AND (c.prev_conversion_timestamp IS NULL OR t.event_timestamp > c.prev_conversion_timestamp)
    AND t.event_timestamp >= c.conversion_timestamp - (30 * 24 * 60 * 60 * 1000000)
),
all_channels AS (
  SELECT DISTINCT channel FROM touchpoint_window
),
-- Last Click: 100% to the touchpoint closest to conversion
last_click AS (
  SELECT channel, COUNT(*) AS weighted
  FROM touchpoint_window WHERE touch_order_desc = 1
  GROUP BY 1
),
-- First Click: 100% to the first touchpoint in the window
first_click AS (
  SELECT channel, COUNT(*) AS weighted
  FROM touchpoint_window WHERE touch_order_asc = 1
  GROUP BY 1
),
-- Last Non-Direct: 100% to the last non-direct touchpoint
-- Falls back to last click if no non-direct touchpoints exist in the window
last_non_direct AS (
  SELECT
    channel,
    COUNT(*) AS weighted
  FROM (
    SELECT
      blended_user_id, conversion_number, channel,
      ROW_NUMBER() OVER (
        PARTITION BY blended_user_id, conversion_number
        ORDER BY CASE WHEN is_non_direct THEN 0 ELSE 1 END, event_timestamp DESC
      ) AS rn
    FROM touchpoint_window
  )
  WHERE rn = 1
  GROUP BY 1
),
-- Linear: 1/N credit per touchpoint (N = total touchpoints in conversion cycle)
linear AS (
  SELECT channel, SUM(1.0 / total_touchpoints) AS weighted
  FROM touchpoint_window
  GROUP BY 1
),
-- Time Decay: exponential decay, half-life = 7 days
time_decay AS (
  SELECT
    channel,
    SUM(POWER(0.5, (conversion_timestamp - event_timestamp) / (7.0 * 24 * 60 * 60 * 1000000))) AS weighted
  FROM touchpoint_window
  GROUP BY 1
),
-- Position-Based (U-Shaped): 40% first, 40% last, 20% middle split evenly
-- Edge cases: 1 touch = 100%, 2 touches = 50/50
position_based AS (
  SELECT
    channel,
    SUM(
      CASE
        WHEN total_touchpoints = 1 THEN 1.0
        WHEN total_touchpoints = 2 THEN 0.5
        WHEN touch_order_asc = 1 THEN 0.4
        WHEN touch_order_desc = 1 THEN 0.4
        ELSE 0.2 / (total_touchpoints - 2)
      END
    ) AS weighted
  FROM touchpoint_window
  GROUP BY 1
)
SELECT
  ac.channel,
  COALESCE(lc.weighted, 0) AS last_click_weighted,
  COALESCE(fc.weighted, 0) AS first_click_weighted,
  COALESCE(lnd.weighted, 0) AS last_non_direct_weighted,
  ROUND(COALESCE(ln.weighted, 0), 2) AS linear_weighted,
  ROUND(COALESCE(td.weighted, 0), 2) AS time_decay_weighted,
  ROUND(COALESCE(pb.weighted, 0), 2) AS position_based_weighted,
  ROUND(COALESCE(lc.weighted, 0) * 100.0 / NULLIF(SUM(lc.weighted) OVER(), 0), 2) AS last_click_pct,
  ROUND(COALESCE(fc.weighted, 0) * 100.0 / NULLIF(SUM(fc.weighted) OVER(), 0), 2) AS first_click_pct,
  ROUND(COALESCE(lnd.weighted, 0) * 100.0 / NULLIF(SUM(lnd.weighted) OVER(), 0), 2) AS last_non_direct_pct,
  ROUND(COALESCE(ln.weighted, 0) * 100.0 / NULLIF(SUM(ln.weighted) OVER(), 0), 2) AS linear_pct,
  ROUND(COALESCE(td.weighted, 0) * 100.0 / NULLIF(SUM(td.weighted) OVER(), 0), 2) AS time_decay_pct,
  ROUND(COALESCE(pb.weighted, 0) * 100.0 / NULLIF(SUM(pb.weighted) OVER(), 0), 2) AS position_based_pct
FROM all_channels ac
LEFT JOIN last_click lc ON ac.channel = lc.channel
LEFT JOIN first_click fc ON ac.channel = fc.channel
LEFT JOIN last_non_direct lnd ON ac.channel = lnd.channel
LEFT JOIN linear ln ON ac.channel = ln.channel
LEFT JOIN time_decay td ON ac.channel = td.channel
LEFT JOIN position_based pb ON ac.channel = pb.channel
ORDER BY last_click_weighted DESC
LIMIT 50;
