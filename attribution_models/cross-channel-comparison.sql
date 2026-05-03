-- Cross-Channel Attribution Comparison (Session-Based)
-- Compares 6 models from a single shared base: sessions + conversions.
-- Models: Last Click, First Click, Last Non-Direct, Linear, Time Decay, U-Shaped.

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

WITH sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    MIN(TIMESTAMP_MICROS(event_timestamp)) AS session_start,
    IFNULL(ANY_VALUE(traffic_source.source), '(direct)') AS source,
    IFNULL(ANY_VALUE(traffic_source.medium), '(none)') AS medium,
    CASE
      WHEN ANY_VALUE(traffic_source.medium) = 'cpc' THEN 'Paid Search'
      WHEN ANY_VALUE(traffic_source.medium) = 'organic' THEN 'Organic Search'
      WHEN LOWER(ANY_VALUE(traffic_source.medium)) LIKE '%social%' THEN 'Social'
      WHEN ANY_VALUE(traffic_source.medium) = 'email' THEN 'Email'
      WHEN ANY_VALUE(traffic_source.medium) = 'referral' THEN 'Referral'
      WHEN ANY_VALUE(traffic_source.medium) = '(none)' THEN 'Direct'
      WHEN ANY_VALUE(traffic_source.medium) IS NULL THEN 'Direct'
      ELSE CONCAT(IFNULL(ANY_VALUE(traffic_source.source), '(direct)'), ' / ', IFNULL(ANY_VALUE(traffic_source.medium), '(none)'))
    END AS channel
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'session_start'
  GROUP BY 1, 2
),
conversions AS (
  SELECT
    user_pseudo_id,
    TIMESTAMP_MICROS(event_timestamp) AS conversion_ts,
    ROW_NUMBER() OVER (PARTITION BY user_pseudo_id ORDER BY event_timestamp) AS conversion_number,
    LAG(TIMESTAMP_MICROS(event_timestamp)) OVER (PARTITION BY user_pseudo_id ORDER BY event_timestamp) AS prev_conversion_ts
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'purchase'
),
-- Shared: ordered sessions per conversion with metadata
journey_sessions AS (
  SELECT
    c.user_pseudo_id,
    c.conversion_ts,
    c.conversion_number,
    s.channel,
    s.session_start,
    TIMESTAMP_DIFF(c.conversion_ts, s.session_start, HOUR) AS hours_before,
    ROW_NUMBER() OVER (PARTITION BY c.user_pseudo_id, c.conversion_number ORDER BY s.session_start) AS position_asc,
    ROW_NUMBER() OVER (PARTITION BY c.user_pseudo_id, c.conversion_number ORDER BY s.session_start DESC) AS position_desc,
    COUNT(*) OVER (PARTITION BY c.user_pseudo_id, c.conversion_number) AS total_sessions
  FROM conversions c
  JOIN sessions s
    ON c.user_pseudo_id = s.user_pseudo_id
   AND s.session_start <= c.conversion_ts
   AND (c.prev_conversion_ts IS NULL OR s.session_start > c.prev_conversion_ts)
   AND s.session_start >= TIMESTAMP_SUB(c.conversion_ts, INTERVAL 30 DAY)
),
all_channels AS (
  SELECT DISTINCT channel FROM journey_sessions
),
last_click AS (
  SELECT channel, COUNT(*) AS weighted FROM journey_sessions WHERE position_desc = 1 GROUP BY 1
),
first_click AS (
  SELECT channel, COUNT(*) AS weighted FROM journey_sessions WHERE position_asc = 1 GROUP BY 1
),
last_non_direct AS (
  SELECT channel, COUNT(*) AS weighted
  FROM (
    SELECT user_pseudo_id, conversion_number, channel,
      ROW_NUMBER() OVER (PARTITION BY user_pseudo_id, conversion_number
        ORDER BY CASE WHEN channel = 'Direct' THEN 1 ELSE 0 END, position_desc) AS rn
    FROM journey_sessions
  ) WHERE rn = 1
  GROUP BY 1
),
linear AS (
  SELECT channel, SUM(1.0 / total_sessions) AS weighted FROM journey_sessions GROUP BY 1
),
time_decay AS (
  SELECT channel,
    SUM(EXP(-0.1 * hours_before) / NULLIF(SUM(EXP(-0.1 * hours_before)) OVER (PARTITION BY user_pseudo_id, conversion_number), 0)) AS weighted
  FROM journey_sessions
  GROUP BY 1
),
u_shaped AS (
  SELECT channel,
    SUM(CASE
      WHEN total_sessions = 1 THEN 1.0
      WHEN total_sessions = 2 THEN 0.5
      WHEN position_asc = 1 THEN 0.4
      WHEN position_desc = 1 THEN 0.4
      ELSE 0.2 / (total_sessions - 2)
    END) AS weighted
  FROM journey_sessions
  GROUP BY 1
)
SELECT
  ac.channel,
  COALESCE(lc.weighted, 0) AS last_click,
  COALESCE(fc.weighted, 0) AS first_click,
  COALESCE(lnd.weighted, 0) AS last_non_direct,
  ROUND(COALESCE(ln.weighted, 0), 2) AS linear,
  ROUND(COALESCE(td.weighted, 0), 2) AS time_decay,
  ROUND(COALESCE(us.weighted, 0), 2) AS u_shaped,
  ROUND(COALESCE(lc.weighted, 0) * 100.0 / NULLIF(SUM(lc.weighted) OVER(), 0), 2) AS last_click_pct,
  ROUND(COALESCE(fc.weighted, 0) * 100.0 / NULLIF(SUM(fc.weighted) OVER(), 0), 2) AS first_click_pct,
  ROUND(COALESCE(lnd.weighted, 0) * 100.0 / NULLIF(SUM(lnd.weighted) OVER(), 0), 2) AS last_non_direct_pct,
  ROUND(COALESCE(ln.weighted, 0) * 100.0 / NULLIF(SUM(ln.weighted) OVER(), 0), 2) AS linear_pct,
  ROUND(COALESCE(td.weighted, 0) * 100.0 / NULLIF(SUM(td.weighted) OVER(), 0), 2) AS time_decay_pct,
  ROUND(COALESCE(us.weighted, 0) * 100.0 / NULLIF(SUM(us.weighted) OVER(), 0), 2) AS u_shaped_pct
FROM all_channels ac
LEFT JOIN last_click lc ON ac.channel = lc.channel
LEFT JOIN first_click fc ON ac.channel = fc.channel
LEFT JOIN last_non_direct lnd ON ac.channel = lnd.channel
LEFT JOIN linear ln ON ac.channel = ln.channel
LEFT JOIN time_decay td ON ac.channel = td.channel
LEFT JOIN u_shaped us ON ac.channel = us.channel
ORDER BY last_click DESC
LIMIT 50;
