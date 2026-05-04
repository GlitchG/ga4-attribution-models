-- GA4 Data Preparation — Session-Based Attribution Foundation
-- Extracts session-level source/medium and builds ordered user journeys.
--
-- ════════════════════════════════════════════════════════════════════════════════════
-- GA4 BIGQUERY EXPORT: WHICH SOURCE/MEDIUM FIELD TO USE (2026)
-- ════════════════════════════════════════════════════════════════════════════════════
--
-- The GA4 BigQuery export has evolved. Here is the correct approach
-- depending on your export date and SDK version:
--
-- PREFERRED (exports after 2024-07-17):
--   session_traffic_source_last_click.source
--   session_traffic_source_last_click.medium
--   → Session-level, matches GA4 UI reports. No extraction needed.
--
-- ALTERNATIVE (exports after June 2023, SDK ≥ Android 17.2.5 / iOS 16.20.0):
--   collected_traffic_source.source
--   collected_traffic_source.medium
--   → Event-level struct, cleaner than UNNEST. Still needs sessionising.
--
-- FALLBACK (all exports, including public sample):
--   (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source')
--   (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium')
--   → Works on all GA4 exports including the obfuscated public sample.
--     This is what the queries below use.
--
-- NEVER USE (wrong for session attribution):
--   traffic_source.source / traffic_source.medium
--   → User-level first-touch. Repeats the same channel across all
--     sessions for a user. Will make all attribution models identical.
--
-- References:
--   https://support.google.com/analytics/answer/7029846 (BigQuery Export schema)
--   https://tanelytics.com/ga4-bigquery-session-traffic_source/ (deep dive)

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

-- ============================================================================
-- STEP 1: Extract sessions using GA4-UI-style first-non-auto-event rule
-- ============================================================================
-- Logic: GA4 attributes session source to the first non-session_start/first_visit
-- event that has source/medium in event_params. Falls back to session_start params
-- (needed for the public sample dataset and quiet sessions).
-- This aligns source/medium extraction with the GA4 UI Session Acquisition report,
-- reducing drift vs. the UI from 5-15% (observed on production data).
--
-- NOTE: The 30-day lookback is silently truncated by the _TABLE_SUFFIX filter.
-- If your conversion date is 2021-01-31 and you filter _TABLE_SUFFIX to January,
-- sessions from December 31 are excluded even though they're within 30 days.
-- For exact 30-day lookback, replace the _TABLE_SUFFIX filter with a date-math
-- filter on event_timestamp (e.g. DATE(TIMESTAMP_MICROS(event_timestamp))).
-- ============================================================================

CREATE OR REPLACE TABLE `your_project.your_dataset.attribution_sessions` AS
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
      STRUCT(source, medium, event_timestamp)
      ORDER BY
        CASE WHEN event_name NOT IN ('session_start', 'first_visit') AND (source IS NOT NULL OR medium IS NOT NULL) THEN 0 ELSE 1 END,
        CASE WHEN event_name = 'session_start' AND (source IS NOT NULL OR medium IS NOT NULL) THEN 0 ELSE 1 END,
        event_timestamp
    )[SAFE_OFFSET(0)] AS resolved_traffic
  FROM session_event_traffic
  GROUP BY 1, 2
),
deduped_sessions AS (
  SELECT
    user_pseudo_id,
    session_id,
    TIMESTAMP_MICROS(resolved_traffic.event_timestamp) AS session_start,
    COALESCE(resolved_traffic.source, '(direct)') AS source,
    COALESCE(resolved_traffic.medium, '(none)') AS medium,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'campaign') AS campaign,
    CASE
      WHEN COALESCE(resolved_traffic.medium, '(none)') IN ('cpc', 'ppc', 'paidsearch') THEN 'Paid Search'
      WHEN COALESCE(resolved_traffic.medium, '(none)') = 'organic' THEN 'Organic Search'
      WHEN LOWER(COALESCE(resolved_traffic.medium, '')) LIKE '%social%' THEN 'Social'
      WHEN COALESCE(resolved_traffic.medium, '(none)') = 'email' THEN 'Email'
      WHEN COALESCE(resolved_traffic.medium, '(none)') IN ('display', 'banner') THEN 'Display'
      WHEN COALESCE(resolved_traffic.medium, '(none)') = 'referral' THEN 'Referral'
      WHEN COALESCE(resolved_traffic.medium, '(none)') = 'affiliate' THEN 'Affiliate'
      WHEN COALESCE(resolved_traffic.medium, '(none)') IN ('(none)', '') THEN 'Direct'
      ELSE CONCAT(COALESCE(resolved_traffic.source, '(direct)'), ' / ', COALESCE(resolved_traffic.medium, '(none)'))
    END AS channel
  FROM session_traffic_resolved
)
SELECT * FROM deduped_sessions;

