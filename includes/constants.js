// Centralised constants with safe defaults.
// Override via workflow_settings.yaml vars.
const GA4_PROJECT = dataform.projectConfig.vars.ga4_project || "bigquery-public-data";
const GA4_DATASET = dataform.projectConfig.vars.ga4_dataset || "ga4_obfuscated_sample_ecommerce";
const START_DATE = dataform.projectConfig.vars.start_date || "20201101";
const END_DATE = dataform.projectConfig.vars.end_date || "20201220";
const LOOKBACK_DAYS = dataform.projectConfig.vars.lookback_days || 30;

module.exports = { GA4_PROJECT, GA4_DATASET, START_DATE, END_DATE, LOOKBACK_DAYS };
