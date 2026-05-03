-- Last Click Attribution Model
-- Credits the conversion session's traffic source with 100% of the conversion.
-- Uses session-level source from session_start events (correct scope).
-- Never use traffic_source — that's user-level first touch and persists forever.
--
-- For 2026 production GA4 exports, replace the session_sources CTE with:
--   session_traffic_source_last_click.cross_channel_campaign.source / .medium

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

WITH session_sources AS (
  -- One row per session: source/medium from session_start event_params.
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
  -- One conversion per user-session
  SELECT DISTINCT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'purchase'
)

SELECT
  COALESCE(ss.source, '(direct)') AS source,
  COALESCE(ss.medium, '(none)') AS medium,
  ss.campaign,
  COUNT(*) AS conversions,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS attribution_pct
FROM conversions c
LEFT JOIN session_sources ss
  ON c.user_pseudo_id = ss.user_pseudo_id
  AND c.ga_session_id = ss.ga_session_id
GROUP BY 1, 2, 3
ORDER BY conversions DESC
LIMIT 50;
