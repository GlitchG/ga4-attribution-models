-- Cross-Channel Attribution Comparison
-- Runs Last Click, First Click, Linear, and Time Decay models side by side
-- to reveal how different models tell different stories about channel value.
-- All models use session-level attribution (not event-level).

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

WITH session_sources AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    MIN(event_timestamp) AS session_start_us,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS medium,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'campaign') AS campaign
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'session_start'
    AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') IS NOT NULL
  GROUP BY 1, 2, 4, 5, 6
  QUALIFY ROW_NUMBER() OVER (PARTITION BY user_pseudo_id, ga_session_id ORDER BY session_start_us) = 1
),

conversions AS (
  SELECT DISTINCT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    MIN(event_timestamp) AS conversion_us
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'purchase'
  GROUP BY 1, 2
),

-- Build a unified conversion path table: all sessions before each conversion
conversion_paths AS (
  SELECT
    c.user_pseudo_id,
    c.ga_session_id AS conversion_session_id,
    c.conversion_us,
    ss.source,
    ss.medium,
    ss.ga_session_id AS session_id,
    ss.session_start_us,
    ROW_NUMBER() OVER (
      PARTITION BY c.user_pseudo_id, c.ga_session_id
      ORDER BY ss.ga_session_id
    ) AS session_position,
    COUNT(*) OVER (
      PARTITION BY c.user_pseudo_id, c.ga_session_id
    ) AS total_sessions
  FROM conversions c
  JOIN session_sources ss
    ON c.user_pseudo_id = ss.user_pseudo_id
    AND ss.ga_session_id <= c.ga_session_id
),

-- Model 1: Last Click (conversion session gets 100%)
last_click_model AS (
  SELECT
    CONCAT(source, ' / ', medium) AS channel,
    COUNT(DISTINCT CONCAT(user_pseudo_id, '-', conversion_session_id)) AS last_click_conversions
  FROM conversion_paths
  WHERE session_position = total_sessions  -- last session = conversion session
  GROUP BY 1
),

-- Model 2: First Click (first session gets 100%)
first_click_model AS (
  SELECT
    CONCAT(source, ' / ', medium) AS channel,
    COUNT(DISTINCT CONCAT(user_pseudo_id, '-', conversion_session_id)) AS first_click_conversions
  FROM conversion_paths
  WHERE session_position = 1
  GROUP BY 1
),

-- Model 3: Linear (equal credit across all sessions)
linear_model AS (
  SELECT
    CONCAT(source, ' / ', medium) AS channel,
    SUM(1.0 / total_sessions) AS linear_conversions
  FROM conversion_paths
  GROUP BY 1
),

-- Model 4: Time Decay (exponential, half-life 24h, cap 7 days)
time_decay_model AS (
  SELECT
    CONCAT(source, ' / ', medium) AS channel,
    SUM(
      POWER(0.5, LEAST(
        (conversion_us - session_start_us) / (1000000.0 * 3600.0),
        168.0
      ) / 24.0)
    ) AS time_decay_conversions
  FROM conversion_paths
  GROUP BY 1
)

SELECT
  COALESCE(lc.channel, fc.channel, ln.channel, td.channel) AS channel,
  COALESCE(lc.last_click_conversions, 0) AS last_click,
  ROUND(COALESCE(lc.last_click_conversions, 0) * 100.0
    / SUM(COALESCE(lc.last_click_conversions, 0)) OVER(), 2) AS last_click_pct,
  COALESCE(fc.first_click_conversions, 0) AS first_click,
  ROUND(COALESCE(fc.first_click_conversions, 0) * 100.0
    / SUM(COALESCE(fc.first_click_conversions, 0)) OVER(), 2) AS first_click_pct,
  ROUND(COALESCE(ln.linear_conversions, 0), 2) AS linear,
  ROUND(COALESCE(ln.linear_conversions, 0) * 100.0
    / SUM(COALESCE(ln.linear_conversions, 0)) OVER(), 2) AS linear_pct,
  ROUND(COALESCE(td.time_decay_conversions, 0), 2) AS time_decay,
  ROUND(COALESCE(td.time_decay_conversions, 0) * 100.0
    / SUM(COALESCE(td.time_decay_conversions, 0)) OVER(), 2) AS time_decay_pct
FROM last_click_model lc
FULL OUTER JOIN first_click_model fc ON lc.channel = fc.channel
FULL OUTER JOIN linear_model ln ON COALESCE(lc.channel, fc.channel) = ln.channel
FULL OUTER JOIN time_decay_model td ON COALESCE(lc.channel, fc.channel, ln.channel) = td.channel
ORDER BY last_click DESC
LIMIT 50;
