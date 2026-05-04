function sourceResolutionLogic() {
  return `ARRAY_AGG(
    STRUCT(source, medium, campaign, content, term, event_timestamp)
    ORDER BY
      CASE WHEN event_name NOT IN ('session_start', 'first_visit') AND (source IS NOT NULL OR medium IS NOT NULL) THEN 0 ELSE 1 END,
      CASE WHEN event_name = 'session_start' AND (source IS NOT NULL OR medium IS NOT NULL) THEN 0 ELSE 1 END,
      event_timestamp
  )[SAFE_OFFSET(0)]`;
}

module.exports = { sourceResolutionLogic };
