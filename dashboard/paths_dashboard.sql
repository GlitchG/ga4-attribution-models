-- Conversion Paths Dashboard Query
-- Most common source/medium sequences leading to purchase.
-- Paste into Looker Studio as a Custom Query data source.

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

WITH conversions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    event_timestamp AS conversion_timestamp
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'purchase'
),
user_journey AS (
  SELECT
    c.user_pseudo_id,
    c.session_id,
    STRING_AGG(
      CONCAT(
        (SELECT value.string_value FROM UNNEST(e.event_params) WHERE key = 'source'),
        '/',
        (SELECT value.string_value FROM UNNEST(e.event_params) WHERE key = 'medium')
      )
      ORDER BY e.event_timestamp
      LIMIT 10
      SEPARATOR ' → '
    ) AS conversion_path,
    COUNT(*) AS touchpoint_count
  FROM conversions c
  JOIN `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` e
    ON c.user_pseudo_id = e.user_pseudo_id
    AND e.event_timestamp <= c.conversion_timestamp
    AND e.event_timestamp >= c.conversion_timestamp - (30 * 24 * 60 * 60 * 1000000)
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND (SELECT value.string_value FROM UNNEST(e.event_params) WHERE key = 'source') IS NOT NULL
  GROUP BY 1, 2
)
SELECT
  conversion_path,
  COUNT(*) AS conversions,
  ROUND(AVG(touchpoint_count), 1) AS avg_touchpoints,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct_of_total
FROM user_journey
GROUP BY 1
ORDER BY conversions DESC
LIMIT 20;
