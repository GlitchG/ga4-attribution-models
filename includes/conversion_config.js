// Defines all conversion events the pipeline tracks.
// Add a new conversion type by appending to CONVERSION_EVENTS — no SQL changes needed.
const CONVERSION_EVENTS = [
  {
    event: 'purchase',
    value_mode: 'revenue',           // 'revenue' | 'fixed' | 'count'
    value_field: 'purchase_revenue_in_usd',
    fixed_value_usd: null,
    lookback_days: 30
  },
  {
    event: 'begin_checkout',
    value_mode: 'count',
    value_field: null,
    fixed_value_usd: null,
    lookback_days: 14
  },
  {
    event: 'add_to_cart',
    value_mode: 'count',
    value_field: null,
    fixed_value_usd: null,
    lookback_days: 7
  },
  // Lead-gen template — uncomment and edit per client:
  // {
  //   event: 'generate_lead',
  //   value_mode: 'fixed',
  //   value_field: null,
  //   fixed_value_usd: 50.0,
  //   lookback_days: 7
  // },
];

function getEventList() {
  return CONVERSION_EVENTS.map(e => `'${e.event}'`).join(', ');
}

function getMaxLookback() {
  return Math.max(...CONVERSION_EVENTS.map(e => e.lookback_days));
}

function getLookbackCase(eventColumn) {
  // Returns SQL CASE expression mapping event name → lookback_days
  const cases = CONVERSION_EVENTS
    .map(e => `WHEN ${eventColumn} = '${e.event}' THEN ${e.lookback_days}`)
    .join('\n      ');
  return `CASE\n      ${cases}\n      ELSE 30\n    END`;
}

function getValueExpr(eventColumn, revenueColumn, creditColumn) {
  // Returns SQL CASE expression computing attributed_value_usd per event.
  // For 'count' mode, returns NULL (dashboards distinguish from zero).
  const cases = CONVERSION_EVENTS.map(e => {
    if (e.value_mode === 'revenue') {
      return `WHEN ${eventColumn} = '${e.event}' THEN ${revenueColumn} * ${creditColumn}`;
    } else if (e.value_mode === 'fixed') {
      return `WHEN ${eventColumn} = '${e.event}' THEN ${e.fixed_value_usd} * ${creditColumn}`;
    } else {
      return `WHEN ${eventColumn} = '${e.event}' THEN NULL`;
    }
  }).join('\n      ');
  return `CASE\n      ${cases}\n      ELSE NULL\n    END`;
}

function getValueModeCase(eventColumn) {
  const cases = CONVERSION_EVENTS
    .map(e => `WHEN ${eventColumn} = '${e.event}' THEN '${e.value_mode}'`)
    .join('\n      ');
  return `CASE\n      ${cases}\n      ELSE 'count'\n    END`;
}

function getRevenueEvents() {
  return CONVERSION_EVENTS.filter(e => e.value_mode === 'revenue').map(e => `'${e.event}'`).join(', ');
}

function getFixedEvents() {
  return CONVERSION_EVENTS.filter(e => e.value_mode === 'fixed').map(e => `'${e.event}'`).join(', ');
}

function getCountEvents() {
  return CONVERSION_EVENTS.filter(e => e.value_mode === 'count').map(e => `'${e.event}'`).join(', ');
}

module.exports = {
  CONVERSION_EVENTS,
  getEventList,
  getMaxLookback,
  getLookbackCase,
  getValueExpr,
  getValueModeCase,
  getRevenueEvents,
  getFixedEvents,
  getCountEvents
};
