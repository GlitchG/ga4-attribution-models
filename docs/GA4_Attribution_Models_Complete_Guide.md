# GA4 Attribution Models v2.0

## A Practical Guide to Session-Based Multi-Touch Attribution in BigQuery

---

**Version:** 2.0.0  
**Last updated:** May 2026  
**Repository:** github.com/GlitchG/ga4-attribution-models  
**License:** MIT

---

## What This Project Does

This is a production-ready Dataform pipeline that turns raw GA4 BigQuery export data into eight different attribution models. It answers the question every marketing team asks: which channels actually drive conversions?

Unlike GA4's built-in attribution reports (which only show one model at a time and only for purchase events), this pipeline lets you compare all major attribution models side by side, across any conversion event you care about, with full control over how revenue is counted.

**What you get:**
- Eight attribution models running on the same dataset
- Multi-conversion support (not just purchases)
- 17-channel taxonomy with brand vs non-brand split
- Automatic source extraction that works with any GA4 export version
- Full ecommerce payload plus click IDs, page context, and privacy fields
- A single mart table that feeds into Looker Studio, Tableau, or any BI tool

---

## What Changed in v2.0

If you used v1.x, here is what is new:

| What | v1.x | v2.0 |
|---|---|---|
| Conversion events | Hardcoded `purchase` only | Configure any event in one file |
| Value tracking | Revenue only | Revenue, fixed value, or count only |
| Channels | 8 | 17 (including brand split) |
| Source extraction | Manual `event_params` only | Auto mode that adapts to your export version |
| Click IDs | None | gclid, dclid, srsltid, and more |
| Privacy fields | None | Consent mode v2 passthrough |
| Column names | `purchase_revenue` | `conversion_value_usd` (event-agnostic) |

---

## Architecture

The pipeline is session-based, not event-based. A session is the atomic unit of a marketing touchpoint. Here is the flow:

```
GA4 events_* (raw export)
    ↓
stg_ga4_sessions — deduplicated sessions with source/medium
stg_ga4_conversions — all configured conversion events
    ↓
int_attribution_journeys — for each conversion, all sessions within lookback window
int_attribution_path_rows — unnested into one row per session per conversion
    ↓
Eight attribution models (run in parallel)
    ↓
attribution_mart — unified output table
cross_channel_comparison — pre-aggregated for dashboards
```

**Key design choices:**

- **Session deduplication:** Every session is identified by `user_pseudo_id + ga_session_id`. Duplicates are removed with `ROW_NUMBER()`.
- **Conversion deduplication:** Every conversion is identified by `user_pseudo_id + event_timestamp + transaction_id` (or event name if no transaction ID).
- **Multi-conversion:** A single user can convert multiple times. Each conversion gets its own journey. No merging.
- **Ordered paths:** Sessions within a journey are sorted by `session_start`, with position numbering for model calculations.
- **Exact lookback:** The pipeline does not just filter by date range. It checks every session's timestamp against the conversion timestamp, ensuring the lookback is exact.

---

## Prerequisites

Before you start, you need:

1. **A Google Cloud project** with BigQuery enabled
2. **A GA4 BigQuery export** (your own data or the public sample)
3. **Dataform CLI** installed: `npm install -g @dataform/cli`
4. **BigQuery permissions:** Your service account needs `bigquery.dataEditor` and `bigquery.jobUser`

---

## Setup

### Step 1: Clone and install

```bash
git clone https://github.com/GlitchG/ga4-attribution-models.git
cd ga4-attribution-models
npm install
```

### Step 2: Create credentials

Create a file called `.df-credentials.json` in the project root:

```json
{
  "projectId": "your-gcp-project",
  "location": "US",
  "credentials": "BASE64_ENCODED_SERVICE_ACCOUNT_JSON"
}
```

To get the base64 string:

```bash
cat your-service-account.json | base64 -w 0
```

**Alternative:** If you are logged in with `gcloud auth application-default login`, you can use `"credentials": "gcloud"` instead of base64.

### Step 3: Configure your dataset

Open `workflow_settings.yaml` and set these variables:

