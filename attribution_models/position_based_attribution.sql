-- Position-Based Attribution Model (U-Shaped)
-- Standard split: 40% first touch, 40% last touch, 20% distributed across middle touchpoints
-- Edge cases: 1 touchpoint = 100%, 2 touchpoints = 50/50, 3+ = 40/40/20 split
-- Features: user stitching, multi-conversion cycles, 30-day lookback

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

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
    e.source,
    e.medium,
    e.campaign
  FROM all_events e
  JOIN user_stitching u ON e.user_pseudo_id = u.user_pseudo_id
  WHERE e.source IS NOT NULL
),
conversion_paths AS (
  SELECT
    c.blended_user_id,
    c.session_id AS conversion_session_id,
    c.conversion_timestamp,
    c.conversion_number,
    ARRAY_AGG(
      STRUCT(
        t.source,
        t.medium,
        t.campaign,
        ROW_NUMBER() OVER (
          PARTITION BY c.blended_user_id, c.conversion_number 
          ORDER BY t.event_timestamp
        ) AS touch_position,
        COUNT(*) OVER (
          PARTITION BY c.blended_user_id, c.conversion_number
        ) AS total_touchpoints
      )
    ) AS touchpoints_array
  FROM conversions c
  JOIN touchpoints t
    ON c.blended_user_id = t.blended_user_id
    AND t.event_timestamp <= c.conversion_timestamp
    AND (c.prev_conversion_timestamp IS NULL OR t.event_timestamp > c.prev_conversion_timestamp)
    AND t.event_timestamp >= c.conversion_timestamp - (30 * 24 * 60 * 60 * 1000000)
  GROUP BY 1, 2, 3, 4
),
attribution_calc AS (
  SELECT
    tp.source,
    tp.medium,
    tp.campaign,
    tp.touch_position,
    tp.total_touchpoints,
    CASE
      WHEN tp.total_touchpoints = 1 THEN 1.0
      WHEN tp.total_touchpoints = 2 THEN 0.5
      WHEN tp.touch_position = 1 THEN 0.4
      WHEN tp.touch_position = tp.total_touchpoints THEN 0.4
      ELSE 0.2 / (tp.total_touchpoints - 2)
    END AS position_weight
  FROM conversion_paths cp,
  UNNEST(cp.touchpoints_array) AS tp
)
SELECT
  source,
  medium,
  campaign,
  COUNT(*) AS total_touchpoints,
  ROUND(SUM(position_weight), 4) AS weighted_conversions,
  ROUND(SUM(position_weight) * 100.0 / SUM(SUM(position_weight)) OVER(), 2) AS attribution_pct
FROM attribution_calc
GROUP BY 1, 2, 3
ORDER BY weighted_conversions DESC
LIMIT 50;
