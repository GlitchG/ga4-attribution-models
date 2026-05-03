-- Last Non-Direct Attribution Model
-- Credits the last session whose source is NOT direct/none with 100% credit.
-- If the conversion session has a valid source, it gets credit.
-- Otherwise, looks back to the most recent non-direct session.
--
-- For 2026 production GA4 exports, session_traffic_source_last_click.cross_channel_campaign
-- already applies last-non-direct model — just select .source / .medium directly.

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

WITH session_sources AS (
  -- One row per session: source/medium from session_start event_params.
  -- Excludes direct/none sessions — only meaningful traffic sources.
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS medium,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'campaign') AS campaign
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'session_start'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY user_pseudo_id, ga_session_id ORDER BY event_timestamp) = 1
),

non_direct_sessions AS (
  SELECT *
  FROM session_sources
  WHERE source IS NOT NULL
    AND source != '(direct)'
    AND medium != '(none)'
),

conversions AS (
  SELECT DISTINCT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'purchase'
),

attributed AS (
  -- For each conversion, find the most recent non-direct session
  -- (same session or earlier, ordered by ga_session_id descending)
  SELECT
    c.user_pseudo_id,
    c.ga_session_id AS conversion_session_id,
    ARRAY_AGG(
      STRUCT(nds.source, nds.medium, nds.campaign)
      ORDER BY nds.ga_session_id DESC
      LIMIT 1
    )[OFFSET(0)] AS last_non_direct
  FROM conversions c
  JOIN non_direct_sessions nds
    ON c.user_pseudo_id = nds.user_pseudo_id
    AND nds.ga_session_id <= c.ga_session_id
  GROUP BY 1, 2
)

SELECT
  COALESCE(last_non_direct.source, '(direct)') AS source,
  COALESCE(last_non_direct.medium, '(none)') AS medium,
  last_non_direct.campaign,
  COUNT(*) AS conversions,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS attribution_pct
FROM attributed
GROUP BY 1, 2, 3
ORDER BY conversions DESC
LIMIT 50;