```yaml
defaultProject: your-gcp-project
vars:
  ga4_project: "your-ga4-project"
  ga4_dataset: "analytics_123456789"
  start_date: "20240101"
  end_date: "20240131"
  lookback_days: "30"
  source_extraction_mode: "event_params"
  exclude_modeled_events: "false"
```

**What each variable does:**

| Variable | Default | What it controls |
|---|---|---|
| `ga4_project` | `bigquery-public-data` | Which GCP project has your GA4 data |
| `ga4_dataset` | `ga4_obfuscated_sample_ecommerce` | Which dataset |
| `start_date` / `end_date` | 2020-11-01 to 2020-12-20 | Date range to analyse |
| `lookback_days` | 30 | How many days before a conversion to include sessions |
| `source_extraction_mode` | event_params | How to extract source/medium (see below) |
| `exclude_modeled_events` | false | Whether to exclude consent-modeled events |

### Step 4: Compile

```bash
dataform compile --default-database=your-gcp-project
```

You should see `Compiled 32 action(s).` with no errors.

### Step 5: Run

```bash
dataform run --default-database=your-gcp-project
```

The first run will take about 9 minutes on the public sample. Production datasets will vary.

---

## Configuration Guide

### Conversion Events

All conversion configuration lives in one file: `includes/conversion_config.js`.

Here is the default:

```javascript
const CONVERSION_EVENTS = [
  {
    event: 'purchase',
    value_mode: 'revenue',
    description: 'Completed purchase'
  },
  {
    event: 'begin_checkout',
    value_mode: 'count',
    description: 'Checkout started'
  },
  {
    event: 'add_to_cart',
    value_mode: 'count',
    description: 'Item added to cart'
  }
];
```

**To add a new conversion:**

1. Append a new object to the array
2. Choose a `value_mode`:
   - `revenue` — uses `purchase_revenue_in_usd` from the GA4 event
   - `fixed` — assign a fixed dollar value (edit `getValueExpr()` to set the amount)
   - `count` — no monetary value; the model counts conversions only
3. Recompile and run

No SQL files need editing. The pipeline reads this config automatically.

**Example — adding a lead form submission:**

```javascript
{
  event: 'generate_lead',
  value_mode: 'fixed',
  description: 'Lead form submitted'
}
```

Then in `getValueExpr()`, add:

```javascript
if (evt.event === 'generate_lead') return '50.0';
```

This assigns $50 to every lead submission.

### Channel Grouping

The pipeline uses a 17-channel taxonomy defined in `includes/channel_grouping.js`:

1. Cross-network
2. Paid Search Brand
3. Paid Search Non-Brand
4. Paid Shopping
5. Paid Social
6. Paid Video
7. Display
8. Organic Search
9. Organic Shopping
10. Organic Social
11. Organic Video
12. Email
13. SMS
14. Affiliate
15. Audio
16. Mobile Push
17. Referral
18. Direct

**To change the brand terms** (for the Paid Search Brand / Non-Brand split):

Edit `includes/constants.js`:

```javascript
const BRAND_TERMS_REGEX = 'mybrand|mycompany|myproduct';
```

If the source field matches this regex (case-insensitive), the channel becomes "Paid Search Brand". Otherwise it becomes "Paid Search Non-Brand".

**To add a custom channel:**

Edit `includes/channel_grouping.js` and add a `WHEN` clause before the `ELSE` catch-all. Also add the channel name to `getChannelList()` so the BQML model knows about it.

### Source Extraction Mode

This is the most important config decision. GA4 has changed its BigQuery schema multiple times, and different fields work best for different export versions.

| Mode | Use when | Description |
|---|---|---|
| `event_params` | Any export (default) | Extracts source/medium from event-level `event_params`. Works on all GA4 exports, including the public sample. |
| `session_stslc` | Post-July 2024 exports | Uses `session_traffic_source_last_click.cross_channel_campaign`. Matches GA4 UI attribution. Fixes the google/organic misattribution bug. |
| `collected` | Post-June 2023 exports | Uses `collected_traffic_source.manual_source`. Cleaner than UNNEST, but no session scoping. |
| `auto` | Post-July 2024 exports | Tries `session_stslc` first, then `collected`, then `event_params`. Best for newer exports. |

