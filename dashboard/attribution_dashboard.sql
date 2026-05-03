-- Unified Attribution Dashboard Query (Session-Based)
-- Paste into Looker Studio as a Custom Query data source.
-- Session-level source/medium from event_params.

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

WITH sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    event_timestamp AS session_start_micros,
    CASE
      WHEN COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium'), '(none)') IN ('cpc','ppc','paidsearch') THEN 'Paid Search'
      WHEN COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium'), '(none)') = 'organic' THEN 'Organic Search'
      WHEN LOWER(COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium'), '')) LIKE '%social%' THEN 'Social'
      WHEN COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium'), '(none)') = 'email' THEN 'Email'
      WHEN COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium'), '(none)') IN ('display','banner') THEN 'Display'
      WHEN COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium'), '(none)') IN ('(none)','') THEN 'Direct'
      ELSE CONCAT(COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source'), '(direct)'), ' / ', COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium'), '(none)'))
    END AS channel
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'session_start'
    AND (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY user_pseudo_id, session_id ORDER BY event_timestamp) = 1
),
conversions AS (
  SELECT user_pseudo_id, TIMESTAMP_MICROS(event_timestamp) AS conversion_ts,
    ROW_NUMBER() OVER (PARTITION BY user_pseudo_id ORDER BY event_timestamp) AS conversion_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date AND event_name = 'purchase'
),
js AS (
  SELECT c.user_pseudo_id, c.conversion_ts, c.conversion_id, s.channel,
    LEAST(TIMESTAMP_DIFF(c.conversion_ts, TIMESTAMP_MICROS(s.session_start_micros), HOUR), 168) AS h,
    ROW_NUMBER() OVER (PARTITION BY c.user_pseudo_id, c.conversion_id ORDER BY s.session_start_micros) AS pa,
    ROW_NUMBER() OVER (PARTITION BY c.user_pseudo_id, c.conversion_id ORDER BY s.session_start_micros DESC) AS pd,
    COUNT(*) OVER (PARTITION BY c.user_pseudo_id, c.conversion_id) AS ts
  FROM conversions c JOIN sessions s ON c.user_pseudo_id = s.user_pseudo_id
   AND TIMESTAMP_MICROS(s.session_start_micros) <= c.conversion_ts
   AND TIMESTAMP_MICROS(s.session_start_micros) >= TIMESTAMP_SUB(c.conversion_ts, INTERVAL 30 DAY)
),
m1 AS (SELECT channel, 'Last Click' AS model, COUNT(*) AS c FROM js WHERE pd=1 GROUP BY 1),
m2 AS (SELECT channel, 'First Click' AS model, COUNT(*) AS c FROM js WHERE pa=1 GROUP BY 1),
m3 AS (SELECT channel, 'Last Non-Direct' AS model, COUNT(*) AS c FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY user_pseudo_id, conversion_id ORDER BY CASE WHEN channel='Direct' THEN 1 ELSE 0 END, pd) AS rn FROM js) WHERE rn=1 GROUP BY 1),
m4 AS (SELECT channel, 'Linear' AS model, SUM(1.0/ts) AS c FROM js GROUP BY 1),
m5 AS (SELECT channel, 'Time Decay' AS model, SUM(EXP(-0.1*h)/NULLIF(SUM(EXP(-0.1*h)) OVER (PARTITION BY user_pseudo_id, conversion_id),0)) AS c FROM js GROUP BY 1),
m6 AS (SELECT channel, 'U-Shaped' AS model, SUM(CASE WHEN ts=1 THEN 1.0 WHEN ts=2 THEN 0.5 WHEN pa=1 THEN 0.4 WHEN pd=1 THEN 0.4 ELSE 0.2/(ts-2) END) AS c FROM js GROUP BY 1),
unified AS (SELECT * FROM m1 UNION ALL SELECT * FROM m2 UNION ALL SELECT * FROM m3 UNION ALL SELECT * FROM m4 UNION ALL SELECT * FROM m5 UNION ALL SELECT * FROM m6)
SELECT model, channel, ROUND(c,4) AS attributed_conversions,
  ROUND(c*100.0/SUM(c) OVER (PARTITION BY model),2) AS attribution_pct,
  SUM(c) OVER (PARTITION BY model) AS model_total
FROM unified ORDER BY model, attributed_conversions DESC;
