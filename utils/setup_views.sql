# Setup Views for GA4 Attribution Analysis

-- This script helps you set up a reusable view for GA4 analysis
-- To use: Replace `your_project.your_dataset` with your own BigQuery project and dataset
-- Then run the CREATE VIEW statement

-- Option 1: Create a view in your own dataset (uncomment and update):
-- CREATE OR REPLACE VIEW `your_project.your_dataset.ga4_events_view` AS
-- SELECT
--   user_pseudo_id,
--   event_name,
--   event_timestamp,
--   (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
--   (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_number') AS session_number,
--   (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source,
--   (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS medium,
--   (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'campaign') AS campaign,
--   (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location
-- FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
-- WHERE _TABLE_SUFFIX BETWEEN '20210101' AND '20210131';

-- Option 2: Direct query (no setup needed, works immediately):
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
WHERE _TABLE_SUFFIX BETWEEN '20210101' AND '20210131'
LIMIT 100;