**How to tell which mode to use:**

Run this query on your GA4 dataset:

```sql
SELECT
  COUNT(*) AS total_rows,
  COUNT(session_traffic_source_last_click.cross_channel_campaign.source) AS has_stslc,
  COUNT(collected_traffic_source.manual_source) AS has_collected
FROM `your-project.your-dataset.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
```

- If `has_stslc` > 0, use `session_stslc` or `auto`
- If `has_collected` > 0 but `has_stslc` = 0, use `collected`
- Otherwise, use `event_params` (always safe)

**Important:** The public sample dataset is from 2020. It does not have `session_traffic_source_last_click` or `collected_traffic_source`. Use `event_params` (the default) for this dataset.

### Lookback Window

Set in `workflow_settings.yaml`:

```yaml
vars:
  lookback_days: "30"
```

This means: for each conversion, include all sessions that started within 30 days before the conversion timestamp.

The pipeline also extends the `_TABLE_SUFFIX` range by `lookback_days` to ensure all relevant partitions are scanned. This is exact, not approximate.

### Privacy / Consent Mode

Set in `workflow_settings.yaml`:

```yaml
vars:
  exclude_modeled_events: "false"
```

When set to `"true"`, sessions with `privacy_info.uses_transient_token = 'Yes'` are excluded. These are events modeled by Google when consent is denied.

All privacy fields are passed through to staging and attribution tables regardless of this setting, so you can audit them in your output.

**Note:** The public sample dataset (2020) does not contain consent mode v2 fields. These will be NULL.

---

## Running the Pipeline

### Full run

```bash
dataform run --default-database=your-gcp-project
```

### Run specific parts

```bash
# Staging tables only
dataform run --tags=staging

# Attribution models (skip BQML)
dataform run --tags=attribution,model

# BQML training only
dataform run --tags=ml

# Dashboard views
dataform run --tags=dashboard
```

### Force rebuild

```bash
dataform run --full-refresh
```

This drops and recreates all tables. Use when you change config or column names.

### Schedule in production

Option 1: Dataform UI scheduling (recommended)
- Open your Dataform project in the GCP console
- Go to "Workflows" and click "Schedule"
- Set cron expression: `0 6 * * *` (daily at 6 AM UTC)

Option 2: Cloud Scheduler

```bash
gcloud scheduler jobs create http daily-attribution \
  --schedule="0 6 * * *" \
  --uri="https://dataform.googleapis.com/v1beta1/projects/YOUR_PROJECT/locations/us/repositories/ga4-attribution-models/workflowInvocations" \
  --http-method=POST \
  --message-body='{"compilationResult":"projects/YOUR_PROJECT/locations/us/repositories/ga4-attribution-models/compilationResults/latest"}'
```

---

## Understanding the Output

### attribution_mart

This is the main output table. One row per touchpoint per conversion per model.

**Key columns:**

| Column | What it means |
|---|---|
| `user_pseudo_id` | The GA4 user identifier |
| `conversion_id` | Unique ID for this conversion |
| `conversion_ts` | When the conversion happened |
| `conversion_event` | Event name (purchase, begin_checkout, etc.) |
| `transaction_id` | Ecommerce transaction ID (if available) |
| `conversion_value_local` | Revenue in local currency |
| `conversion_value_usd` | Revenue in USD |
| `path_length` | How many sessions were in this journey |
| `source` / `medium` / `campaign` / `channel` | The touchpoint details |
| `model` | Which attribution model |
| `attributed_credit` | Fraction of credit (always sums to 1.0 per conversion) |
| `attributed_value_usd` | Credit × conversion_value_usd |

**Example query — top channels by revenue (last-click):**

```sql
SELECT
  channel,
  SUM(attributed_value_usd) AS revenue,
  COUNT(DISTINCT conversion_id) AS conversions
FROM `your-project.attribution_models.attribution_mart`
WHERE model = 'last_click'
  AND conversion_event = 'purchase'
