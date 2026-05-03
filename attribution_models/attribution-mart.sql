-- Attribution Mart — Unified Output Table
-- Creates a single table with all attribution model results.
-- Schema: channel, model, attributed_conversions, conversion_ts, user_pseudo_id

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

CREATE OR REPLACE TABLE `your_project.your_dataset.attribution_mart` AS

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
  JOIN sessions s ON c.user_pseudo_id = s.user_pseudo_id
   AND TIMESTAMP_MICROS(s.session_start_micros) <= c.conversion_ts
   AND TIMESTAMP_MICROS(s.session_start_micros) >= TIMESTAMP_SUB(c.conversion_ts, INTERVAL 30 DAY)
),
m1 AS (SELECT user_pseudo_id, conversion_ts, channel, 'Last Click' AS model, 1.0 AS weight FROM journey_sessions WHERE pos_desc = 1),
m2 AS (SELECT user_pseudo_id, conversion_ts, channel, 'First Click' AS model, 1.0 AS weight FROM journey_sessions WHERE pos_asc = 1),
m3 AS (SELECT user_pseudo_id, conversion_ts, channel, 'Last Non-Direct' AS model, 1.0 AS weight FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY user_pseudo_id, conversion_id ORDER BY CASE WHEN channel='Direct' THEN 1 ELSE 0 END, pos_desc) AS rn FROM journey_sessions) WHERE rn=1),
m4 AS (SELECT user_pseudo_id, conversion_ts, channel, 'Linear' AS model, 1.0/COUNT(*) OVER (PARTITION BY user_pseudo_id, conversion_id) AS weight FROM (SELECT DISTINCT user_pseudo_id, conversion_ts, conversion_id, channel FROM journey_sessions)),
m5 AS (SELECT user_pseudo_id, conversion_ts, channel, 'Time Decay' AS model, EXP(-0.1*hours_before)/NULLIF(SUM(EXP(-0.1*hours_before)) OVER (PARTITION BY user_pseudo_id, conversion_id),0) AS weight FROM journey_sessions),
m6 AS (SELECT user_pseudo_id, conversion_ts, channel, 'U-Shaped' AS model, CASE WHEN total_sessions=1 THEN 1.0 WHEN total_sessions=2 THEN 0.5 WHEN pos_asc=1 THEN 0.4 WHEN pos_desc=1 THEN 0.4 ELSE 0.2/(total_sessions-2) END AS weight FROM journey_sessions)
SELECT user_pseudo_id, conversion_ts, model, channel, weight AS attributed_conversions FROM m1
UNION ALL SELECT * FROM m2 UNION ALL SELECT * FROM m3
UNION ALL SELECT * FROM m4 UNION ALL SELECT * FROM m5 UNION ALL SELECT * FROM m6;
