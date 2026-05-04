-- Cross-Channel Attribution Comparison (Session-Based)
-- Compares 6 models from a single shared base: sessions + conversions.
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
    s.session_start_micros,
    LEAST(TIMESTAMP_DIFF(c.conversion_ts, TIMESTAMP_MICROS(s.session_start_micros), HOUR), 168) AS hours_before,
    ROW_NUMBER() OVER (PARTITION BY c.user_pseudo_id, c.conversion_id ORDER BY s.session_start_micros) AS pos_asc,
    ROW_NUMBER() OVER (PARTITION BY c.user_pseudo_id, c.conversion_id ORDER BY s.session_start_micros DESC) AS pos_desc,
    COUNT(*) OVER (PARTITION BY c.user_pseudo_id, c.conversion_id) AS total_sessions
  FROM conversions c
  JOIN sessions s
    ON c.user_pseudo_id = s.user_pseudo_id
   AND TIMESTAMP_MICROS(s.session_start_micros) <= c.conversion_ts
   AND TIMESTAMP_MICROS(s.session_start_micros) >= TIMESTAMP_SUB(c.conversion_ts, INTERVAL 30 DAY)
),
all_channels AS (SELECT DISTINCT channel FROM journey_sessions),
lc  AS (SELECT channel, COUNT(*) AS w FROM journey_sessions WHERE pos_desc = 1 GROUP BY 1),
fc  AS (SELECT channel, COUNT(*) AS w FROM journey_sessions WHERE pos_asc = 1 GROUP BY 1),
lnd AS (SELECT channel, COUNT(*) AS w FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY user_pseudo_id, conversion_id ORDER BY CASE WHEN channel = 'Direct' THEN 1 ELSE 0 END, pos_desc) AS rn FROM journey_sessions) WHERE rn = 1 GROUP BY 1),
lin AS (SELECT channel, SUM(1.0 / total_sessions) AS w FROM journey_sessions GROUP BY 1),
td  AS (SELECT channel, SUM(EXP(-0.00412 * hours_before) / NULLIF(SUM(EXP(-0.00412 * hours_before)) OVER (PARTITION BY user_pseudo_id, conversion_id), 0)) AS w FROM journey_sessions GROUP BY 1),
us  AS (SELECT channel, SUM(CASE WHEN total_sessions = 1 THEN 1.0 WHEN total_sessions = 2 THEN 0.5 WHEN pos_asc = 1 THEN 0.4 WHEN pos_desc = 1 THEN 0.4 ELSE 0.2/(total_sessions - 2) END) AS w FROM journey_sessions GROUP BY 1)
SELECT
  ac.channel,
  COALESCE(lc.w,0) AS last_click, COALESCE(fc.w,0) AS first_click,
  COALESCE(lnd.w,0) AS last_non_direct, ROUND(COALESCE(lin.w,0),2) AS linear,
  ROUND(COALESCE(td.w,0),2) AS time_decay, ROUND(COALESCE(us.w,0),2) AS u_shaped,
  ROUND(COALESCE(lc.w,0)*100.0/NULLIF(SUM(lc.w) OVER(),0),2) AS lc_pct,
  ROUND(COALESCE(fc.w,0)*100.0/NULLIF(SUM(fc.w) OVER(),0),2) AS fc_pct,
  ROUND(COALESCE(lnd.w,0)*100.0/NULLIF(SUM(lnd.w) OVER(),0),2) AS lnd_pct,
  ROUND(COALESCE(lin.w,0)*100.0/NULLIF(SUM(lin.w) OVER(),0),2) AS lin_pct,
  ROUND(COALESCE(td.w,0)*100.0/NULLIF(SUM(td.w) OVER(),0),2) AS td_pct,
  ROUND(COALESCE(us.w,0)*100.0/NULLIF(SUM(us.w) OVER(),0),2) AS us_pct
FROM all_channels ac
LEFT JOIN lc ON ac.channel = lc.channel LEFT JOIN fc ON ac.channel = fc.channel
LEFT JOIN lnd ON ac.channel = lnd.channel LEFT JOIN lin ON ac.channel = lin.channel
LEFT JOIN td ON ac.channel = td.channel LEFT JOIN us ON ac.channel = us.channel
ORDER BY last_click DESC LIMIT 50;
