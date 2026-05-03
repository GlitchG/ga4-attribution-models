-- First Click Attribution Model (Session-Based)
-- Assigns 100% credit to the first session in the conversion journey.
-- Uses session-level source/medium from event_params on session_start events.

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

WITH sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    event_timestamp AS session_start_micros,
    COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source'), '(direct)') AS source,
    COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium'), '(none)') AS medium,
    CASE
      WHEN COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium'), '(none)') IN ('cpc', 'ppc', 'paidsearch') THEN 'Paid Search'
      WHEN COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium'), '(none)') = 'organic' THEN 'Organic Search'
      WHEN LOWER(COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium'), '')) LIKE '%social%' THEN 'Social'
      WHEN COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium'), '(none)') = 'email' THEN 'Email'
      WHEN COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium'), '(none)') IN ('display', 'banner') THEN 'Display'
      WHEN COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium'), '(none)') IN ('(none)', '') THEN 'Direct'
      ELSE CONCAT(COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source'), '(direct)'), ' / ', COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium'), '(none)'))
    END AS channel
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'session_start'
    AND (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY user_pseudo_id, session_id ORDER BY event_timestamp) = 1
),
conversions AS (
  SELECT
    user_pseudo_id,
    TIMESTAMP_MICROS(event_timestamp) AS conversion_ts,
    ROW_NUMBER() OVER (PARTITION BY user_pseudo_id ORDER BY event_timestamp) AS conversion_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'purchase'
),
journeys AS (
  SELECT
    c.user_pseudo_id,
    c.conversion_ts,
    c.conversion_id,
    ARRAY_AGG(
      STRUCT(s.channel)
      ORDER BY s.session_start_micros
    ) AS path
  FROM conversions c
  JOIN sessions s
    ON c.user_pseudo_id = s.user_pseudo_id
   AND TIMESTAMP_MICROS(s.session_start_micros) <= c.conversion_ts
   AND TIMESTAMP_MICROS(s.session_start_micros) >= TIMESTAMP_SUB(c.conversion_ts, INTERVAL 30 DAY)
  GROUP BY 1, 2, 3
),
first_touch AS (
  SELECT
    user_pseudo_id,
    conversion_id,
    path[SAFE_OFFSET(0)].channel AS attributed_channel
  FROM journeys
  WHERE ARRAY_LENGTH(path) > 0
)
SELECT
  attributed_channel AS channel,
  COUNT(*) AS attributed_conversions,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS attribution_pct
FROM first_touch
WHERE attributed_channel IS NOT NULL
GROUP BY 1
ORDER BY attributed_conversions DESC
LIMIT 50;
