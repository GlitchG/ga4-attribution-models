-- Linear Attribution Model
-- Distributes credit equally across all touchpoints in the conversion path
-- Each conversion is split evenly: a 3-touchpoint path gives 1/3 credit per touchpoint
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
conversion_touchpoints AS (
  SELECT
    c.blended_user_id,
    c.session_id AS conversion_session_id,
    c.conversion_timestamp,
    c.conversion_number,
    t.source,
    t.medium,
    t.campaign
  FROM conversions c
  JOIN touchpoints t
    ON c.blended_user_id = t.blended_user_id
    AND t.event_timestamp <= c.conversion_timestamp
    AND (c.prev_conversion_timestamp IS NULL OR t.event_timestamp > c.prev_conversion_timestamp)
    AND t.event_timestamp >= c.conversion_timestamp - (30 * 24 * 60 * 60 * 1000000)
),
-- Count touchpoints per conversion cycle for equal-split weighting
path_lengths AS (
  SELECT
    blended_user_id,
    conversion_session_id,
    conversion_timestamp,
    conversion_number,
    COUNT(*) AS touchpoint_count
  FROM conversion_touchpoints
  GROUP BY 1, 2, 3, 4
),
-- Each touchpoint gets 1/N credit where N = touchpoints in that conversion cycle
weighted AS (
  SELECT
    t.source,
    t.medium,
    t.campaign,
    1.0 / p.touchpoint_count AS linear_weight
  FROM conversion_touchpoints t
  JOIN path_lengths p
    ON t.blended_user_id = p.blended_user_id
    AND t.conversion_session_id = p.conversion_session_id
    AND t.conversion_number = p.conversion_number
)
SELECT
  source,
  medium,
  campaign,
  COUNT(*) AS total_touchpoints,
  ROUND(SUM(linear_weight), 4) AS weighted_conversions,
  ROUND(SUM(linear_weight) * 100.0 / SUM(SUM(linear_weight)) OVER(), 2) AS attribution_pct
FROM weighted
GROUP BY 1, 2, 3
ORDER BY weighted_conversions DESC
LIMIT 50;
