-- Attribution Mart — Unified Output Table
-- Creates a single table with all attribution model results in a dashboard-ready format.
-- Output schema: channel, model, attributed_conversions
-- Connect Looker Studio directly to this table.

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

CREATE OR REPLACE TABLE `your_project.your_dataset.attribution_mart` AS

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
journey_sessions AS (
  SELECT
    c.user_pseudo_id,
    c.conversion_ts,
    c.conversion_number,
    s.channel,
    s.session_start,
    TIMESTAMP_DIFF(c.conversion_ts, s.session_start, HOUR) AS hours_before,
    ROW_NUMBER() OVER (PARTITION BY c.user_pseudo_id, c.conversion_number ORDER BY s.session_start) AS pos_asc,
    ROW_NUMBER() OVER (PARTITION BY c.user_pseudo_id, c.conversion_number ORDER BY s.session_start DESC) AS pos_desc,
    COUNT(*) OVER (PARTITION BY c.user_pseudo_id, c.conversion_number) AS total_sessions
  FROM conversions c
  JOIN sessions s
    ON c.user_pseudo_id = s.user_pseudo_id
   AND s.session_start <= c.conversion_ts
   AND (c.prev_conversion_ts IS NULL OR s.session_start > c.prev_conversion_ts)
   AND s.session_start >= TIMESTAMP_SUB(c.conversion_ts, INTERVAL 30 DAY)
),

-- Model 1: Last Click
m1 AS (
  SELECT channel, 'Last Click' AS model, COUNT(*) AS attributed_conversions
  FROM journey_sessions WHERE pos_desc = 1 GROUP BY 1
),
-- Model 2: First Click
m2 AS (
  SELECT channel, 'First Click' AS model, COUNT(*) AS attributed_conversions
  FROM journey_sessions WHERE pos_asc = 1 GROUP BY 1
),
-- Model 3: Last Non-Direct
m3 AS (
  SELECT channel, 'Last Non-Direct' AS model, COUNT(*) AS attributed_conversions
  FROM (
    SELECT user_pseudo_id, conversion_number, channel,
      ROW_NUMBER() OVER (PARTITION BY user_pseudo_id, conversion_number
        ORDER BY CASE WHEN channel = 'Direct' THEN 1 ELSE 0 END, pos_desc) AS rn
    FROM journey_sessions
  ) WHERE rn = 1 GROUP BY 1
),
-- Model 4: Linear
m4 AS (
  SELECT channel, 'Linear' AS model, SUM(1.0 / total_sessions) AS attributed_conversions
  FROM journey_sessions GROUP BY 1
),
-- Model 5: Time Decay
m5 AS (
  SELECT channel, 'Time Decay' AS model,
    SUM(EXP(-0.1 * hours_before) / NULLIF(SUM(EXP(-0.1 * hours_before)) OVER (PARTITION BY user_pseudo_id, conversion_number), 0)) AS attributed_conversions
  FROM journey_sessions GROUP BY 1
),
-- Model 6: U-Shaped
m6 AS (
  SELECT channel, 'U-Shaped' AS model,
    SUM(CASE
      WHEN total_sessions = 1 THEN 1.0 WHEN total_sessions = 2 THEN 0.5
      WHEN pos_asc = 1 THEN 0.4 WHEN pos_desc = 1 THEN 0.4
      ELSE 0.2 / (total_sessions - 2) END
    ) AS attributed_conversions
  FROM journey_sessions GROUP BY 1
)

SELECT * FROM m1 UNION ALL SELECT * FROM m2 UNION ALL SELECT * FROM m3
UNION ALL SELECT * FROM m4 UNION ALL SELECT * FROM m5 UNION ALL SELECT * FROM m6
ORDER BY model, attributed_conversions DESC;
