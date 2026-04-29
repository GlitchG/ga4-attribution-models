-- Position-Based Attribution Model (U-shaped)
-- Assigns 40% to first touch, 40% to last touch, 20% distributed across middle touchpoints

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
all_events AS (
  SELECT
    user_pseudo_id,
    event_timestamp,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS medium,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'campaign') AS campaign
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
),
conversion_paths AS (
  SELECT
    c.user_pseudo_id,
    c.session_id AS conversion_session_id,
    c.conversion_timestamp,
    ARRAY_AGG(
      STRUCT(
        e.source,
        e.medium,
        e.campaign,
        e.event_timestamp AS touch_timestamp,
        ROW_NUMBER() OVER (PARTITION BY c.user_pseudo_id, c.session_id ORDER BY e.event_timestamp) AS touch_position,
        COUNT(*) OVER (PARTITION BY c.user_pseudo_id, c.session_id) AS total_touchpoints
      )
    ) AS touchpoints
  FROM conversions c
  JOIN all_events e
    ON c.user_pseudo_id = e.user_pseudo_id
    AND e.event_timestamp <= c.conversion_timestamp
  WHERE e.source IS NOT NULL
  GROUP BY 1, 2, 3
),
attribution_calc AS (
  SELECT
    tp.source,
    tp.medium,
    tp.campaign,
    tp.touch_position,
    tp.total_touchpoints,
    CASE
      WHEN tp.touch_position = 1 THEN 0.4  -- First touch: 40%
      WHEN tp.touch_position = tp.total_touchpoints THEN 0.4  -- Last touch: 40%
      ELSE 0.2 / (tp.total_touchpoints - 2)  -- Middle: 20% distributed
    END AS position_weight
  FROM conversion_paths cp,
  UNNEST(cp.touchpoints) AS tp
  WHERE tp.total_touchpoints >= 2
)
SELECT
  source,
  medium,
  campaign,
  COUNT(*) AS total_touchpoints,
  ROUND(SUM(position_weight), 4) AS weighted_conversions,
  ROUND(SUM(position_weight) * 100.0 / (SELECT SUM(position_weight) FROM attribution_calc), 2) AS attribution_pct
FROM attribution_calc
GROUP BY 1, 2, 3
ORDER BY weighted_conversions DESC
LIMIT 50;
