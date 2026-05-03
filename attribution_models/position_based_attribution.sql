-- Position-Based Attribution Model (U-Shaped)
-- 40% credit to first session, 40% to last (conversion) session,
-- 20% distributed equally across middle sessions.
-- Based on session-level touchpoints, not individual events.

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

WITH session_sources AS (
  -- One row per session with traffic source
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS medium,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'campaign') AS campaign
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'session_start'
    AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY user_pseudo_id, ga_session_id ORDER BY event_timestamp) = 1
),

conversions AS (
  SELECT DISTINCT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'purchase'
),

conversion_paths AS (
  -- For each conversion, number the sessions in order and count total
  SELECT
    c.user_pseudo_id,
    c.ga_session_id AS conversion_session_id,
    ss.source,
    ss.medium,
    ss.campaign,
    ROW_NUMBER() OVER (
      PARTITION BY c.user_pseudo_id, c.ga_session_id
      ORDER BY ss.ga_session_id
    ) AS position,
    COUNT(*) OVER (
      PARTITION BY c.user_pseudo_id, c.ga_session_id
    ) AS total_sessions
  FROM conversions c
  JOIN session_sources ss
    ON c.user_pseudo_id = ss.user_pseudo_id
    AND ss.ga_session_id <= c.ga_session_id
),

attribution AS (
  SELECT
    source,
    medium,
    campaign,
    CASE
      WHEN position = 1 THEN 0.4                          -- First session: 40%
      WHEN position = total_sessions THEN 0.4             -- Last session: 40%
      WHEN total_sessions <= 2 THEN 0                     -- Only 1-2 sessions: no middle
      ELSE 0.2 / (total_sessions - 2)                     -- Middle sessions: 20% split
    END AS position_weight
  FROM conversion_paths
)

SELECT
  source,
  medium,
  campaign,
  COUNT(*) AS session_occurrences,
  ROUND(SUM(position_weight), 4) AS weighted_conversions,
  ROUND(SUM(position_weight) * 100.0 / SUM(SUM(position_weight)) OVER(), 2) AS attribution_pct
FROM attribution
WHERE position_weight > 0
GROUP BY 1, 2, 3
ORDER BY weighted_conversions DESC
LIMIT 50;
