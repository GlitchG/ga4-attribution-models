-- GA4 Data Preparation — Session-Based Attribution Foundation
-- Extracts sessions and conversions, builds ordered user journeys with channel normalization.
-- This query is the shared foundation for all attribution models in this repository.
-- Run this first to create the base views/tables, then each model queries from them.
--
-- Key design decisions:
--   - Session-based touchpoints (NOT event-based)
--   - Source/medium from traffic_source record (NOT event_params)
--   - 30-day lookback window before each conversion
--   - Multi-conversion: repeat purchasers get separate journeys
--   - Channel normalization: consistent grouping across all models

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

-- ============================================================================
-- STEP 1: Extract sessions from session_start events
-- Uses traffic_source (session-level acquisition data), not event_params
-- ============================================================================
CREATE OR REPLACE TABLE `your_project.your_dataset.attribution_sessions` AS
SELECT
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
  MIN(TIMESTAMP_MICROS(event_timestamp)) AS session_start,
  -- Session-level traffic source (NOT event_params)
  ANY_VALUE(traffic_source.source) AS traffic_source,
  ANY_VALUE(traffic_source.medium) AS traffic_medium,
  ANY_VALUE(traffic_source.name) AS traffic_campaign,
  -- Channel normalization layer
  CASE
    WHEN ANY_VALUE(traffic_source.medium) = 'cpc' THEN 'Paid Search'
    WHEN ANY_VALUE(traffic_source.medium) = 'organic' THEN 'Organic Search'
    WHEN LOWER(ANY_VALUE(traffic_source.medium)) LIKE '%social%' THEN 'Social'
    WHEN ANY_VALUE(traffic_source.medium) = 'email' THEN 'Email'
    WHEN ANY_VALUE(traffic_source.medium) = 'referral' THEN 'Referral'
    WHEN ANY_VALUE(traffic_source.medium) = 'affiliate' THEN 'Affiliate'
    WHEN ANY_VALUE(traffic_source.medium) = '(none)' THEN 'Direct'
    WHEN ANY_VALUE(traffic_source.medium) IS NULL THEN 'Direct'
    ELSE CONCAT(
      IFNULL(ANY_VALUE(traffic_source.source), '(direct)'),
      ' / ',
      IFNULL(ANY_VALUE(traffic_source.medium), '(none)')
    )
  END AS channel,
  -- Raw fields for models that need them
  IFNULL(ANY_VALUE(traffic_source.source), '(direct)') AS raw_source,
  IFNULL(ANY_VALUE(traffic_source.medium), '(none)') AS raw_medium
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
  AND event_name = 'session_start'
GROUP BY user_pseudo_id, session_id;

-- ============================================================================
-- STEP 2: Extract conversions from purchase events
-- ============================================================================
CREATE OR REPLACE TABLE `your_project.your_dataset.attribution_conversions` AS
SELECT
  user_pseudo_id,
  TIMESTAMP_MICROS(event_timestamp) AS conversion_ts,
  ROW_NUMBER() OVER (PARTITION BY user_pseudo_id ORDER BY event_timestamp) AS conversion_number,
  ecommerce.purchase_revenue AS conversion_revenue,
  ecommerce.transaction_id AS transaction_id
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
  AND event_name = 'purchase';

-- ============================================================================
-- STEP 3: Build ordered session journeys for each conversion
-- Each conversion gets its own journey: sessions between previous conversion
-- (or start of window) and the conversion timestamp.
-- ============================================================================
CREATE OR REPLACE TABLE `your_project.your_dataset.attribution_journeys` AS
WITH journey_builder AS (
  SELECT
    c.user_pseudo_id,
    c.conversion_ts,
    c.conversion_number,
    c.conversion_revenue,
    c.transaction_id,
    ARRAY_AGG(
      STRUCT(
        s.session_start,
        s.traffic_source,
        s.traffic_medium,
        s.traffic_campaign,
        s.channel,
        s.raw_source,
        s.raw_medium
      )
      ORDER BY s.session_start
    ) AS path
  FROM `your_project.your_dataset.attribution_conversions` c
  JOIN `your_project.your_dataset.attribution_sessions` s
    ON c.user_pseudo_id = s.user_pseudo_id
   AND s.session_start <= c.conversion_ts
   -- 30-day lookback window (mandatory)
   AND s.session_start >= TIMESTAMP_SUB(c.conversion_ts, INTERVAL 30 DAY)
  GROUP BY 1, 2, 3, 4, 5
)
SELECT
  user_pseudo_id,
  conversion_ts,
  conversion_number,
  conversion_revenue,
  transaction_id,
  path,
  ARRAY_LENGTH(path) AS path_length
FROM journey_builder;

-- ============================================================================
-- OPTIONAL: Create a view returning paths as rows (for models that need it)
-- Unnest the path array into one row per touchpoint per conversion
-- ============================================================================
CREATE OR REPLACE VIEW `your_project.your_dataset.attribution_path_rows` AS
SELECT
  j.user_pseudo_id,
  j.conversion_ts,
  j.conversion_number,
  j.conversion_revenue,
  j.transaction_id,
  j.path_length,
  tp.session_start,
  tp.traffic_source,
  tp.traffic_medium,
  tp.traffic_campaign,
  tp.channel,
  tp.raw_source,
  tp.raw_medium,
  -- Position in path (1 = first session, path_length = last)
  ROW_NUMBER() OVER (
    PARTITION BY j.user_pseudo_id, j.conversion_number
    ORDER BY tp.session_start
  ) AS session_position
FROM `your_project.your_dataset.attribution_journeys` j,
UNNEST(j.path) AS tp
ORDER BY j.user_pseudo_id, j.conversion_number, tp.session_start;
