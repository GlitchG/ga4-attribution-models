-- Time Decay Attribution Model (Session-Based)
-- Gives more credit to sessions closer to conversion.
-- Formula: weight = EXP(-0.1 * hours_before_conversion)
-- Then normalised per user: weight / SUM(weight) OVER user
-- Half-life ≈ 7 hours (after 7h, weight drops to ~50%)

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

WITH sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    MIN(TIMESTAMP_MICROS(event_timestamp)) AS session_start,
    IFNULL(ANY_VALUE(traffic_source.source), '(direct)') AS source,
    IFNULL(ANY_VALUE(traffic_source.medium), '(none)') AS medium,
    CASE
      WHEN ANY_VALUE(traffic_source.medium) = 'cpc' THEN 'Paid Search'
      WHEN ANY_VALUE(traffic_source.medium) = 'organic' THEN 'Organic Search'
      WHEN LOWER(ANY_VALUE(traffic_source.medium)) LIKE '%social%' THEN 'Social'
      WHEN ANY_VALUE(traffic_source.medium) = 'email' THEN 'Email'
      WHEN ANY_VALUE(traffic_source.medium) = 'referral' THEN 'Referral'
      WHEN ANY_VALUE(traffic_source.medium) = '(none)' THEN 'Direct'
      WHEN ANY_VALUE(traffic_source.medium) IS NULL THEN 'Direct'
      ELSE CONCAT(IFNULL(ANY_VALUE(traffic_source.source), '(direct)'), ' / ', IFNULL(ANY_VALUE(traffic_source.medium), '(none)'))
    END AS channel
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'session_start'
  GROUP BY 1, 2
),
conversions AS (
  SELECT
    user_pseudo_id,
    TIMESTAMP_MICROS(event_timestamp) AS conversion_ts,
    ROW_NUMBER() OVER (PARTITION BY user_pseudo_id ORDER BY event_timestamp) AS conversion_number,
    LAG(TIMESTAMP_MICROS(event_timestamp)) OVER (PARTITION BY user_pseudo_id ORDER BY event_timestamp) AS prev_conversion_ts
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name = 'purchase'
),
-- Sessions before each conversion with time distance
journey_sessions AS (
  SELECT
    c.user_pseudo_id,
    c.conversion_ts,
    c.conversion_number,
    s.channel,
    -- Hours between session start and conversion
    TIMESTAMP_DIFF(c.conversion_ts, s.session_start, HOUR) AS hours_before_conversion
  FROM conversions c
  JOIN sessions s
    ON c.user_pseudo_id = s.user_pseudo_id
   AND s.session_start <= c.conversion_ts
   AND (c.prev_conversion_ts IS NULL OR s.session_start > c.prev_conversion_ts)
   AND s.session_start >= TIMESTAMP_SUB(c.conversion_ts, INTERVAL 30 DAY)
),
-- Apply decay then normalise per user
weighted AS (
  SELECT
    user_pseudo_id,
    conversion_number,
    channel,
    -- Exponential decay: closer to conversion = higher weight
    EXP(-0.1 * hours_before_conversion) AS raw_weight,
    -- Normalise: divide by sum of weights for this user's conversion path
    EXP(-0.1 * hours_before_conversion) / NULLIF(
      SUM(EXP(-0.1 * hours_before_conversion)) OVER (
        PARTITION BY user_pseudo_id, conversion_number
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
