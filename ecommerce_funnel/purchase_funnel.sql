-- Ecommerce Purchase Funnel Analysis
-- Tracks users through: view_item → add_to_cart → begin_checkout → purchase

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

WITH funnel_steps AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name IN ('view_item', 'add_to_cart', 'begin_checkout', 'purchase')
),
session_funnel AS (
  SELECT
    session_id,
    COUNT(DISTINCT IF(event_name = 'view_item', user_pseudo_id, NULL)) AS viewed_items,
    COUNT(DISTINCT IF(event_name = 'add_to_cart', user_pseudo_id, NULL)) AS added_to_cart,
    COUNT(DISTINCT IF(event_name = 'begin_checkout', user_pseudo_id, NULL)) AS began_checkout,
    COUNT(DISTINCT IF(event_name = 'purchase', user_pseudo_id, NULL)) AS purchased
  FROM funnel_steps
  GROUP BY session_id
)
SELECT
  'View Item' AS step,
  viewed_items AS users,
  100.0 AS pct_of_previous,
  100.0 AS pct_of_start
FROM session_funnel

UNION ALL

SELECT
  'Add to Cart' AS step,
  added_to_cart AS users,
  ROUND(added_to_cart * 100.0 / viewed_items, 2) AS pct_of_previous,
  ROUND(added_to_cart * 100.0 / viewed_items, 2) AS pct_of_start
FROM session_funnel

UNION ALL

SELECT
  'Begin Checkout' AS step,
  began_checkout AS users,
  ROUND(began_checkout * 100.0 / added_to_cart, 2) AS pct_of_previous,
  ROUND(began_checkout * 100.0 / viewed_items, 2) AS pct_of_start
FROM session_funnel

UNION ALL

SELECT
  'Purchase' AS step,
  purchased AS users,
  ROUND(purchased * 100.0 / began_checkout, 2) AS pct_of_previous,
  ROUND(purchased * 100.0 / viewed_items, 2) AS pct_of_start
FROM session_funnel;
