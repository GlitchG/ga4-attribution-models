-- ═══════════════════════════════════════════════════════════════════════════════
-- VALIDATION QUERIES — GA4 Attribution Pipeline v2.0
--
-- Run these after each pipeline execution to verify correctness.
-- All queries should return zero rows. Any non-zero result indicates a bug.
-- ═══════════════════════════════════════════════════════════════════════════════

-- 1. Credit sums to 1.0 per (conversion_id, conversion_event, model)
SELECT model, conversion_event, conversion_id, ROUND(SUM(attributed_credit), 4) AS credit_sum
FROM `${project}.attribution_models.attribution_mart`
GROUP BY 1, 2, 3
HAVING ABS(credit_sum - 1.0) > 0.001;

-- 2. No unconfigured conversion events leak into mart
SELECT DISTINCT conversion_event
FROM `${project}.attribution_models.attribution_mart`
WHERE conversion_event NOT IN (${conversion_config.getEventList()});

-- 3. Revenue mode events: total attributed value = total raw value
SELECT
  model, conversion_event,
  SUM(attributed_value_usd) AS attributed_total,
  (SELECT SUM(conversion_value_usd) FROM `${project}.intermediate.int_attribution_journeys` j
   WHERE j.conversion_event = m.conversion_event) AS raw_total
FROM `${project}.attribution_models.attribution_mart` m
WHERE conversion_event IN (${conversion_config.getRevenueEvents()})
GROUP BY 1, 2
HAVING ABS(attributed_total - raw_total) > 1.0;

-- 4. Count mode events: attributed_value_usd IS NULL (not zero)
SELECT model, conversion_event, COUNT(*) AS bad_rows
FROM `${project}.attribution_models.attribution_mart`
WHERE conversion_event IN (${conversion_config.getCountEvents()})
  AND attributed_value_usd IS NOT NULL
GROUP BY 1, 2;

-- 5. Fixed mode events: attributed_value_usd = fixed_value * credit
SELECT model, conversion_event, COUNT(*) AS bad_rows
FROM `${project}.attribution_models.attribution_mart`
WHERE conversion_event IN (${conversion_config.getFixedEvents()})
  AND ABS(attributed_value_usd - (attributed_credit * 50.0)) > 0.01
GROUP BY 1, 2;

-- 6. Channel coverage matches getChannelList()
SELECT DISTINCT channel
FROM `${project}.attribution_models.attribution_mart`
WHERE channel NOT IN (${channel_grouping.getChannelList().map(c => `'${c}'`).join(', ')});

-- 7. Each conversion_event has BQML output (if BQML ran)
SELECT conversion_event, COUNT(*) AS rows
FROM `${project}.attribution_models.attr_data_driven_bqml`
GROUP BY 1;

-- 8. BQML channel coverage matches getChannelList()
SELECT DISTINCT channel
FROM `${project}.attribution_models.attr_data_driven_bqml`
WHERE channel NOT IN (${channel_grouping.getChannelList().map(c => `'${c}'`).join(', ')});

-- 9. No duplicate (user_pseudo_id, session_id) in staging
SELECT user_pseudo_id, session_id, COUNT(*) AS dupes
FROM `${project}.staging.stg_ga4_sessions`
GROUP BY 1, 2
HAVING COUNT(*) > 1;

-- 10. No duplicate (user_pseudo_id, conversion_ts, conversion_event) in journeys
SELECT user_pseudo_id, conversion_ts, conversion_event, COUNT(*) AS dupes
FROM `${project}.intermediate.int_attribution_journeys`
GROUP BY 1, 2, 3
HAVING COUNT(*) > 1;
