-- U-Shaped Attribution Model (Position-Based, Session-Based)
-- 40% first session, 40% last session, 20% distributed across middle sessions.
-- Edge cases: 1 session = 100%, 2 sessions = 50/50, 3+ = 40/40/20.
-- Uses GA4-UI-style first-non-auto-event source extraction with session_start fallback.

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

WITH session_event_traffic AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    event_timestamp,
    event_name,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS medium
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') IS NOT NULL
),
session_traffic_resolved AS (
  SELECT
    user_pseudo_id,
    session_id,
    ARRAY_AGG(
      STRUCT(source, medium, event_timestamp)
      ORDER BY
        CASE WHEN event_name NOT IN ('session_start', 'first_visit') AND (source IS NOT NULL OR medium IS NOT NULL) THEN 0 ELSE 1 END,
        CASE WHEN event_name = 'session_start' AND (source IS NOT NULL OR medium IS NOT NULL) THEN 0 ELSE 1 END,
        event_timestamp
    )[SAFE_OFFSET(0)] AS resolved_traffic
  FROM session_event_traffic
  GROUP BY 1, 2
),
sessions AS (
  SELECT
    user_pseudo_id,
    session_id,
    resolved_traffic.event_timestamp AS session_start_micros,
    COALESCE(resolved_traffic.source, '(direct)') AS source,
    COALESCE(resolved_traffic.medium, '(none)') AS medium,
    CASE
      WHEN COALESCE(resolved_traffic.medium, '(none)') IN ('cpc', 'ppc', 'paidsearch') THEN 'Paid Search'
      WHEN COALESCE(resolved_traffic.medium, '(none)') = 'organic' THEN 'Organic Search'
      WHEN LOWER(COALESCE(resolved_traffic.medium, '')) LIKE '%social%' THEN 'Social'
      WHEN COALESCE(resolved_traffic.medium, '(none)') = 'email' THEN 'Email'
      WHEN COALESCE(resolved_traffic.medium, '(none)') IN ('display', 'banner') THEN 'Display'
      WHEN COALESCE(resolved_traffic.medium, '(none)') = 'referral' THEN 'Referral'
      WHEN COALESCE(resolved_traffic.medium, '(none)') = 'affiliate' THEN 'Affiliate'
      WHEN COALESCE(resolved_traffic.medium, '(none)') IN ('(none)', '') THEN 'Direct'
      ELSE CONCAT(COALESCE(resolved_traffic.source, '(direct)'), ' / ', COALESCE(resolved_traffic.medium, '(none)'))
    END AS channel
  FROM session_traffic_resolved
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
journey_sessions AS (
  SELECT
    c.user_pseudo_id,
    c.conversion_ts,
    c.conversion_id,
    s.channel,
    ROW_NUMBER() OVER (PARTITION BY c.user_pseudo_id, c.conversion_id ORDER BY s.session_start_micros) AS session_position,
    COUNT(*) OVER (PARTITION BY c.user_pseudo_id, c.conversion_id) AS total_sessions
  FROM conversions c
  JOIN sessions s
    ON c.user_pseudo_id = s.user_pseudo_id
   AND TIMESTAMP_MICROS(s.session_start_micros) <= c.conversion_ts
   AND TIMESTAMP_MICROS(s.session_start_micros) >= TIMESTAMP_SUB(c.conversion_ts, INTERVAL 30 DAY)
),
weighted AS (
  SELECT
    channel,
    CASE
      WHEN total_sessions = 1 THEN 1.0
      WHEN total_sessions = 2 THEN 0.5
      WHEN session_position = 1 THEN 0.4
      WHEN session_position = total_sessions THEN 0.4
      ELSE 0.2 / (total_sessions - 2)
    END AS position_weight
  FROM journey_sessions
)
SELECT
  channel,
  COUNT(*) AS total_sessions,
  ROUND(SUM(position_weight), 4) AS attributed_conversions,
  ROUND(SUM(position_weight) * 100.0 / SUM(SUM(position_weight)) OVER(), 2) AS attribution_pct
FROM weighted
GROUP BY 1
ORDER BY attributed_conversions DESC
LIMIT 50;
