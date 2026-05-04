function ga4EventsTable() {
  const project = dataform.projectConfig.vars.ga4_project || 'bigquery-public-data';
  const dataset = dataform.projectConfig.vars.ga4_dataset || 'ga4_obfuscated_sample_ecommerce';
  return `\`${project}.${dataset}.events_*\``;
}

module.exports = { ga4EventsTable };