-- ============================================================================
-- STEP 2: Extract conversions from purchase events
-- ============================================================================
CREATE OR REPLACE TABLE `your_project.your_dataset.attribution_conversions` AS
SELECT
  user_pseudo_id,
  TIMESTAMP_MICROS(event_timestamp) AS conversion_ts,
  ROW_NUMBER() OVER (PARTITION BY user_pseudo_id ORDER BY event_timestamp) AS conversion_id,
  ecommerce.purchase_revenue AS conversion_revenue,
  ecommerce.transaction_id AS transaction_id
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
  AND event_name = 'purchase';

-- ============================================================================
-- STEP 3: Build ordered session journeys per conversion
-- CRITICAL: partition by (user_pseudo_id, conversion_id) for journey isolation
-- ============================================================================
CREATE OR REPLACE TABLE `your_project.your_dataset.attribution_journeys` AS
SELECT
  c.user_pseudo_id,
  c.conversion_ts,
  c.conversion_id,
  c.conversion_revenue,
  c.transaction_id,
  ARRAY_AGG(
    STRUCT(
      s.session_start,
      s.source,
      s.medium,
      s.campaign,
      s.channel
    )
    ORDER BY s.session_start
  ) AS path,
  ARRAY_LENGTH(ARRAY_AGG(STRUCT(s.channel) ORDER BY s.session_start)) AS path_length
FROM `your_project.your_dataset.attribution_conversions` c
JOIN `your_project.your_dataset.attribution_sessions` s
  ON c.user_pseudo_id = s.user_pseudo_id
 AND s.session_start <= c.conversion_ts
 AND s.session_start >= TIMESTAMP_SUB(c.conversion_ts, INTERVAL 30 DAY)
GROUP BY c.user_pseudo_id, c.conversion_ts, c.conversion_id, c.conversion_revenue, c.transaction_id;

-- ============================================================================
-- VIEW: Unnest paths to rows (for models that prefer row-based access)
-- ============================================================================
CREATE OR REPLACE VIEW `your_project.your_dataset.attribution_path_rows` AS
SELECT
  j.user_pseudo_id,
  j.conversion_ts,
  j.conversion_id,
  j.path_length,
  tp.session_start,
  tp.source,
  tp.medium,
  tp.campaign,
  tp.channel,
  ROW_NUMBER() OVER (
    PARTITION BY j.user_pseudo_id, j.conversion_id
    ORDER BY tp.session_start
  ) AS session_position
FROM `your_project.your_dataset.attribution_journeys` j,
UNNEST(j.path) AS tp;

-- ============================================================================
-- VALIDATION: Check for duplicate sessions (should return 0 rows)
-- ============================================================================
-- SELECT user_pseudo_id, session_id, COUNT(*) AS cnt
-- FROM `your_project.your_dataset.attribution_sessions`
-- GROUP BY 1, 2
-- HAVING COUNT(*) > 1;

-- ============================================================================
-- OPTIONAL: Use collected_traffic_source instead of event_params (newer GA4)
-- If your GA4 export includes collected_traffic_source, replace the source/medium
-- extraction with:
--   COALESCE(collected_traffic_source.source, '(direct)') AS source,
--   COALESCE(collected_traffic_source.medium, '(none)') AS medium
-- collected_traffic_source is session-level and avoids the UNNEST overhead.
