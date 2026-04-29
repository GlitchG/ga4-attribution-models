# Setup Views for GA4 Attribution Analysis

-- Create a view to simplify GA4 event data access
-- Run this once to set up reusable views

CREATE OR REPLACE VIEW `marketing-test-task.ga4_analysis.events_view` AS
SELECT
  user_pseudo_id,
  event_name,
  event_timestamp,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_number') AS session_number,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS medium,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'campaign') AS campaign,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20210101' AND '20210131';

-- Verify the view
SELECT COUNT(*) as total_events FROM `marketing-test-task.ga4_analysis.events_view`;
