-- Time Decay Attribution Model (Session-Based)
-- Gives more credit to sessions closer to conversion.
-- Decay: EXP(-0.1 * hours_before), capped at 168 hours (7 days).
-- Normalised per (user, conversion_id): weight / SUM(weight) OVER partition.

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

WITH sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    event_timestamp AS session_start_micros,
    COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source'), '(direct)') AS source,
    COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium'), '(none)') AS medium,
    CASE
      WHEN COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium'), '(none)') IN ('cpc', 'ppc', 'paidsearch') THEN 'Paid Search'
      WHEN COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium'), '(none)') = 'organic' THEN 'Organic Search'
      WHEN LOWER(COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium'), '')) LIKE '%social%' THEN 'Social'
      WHEN COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium'), '(none)') = 'email' THEN 'Email'
      WHEN COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium'), '(none)') IN ('display', 'banner') THEN 'Display'
      WHEN COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium'), '(none)') IN ('(none)', '') THEN 'Direct'
      ELSE CONCAT(COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source'), '(direct)'), ' / ', COALESCE((SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium'), '(none)'))
    END AS channel
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'session_start'
    AND (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY user_pseudo_id, session_id ORDER BY event_timestamp) = 1
),
conversions AS (
  SELECT
    user_pseudo_id,
    TIMESTAMP_MICROS(event_timestamp) AS conversion_ts,
    ROW_NUMBER() OVER (PARTITION BY user_pseudo_id ORDER BY event_timestamp) AS conversion_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'purchase'
),
journey_sessions AS (
  SELECT
    c.user_pseudo_id,
    c.conversion_ts,
    c.conversion_id,
    s.channel,
    -- Hours since session, capped at 168 (7 days)
    LEAST(
      TIMESTAMP_DIFF(c.conversion_ts, TIMESTAMP_MICROS(s.session_start_micros), HOUR),
      168
    ) AS hours_before_conversion
  FROM conversions c
  JOIN sessions s
    ON c.user_pseudo_id = s.user_pseudo_id
   AND TIMESTAMP_MICROS(s.session_start_micros) <= c.conversion_ts
   AND TIMESTAMP_MICROS(s.session_start_micros) >= TIMESTAMP_SUB(c.conversion_ts, INTERVAL 30 DAY)
),
-- Weighted with decay, normalised per (user, conversion_id)
weighted AS (
  SELECT
    user_pseudo_id,
    conversion_id,
    channel,
    EXP(-0.1 * hours_before_conversion) AS raw_weight,
    -- Normalise: this session's share of the conversion
    EXP(-0.1 * hours_before_conversion) / NULLIF(
      SUM(EXP(-0.1 * hours_before_conversion)) OVER (
        PARTITION BY user_pseudo_id, conversion_id
      ), 0
    ) AS decay_weight
  FROM journey_sessions
)
SELECT
  channel,
  COUNT(*) AS total_sessions,
  ROUND(SUM(decay_weight), 4) AS attributed_conversions,
  ROUND(SUM(decay_weight) * 100.0 / SUM(SUM(decay_weight)) OVER(), 2) AS attribution_pct
FROM weighted
GROUP BY 1
ORDER BY attributed_conversions DESC
LIMIT 50;
