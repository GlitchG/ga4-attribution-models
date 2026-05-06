-- GA4 Session-Level Source Extraction (2026 Best Practice)
--
-- CORRECT way to extract traffic source for session-based attribution.
-- The common mistake is using `traffic_source` (user-level first touch) or
-- extracting source/medium from all events indiscriminately.
--
-- ============================================================================
-- GA4 BigQuery Export: Traffic Source Field Reference
-- ============================================================================
-- | Field                                          | Scope       | Added    | Use for attribution? |
-- |------------------------------------------------|-------------|----------|----------------------|
-- | traffic_source.source / .medium                | User-level  | Start    | NEVER (first touch)  |
-- | event_params WHERE key='source'/'medium'       | Event-level | Start    | Yes, with first-non-auto-event rule |
-- | collected_traffic_source.manual_source/medium   | Event-level | ~2023    | Yes (raw values)     |
-- | session_traffic_source_last_click.cross_channel | Session-lvl | Late '24 | BEST (prod standard) |
-- ============================================================================
--
-- QUICK START: Copy this file, uncomment the section matching your GA4 setup,
-- and paste into BigQuery Console.
--
--
-- ============================================================================
-- PATH A: Public Dataset / Pre-July 2024 GA4 Exports
-- ============================================================================
-- Extracts source, medium, campaign from event_params using the first-non-auto-event
-- rule. This matches how the GA4 UI attributes session source/medium and reduces
-- drift vs. the UI from 5-15% on production data.
--
-- Downside: doesn't fix the google/cpc → google/organic misattribution bug
-- (Google Ads auto-tagged traffic shows as organic in event_params).
-- ============================================================================

/*
WITH session_event_traffic AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    event_timestamp,
    event_name,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS medium,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'campaign') AS campaign
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20210101' AND '20210131'
    AND (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') IS NOT NULL
),
session_traffic_resolved AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    ARRAY_AGG(
      STRUCT(source, medium, campaign)
      ORDER BY
        CASE WHEN event_name NOT IN ('session_start', 'first_visit') AND (source IS NOT NULL OR medium IS NOT NULL) THEN 0 ELSE 1 END,
        CASE WHEN event_name = 'session_start' AND (source IS NOT NULL OR medium IS NOT NULL) THEN 0 ELSE 1 END,
        event_timestamp
    )[SAFE_OFFSET(0)] AS resolved_traffic
  FROM session_event_traffic
  GROUP BY 1, 2
)
SELECT
  COALESCE(resolved_traffic.source, '(direct)') AS source,
  COALESCE(resolved_traffic.medium, '(none)') AS medium,
  resolved_traffic.campaign AS campaign,
  COUNT(*) AS sessions
FROM session_traffic_resolved
GROUP BY 1, 2, 3
ORDER BY sessions DESC;
*/


-- ============================================================================
-- PATH B: Modern GA4 Exports (July 2024+) — PRODUCTION STANDARD
-- ============================================================================
-- Uses session_traffic_source_last_click.cross_channel_campaign.
-- This is the session-level, last-non-direct-attributed traffic source that
-- matches the GA4 UI Session Acquisition report.
--
-- Advantages over event_params extraction:
--   - Fixes the google/cpc misattribution bug (gclid links without UTM params
--     no longer show as google / organic)
--   - Applies last-non-direct model (session with no source inherits prior
--     session's source)
--   - No need to filter for session_start events
--   - Cheaper to query (no UNNEST on event_params)
-- ============================================================================

/*
SELECT
  COALESCE(
    session_traffic_source_last_click.cross_channel_campaign.source,
    '(direct)'
  ) AS source,
  COALESCE(
    session_traffic_source_last_click.cross_channel_campaign.medium,
    '(none)'
  ) AS medium,
  session_traffic_source_last_click.cross_channel_campaign.campaign_name AS campaign,
  COUNT(DISTINCT CONCAT(user_pseudo_id, '-',
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
  )) AS sessions
FROM `your_project.your_dataset.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240701' AND '20240731'
GROUP BY 1, 2, 3
ORDER BY sessions DESC;
*/


-- ============================================================================
-- BUG EXPLAINED: The google/cpc → google/organic Misattribution
-- ============================================================================
-- When Google Ads auto-tagging is enabled, ad clicks arrive with a gclid
-- parameter but NO utm_source/utm_medium. GA4's event_params correctly stores
-- nothing for source/medium on these events, making them appear as direct or
-- organic in queries that extract from event_params.
--
-- Fix options (in order of preference):
--   1. session_traffic_source_last_click.cross_channel_campaign (production, Jul 2024+)
--   2. collected_traffic_source.manual_source/medium (production, 2023+)
--   3. JOIN with Google Ads Data Transfer to resolve gclid → campaign data
--   4. Accept the limitation (public dataset / pre-2023 exports)
-- ============================================================================


-- ============================================================================
-- COMMON MISTAKE: Using traffic_source (User-Level First Touch)
-- ============================================================================
-- DO NOT DO THIS:
--   SELECT traffic_source.source, traffic_source.medium FROM ...
--
-- traffic_source is the user's FIRST-EVER acquisition source. It persists
-- across ALL sessions for that user's lifetime. Using it for session-based
-- attribution makes every model produce identical results because every
-- session gets the same source.
--
-- The official docs state: "traffic_source values do not change if the user
-- interacts with subsequent campaigns after installation."
-- https://support.google.com/analytics/answer/7029846
-- ============================================================================
