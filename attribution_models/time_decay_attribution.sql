-- Time Decay Attribution Model
-- Gives more credit to touchpoints closer to conversion
-- Uses exponential decay: credit = 1 / (days_since_conversion + 1)

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

WITH conversions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    TIMESTAMP_MICROS(event_timestamp) AS conversion_time
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'purchase'
),
all_touchpoints AS (
  SELECT
    c.user_pseudo_id,
    c.session_id AS conversion_session_id,
    c.conversion_time,
    e.event_timestamp AS touchpoint_timestamp,
    (SELECT value.string_value FROM UNNEST(e.event_params) WHERE key = 'source') AS source,
    (SELECT value.string_value FROM UNNEST(e.event_params) WHERE key = 'medium') AS medium,
    (SELECT value.string_value FROM UNNEST(e.event_params) WHERE key = 'campaign') AS campaign,
    DATE_DIFF(
      DATE(c.conversion_time),
      DATE(TIMESTAMP_MICROS(e.event_timestamp)),
      DAY
    ) AS days_before_conversion
  FROM conversions c
  JOIN `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` e
    ON c.user_pseudo_id = e.user_pseudo_id
    AND e.event_timestamp <= c.conversion_time
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND (SELECT value.string_value FROM UNNEST(e.event_params) WHERE key = 'source') IS NOT NULL
),
weighted_touchpoints AS (
  SELECT
    *,
    -- Exponential decay: 1 / (days + 1), capped at 1.0
    POWER(0.5, days_before_conversion) AS decay_weight
  FROM all_touchpoints
)
SELECT
  source,
  medium,
  campaign,
  COUNT(*) AS total_touchpoints,
  ROUND(SUM(decay_weight), 2) AS weighted_conversions,
  ROUND(SUM(decay_weight) * 100.0 / (SELECT SUM(decay_weight) FROM weighted_touchpoints), 2) AS attribution_pct
FROM weighted_touchpoints
GROUP BY 1, 2, 3
ORDER BY weighted_conversions DESC
LIMIT 50;
