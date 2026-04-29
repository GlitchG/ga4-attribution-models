-- Cart Abandonment Analysis
-- Identifies users who added items to cart but didn't complete purchase

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

WITH user_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    ARRAY_AGG(DISTINCT event_name) AS events
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
  GROUP BY 1, 2
),
cart_activity AS (
  SELECT
    user_pseudo_id,
    session_id,
    'add_to_cart' IN UNNEST(events) AS added_to_cart,
    'purchase' IN UNNEST(events) AS purchased
  FROM user_sessions
),
abandonment_stats AS (
  SELECT
    COUNT(DISTINCT user_pseudo_id || '-' || session_id) AS total_cart_sessions,
    COUNT(DISTINCT IF(added_to_cart AND NOT purchased, user_pseudo_id || '-' || session_id, NULL)) AS abandoned_carts,
    COUNT(DISTINCT IF(added_to_cart AND purchased, user_pseudo_id || '-' || session_id, NULL)) AS completed_purchases
  FROM cart_activity
  WHERE added_to_cart
)
SELECT
  total_cart_sessions,
  abandoned_carts,
  completed_purchases,
  ROUND(abandoned_carts * 100.0 / total_cart_sessions, 2) AS abandonment_rate_pct,
  ROUND(completed_purchases * 100.0 / total_cart_sessions, 2) AS conversion_rate_pct
FROM abandonment_stats;
