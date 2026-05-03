-- Linear Attribution Model (Session-Based)
-- Distributes credit equally across all distinct sessions in the conversion journey.
-- Deduplicates: same session appearing multiple times counts once.
-- Formula: 1.0 / COUNT(DISTINCT session_id) per conversion.

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
-- One row per (user, conversion, session) — deduplicated
journey_sessions AS (
  SELECT DISTINCT
    c.user_pseudo_id,
    c.conversion_id,
    s.session_id,
    s.channel
  FROM conversions c
  JOIN sessions s
    ON c.user_pseudo_id = s.user_pseudo_id
   AND TIMESTAMP_MICROS(s.session_start_micros) <= c.conversion_ts
   AND TIMESTAMP_MICROS(s.session_start_micros) >= TIMESTAMP_SUB(c.conversion_ts, INTERVAL 30 DAY)
),
-- Count distinct sessions per conversion path
path_lengths AS (
  SELECT
    user_pseudo_id,
    conversion_id,
    COUNT(DISTINCT session_id) AS session_count
  FROM journey_sessions
  GROUP BY 1, 2
),
-- Weight each session: 1 / path_length, partitioned by conversion_id
weighted AS (
  SELECT
    js.user_pseudo_id,
    js.conversion_id,
    js.channel,
    1.0 / COUNT(DISTINCT js.session_id) OVER (
      PARTITION BY js.user_pseudo_id, js.conversion_id
    ) AS linear_weight
  FROM journey_sessions js
)
SELECT
  channel,
  COUNT(*) AS total_sessions,
  ROUND(SUM(linear_weight), 4) AS attributed_conversions,
  ROUND(SUM(linear_weight) * 100.0 / SUM(SUM(linear_weight)) OVER(), 2) AS attribution_pct
FROM weighted
GROUP BY 1
ORDER BY attributed_conversions DESC
LIMIT 50;
