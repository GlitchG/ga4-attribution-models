// Centralised constants with safe defaults.
// Override via workflow_settings.yaml vars.
const GA4_PROJECT = dataform.projectConfig.vars.ga4_project || "bigquery-public-data";
const GA4_DATASET = dataform.projectConfig.vars.ga4_dataset || "ga4_obfuscated_sample_ecommerce";
const START_DATE = dataform.projectConfig.vars.start_date || "20201101";
const END_DATE = dataform.projectConfig.vars.end_date || "20201220";
const LOOKBACK_DAYS = dataform.projectConfig.vars.lookback_days || 30;
const SOURCE_EXTRACTION_MODE = dataform.projectConfig.vars.source_extraction_mode || "auto";
const EXCLUDE_MODELED_EVENTS = dataform.projectConfig.vars.exclude_modeled_events || "false";

// Edit this regex per client. Used to split Paid Search into Brand vs Non-Brand.
// Examples: 'mybrand|my-brand|brandcampaign' or '^BRD_'.
const BRAND_TERMS_REGEX = 'your-brand-here|yourbrand';

function getModeledEventsFilter() {
  return EXCLUDE_MODELED_EVENTS === "true"
    ? "AND COALESCE(privacy_info.uses_transient_token, 'No') != 'Yes'"
    : "";
}

module.exports = { GA4_PROJECT, GA4_DATASET, START_DATE, END_DATE, LOOKBACK_DAYS, SOURCE_EXTRACTION_MODE, EXCLUDE_MODELED_EVENTS, BRAND_TERMS_REGEX, getModeledEventsFilter };
