-- Ecommerce Purchase Funnel Analysis
-- Tracks users through: view_item → add_to_cart → begin_checkout → purchase
-- Reports drop-off rates between each sequential stage

DECLARE start_date STRING DEFAULT '20210101';
DECLARE end_date STRING DEFAULT '20210131';

WITH funnel_events AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
    AND event_name IN ('view_item', 'add_to_cart', 'begin_checkout', 'purchase')
),
-- Aggregate across all users/sessions — single funnel
funnel_counts AS (
  SELECT
    COUNT(DISTINCT IF(event_name = 'view_item', user_pseudo_id, NULL)) AS viewed_items,
    COUNT(DISTINCT IF(event_name = 'add_to_cart', user_pseudo_id, NULL)) AS added_to_cart,
    COUNT(DISTINCT IF(event_name = 'begin_checkout', user_pseudo_id, NULL)) AS began_checkout,
    COUNT(DISTINCT IF(event_name = 'purchase', user_pseudo_id, NULL)) AS purchased
  FROM funnel_events
)
SELECT 'View Item' AS step, viewed_items AS users,
  NULL AS pct_of_previous,
  ROUND(viewed_items * 100.0 / NULLIF(viewed_items, 0), 2) AS pct_of_start
FROM funnel_counts

UNION ALL

SELECT 'Add to Cart' AS step, added_to_cart AS users,
  ROUND(added_to_cart * 100.0 / NULLIF(viewed_items, 0), 2) AS pct_of_previous,
  ROUND(added_to_cart * 100.0 / NULLIF(viewed_items, 0), 2) AS pct_of_start
FROM funnel_counts

UNION ALL

SELECT 'Begin Checkout' AS step, began_checkout AS users,
  ROUND(began_checkout * 100.0 / NULLIF(added_to_cart, 0), 2) AS pct_of_previous,
  ROUND(began_checkout * 100.0 / NULLIF(viewed_items, 0), 2) AS pct_of_start
FROM funnel_counts

UNION ALL

SELECT 'Purchase' AS step, purchased AS users,
  ROUND(purchased * 100.0 / NULLIF(began_checkout, 0), 2) AS pct_of_previous,
  ROUND(purchased * 100.0 / NULLIF(viewed_items, 0), 2) AS pct_of_start
FROM funnel_counts;
