-- Linear Attribution Model
-- Distributes credit equally across all sessions in the conversion path.
-- Each session counts as one touchpoint (session-level, not event-level).
-- Individual page_views and scrolls don't get separate credit.

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

WITH session_sources AS (
  -- One row per session with its traffic source
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
  -- For each conversion, get all prior sessions (including the conversion session)
  SELECT
    c.user_pseudo_id,
    c.ga_session_id AS conversion_session_id,
    ss.source,
    ss.medium,
    ss.campaign,
    COUNT(*) OVER (PARTITION BY c.user_pseudo_id, c.ga_session_id) AS sessions_in_path
  FROM conversions c
  JOIN session_sources ss
    ON c.user_pseudo_id = ss.user_pseudo_id
    AND ss.ga_session_id <= c.ga_session_id
)

SELECT
  source,
  medium,
  campaign,
  COUNT(*) AS touchpoint_occurrences,
  -- Each touchpoint in a path gets 1/sessions_in_path credit
  ROUND(SUM(1.0 / sessions_in_path), 2) AS weighted_conversions,
  ROUND(SUM(1.0 / sessions_in_path) * 100.0
    / SUM(SUM(1.0 / sessions_in_path)) OVER(), 2) AS attribution_pct
FROM conversion_paths
GROUP BY 1, 2, 3
ORDER BY weighted_conversions DESC
LIMIT 50;
