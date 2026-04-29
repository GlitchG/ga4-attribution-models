-- Linear Attribution Model
-- Distributes credit equally across all touchpoints in the conversion path

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

WITH conversions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    event_timestamp AS conversion_timestamp
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'purchase'
),
all_touchpoints AS (
  SELECT
    c.user_pseudo_id,
    c.session_id AS conversion_session_id,
    c.conversion_timestamp,
    e.event_timestamp,
    (SELECT value.string_value FROM UNNEST(e.event_params) WHERE key = 'source') AS source,
    (SELECT value.string_value FROM UNNEST(e.event_params) WHERE key = 'medium') AS medium,
    (SELECT value.string_value FROM UNNEST(e.event_params) WHERE key = 'campaign') AS campaign
  FROM conversions c
  JOIN `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` e
    ON c.user_pseudo_id = e.user_pseudo_id
    AND e.event_timestamp <= c.conversion_timestamp
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND (SELECT value.string_value FROM UNNEST(e.event_params) WHERE key = 'source') IS NOT NULL
),
touchpoint_counts AS (
  SELECT
    user_pseudo_id,
    conversion_session_id,
    COUNT(*) AS total_touchpoints
  FROM all_touchpoints
  GROUP BY 1, 2
)
SELECT
  t.source,
  t.medium,
  t.campaign,
  COUNT(DISTINCT t.user_pseudo_id || '-' || t.conversion_session_id) AS conversion_paths,
  COUNT(*) AS total_touchpoints,
  ROUND(COUNT(*) * 1.0 / SUM(COUNT(*)) OVER(), 4) AS weighted_conversions,
  ROUND(COUNT(*) * 100.0 / (SELECT SUM(total_touchpoints) FROM touchpoint_counts), 2) AS attribution_pct
FROM all_touchpoints t
GROUP BY 1, 2, 3
ORDER BY total_touchpoints DESC
LIMIT 50;
