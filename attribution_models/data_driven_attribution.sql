-- Data-Driven Attribution Model (BigQuery ML)
-- Uses logistic regression to learn attribution weights from historical conversion patterns
-- Requires BigQuery ML enabled in your project
-- Note: the public GA4 sample has very few conversions; this model needs 500+ to produce useful weights

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

-- Step 1: Create training dataset with user journey features and conversion outcome
-- Replace `your_project.your_dataset` with your actual BigQuery project and dataset
CREATE OR REPLACE TABLE `your_project.your_dataset.user_journey_features` AS
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
    event_name,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS medium
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND user_pseudo_id IS NOT NULL
),
journey_features AS (
  SELECT
    t.user_pseudo_id,
    CASE WHEN c.user_pseudo_id IS NOT NULL THEN 1 ELSE 0 END AS converted,
    COUNT(*) AS touchpoint_count,
    COUNT(DISTINCT CONCAT(t.source, ' / ', t.medium)) AS distinct_channels,
    MAX(CASE WHEN t.medium = 'organic' THEN 1 ELSE 0 END) AS has_organic,
    MAX(CASE WHEN t.medium = 'cpc' THEN 1 ELSE 0 END) AS has_cpc,
    MAX(CASE WHEN t.medium IN ('social', 'social-network', 'social-media') THEN 1 ELSE 0 END) AS has_social,
    MAX(CASE WHEN t.medium = 'email' THEN 1 ELSE 0 END) AS has_email,
    ROUND((MAX(event_timestamp) - MIN(event_timestamp)) / (1000000 * 60 * 60), 2) AS journey_hours
  FROM user_touchpoints t
  LEFT JOIN conversions c
    ON t.user_pseudo_id = c.user_pseudo_id
    AND t.event_timestamp <= c.conversion_timestamp
  GROUP BY 1, 2
)
SELECT * FROM journey_features;

-- Step 2: Train logistic regression model
CREATE OR REPLACE MODEL `your_project.your_dataset.attribution_model`
OPTIONS(
  model_type = 'LOGISTIC_REG',
  input_label_cols = ['converted'],
  data_split_method = 'AUTO_SPLIT'
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
FROM `your_project.your_dataset.user_journey_features`;

-- Step 3: View feature importance (attribution weights)
-- ML.WEIGHTS returns (processed_input, weight, category_weights)
SELECT
  processed_input AS feature,
  ROUND(weight, 4) AS attribution_weight,
  ROUND(ABS(weight) / SUM(ABS(weight)) OVER(), 4) AS normalized_weight_pct
FROM ML.WEIGHTS(MODEL `your_project.your_dataset.attribution_model`)
WHERE weight IS NOT NULL
ORDER BY ABS(weight) DESC;

-- Step 4: Channel summary (supplementary — not driven by the ML model)
-- Quick reference showing conversion volume by channel for context
-- For model-driven attribution, use ML.PREDICT with the trained model above
WITH channel_summary AS (
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
  ROUND(conversions * 100.0 / NULLIF(SUM(conversions) OVER(), 0), 2) AS pct_of_total_conversions
FROM channel_summary
ORDER BY conversions DESC
LIMIT 50;

-- Cleanup (run separately when done)
-- DROP TABLE IF EXISTS `your_project.your_dataset.user_journey_features`;
-- DROP MODEL IF EXISTS `your_project.your_dataset.attribution_model`;
