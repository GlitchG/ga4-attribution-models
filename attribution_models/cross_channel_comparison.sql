-- Cross-Channel Attribution Comparison
-- Compares attribution credit across Last Click, First Click, Linear, and Time-Decay models
-- Helps identify which channels are over/under-valued by different attribution approaches

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

WITH conversions AS (
  SELECT
    user_pseudo_id,
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
    AND user_pseudo_id IS NOT NULL
),
-- Last Click Attribution
last_click AS (
  SELECT
    CONCAT(e.source, ' / ', e.medium) AS channel,
    COUNT(*) AS last_click_conversions
  FROM conversions c
  CROSS JOIN UNNEST(ARRAY(
    SELECT AS STRUCT *
    FROM all_events e
    WHERE e.user_pseudo_id = c.user_pseudo_id
      AND e.event_timestamp <= c.conversion_timestamp
      AND e.source IS NOT NULL
    ORDER BY e.event_timestamp DESC
    LIMIT 1
  )) e
  GROUP BY 1
),
-- First Click Attribution
first_click AS (
  SELECT
    CONCAT(e.source, ' / ', e.medium) AS channel,
    COUNT(*) AS first_click_conversions
  FROM conversions c
  CROSS JOIN UNNEST(ARRAY(
    SELECT AS STRUCT *
    FROM all_events e
    WHERE e.user_pseudo_id = c.user_pseudo_id
      AND e.event_timestamp <= c.conversion_timestamp
      AND e.source IS NOT NULL
    ORDER BY e.event_timestamp ASC
    LIMIT 1
  )) e
  GROUP BY 1
),
-- Linear Attribution (equal credit to all touchpoints)
linear AS (
  SELECT
    CONCAT(e.source, ' / ', e.medium) AS channel,
    COUNT(*) AS linear_conversions
  FROM conversions c
  JOIN all_events e
    ON c.user_pseudo_id = e.user_pseudo_id
    AND e.event_timestamp <= c.conversion_timestamp
  WHERE e.source IS NOT NULL
  GROUP BY 1
),
-- Time Decay Attribution (more credit to recent touchpoints)
time_decay AS (
  SELECT
    CONCAT(e.source, ' / ', e.medium) AS channel,
    SUM(EXP(-0.3 * (c.conversion_timestamp - e.event_timestamp) / (24 * 60 * 60 * 1000000))) AS time_decay_conversions
  FROM conversions c
  JOIN all_events e
    ON c.user_pseudo_id = e.user_pseudo_id
    AND e.event_timestamp <= c.conversion_timestamp
  WHERE e.source IS NOT NULL
  GROUP BY 1
)
-- Combine all models
SELECT
  COALESCE(lc.channel, fc.channel, ln.channel, td.channel) AS channel,
  COALESCE(lc.last_click_conversions, 0) AS last_click_conversions,
  COALESCE(fc.first_click_conversions, 0) AS first_click_conversions,
  COALESCE(ln.linear_conversions, 0) AS linear_conversions,
  ROUND(COALESCE(td.time_decay_conversions, 0), 2) AS time_decay_conversions,
  -- Calculate percentage for each model
  ROUND(lc.last_click_conversions * 100.0 / SUM(lc.last_click_conversions) OVER(), 2) AS last_click_pct,
  ROUND(fc.first_click_conversions * 100.0 / SUM(fc.first_click_conversions) OVER(), 2) AS first_click_pct,
  ROUND(ln.linear_conversions * 100.0 / SUM(ln.linear_conversions) OVER(), 2) AS linear_pct,
  ROUND(td.time_decay_conversions * 100.0 / SUM(td.time_decay_conversions) OVER(), 2) AS time_decay_pct
FROM last_click lc
FULL OUTER JOIN first_click fc ON lc.channel = fc.channel
FULL OUTER JOIN linear ln ON COALESCE(lc.channel, fc.channel) = ln.channel
FULL OUTER JOIN time_decay td ON COALESCE(lc.channel, fc.channel, ln.channel) = td.channel
ORDER BY last_click_conversions DESC
LIMIT 50;
