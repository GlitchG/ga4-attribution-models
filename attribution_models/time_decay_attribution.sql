-- Time Decay Attribution Model
-- Gives more credit to touchpoints closer to conversion
-- Uses exponential decay with a 7-day half-life: weight = 0.5^(days_before / 7)
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
-- Weighted touchpoints with decay factor
-- Half-life of 7 days: same-day touch = 1.0, 7 days before = 0.5, 14 days = 0.25
weighted_touchpoints AS (
  SELECT
    t.source,
    t.medium,
    t.campaign,
    POWER(0.5, (c.conversion_timestamp - t.event_timestamp) / (7.0 * 24 * 60 * 60 * 1000000)) AS decay_weight
  FROM conversions c
  JOIN touchpoints t
    ON c.blended_user_id = t.blended_user_id
    AND t.event_timestamp <= c.conversion_timestamp
    AND (c.prev_conversion_timestamp IS NULL OR t.event_timestamp > c.prev_conversion_timestamp)
    AND t.event_timestamp >= c.conversion_timestamp - (30 * 24 * 60 * 60 * 1000000)
)
SELECT
  source,
  medium,
  campaign,
  COUNT(*) AS total_touchpoints,
  ROUND(SUM(decay_weight), 2) AS weighted_conversions,
  ROUND(SUM(decay_weight) * 100.0 / SUM(SUM(decay_weight)) OVER(), 2) AS attribution_pct
FROM weighted_touchpoints
GROUP BY 1, 2, 3
ORDER BY weighted_conversions DESC
LIMIT 50;
