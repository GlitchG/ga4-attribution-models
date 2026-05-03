-- GA4 Data Preparation — Session-Based Attribution Foundation
-- Extracts session-level source/medium and builds ordered user journeys.
--
-- ═══════════════════════════════════════════════════════════════════
-- GA4 BIGQUERY EXPORT: WHICH SOURCE/MEDIUM FIELD TO USE (2026)
-- ═══════════════════════════════════════════════════════════════════
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
-- STEP 1: Extract sessions from session_start events with session-level source
-- ============================================================================
CREATE OR REPLACE TABLE `your_project.your_dataset.attribution_sessions` AS
WITH raw_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    event_timestamp AS session_start_micros,
    -- Session-level source/medium from event_params (NOT traffic_source)
    COALESCE(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source'),
      '(direct)'
    ) AS source,
    COALESCE(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium'),
      '(none)'
    ) AS medium,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'campaign') AS campaign
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'session_start'
    -- Ensure session_id is valid
    AND (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') IS NOT NULL
),
-- Deduplicate: one row per (user, session_id)
deduped_sessions AS (
  SELECT
    user_pseudo_id,
    session_id,
    TIMESTAMP_MICROS(session_start_micros) AS session_start,
    source,
    medium,
    campaign,
    -- Channel normalization
    CASE
      WHEN medium IN ('cpc', 'ppc', 'paidsearch') THEN 'Paid Search'
      WHEN medium = 'organic' THEN 'Organic Search'
      WHEN LOWER(medium) LIKE '%social%' THEN 'Social'
      WHEN medium = 'email' THEN 'Email'
      WHEN medium IN ('display', 'banner') THEN 'Display'
      WHEN medium = 'referral' THEN 'Referral'
      WHEN medium = 'affiliate' THEN 'Affiliate'
      WHEN medium IN ('(none)', '') OR source = '(direct)' THEN 'Direct'
      WHEN source IS NULL AND medium IS NULL THEN 'Direct'
      ELSE CONCAT(source, ' / ', medium)
    END AS channel
  FROM raw_sessions
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY user_pseudo_id, session_id
    ORDER BY session_start_micros
  ) = 1
)
SELECT * FROM deduped_sessions;

-- ============================================================================
-- STEP 2: Extract conversions from purchase events
-- ============================================================================
CREATE OR REPLACE TABLE `your_project.your_dataset.attribution_conversions` AS
SELECT
  user_pseudo_id,
  TIMESTAMP_MICROS(event_timestamp) AS conversion_ts,
  -- conversion_id: unique identifier per user's conversion sequence
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
