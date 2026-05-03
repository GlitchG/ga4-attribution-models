-- Time Decay Attribution Model
-- More credit to sessions closer to conversion (exponential decay).
-- Each session = one touchpoint. Credit = 0.5^(days_before_conversion / half_life).
-- Capped at 7 days to prevent extreme skew in long journeys.

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

WITH session_sources AS (
  -- One row per session with traffic source and start timestamp
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
  -- One conversion per user-session with the conversion timestamp
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    MIN(event_timestamp) AS conversion_us
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'purchase'
  GROUP BY 1, 2
),

weighted_touchpoints AS (
  SELECT
    c.user_pseudo_id,
    c.ga_session_id AS conversion_session_id,
    ss.source,
    ss.medium,
    ss.campaign,
    -- Hours between session start and conversion (capped at 168 = 7 days)
    -- Half-life: ~24 hours (0.5 power for each day)
    LEAST(
      (c.conversion_us - ss.session_start_us) / (1000000.0 * 3600.0),
      168.0
    ) AS hours_before_conversion,
    POWER(0.5, LEAST(
      (c.conversion_us - ss.session_start_us) / (1000000.0 * 3600.0),
      168.0
    ) / 24.0) AS decay_weight
  FROM conversions c
  JOIN session_sources ss
    ON c.user_pseudo_id = ss.user_pseudo_id
    AND ss.ga_session_id <= c.ga_session_id
  WHERE c.conversion_us >= ss.session_start_us
)

SELECT
  source,
  medium,
  campaign,
  COUNT(*) AS sessions_in_path,
  ROUND(SUM(decay_weight), 4) AS weighted_conversions,
  ROUND(SUM(decay_weight) * 100.0 / SUM(SUM(decay_weight)) OVER(), 2) AS attribution_pct
FROM weighted_touchpoints
GROUP BY 1, 2, 3
ORDER BY weighted_conversions DESC
LIMIT 50;
