-- Data-Driven Attribution Model (BigQuery ML)
-- Uses machine learning to determine attribution weights based on historical conversion patterns
-- Note: Requires BigQuery ML enabled in your project

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

-- Step 1: Create training dataset (user journeys with conversion outcome)
CREATE OR REPLACE TABLE temp.user_journey_features AS
WITH conversions AS (
  SELECT
    user_pseudo_id,
    event_timestamp AS conversion_timestamp
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'purchase'
    AND user_pseudo_id IS NOT NULL
),
user_touchpoints AS (
  SELECT
    user_pseudo_id,
    event_timestamp,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS medium,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'campaign') AS campaign,
    event_name
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND user_pseudo_id IS NOT NULL
),
journey_features AS (
  SELECT
    t.user_pseudo_id,
    -- Target: did they convert?
    CASE WHEN c.user_pseudo_id IS NOT NULL THEN 1 ELSE 0 END AS converted,
    -- Feature: number of touchpoints
    COUNT(*) AS touchpoint_count,
    -- Feature: distinct channels
    COUNT(DISTINCT CONCAT(t.source, ' / ', t.medium)) AS distinct_channels,
    -- Feature: has organic search
    MAX(CASE WHEN t.medium = 'organic' THEN 1 ELSE 0 END) AS has_organic,
    -- Feature: has paid search
    MAX(CASE WHEN t.medium = 'cpc' THEN 1 ELSE 0 END) AS has_cpc,
    -- Feature: has social
    MAX(CASE WHEN t.medium IN ('social', 'social-network', 'social-media') THEN 1 ELSE 0 END) AS has_social,
    -- Feature: has email
    MAX(CASE WHEN t.medium = 'email' THEN 1 ELSE 0 END) AS has_email,
    -- Feature: journey duration (hours)
    ROUND((MAX(event_timestamp) - MIN(event_timestamp)) / (1000000 * 60 * 60), 2) AS journey_hours
  FROM user_touchpoints t
  LEFT JOIN conversions c 
    ON t.user_pseudo_id = c.user_pseudo_id
    AND t.event_timestamp <= c.conversion_timestamp
  GROUP BY 1, 2
)
SELECT * FROM journey_features;

-- Step 2: Train logistic regression model
CREATE OR REPLACE MODEL `temp.attribution_model`
OPTIONS(
  model_type='LOGISTIC_REG',
  input_label_cols=['converted'],
  data_split_method='AUTO_SPLIT'
) AS
SELECT
  converted,
  touchpoint_count,
  distinct_channels,
  has_organic,
  has_cpc,
  has_social,
  has_email,
  journey_hours
FROM temp.user_journey_features;

-- Step 3: Get feature importance (attribution weights)
SELECT
  'Data-Driven Attribution: Feature Importance' AS model_type,
  feature,
  ROUND(weight, 4) AS attribution_weight,
  ROUND(weight / SUM(weight) OVER(), 4) AS normalized_weight_pct
FROM ML.WEIGHTS(MODEL `temp.attribution_model`)
WHERE weight IS NOT NULL
ORDER BY weight DESC;

-- Step 4: Channel-level attribution (simplified)
-- Calculate conversion credit based on feature importance
WITH channel_conversions AS (
  SELECT
    CONCAT(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source'),
      ' / ',
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium')
    ) AS channel,
    COUNT(DISTINCT user_pseudo_id) AS users,
    COUNTIF(event_name = 'purchase') AS conversions
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND user_pseudo_id IS NOT NULL
  GROUP BY 1
)
SELECT
  channel,
  users,
  conversions,
  ROUND(conversions * 100.0 / SUM(conversions) OVER(), 2) AS pct_of_total_conversions
FROM channel_conversions
ORDER BY conversions DESC
LIMIT 50;

-- Cleanup (optional)
-- DROP TABLE temp.user_journey_features;
-- DROP MODEL temp.attribution_model;
