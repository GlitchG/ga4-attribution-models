-- ═══════════════════════════════════════════════════════════════════════════════
-- VALIDATION QUERIES — GA4 Attribution Pipeline v2.0
--
-- Run these after each pipeline execution to verify correctness.
-- All queries should return zero rows. Any non-zero result indicates a bug.
--
-- INSTRUCTIONS: Replace YOUR_PROJECT_ID with your actual GCP project ID
-- before running. These queries are plain BigQuery SQL (not Dataform-compiled).
-- ═══════════════════════════════════════════════════════════════════════════════

DECLARE project_id STRING DEFAULT 'YOUR_PROJECT_ID';

-- 1. Credit sums to 1.0 per (conversion_id, conversion_event, model)
EXECUTE IMMEDIATE """
SELECT model, conversion_event, conversion_id, ROUND(SUM(attributed_credit), 4) AS credit_sum
FROM `""" || project_id || """.attribution_models.attribution_mart`
GROUP BY 1, 2, 3
HAVING ABS(credit_sum - 1.0) > 0.001
""";

-- 2. No unconfigured conversion events leak into mart
EXECUTE IMMEDIATE """
SELECT DISTINCT conversion_event
FROM `""" || project_id || """.attribution_models.attribution_mart`
WHERE conversion_event NOT IN ('purchase', 'begin_checkout', 'add_to_cart')
""";

-- 3. Revenue mode events: total attributed value = total raw value
EXECUTE IMMEDIATE """
SELECT
  model, conversion_event,
  SUM(attributed_value_usd) AS attributed_total,
  (SELECT SUM(conversion_value_usd) FROM `""" || project_id || """.intermediate.int_attribution_journeys` j
   WHERE j.conversion_event = m.conversion_event) AS raw_total
FROM `""" || project_id || """.attribution_models.attribution_mart` m
WHERE conversion_event IN ('purchase')
GROUP BY 1, 2
HAVING ABS(attributed_total - raw_total) > 5.0
""";

-- 4. Count mode events: attributed_value_usd IS NULL (not zero)
EXECUTE IMMEDIATE """
SELECT model, conversion_event, COUNT(*) AS bad_rows
FROM `""" || project_id || """.attribution_models.attribution_mart`
WHERE conversion_event IN ('begin_checkout', 'add_to_cart')
  AND attributed_value_usd IS NOT NULL
GROUP BY 1, 2
""";

-- 5. Fixed mode events: attributed_value_usd = fixed_value * credit
-- (No fixed-value events currently configured; uncomment and edit when adding one)
-- EXECUTE IMMEDIATE """
-- SELECT model, conversion_event, COUNT(*) AS bad_rows
-- FROM `""" || project_id || """.attribution_models.attribution_mart`
-- WHERE conversion_event IN ('generate_lead')
--   AND ABS(attributed_value_usd - (attributed_credit * 50.0)) > 0.01
-- GROUP BY 1, 2
-- """;

-- 6. Channel coverage matches expected list
EXECUTE IMMEDIATE """
SELECT DISTINCT channel
FROM `""" || project_id || """.attribution_models.attribution_mart`
WHERE channel NOT IN (
  'Cross-network', 'Paid Search Brand', 'Paid Search Non-Brand',
  'Paid Shopping', 'Paid Social', 'Paid Video', 'Display',
  'Organic Search', 'Organic Shopping', 'Organic Social', 'Organic Video',
  'Email', 'SMS', 'Affiliate', 'Audio', 'Mobile Push', 'Referral', 'Direct', 'Unknown'
)
""";

-- 7. Each conversion_event has BQML output (if BQML ran)
EXECUTE IMMEDIATE """
SELECT conversion_event, COUNT(*) AS rows
FROM `""" || project_id || """.attribution_models.attr_data_driven_bqml`
GROUP BY 1
""";

-- 8. BQML channel coverage matches expected list
EXECUTE IMMEDIATE """
SELECT DISTINCT channel
FROM `""" || project_id || """.attribution_models.attr_data_driven_bqml`
WHERE channel NOT IN (
  'Cross-network', 'Paid Search Brand', 'Paid Search Non-Brand',
  'Paid Shopping', 'Paid Social', 'Paid Video', 'Display',
  'Organic Search', 'Organic Shopping', 'Organic Social', 'Organic Video',
  'Email', 'SMS', 'Affiliate', 'Audio', 'Mobile Push', 'Referral', 'Direct', 'Unknown'
)
""";

-- 9. No duplicate (user_pseudo_id, session_id) in staging
EXECUTE IMMEDIATE """
SELECT user_pseudo_id, session_id, COUNT(*) AS dupes
FROM `""" || project_id || """.staging.stg_ga4_sessions`
GROUP BY 1, 2
HAVING COUNT(*) > 1
""";

-- 10. No duplicate (user_pseudo_id, conversion_ts, conversion_event, transaction_id) in journeys
EXECUTE IMMEDIATE """
SELECT user_pseudo_id, conversion_ts, conversion_event, transaction_id, COUNT(*) AS dupes
FROM `""" || project_id || """.intermediate.int_attribution_journeys`
GROUP BY 1, 2, 3, 4
HAVING COUNT(*) > 1
""";
