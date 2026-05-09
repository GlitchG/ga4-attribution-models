// Source resolution SQL fragments for stg_ga4_sessions.sqlx.
// Mode is controlled by the source_extraction_mode var (falls back to constants.SOURCE_EXTRACTION_MODE).
const constants = require('./constants');

function getSourceResolutionFrag() {
  var mode = dataform.projectConfig.vars.source_extraction_mode || constants.SOURCE_EXTRACTION_MODE || 'event_params';
  if (mode === 'event_params') {
    return `
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS source,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS medium,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'campaign') AS campaign,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'content') AS content,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'term') AS term,`;
  } else if (mode === 'session_stslc') {
    return `
    session_traffic_source_last_click.cross_channel_campaign.source AS source,
    session_traffic_source_last_click.cross_channel_campaign.medium AS medium,
    session_traffic_source_last_click.cross_channel_campaign.campaign_name AS campaign,
    session_traffic_source_last_click.cross_channel_campaign.content AS content,
    session_traffic_source_last_click.cross_channel_campaign.term AS term,`;
  } else if (mode === 'collected') {
    return `
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_campaign_name AS campaign,
    collected_traffic_source.manual_content AS content,
    collected_traffic_source.manual_term AS term,`;
  } else {
    return `
    COALESCE(
      session_traffic_source_last_click.cross_channel_campaign.source,
      collected_traffic_source.manual_source,
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source')
    ) AS source,
    COALESCE(
      session_traffic_source_last_click.cross_channel_campaign.medium,
      collected_traffic_source.manual_medium,
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium')
    ) AS medium,
    COALESCE(
      session_traffic_source_last_click.cross_channel_campaign.campaign_name,
      collected_traffic_source.manual_campaign_name,
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'campaign')
    ) AS campaign,
    COALESCE(
      session_traffic_source_last_click.cross_channel_campaign.content,
      collected_traffic_source.manual_content,
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'content')
    ) AS content,
    COALESCE(
      session_traffic_source_last_click.cross_channel_campaign.term,
      collected_traffic_source.manual_term,
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'term')
    ) AS term,`;
  }
}

function getClickIdFrag() {
  var mode = dataform.projectConfig.vars.source_extraction_mode || constants.SOURCE_EXTRACTION_MODE || 'event_params';
  if (mode === 'event_params' || mode === 'session_stslc') {
    return `
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'gclid') AS gclid,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'dclid') AS dclid,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'srsltid') AS srsltid,`;
  } else if (mode === 'collected') {
    return `
    collected_traffic_source.gclid AS gclid,
    collected_traffic_source.dclid AS dclid,
    collected_traffic_source.srsltid AS srsltid,`;
  } else {
    return `
    COALESCE(collected_traffic_source.gclid, (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'gclid')) AS gclid,
    COALESCE(collected_traffic_source.dclid, (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'dclid')) AS dclid,
    COALESCE(collected_traffic_source.srsltid, (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'srsltid')) AS srsltid,`;
  }
}

function getPrivacyFrag() {
  var hasPrivacy = dataform.projectConfig.vars.has_privacy_info === "true";
  if (hasPrivacy) {
    return `privacy_info.analytics_storage AS privacy_analytics_storage,
    privacy_info.ads_storage AS privacy_ads_storage,
    privacy_info.uses_transient_token AS privacy_uses_transient_token,`;
  } else {
    return `NULL AS privacy_analytics_storage,
    NULL AS privacy_ads_storage,
    NULL AS privacy_uses_transient_token,`;
  }
}

module.exports = { getSourceResolutionFrag, getClickIdFrag, getPrivacyFrag };