GROUP BY channel
ORDER BY revenue DESC;
```

### cross_channel_comparison

Pre-aggregated for dashboards. One row per model × conversion_event × channel.

| Column | What it means |
|---|---|
| `model` | Attribution model name |
| `conversion_event` | Conversion event |
| `channel` | Channel |
| `attributed_conversions` | Number of conversions |
| `total_value_local` | Sum of attributed local currency |
| `total_value_usd` | Sum of attributed USD |
| `avg_path_length` | Average path length for this segment |

**Example query — compare all models for purchase:**

```sql
SELECT
  model,
  channel,
  attributed_conversions,
  total_value_usd
FROM `your-project.attribution_models.cross_channel_comparison`
WHERE conversion_event = 'purchase'
ORDER BY model, total_value_usd DESC;
```

### int_attribution_journeys

Raw journey data for custom analysis.

```sql
-- Find the longest customer journeys
SELECT *
FROM `your-project.intermediate.int_attribution_journeys`
ORDER BY path_length DESC
LIMIT 10;
```

---

## The Eight Attribution Models

### First Click

Gives 100% credit to the first session in the journey.

**Best for:** Brand awareness campaigns. You want to know which channel introduced the customer.

### Last Click

Gives 100% credit to the last session before conversion.

**Best for:** Direct response. Simple, but overvalues bottom-funnel channels.

### Last Non-Direct Click

Gives 100% credit to the last non-Direct session. If the entire path is Direct, falls back to Direct.

**Best for:** General marketing reporting. This is what GA4 uses by default.

### Linear

Splits credit equally across all sessions.

**Best for:** Long consideration cycles where every touchpoint matters.

### Time Decay

Credit decays exponentially with a 7-day half-life. Sessions closer to conversion get more credit.

**Best for:** When recency matters. Recent touchpoints are more influential.

### U-Shape

40% to first session, 40% to last session, 20% split among middle sessions.

**Best for:** When both discovery and conversion touchpoints matter.

### Position Weighted

50% to first, 30% to last, 20% to middle.

**Best for:** A calibrated heuristic when you do not have enough data for data-driven.

### Data-Driven (BQML)

Trains a logistic regression model on your actual data. For each touchpoint, it calculates the marginal contribution to conversion probability.

**Best for:** When you have enough data (recommend: >1,000 conversions, >10,000 non-converters).

**How it works:**
1. Creates a training dataset of converted vs non-converted journeys
2. Trains a logistic regression model with 18 features (conversion_event + 17 channel flags)
3. For each touchpoint in a converted journey, predicts conversion probability with and without that channel
4. The difference is the channel's marginal contribution
5. Contributions are normalised to sum to 1.0 per conversion

**Limitations:**
- Single model for all conversion events. If your funnel stages have very different channel effects, the model averages them together.
- Training takes 2–5 minutes
- Requires sufficient training data

---

## Troubleshooting

### Compilation Errors

| Error | Cause | Fix |
|---|---|---|
| `Unrecognized name: session_traffic_source_last_click` | You set `source_extraction_mode` to `session_stslc` or `auto`, but your GA4 export does not have this field | Set `source_extraction_mode: "event_params"` |
| `No actions to run` | All tables already exist and Dataform thinks they are up to date | Use `--full-refresh` or manually delete tables |
| `Concurrent model update` | BQML model is being trained by another process | Wait 5 minutes and retry, or run `DROP MODEL IF EXISTS` |
| `Permission denied` | Service account lacks BigQuery roles | Grant `bigquery.dataEditor` and `bigquery.jobUser` |

### Runtime Errors

| Error | Cause | Fix |
|---|---|---|
| `attr_data_driven_train` fails with "empty training data" | `int_attribution_path_rows` has no rows | Check that `stg_ga4_conversions` has data. Verify your date range includes conversions. |
| `int_attribution_journeys` is empty | No conversions in the date range | Extend `start_date`/`end_date`. Check that your conversion events are configured correctly. |
| Attribution credit sums to <1.0 | Usually a path-length edge case | Update to v2.0+ (this was fixed) |
| `last_non_direct_click` drops conversions | Logic bug with session position counting | Update to v2.0+ (rewrote with ROW_NUMBER()) |
| Channel shows as "source / medium" | Catch-all triggered — unknown combination | Add channel mapping in `channel_grouping.js` |

### Data Quality Issues

| Symptom | Diagnosis | Fix |
|---|---|---|
| All sessions are "Direct" | Source extraction mode does not match your export schema | Check your GA4 export version and switch mode |
| 0 conversions | Wrong event names in config | Verify event names in `conversion_config.js` match your GA4 data |
| Revenue is NULL | `value_mode` set to `count` | Change to `revenue` in `conversion_config.js` |
| Very long paths (>20 sessions) | Bot traffic or returning users | Add bot filtering in `stg_ga4_sessions` WHERE clause |
| Duplicate sessions | Rare edge case in dedup | Check that `ga_session_id` is populated in your GA4 export |

### Performance Issues

| Symptom | Fix |
|---|---|
| Pipeline runs >30 minutes | Reduce `lookback_days`; narrow date range; use incremental models |
| High BigQuery costs | Avoid full refreshes; the pipeline already uses `_TABLE_SUFFIX` partitioning |
| BQML training fails | Ensure training table has >100 rows; check for NULL features |

---

## Validation & Testing

The pipeline was tested end-to-end on `bigquery-public-data.ga4_obfuscated_sample_ecommerce`.

### Built-in Assertions (all pass)

- 0 duplicate sessions
- 0 duplicate journeys
- 0 duplicate path rows
- Credit sums to 1.0 per conversion
- Revenue conservation: attributed total equals raw total
- 0 unexpected channels

### Dataset Characteristics

- **Date range:** 2020-11-01 to 2020-12-20
- **Total journeys:** 63,578
- **Conversion events:** purchase, begin_checkout, add_to_cart
- **Multi-conversion users:** 71% of users converted more than once
- **Path length:** 54% single-session, 17.5% two-session, 28.5% three or more
- **Average lookback:** 3.5 days
- **Max lookback:** 30 days (exact)

### Channel Distribution (public sample)

- Direct: 87.4%
- Organic Search: 12.5%
- Referral: 8.9%
- Paid Search Non-Brand: 1.1%
- Other channels: 0% (2020 merchandising store has limited paid media)

### Post-Run Validation

After every run, run these checks from `validation/validation-queries.sql`:

```sql
-- 1. Credit sums to 1.0 per conversion
SELECT model, conversion_id, SUM(attributed_credit) AS total_credit
FROM `your-project.attribution_models.attribution_mart`
GROUP BY model, conversion_id
HAVING ABS(total_credit - 1.0) > 0.01;
-- Should return 0 rows

