-- User Path Analysis (Session-Level)
-- Shows common conversion paths as sequences of sessions (channels).
-- Each step in the path represents one session, not one event,
-- so you see the actual multi-session journey, not page_view noise.

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

WITH session_sources AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    MIN(event_timestamp) AS session_start_us,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS medium
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'session_start'
    AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') IS NOT NULL
  GROUP BY 1, 2, 4, 5
  QUALIFY ROW_NUMBER() OVER (PARTITION BY user_pseudo_id, ga_session_id ORDER BY session_start_us) = 1
),

conversions AS (
  SELECT DISTINCT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'purchase'
),

user_journey AS (
  SELECT
    c.user_pseudo_id,
    c.ga_session_id AS conversion_session_id,
    STRING_AGG(
      CONCAT(ss.source, '/', ss.medium)
      ORDER BY ss.ga_session_id
      SEPARATOR ' → '
    ) AS conversion_path,
    COUNT(*) AS session_count
  FROM conversions c
  JOIN session_sources ss
    ON c.user_pseudo_id = ss.user_pseudo_id
    AND ss.ga_session_id <= c.ga_session_id
  GROUP BY 1, 2
)

SELECT
  conversion_path,
  COUNT(*) AS journeys,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS journey_pct,
  AVG(session_count) AS avg_sessions_to_convert
FROM user_journey
GROUP BY 1
ORDER BY journeys DESC
LIMIT 50;
