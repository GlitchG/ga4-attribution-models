-- Last Click Attribution Model
-- Assigns 100% credit to the last non-direct touchpoint before conversion

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

WITH conversions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    event_timestamp,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_number') AS session_number
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'purchase'
),
all_events AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    event_timestamp,
    event_name,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS medium,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'campaign') AS campaign
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
),
last_touch AS (
  SELECT
    c.user_pseudo_id,
    c.session_id AS conversion_session_id,
    c.event_timestamp AS conversion_timestamp,
    ARRAY_AGG(
      STRUCT(
        e.source,
        e.medium,
        e.campaign,
        e.event_timestamp
      )
      ORDER BY e.event_timestamp DESC
      LIMIT 1
    )[OFFSET(0)] AS last_touchpoint
  FROM conversions c
  LEFT JOIN all_events e
    ON c.user_pseudo_id = e.user_pseudo_id
    AND e.event_timestamp <= c.event_timestamp
  WHERE e.source IS NOT NULL
  GROUP BY 1, 2, 3
)
SELECT
  last_touchpoint.source,
  last_touchpoint.medium,
  last_touchpoint.campaign,
  COUNT(*) AS conversions,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS conversion_rate_pct
FROM last_touch
GROUP BY 1, 2, 3
ORDER BY conversions DESC
LIMIT 50;
