-- Data-Driven Attribution Model (BigQuery ML)
-- Trains a logistic regression model on user journey features, then uses marginal
-- contribution analysis (feature-ablation attribution) to attribute conversion credit to channels.
-- Requires BigQuery ML enabled in your project.
-- Note: the public GA4 sample has very few conversions; this model needs 500+ to produce reliable weights.

DECLARE start_date STRING DEFAULT '20201101';
DECLARE end_date STRING DEFAULT '20201220';

-- ============================================================================
-- STEP 1: Create training dataset — one row per user with journey features
-- Replace `your_project.your_dataset` with your actual BigQuery project and dataset
-- ============================================================================
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
    MAX(CASE WHEN LOWER(t.medium) IN ('cpc', 'ppc', 'paidsearch') THEN 1 ELSE 0 END) AS has_cpc,
    MAX(CASE WHEN LOWER(t.medium) LIKE '%social%' THEN 1 ELSE 0 END) AS has_social,
    MAX(CASE WHEN t.medium = 'email' THEN 1 ELSE 0 END) AS has_email,
    MAX(CASE WHEN t.medium IN ('display', 'banner') THEN 1 ELSE 0 END) AS has_display,
    MAX(CASE WHEN t.medium = 'referral' THEN 1 ELSE 0 END) AS has_referral,
    MAX(CASE WHEN t.medium = 'affiliate' THEN 1 ELSE 0 END) AS has_affiliate,
    MAX(CASE WHEN COALESCE(t.medium, '(none)') IN ('(none)', '') THEN 1 ELSE 0 END) AS has_direct,
    ROUND((MAX(event_timestamp) - MIN(event_timestamp)) / (1000000 * 60 * 60), 2) AS journey_hours
  FROM user_touchpoints t
  LEFT JOIN conversions c
    ON t.user_pseudo_id = c.user_pseudo_id
    AND t.event_timestamp <= c.conversion_timestamp
  GROUP BY 1, 2
)
SELECT * FROM journey_features;

-- ============================================================================
-- STEP 2: Train logistic regression — predicts P(conversion | journey features)
-- ============================================================================
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
  has_display,
  has_referral,
  has_affiliate,
  has_direct,
  journey_hours
FROM `your_project.your_dataset.user_journey_features`;

-- ============================================================================
-- STEP 3: Feature importance — which journey characteristics correlate with conversion?
-- ML.WEIGHTS returns (processed_input, weight, category_weights)
-- ============================================================================
SELECT
  processed_input AS feature,
  ROUND(weight, 4) AS coefficient,
  CASE
    WHEN weight > 0 THEN 'Positive driver — having this channel increases P(conversion)'
    WHEN weight < 0 THEN 'Negative driver — having this channel decreases P(conversion)'
    ELSE 'No effect'
  END AS interpretation
FROM ML.WEIGHTS(MODEL `your_project.your_dataset.attribution_model`)
WHERE weight IS NOT NULL
ORDER BY ABS(weight) DESC;

