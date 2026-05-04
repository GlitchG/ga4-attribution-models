-- Validation Queries for GA4 Attribution Pipeline
-- Run these after building sessions and before trusting attribution output.
-- All queries should return expected values (0 rows for duplicates, etc.)

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

-- ============================================================================
-- 1. DUPLICATE SESSIONS CHECK
-- Should return 0 rows. If not, deduplication failed.
-- ============================================================================
SELECT 'DUPLICATE SESSIONS' AS check_name,
  user_pseudo_id, session_id, COUNT(*) AS cnt
FROM (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') IS NOT NULL
  GROUP BY 1, 2
)
GROUP BY 1, 2, 3
HAVING COUNT(*) > 1;

-- ============================================================================
-- 2. CHANNEL DISTRIBUTION SANITY
-- Check for unexpected NULLs, empty strings, or anomalies in channel grouping.
-- Uses GA4-UI-style first-non-auto-event source extraction.
-- ============================================================================
WITH session_event_traffic AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    event_timestamp,
    event_name,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS medium
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') IS NOT NULL
),
session_traffic_resolved AS (
  SELECT
    user_pseudo_id,
    session_id,
    ARRAY_AGG(
      STRUCT(source, medium)
      ORDER BY
        CASE WHEN event_name NOT IN ('session_start', 'first_visit') AND (source IS NOT NULL OR medium IS NOT NULL) THEN 0 ELSE 1 END,
        CASE WHEN event_name = 'session_start' AND (source IS NOT NULL OR medium IS NOT NULL) THEN 0 ELSE 1 END,
        event_timestamp
    )[SAFE_OFFSET(0)] AS resolved_traffic
  FROM session_event_traffic
  GROUP BY 1, 2
)
SELECT 'CHANNEL DISTRIBUTION' AS check_name,
  CASE
    WHEN COALESCE(resolved_traffic.medium, '(none)') IN ('cpc','ppc','paidsearch') THEN 'Paid Search'
    WHEN COALESCE(resolved_traffic.medium, '(none)') = 'organic' THEN 'Organic Search'
    WHEN LOWER(COALESCE(resolved_traffic.medium, '')) LIKE '%social%' THEN 'Social'
    WHEN COALESCE(resolved_traffic.medium, '(none)') = 'email' THEN 'Email'
    WHEN COALESCE(resolved_traffic.medium, '(none)') IN ('display','banner') THEN 'Display'
    WHEN COALESCE(resolved_traffic.medium, '(none)') = 'referral' THEN 'Referral'
    WHEN COALESCE(resolved_traffic.medium, '(none)') = 'affiliate' THEN 'Affiliate'
    WHEN COALESCE(resolved_traffic.medium, '(none)') IN ('(none)','') THEN 'Direct'
    ELSE CONCAT(COALESCE(resolved_traffic.source, '(direct)'), ' / ', COALESCE(resolved_traffic.medium, '(none)'))
  END AS channel,
  COUNT(*) AS session_count
FROM session_traffic_resolved
GROUP BY 1, 2
ORDER BY session_count DESC;

-- ============================================================================
-- 3. ATTRIBUTION SUM CHECK (per model)
-- Each model's total attributed conversions should equal the number of conversions.
-- Run this after the attribution mart is populated.
-- ============================================================================
-- SELECT model, SUM(attributed_conversions) AS total_attributed,
--   (SELECT COUNT(*) FROM `your_project.your_dataset.attribution_conversions`) AS total_conversions,
--   ROUND(SUM(attributed_conversions) - (SELECT COUNT(*) FROM `your_project.your_dataset.attribution_conversions`), 4) AS diff
-- FROM `your_project.your_dataset.attribution_mart`
-- GROUP BY model
-- HAVING ABS(SUM(attributed_conversions) - (SELECT COUNT(*) FROM `your_project.your_dataset.attribution_conversions`)) > 0.01;

-- ============================================================================
-- 4. JOURNEY COVERAGE CHECK
-- How many conversions have at least one session in their lookback window?
-- ============================================================================
SELECT 'JOURNEY COVERAGE' AS check_name,
  COUNT(DISTINCT c.user_pseudo_id) AS total_converting_users,
  COUNT(DISTINCT CASE WHEN j.user_pseudo_id IS NOT NULL THEN c.user_pseudo_id END) AS users_with_journeys,
  ROUND(COUNT(DISTINCT CASE WHEN j.user_pseudo_id IS NOT NULL THEN c.user_pseudo_id END) * 100.0 / NULLIF(COUNT(DISTINCT c.user_pseudo_id), 0), 2) AS coverage_pct
FROM (
  SELECT DISTINCT user_pseudo_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date AND event_name = 'purchase'
) c
LEFT JOIN (
  SELECT DISTINCT s.user_pseudo_id
  FROM (
    SELECT user_pseudo_id, event_timestamp
    FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
    WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date AND event_name = 'session_start'
  ) s
  JOIN (
    SELECT user_pseudo_id, event_timestamp AS conversion_ts
    FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
    WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date AND event_name = 'purchase'
  ) c ON s.user_pseudo_id = c.user_pseudo_id
   AND TIMESTAMP_MICROS(s.event_timestamp) <= TIMESTAMP_MICROS(c.conversion_ts)
   AND TIMESTAMP_MICROS(s.event_timestamp) >= TIMESTAMP_SUB(TIMESTAMP_MICROS(c.conversion_ts), INTERVAL 30 DAY)
) j ON c.user_pseudo_id = j.user_pseudo_id;

-- ============================================================================
-- 5. NULL SOURCE/MEDIUM CHECK
-- Count sessions with NULL source or medium before COALESCE.
-- Uses the first-non-auto-event rule (primary) vs session_start fallback.
-- ============================================================================
WITH session_event_traffic AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    event_name,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS medium
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') IS NOT NULL
),
session_traffic_resolved AS (
  SELECT
    user_pseudo_id,
    session_id,
    ARRAY_AGG(
      STRUCT(source, medium)
      ORDER BY
        CASE WHEN event_name NOT IN ('session_start', 'first_visit') AND (source IS NOT NULL OR medium IS NOT NULL) THEN 0 ELSE 1 END,
        CASE WHEN event_name = 'session_start' AND (source IS NOT NULL OR medium IS NOT NULL) THEN 0 ELSE 1 END,
        event_timestamp
    )[SAFE_OFFSET(0)] AS resolved_traffic
  FROM session_event_traffic
  GROUP BY 1, 2
)
SELECT 'NULL SOURCE/MEDIUM' AS check_name,
  COUNTIF(resolved_traffic.source IS NULL) AS null_source,
  COUNTIF(resolved_traffic.medium IS NULL) AS null_medium,
  COUNT(*) AS total_sessions
FROM session_traffic_resolved;
