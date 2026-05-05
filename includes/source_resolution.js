function sourceResolutionLogic_eventParams() {
  return `ARRAY_AGG(
    STRUCT(source, medium, campaign, content, term, event_timestamp)
    ORDER BY
      CASE WHEN event_name NOT IN ('session_start', 'first_visit') AND (source IS NOT NULL OR medium IS NOT NULL) THEN 0 ELSE 1 END,
      CASE WHEN event_name = 'session_start' AND (source IS NOT NULL OR medium IS NOT NULL) THEN 0 ELSE 1 END,
      event_timestamp
  )[SAFE_OFFSET(0)]`;
}

function sourceResolutionLogic_collected() {
  return `STRUCT(
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_campaign_name AS campaign,
    collected_traffic_source.manual_content AS content,
    collected_traffic_source.manual_term AS term,
    event_timestamp
  )`;
}

function sourceResolutionLogic_sessionStslc() {
  return `STRUCT(
    session_traffic_source_last_click.cross_channel_campaign.source AS source,
    session_traffic_source_last_click.cross_channel_campaign.medium AS medium,
    session_traffic_source_last_click.cross_channel_campaign.campaign_name AS campaign,
    session_traffic_source_last_click.cross_channel_campaign.content AS content,
    session_traffic_source_last_click.cross_channel_campaign.term AS term,
    event_timestamp
  )`;
}

function resolveSourceLogic(mode) {
  if (mode === 'event_params') {
    return sourceResolutionLogic_eventParams();
  }
  if (mode === 'collected') {
    return sourceResolutionLogic_collected();
  }
  if (mode === 'session_stslc') {
    return sourceResolutionLogic_sessionStslc();
  }

  // Auto mode: COALESCE across all three sources with priority
  // session_stslc > collected > event_params
  // Missing columns in older exports gracefully fall through via SAFE. prefix
  return `STRUCT(
    COALESCE(
      SAFE.session_traffic_source_last_click.cross_channel_campaign.source,
      SAFE.collected_traffic_source.manual_source,
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source')
    ) AS source,
    COALESCE(
      SAFE.session_traffic_source_last_click.cross_channel_campaign.medium,
      SAFE.collected_traffic_source.manual_medium,
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium')
    ) AS medium,
    COALESCE(
      SAFE.session_traffic_source_last_click.cross_channel_campaign.campaign_name,
      SAFE.collected_traffic_source.manual_campaign_name,
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'campaign')
    ) AS campaign,
    COALESCE(
      SAFE.session_traffic_source_last_click.cross_channel_campaign.content,
      SAFE.collected_traffic_source.manual_content,
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'content')
    ) AS content,
    COALESCE(
      SAFE.session_traffic_source_last_click.cross_channel_campaign.term,
      SAFE.collected_traffic_source.manual_term,
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'term')
    ) AS term,
    event_timestamp
  )`;
}

module.exports = { resolveSourceLogic };
