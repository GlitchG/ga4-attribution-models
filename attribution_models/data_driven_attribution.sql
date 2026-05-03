-- Data-Driven Attribution Model (BigQuery ML)
-- Uses logistic regression to learn which journey features predict conversion,
-- then applies Shapley-style feature importance as attribution weights.
-- 
-- Prerequisites: BigQuery ML must be enabled in your project.
-- Replace `your_project.your_dataset` with your own BigQuery project and dataset.

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

-- ============================================================================
-- Step 1: Build training dataset (journey features + conversion outcome)
-- ============================================================================

CREATE OR REPLACE TABLE `your_project.your_dataset.temp_journey_features` AS
WITH session_sources AS (
  -- Session-level source/medium extraction
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS medium
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'session_start'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY user_pseudo_id, ga_session_id ORDER BY event_timestamp) = 1
),

conversions AS (
  SELECT DISTINCT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'purchase'
),

journey_features AS (
  SELECT
    ss.user_pseudo_id,
    -- Target: did this user convert?
    CASE WHEN c.user_pseudo_id IS NOT NULL THEN 1 ELSE 0 END AS converted,
    -- Features from session-level analysis
    COUNT(*) AS session_count,
    COUNT(DISTINCT CONCAT(ss.source, ' / ', ss.medium)) AS distinct_channels,
    -- Channel presence features
    MAX(CASE WHEN ss.medium = 'organic' THEN 1 ELSE 0 END) AS has_organic,
    MAX(CASE WHEN ss.medium IN ('cpc', 'ppc', 'paidsearch') THEN 1 ELSE 0 END) AS has_paid_search,
    MAX(CASE WHEN ss.medium IN ('social', 'social-network', 'social-media') THEN 1 ELSE 0 END) AS has_social,
    MAX(CASE WHEN ss.medium = 'email' THEN 1 ELSE 0 END) AS has_email,
    MAX(CASE WHEN ss.medium = 'referral' THEN 1 ELSE 0 END) AS has_referral
  FROM session_sources ss
  LEFT JOIN conversions c
    ON ss.user_pseudo_id = c.user_pseudo_id
    AND ss.ga_session_id <= c.ga_session_id
  WHERE ss.source IS NOT NULL
  GROUP BY 1, 2
)

SELECT * FROM journey_features;


-- ============================================================================
-- Step 2: Train logistic regression model
-- ============================================================================

CREATE OR REPLACE MODEL `your_project.your_dataset.attribution_model`
OPTIONS(
  model_type = 'LOGISTIC_REG',
  input_label_cols = ['converted'],
  data_split_method = 'AUTO_SPLIT'
) AS
SELECT
  converted,
  session_count,
  distinct_channels,
  has_organic,
  has_paid_search,
  has_social,
  has_email,
  has_referral
FROM `your_project.your_dataset.temp_journey_features`;


-- ============================================================================
-- Step 3: Feature importance (attribution weights from the model)
-- ============================================================================

SELECT
  'Data-Driven Attribution: Feature Importance' AS model_type,
  feature,
  ROUND(weight, 6) AS attribution_weight,
  ROUND(weight / SUM(ABS(weight)) OVER(), 4) AS normalized_weight_pct
FROM ML.WEIGHTS(MODEL `your_project.your_dataset.attribution_model`)
WHERE weight IS NOT NULL
ORDER BY ABS(weight) DESC;


-- ============================================================================
-- Step 4: Channel-level attribution (session-based)
-- ============================================================================

WITH session_sources AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS medium
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'session_start'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY user_pseudo_id, ga_session_id ORDER BY event_timestamp) = 1
),

conversions AS (
  SELECT DISTINCT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'purchase'
)

SELECT
  CONCAT(
    COALESCE(ss.source, '(direct)'), ' / ',
    COALESCE(ss.medium, '(none)')
  ) AS channel,
  COUNT(DISTINCT ss.user_pseudo_id) AS unique_users,
  COUNT(DISTINCT c.user_pseudo_id) AS converters,
  ROUND(COUNT(DISTINCT c.user_pseudo_id) * 100.0
    / SUM(COUNT(DISTINCT c.user_pseudo_id)) OVER(), 2) AS conversion_share_pct
FROM session_sources ss
LEFT JOIN conversions c
  ON ss.user_pseudo_id = c.user_pseudo_id
  AND ss.ga_session_id = c.ga_session_id
WHERE ss.source IS NOT NULL
GROUP BY 1
ORDER BY converters DESC
LIMIT 50;


-- ============================================================================
-- Cleanup (run separately when done)
-- ============================================================================
-- DROP TABLE IF EXISTS `your_project.your_dataset.temp_journey_features`;
-- DROP MODEL IF EXISTS `your_project.your_dataset.attribution_model`;