-- 2. Revenue conservation
SELECT model, SUM(attributed_value_usd) AS attributed, SUM(conversion_value_usd) AS raw
FROM `your-project.attribution_models.attribution_mart`
WHERE conversion_event = 'purchase'
GROUP BY model
HAVING ABS(attributed - raw) > 5.0;
-- Should return 0 rows
```

---

## Performance & Cost

### Public Sample (default config)

| Stage | BigQuery Processed | Time |
|---|---|---|
| Staging | ~2.9 GiB | ~2 min |
| Intermediate | ~0.15 GiB | ~1 min |
| Attribution models (7 rule-based) | ~0.08 GiB | ~2 min |
| BQML training | ~0.05 GiB | ~3 min |
| Marts | ~0.2 GiB | ~1 min |
| **Total** | **~3.4 GiB** | **~9 min** |

**Cost:** ~$0.02 USD per run (on-demand pricing)

### Production Dataset (1B+ events)

| Optimisation | Impact |
|---|---|
| Incremental models | 10–50x faster daily runs |
| Narrow date range | Linear cost reduction |
| Reduce `lookback_days` | Fewer partitions scanned |
| Materialised intermediates | Faster model re-runs |

---

## Migration from v1.x

### Breaking Changes

| v1.x | v2.0 | Action Required |
|---|---|---|
| `purchase_revenue` | `conversion_value_local` | Update downstream queries |
| `purchase_revenue_in_usd` | `conversion_value_usd` | Update downstream queries |
| `attributed_revenue` | `attributed_value_usd` | Update downstream queries |
| `attributed_revenue_local` | `attributed_value_local` | Update downstream queries |
| Hardcoded `purchase` | Dynamic `conversion_config.js` | Edit config file |
| 8 channels | 17 channels | Update cost module mappings |

### Migration Checklist

- [ ] Update all dashboards and queries with new column names
- [ ] Review `conversion_config.js` — ensure desired events are listed
- [ ] Set `source_extraction_mode` based on your GA4 export version
- [ ] Update cost module channel mappings (if using)
- [ ] Test on public sample before production
- [ ] Run validation queries after first production run

---

## Advanced Topics

### Adding a Custom Attribution Model

1. Create `definitions/attribution_models/attr_my_model.sqlx`
2. Copy structure from `attr_linear.sqlx`
3. Implement your credit-allocation logic
4. Add to `attribution_mart.sqlx` UNION ALL
5. Add to `cross_channel_comparison.sqlx`

### Incremental Models for Production

For daily runs with large datasets, convert staging tables to incremental:

```sql
config {
  type: "incremental",
  // ...
}

