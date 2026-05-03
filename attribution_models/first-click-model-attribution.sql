-- First Click Attribution Model (Session-Based)
-- Assigns 100% credit to the first session in the conversion journey.
-- Depends on: data-preparation/google-analytics-4-data-preparation.sql
--            (run the data prep first to create attribution_path_rows view)

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

-- Self-contained version: include the session extraction inline.
-- Replace `your_project.your_dataset` below, or run data-preparation first
-- and query directly from `your_project.your_dataset.attribution_path_rows`.

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
-- Build ordered session path per conversion
journeys AS (
  SELECT
    c.user_pseudo_id,
    c.conversion_ts,
    c.conversion_number,
    ARRAY_AGG(
      STRUCT(s.session_start, s.source, s.medium, s.channel)
      ORDER BY s.session_start
    ) AS path
  FROM conversions c
  JOIN sessions s
    ON c.user_pseudo_id = s.user_pseudo_id
   AND s.session_start <= c.conversion_ts
   AND (c.prev_conversion_ts IS NULL OR s.session_start > c.prev_conversion_ts)
   AND s.session_start >= TIMESTAMP_SUB(c.conversion_ts, INTERVAL 30 DAY)
  GROUP BY 1, 2, 3
),
-- First touch: first element of the ordered path
first_touch AS (
  SELECT
    user_pseudo_id,
    conversion_ts,
    conversion_number,
    path[ORDINAL(1)].channel AS first_channel
  FROM journeys
  WHERE ARRAY_LENGTH(path) > 0
)
SELECT
  first_channel AS channel,
  COUNT(*) AS attributed_conversions,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS attribution_pct
FROM first_touch
GROUP BY 1
ORDER BY attributed_conversions DESC
LIMIT 50;
