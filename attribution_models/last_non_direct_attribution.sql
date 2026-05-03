-- Last Non-Direct Attribution Model
-- Assigns 100% credit to the last non-direct touchpoint before conversion
-- Excludes direct/none traffic (source = '(direct)' or medium = '(none)')
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
-- Only non-direct touchpoints
non_direct_touchpoints AS (
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
    AND e.source != '(direct)'
    AND e.medium != '(none)'
),
last_non_direct_touch AS (
  SELECT
    c.blended_user_id,
    c.session_id AS conversion_session_id,
    c.conversion_timestamp,
    c.conversion_number,
    ARRAY_AGG(
      STRUCT(t.source, t.medium, t.campaign, t.event_timestamp)
      ORDER BY t.event_timestamp DESC
      LIMIT 1
    )[OFFSET(0)] AS last_touchpoint
  FROM conversions c
  JOIN non_direct_touchpoints t
    ON c.blended_user_id = t.blended_user_id
    AND t.event_timestamp <= c.conversion_timestamp
    AND (c.prev_conversion_timestamp IS NULL OR t.event_timestamp > c.prev_conversion_timestamp)
    AND t.event_timestamp >= c.conversion_timestamp - (30 * 24 * 60 * 60 * 1000000)
  GROUP BY 1, 2, 3, 4
)
SELECT
  last_touchpoint.source,
  last_touchpoint.medium,
  last_touchpoint.campaign,
  COUNT(*) AS conversions,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS attribution_pct
FROM last_non_direct_touch
WHERE last_touchpoint.source IS NOT NULL
GROUP BY 1, 2, 3
ORDER BY conversions DESC
LIMIT 50;