SELECT * FROM ...
${when(incremental(), `WHERE _TABLE_SUFFIX >= '${constants.START_DATE}'`)}
```

### Cross-Project GA4 Exports

If your GA4 data lives in a different project:

```yaml
vars:
  ga4_project: "client-project"
  ga4_dataset: "analytics_123456789"
```

The pipeline reads from `client-project` and writes to your default database.

### Custom Conversion Value

For fixed-value conversions, edit `includes/conversion_config.js`:

```javascript
{
  event: 'sign_up',
  value_mode: 'fixed',
  fixed_value: 50.00,
  description: 'Newsletter signup'
}
```

Then update `getValueExpr()` to return `fixed_value`.

---

## FAQ

**Q: Can I run this on the public sample without a GCP project?**  
A: No. You need a GCP project to write the output tables, even when reading from the public dataset. The public dataset itself is free to query.

**Q: How do I know if my GA4 export has `session_traffic_source_last_click`?**  
A: Run the diagnostic query in the Source Extraction Mode section. If `has_stslc` > 0, you have it.

**Q: Why are all my sessions showing as Direct?**  
A: Either your source extraction mode is wrong, or your GA4 property does not pass UTM parameters correctly. Check `source` and `medium` in `stg_ga4_sessions`.

**Q: Can I exclude certain channels from attribution?**  
A: Yes. Filter them out in `stg_ga4_sessions` or add a WHERE clause in the attribution models.

**Q: Why does BQML take so long?**  
A: Model training is computationally intensive. Expect 2–5 minutes. If it fails, check that your training data has >100 rows.

**Q: Can I use this with Shopify / WooCommerce / custom ecommerce?**  
A: Yes. As long as you have a GA4 BigQuery export with ecommerce events, the pipeline works regardless of your platform.

**Q: How do I connect this to Looker Studio?**  
A: Point Looker Studio to `your-project.attribution_models.cross_channel_comparison` or `attribution_mart`.

**Q: What if I have multiple GA4 properties?**  
A: Create multiple Dataform projects, one per property. Or use a custom source that unions multiple datasets.

---

## File Reference

```
includes/
  channel_grouping.js      -- 17-channel CASE logic
  conversion_config.js     -- Conversion events + value modes
  constants.js             -- Project vars + safe defaults
  source_resolution.js     -- Source extraction mode switch

definitions/
  staging/
    stg_ga4_sessions.sqlx      -- Session extraction
    stg_ga4_conversions.sqlx   -- Conversion extraction
  intermediate/
    int_attribution_journeys.sqlx     -- Path building
    int_attribution_path_rows.sqlx    -- Row-level unnest
  attribution_models/
    attr_*.sqlx                -- 8 attribution models
    attribution_mart.sqlx      -- Unified output
    cross_channel_comparison.sqlx  -- Aggregated comparison
  ml/
    attr_data_driven_train.sqlx   -- BQML training
  cost/
    attribution_with_roas.sqlx    -- Cost enrichment (optional)
  dashboard/
    attribution_dashboard.sqlx    -- Dashboard views
  user_journey/
    path_analysis.sqlx         -- Top 100 paths

validation/
  validation-queries.sql     -- Post-run checks
```

---

*For issues or feature requests, open a GitHub issue at github.com/GlitchG/ga4-attribution-models*
