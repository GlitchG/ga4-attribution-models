-- First Click Attribution Model
-- Credits the FIRST session's traffic source with 100% of the conversion.
-- Uses session-level source from session_start events (correct scope).
-- Never use traffic_source — that's user-level first touch and persists forever.
--
-- For 2026 production GA4 exports, replace the session_sources CTE with:
--   session_traffic_source_last_click.cross_channel_campaign.source / .medium

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

WITH session_sources AS (
  -- One row per session: source/medium from session_start event_params.
  -- session_start carries the traffic source for the entire session.
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    MIN(event_timestamp) AS session_start_ts,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS medium,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'campaign') AS campaign
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'session_start'
  GROUP BY 1, 2, 4, 5, 6
  -- Deduplicate: if session_start fires twice, take the first occurrence
  QUALIFY ROW_NUMBER() OVER (PARTITION BY user_pseudo_id, ga_session_id ORDER BY session_start_ts) = 1
),

conversions AS (
  -- One conversion per user-session (deduplicates multiple purchase events in same session)
  SELECT DISTINCT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'purchase'
),

first_session AS (
  -- Each user's chronologically first session
  SELECT
    user_pseudo_id,
    source,
    medium,
    campaign
  FROM session_sources
  WHERE ga_session_id IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY user_pseudo_id ORDER BY session_start_ts) = 1
)

SELECT
  COALESCE(fs.source, '(direct)') AS source,
  COALESCE(fs.medium, '(none)') AS medium,
  fs.campaign,
  COUNT(DISTINCT CONCAT(c.user_pseudo_id, '-', c.ga_session_id)) AS conversions,
  ROUND(COUNT(DISTINCT CONCAT(c.user_pseudo_id, '-', c.ga_session_id)) * 100.0
    / SUM(COUNT(DISTINCT CONCAT(c.user_pseudo_id, '-', c.ga_session_id))) OVER(), 2) AS attribution_pct
FROM conversions c
JOIN first_session fs ON c.user_pseudo_id = fs.user_pseudo_id
GROUP BY 1, 2, 3
ORDER BY conversions DESC
LIMIT 50;