-- ============================================================================
-- STEP 4: Data-driven attribution (feature-ablation marginal contribution)
-- For each converting user: predict with all channels, then remove each channel
-- one at a time and measure the drop in predicted conversion probability.
-- The drop = that channel's marginal contribution. Normalise per user.
--
-- NOTE: This is NOT Shapley value attribution. It is a single-pass feature
-- ablation (remove one feature at a time from the full set). True Shapley
-- requires evaluating all 2^N subsets, which is computationally expensive in SQL.
-- For a proper Shapley implementation, use a dedicated library or export to Python.
-- ============================================================================
WITH converting_users AS (
  SELECT * FROM `your_project.your_dataset.user_journey_features`
  WHERE converted = 1
),
-- Full prediction: all channels present
full_pred AS (
  SELECT
    user_pseudo_id,
    (SELECT prob FROM UNNEST(predicted_converted_probs) WHERE label = 1) AS full_prob
  FROM ML.PREDICT(MODEL `your_project.your_dataset.attribution_model`,
    (SELECT * FROM converting_users)
  )
),
-- Prediction without organic
no_organic_pred AS (
  SELECT
    user_pseudo_id,
    (SELECT prob FROM UNNEST(predicted_converted_probs) WHERE label = 1) AS prob_no_organic
  FROM ML.PREDICT(MODEL `your_project.your_dataset.attribution_model`,
    (SELECT user_pseudo_id, touchpoint_count, distinct_channels,
            0 AS has_organic, has_cpc, has_social, has_email, has_display, has_referral, has_affiliate, has_direct, journey_hours
     FROM converting_users)
  )
),
-- Prediction without cpc
no_cpc_pred AS (
  SELECT
    user_pseudo_id,
    (SELECT prob FROM UNNEST(predicted_converted_probs) WHERE label = 1) AS prob_no_cpc
  FROM ML.PREDICT(MODEL `your_project.your_dataset.attribution_model`,
    (SELECT user_pseudo_id, touchpoint_count, distinct_channels,
            has_organic, 0 AS has_cpc, has_social, has_email, has_display, has_referral, has_affiliate, has_direct, journey_hours
     FROM converting_users)
  )
),
-- Prediction without social
no_social_pred AS (
  SELECT
    user_pseudo_id,
    (SELECT prob FROM UNNEST(predicted_converted_probs) WHERE label = 1) AS prob_no_social
  FROM ML.PREDICT(MODEL `your_project.your_dataset.attribution_model`,
    (SELECT user_pseudo_id, touchpoint_count, distinct_channels,
            has_organic, has_cpc, 0 AS has_social, has_email, has_display, has_referral, has_affiliate, has_direct, journey_hours
     FROM converting_users)
  )
),
-- Prediction without email
no_email_pred AS (
  SELECT
    user_pseudo_id,
    (SELECT prob FROM UNNEST(predicted_converted_probs) WHERE label = 1) AS prob_no_email
  FROM ML.PREDICT(MODEL `your_project.your_dataset.attribution_model`,
    (SELECT user_pseudo_id, touchpoint_count, distinct_channels,
            has_organic, has_cpc, has_social, 0 AS has_email, has_display, has_referral, has_affiliate, has_direct, journey_hours
     FROM converting_users)
  )
),
-- Prediction without display
no_display_pred AS (
  SELECT
    user_pseudo_id,
    (SELECT prob FROM UNNEST(predicted_converted_probs) WHERE label = 1) AS prob_no_display
  FROM ML.PREDICT(MODEL `your_project.your_dataset.attribution_model`,
    (SELECT user_pseudo_id, touchpoint_count, distinct_channels,
            has_organic, has_cpc, has_social, has_email, 0 AS has_display, has_referral, has_affiliate, has_direct, journey_hours
     FROM converting_users)
  )
),
-- Prediction without referral
no_referral_pred AS (
  SELECT
    user_pseudo_id,
    (SELECT prob FROM UNNEST(predicted_converted_probs) WHERE label = 1) AS prob_no_referral
  FROM ML.PREDICT(MODEL `your_project.your_dataset.attribution_model`,
    (SELECT user_pseudo_id, touchpoint_count, distinct_channels,
            has_organic, has_cpc, has_social, has_email, has_display, 0 AS has_referral, has_affiliate, has_direct, journey_hours
     FROM converting_users)
  )
),
-- Prediction without affiliate
no_affiliate_pred AS (
  SELECT
    user_pseudo_id,
    (SELECT prob FROM UNNEST(predicted_converted_probs) WHERE label = 1) AS prob_no_affiliate
  FROM ML.PREDICT(MODEL `your_project.your_dataset.attribution_model`,
    (SELECT user_pseudo_id, touchpoint_count, distinct_channels,
            has_organic, has_cpc, has_social, has_email, has_display, has_referral, 0 AS has_affiliate, has_direct, journey_hours
     FROM converting_users)
  )
),
-- Prediction without direct
no_direct_pred AS (
  SELECT
    user_pseudo_id,
    (SELECT prob FROM UNNEST(predicted_converted_probs) WHERE label = 1) AS prob_no_direct
  FROM ML.PREDICT(MODEL `your_project.your_dataset.attribution_model`,
    (SELECT user_pseudo_id, touchpoint_count, distinct_channels,
            has_organic, has_cpc, has_social, has_email, has_display, has_referral, has_affiliate, 0 AS has_direct, journey_hours
     FROM converting_users)
  )
),
-- Marginal contributions per user
marginal AS (
  SELECT
    f.user_pseudo_id,
    GREATEST(f.full_prob - COALESCE(o.prob_no_organic, f.full_prob), 0) AS organic_contribution,
    GREATEST(f.full_prob - COALESCE(c.prob_no_cpc, f.full_prob), 0)     AS cpc_contribution,
    GREATEST(f.full_prob - COALESCE(s.prob_no_social, f.full_prob), 0)  AS social_contribution,
    GREATEST(f.full_prob - COALESCE(e.prob_no_email, f.full_prob), 0)   AS email_contribution,
    GREATEST(f.full_prob - COALESCE(d.prob_no_display, f.full_prob), 0) AS display_contribution,
    GREATEST(f.full_prob - COALESCE(r.prob_no_referral, f.full_prob), 0) AS referral_contribution,
    GREATEST(f.full_prob - COALESCE(a.prob_no_affiliate, f.full_prob), 0) AS affiliate_contribution,
    GREATEST(f.full_prob - COALESCE(dr.prob_no_direct, f.full_prob), 0) AS direct_contribution
  FROM full_pred f
  LEFT JOIN no_organic_pred o   ON f.user_pseudo_id = o.user_pseudo_id
  LEFT JOIN no_cpc_pred c       ON f.user_pseudo_id = c.user_pseudo_id
  LEFT JOIN no_social_pred s    ON f.user_pseudo_id = s.user_pseudo_id
  LEFT JOIN no_email_pred e     ON f.user_pseudo_id = e.user_pseudo_id
  LEFT JOIN no_display_pred d   ON f.user_pseudo_id = d.user_pseudo_id
  LEFT JOIN no_referral_pred r  ON f.user_pseudo_id = r.user_pseudo_id
  LEFT JOIN no_affiliate_pred a ON f.user_pseudo_id = a.user_pseudo_id
  LEFT JOIN no_direct_pred dr   ON f.user_pseudo_id = dr.user_pseudo_id
),
-- Normalise: each user's contributions sum to 1.0 (share of their conversion)
normalised AS (
  SELECT
    user_pseudo_id,
    organic_contribution / NULLIF(
      organic_contribution + cpc_contribution + social_contribution + email_contribution
      + display_contribution + referral_contribution + affiliate_contribution + direct_contribution, 0
    ) AS organic_share,
    cpc_contribution / NULLIF(
      organic_contribution + cpc_contribution + social_contribution + email_contribution
      + display_contribution + referral_contribution + affiliate_contribution + direct_contribution, 0
    ) AS cpc_share,
    social_contribution / NULLIF(
      organic_contribution + cpc_contribution + social_contribution + email_contribution
      + display_contribution + referral_contribution + affiliate_contribution + direct_contribution, 0
    ) AS social_share,
    email_contribution / NULLIF(
      organic_contribution + cpc_contribution + social_contribution + email_contribution
      + display_contribution + referral_contribution + affiliate_contribution + direct_contribution, 0
    ) AS email_share,
    display_contribution / NULLIF(
      organic_contribution + cpc_contribution + social_contribution + email_contribution
      + display_contribution + referral_contribution + affiliate_contribution + direct_contribution, 0
    ) AS display_share,
    referral_contribution / NULLIF(
      organic_contribution + cpc_contribution + social_contribution + email_contribution
      + display_contribution + referral_contribution + affiliate_contribution + direct_contribution, 0
    ) AS referral_share,
    affiliate_contribution / NULLIF(
      organic_contribution + cpc_contribution + social_contribution + email_contribution
      + display_contribution + referral_contribution + affiliate_contribution + direct_contribution, 0
    ) AS affiliate_share,
    direct_contribution / NULLIF(
      organic_contribution + cpc_contribution + social_contribution + email_contribution
      + display_contribution + referral_contribution + affiliate_contribution + direct_contribution, 0
    ) AS direct_share
  FROM marginal
)
-- Aggregate: sum of normalised shares = data-driven conversion credit per channel
SELECT 'Organic Search' AS channel, ROUND(SUM(organic_share), 4) AS attributed_conversions FROM normalised
UNION ALL
SELECT 'Paid Search (CPC)' AS channel, ROUND(SUM(cpc_share), 4) FROM normalised
UNION ALL
SELECT 'Social' AS channel, ROUND(SUM(social_share), 4) FROM normalised
UNION ALL
SELECT 'Email' AS channel, ROUND(SUM(email_share), 4) FROM normalised
UNION ALL
SELECT 'Display' AS channel, ROUND(SUM(display_share), 4) FROM normalised
UNION ALL
SELECT 'Referral' AS channel, ROUND(SUM(referral_share), 4) FROM normalised
UNION ALL
SELECT 'Affiliate' AS channel, ROUND(SUM(affiliate_share), 4) FROM normalised
UNION ALL
SELECT 'Direct' AS channel, ROUND(SUM(direct_share), 4) FROM normalised
ORDER BY attributed_conversions DESC;

-- ============================================================================
-- Supplementary: raw channel volume (for context, not model-driven)
-- ============================================================================
-- WITH channel_summary AS (
--   SELECT
--     CONCAT(
--       (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source'),
--       ' / ',
--       (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium')
--     ) AS channel,
--     COUNT(DISTINCT user_pseudo_id) AS users,
--     COUNTIF(event_name = 'purchase') AS conversions
--   FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
--   WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
--     AND user_pseudo_id IS NOT NULL
--   GROUP BY 1
-- )
-- SELECT channel, users, conversions,
--   ROUND(conversions * 100.0 / NULLIF(SUM(conversions) OVER(), 0), 2) AS pct
-- FROM channel_summary ORDER BY conversions DESC LIMIT 50;

-- Cleanup (run separately when done)
-- DROP TABLE IF EXISTS `your_project.your_dataset.user_journey_features`;
-- DROP MODEL IF EXISTS `your_project.your_dataset.attribution_model`;
