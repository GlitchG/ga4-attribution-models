-- Linear Attribution Model (Session-Based)
-- Distributes credit equally across all sessions in the conversion journey.
-- Formula: 1.0 / COUNT(DISTINCT sessions in path)
-- Deduplicates: multiple events in the same session count as one touchpoint.

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

WITH sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    MIN(TIMESTAMP_MICROS(event_timestamp)) AS session_start,
    IFNULL(ANY_VALUE(traffic_source.source), '(direct)') AS source,
    IFNULL(ANY_VALUE(traffic_source.medium), '(none)') AS medium,
    CASE
      WHEN ANY_VALUE(traffic_source.medium) = 'cpc' THEN 'Paid Search'
      WHEN ANY_VALUE(traffic_source.medium) = 'organic' THEN 'Organic Search'
      WHEN LOWER(ANY_VALUE(traffic_source.medium)) LIKE '%social%' THEN 'Social'
      WHEN ANY_VALUE(traffic_source.medium) = 'email' THEN 'Email'
      WHEN ANY_VALUE(traffic_source.medium) = 'referral' THEN 'Referral'
      WHEN ANY_VALUE(traffic_source.medium) = '(none)' THEN 'Direct'
      WHEN ANY_VALUE(traffic_source.medium) IS NULL THEN 'Direct'
      ELSE CONCAT(IFNULL(ANY_VALUE(traffic_source.source), '(direct)'), ' / ', IFNULL(ANY_VALUE(traffic_source.medium), '(none)'))
    END AS channel
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'session_start'
  GROUP BY 1, 2
),
conversions AS (
  SELECT
    user_pseudo_id,
    TIMESTAMP_MICROS(event_timestamp) AS conversion_ts,
    ROW_NUMBER() OVER (PARTITION BY user_pseudo_id ORDER BY event_timestamp) AS conversion_number,
    LAG(TIMESTAMP_MICROS(event_timestamp)) OVER (PARTITION BY user_pseudo_id ORDER BY event_timestamp) AS prev_conversion_ts
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'purchase'
),
-- One row per (user, conversion, session) — deduplicated at session level
journey_sessions AS (
  SELECT DISTINCT
    c.user_pseudo_id,
    c.conversion_ts,
    c.conversion_number,
    s.session_id,
    s.channel
  FROM conversions c
  JOIN sessions s
    ON c.user_pseudo_id = s.user_pseudo_id
   AND s.session_start <= c.conversion_ts
   AND (c.prev_conversion_ts IS NULL OR s.session_start > c.prev_conversion_ts)
   AND s.session_start >= TIMESTAMP_SUB(c.conversion_ts, INTERVAL 30 DAY)
),
-- Count distinct sessions per conversion path
path_lengths AS (
  SELECT
    user_pseudo_id,
    conversion_number,
    COUNT(DISTINCT session_id) AS session_count
  FROM journey_sessions
  GROUP BY 1, 2
),
-- Weight each session as 1 / path_length
weighted AS (
  SELECT
    js.user_pseudo_id,
    js.conversion_number,
    js.channel,
    1.0 / pl.session_count AS linear_weight
  FROM journey_sessions js
  JOIN path_lengths pl
    ON js.user_pseudo_id = pl.user_pseudo_id
    AND js.conversion_number = pl.conversion_number
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
