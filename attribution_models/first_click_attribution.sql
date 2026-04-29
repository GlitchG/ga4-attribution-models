-- First Click Attribution Model
-- Assigns 100% credit to the first touchpoint in the user journey

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

WITH conversions AS (
  SELECT
    user_pseudo_id,
    MIN(event_timestamp) AS first_touch_timestamp,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id, session_id
),
first_touch AS (
  SELECT
    c.user_pseudo_id,
    c.session_id AS conversion_session_id,
    c.first_touch_timestamp,
    ARRAY_AGG(
      STRUCT(
        (SELECT value.string_value FROM UNNEST(e.event_params) WHERE key = 'source') AS source,
        (SELECT value.string_value FROM UNNEST(e.event_params) WHERE key = 'medium') AS medium,
        (SELECT value.string_value FROM UNNEST(e.event_params) WHERE key = 'campaign') AS campaign,
        e.event_timestamp
      )
      ORDER BY e.event_timestamp ASC
      LIMIT 1
    )[OFFSET(0)] AS first_touchpoint
  FROM conversions c
  JOIN `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` e
    ON c.user_pseudo_id = e.user_pseudo_id
    AND e.event_timestamp = c.first_touch_timestamp
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
  GROUP BY 1, 2, 3
)
SELECT
  first_touchpoint.source,
  first_touchpoint.medium,
  first_touchpoint.campaign,
  COUNT(*) AS conversions,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS attribution_pct
FROM first_touch
GROUP BY 1, 2, 3
ORDER BY conversions DESC
LIMIT 50;
