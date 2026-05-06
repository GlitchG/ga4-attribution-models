# GA4 Attribution Models — Usage Guide (v2.0)

**Repository:** [github.com/GlitchG/ga4-attribution-models](https://github.com/GlitchG/ga4-attribution-models)  
**License:** MIT  
**Dataform version:** 3.0.55  
**Last updated:** 2026-05-06

---

## Table of Contents

1. [What This Project Does](#1-what-this-project-does)
2. [Quick Start](#2-quick-start)
3. [Architecture Overview](#3-architecture-overview)
4. [Configuration](#4-configuration)
5. [Running the Pipeline](#5-running-the-pipeline)
6. [Understanding the Output](#6-understanding-the-output)
7. [Attribution Models Explained](#7-attribution-models-explained)
8. [Looker Studio Dashboards](#8-looker-studio-dashboards)
9. [Cost Module (Optional ROAS)](#9-cost-module-optional-roas)
10. [Validation & Testing](#10-validation--testing)
11. [Troubleshooting](#11-troubleshooting)
12. [Performance & Cost](#12-performance--cost)
13. [Migration from v1.x](#13-migration-from-v1x)
14. [Appendix: File Reference](#14-appendix-file-reference)

---

## 1. What This Project Does

This is a production-ready Dataform pipeline that turns raw GA4 BigQuery export data into eight different attribution models. It answers the question every marketing team asks: which channels actually drive conversions?

Unlike GA4's built-in attribution reports (which only show one model at a time and only for purchase events), this pipeline lets you compare all major attribution models side by side, across any conversion event you care about, with full control over how revenue is counted.

**What you get:**
- Eight attribution models running on the same dataset
- Multi-conversion support (not just purchases)
- 19-channel taxonomy with brand vs non-brand split
- Automatic source extraction that works with any GA4 export version
- Full ecommerce payload plus click IDs, page context, and privacy fields
- A single mart table that feeds into Looker Studio, Tableau, or any BI tool
- Optional cost module for ROAS, CPA, and marginal revenue

### What Changed in v2.0

If you used v1.x, here is what is new:

| What | v1.x | v2.0 |
|---|---|---|
| Conversion events | Hardcoded `purchase` only | Configure any event in one file |
| Value tracking | Revenue only | Revenue, fixed value, or count only |
|| Channels | 8 | 19 (including brand split + Unknown) |
| Source extraction | Manual `event_params` only | Auto mode that adapts to your export version |
| Click IDs | None | gclid, dclid, srsltid, and more |
| Privacy fields | None | Consent mode v2 passthrough |
| Column names | `purchase_revenue` | `conversion_value_usd` (event-agnostic) |

---

## 2. Quick Start

### Prerequisites

- A Google Cloud project with BigQuery enabled
- A GA4 BigQuery export (public or private)
- [Dataform CLI](https://www.npmjs.com/package/@dataform/cli) installed (`npm install -g @dataform/cli`)
- BigQuery permissions: `bigquery.dataEditor`, `bigquery.jobUser`

### One-minute setup

```bash
# Clone the repository
git clone https://github.com/GlitchG/ga4-attribution-models.git
cd ga4-attribution-models

# Install dependencies
npm install

# Create credentials (service account with BigQuery access)
gcloud auth application-default login   # or use a service account JSON
echo '{"projectId":"YOUR_PROJECT","location":"US","credentials":"BASE64_ENCODED_JSON"}' > .df-credentials.json

# Configure your GA4 dataset
# Edit workflow_settings.yaml:
#   vars:
#     ga4_project: "your-project"
#     ga4_dataset: "analytics_xxx"
#     start_date: "20240101"
#     end_date: "20240131"

# Compile and run
dataform compile
dataform run
```

### Public sample (free, no setup)

The repo defaults to `bigquery-public-data.ga4_obfuscated_sample_ecommerce`. Just run:

```bash
dataform compile
dataform run --default-database=YOUR_PROJECT
```

### GCP Dataform UI (for first-timers)

1. Go to [console.cloud.google.com/bigquery/dataform](https://console.cloud.google.com/bigquery/dataform)
2. Create a repository in your GCP project
3. Link this GitHub repo via HTTPS (fine-grained PAT with `Contents: Read-only`)
4. Create a workspace on `main`
5. Edit `workflow_settings.yaml`:
   ```yaml
   defaultProject: "your-gcp-project-id"
   defaultLocation: "US"  # or EU region; use US for public dataset
   vars:
     ga4_project: "bigquery-public-data"
     ga4_dataset: "ga4_obfuscated_sample_ecommerce"
     start_date: "20201101"
     end_date: "20210131"
     source_extraction_mode: "auto"
   ```
6. Click **Compile**, then **Run**
7. Wait 5–10 minutes. You now have ~15 tables in BigQuery.

---

## 3. Architecture Overview

**Session-based, not event-based.** The pipeline:

1. **Extracts sessions** using configurable source extraction mode (`event_params`, `session_stslc`, `collected`, or `auto`)
2. **Extracts all configured conversion events** with full ecommerce payload
3. **Builds journeys** — for each conversion, finds all sessions within the lookback window
4. **Unnests paths** into row-level format for attribution calculation
5. **Runs 8 attribution models** in parallel
6. **Unifies results** into a single mart table with cross-model comparison

```
GA4 events_* → stg_ga4_sessions + stg_ga4_conversions
                    ↓
        int_attribution_journeys (path building)
                    ↓
        int_attribution_path_rows (row-level unnest)
                    ↓
    ┌─────────────────────────────────────────────────┐
    │  first_click / last_click / last_non_direct_click              │
    │  linear / time_decay / u_shape / position_weighted             │
    │  data_driven_bqml (ML model)                                   │
    └─────────────────────────────────────────────────┘
                    ↓
        attribution_mart + cross_channel_comparison
```

### Key Design Decisions

| Decision | Rationale |
|---|---|
| Session-based | GA4's session concept aligns with marketing touchpoints; event-level is too granular |
| Multi-conversion | A single user can convert multiple times; each conversion gets its own journey |
| 30-day lookback | Configurable; default matches GA4's default attribution window |
| Auto source resolution | Works across GA4 export versions without schema changes |

**Deduplication strategy:**
- **Sessions:** `user_pseudo_id + ga_session_id` with `ROW_NUMBER()`
- **Conversions:** `user_pseudo_id + event_timestamp + transaction_id` (or event name if no transaction ID)
- **Paths:** Journey aggregation ensures no duplicate touchpoints per conversion

---

## 4. Configuration

### 4.1 Conversion events (`includes/conversion_config.js`)

```javascript
const CONVERSION_EVENTS = [
  {
    event: 'purchase',
    value_mode: 'revenue',   // Uses purchase_revenue_in_usd
    description: 'Completed purchase'
  },
  {
    event: 'begin_checkout',
    value_mode: 'count',     // No revenue; counts conversions only
    description: 'Checkout started'
  },
  {
    event: 'add_to_cart',
    value_mode: 'count',
    description: 'Item added to cart'
  }
];
```

**Value modes:**
- `revenue` — Uses `purchase_revenue_in_usd` (or event-specific revenue field)
- `fixed` — Assigns a fixed value per conversion (configure in `getValueExpr()`)
- `count` — No monetary value; `attributed_value_usd` will be NULL

**To add a new conversion:**
1. Append to `CONVERSION_EVENTS` array
2. Choose `value_mode`
3. Recompile — no SQL changes needed

**Example — adding a lead form submission:**
```javascript
{
  event: 'generate_lead',
  value_mode: 'fixed',
  fixed_value: 25.00,
  description: 'Lead form submitted'
}
```

### 4.2 Channel grouping (`includes/channel_grouping.js`)

19-channel taxonomy:

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
19. Unknown

**Brand vs Non-Brand split:** Edit `BRAND_TERMS_REGEX` in `includes/constants.js`:

```javascript
const BRAND_TERMS_REGEX = "(yourbrand|yourcompany|yourproduct)";
```

This regex is used in the `channelGrouping()` function. If `source` matches (case-insensitive), the channel becomes "Paid Search Brand"; otherwise "Paid Search Non-Brand".

### 4.3 Source extraction mode (`workflow_settings.yaml`)

```yaml
vars:
  source_extraction_mode: "event_params"   # Options: auto, event_params, session_stslc, collected
```

| Mode | Use when | Description |
|---|---|---|
|| `event_params` (effective default) | Any export | Extracts source/medium from event-level `event_params`. Works on all GA4 exports. |
| `session_stslc` | Post-2024-07 exports | Uses `session_traffic_source_last_click` (GA4 UI-native logic). |
| `collected` | Post-2023-06 exports | Uses `collected_traffic_source` (manual override values). |
| `auto` | Post-2024-07 exports | `COALESCE(session_stslc, collected, event_params)` — falls through gracefully. |

**Important:** The public sample dataset (`bigquery-public-data.ga4_obfuscated_sample_ecommerce`) is from 2020 and does NOT have `session_traffic_source_last_click` or `collected_traffic_source`. Use `event_params` (default) for this dataset.

### 4.4 Lookback window (`workflow_settings.yaml`)

```yaml
vars:
  lookback_days: "30"
```

The lookback is **exact**: the pipeline filters sessions where `session_start >= conversion_ts - lookback_days`. Additionally, `_TABLE_SUFFIX` is extended by `lookback_days` to ensure all relevant partitions are scanned.

### 4.5 Privacy / consent mode v2 (`workflow_settings.yaml`)

```yaml
vars:
  exclude_modeled_events: "true"   # Set to "true" to exclude modeled events
```

When enabled, sessions with `privacy_info.uses_transient_token = 'Yes'` are excluded. All privacy fields are passed through to staging and attribution tables for auditability.

**Note:** The public sample dataset (2020) does not contain consent mode v2 fields. These will be NULL.

---

## 5. Running the Pipeline

### Full run (all models)

```bash
dataform run --default-database=your-project
```

### Run specific tags

```bash
# Staging only
dataform run --tags=staging

# Attribution models only (skip ML)
dataform run --tags=attribution,model

# BQML training only
dataform run --tags=ml

# Dashboard views only
dataform run --tags=dashboard

# Cost module only
dataform run --tags=cost
```

### Full refresh (rebuild everything)

```bash
dataform run --full-refresh
```

### Schedule in production

Use Dataform's built-in scheduling (in the Dataform UI) or Cloud Scheduler:

```bash
# Example: daily at 06:00 UTC
gcloud scheduler jobs create http daily-attribution \
  --schedule="0 6 * * *" \
  --uri="https://dataform.googleapis.com/v1beta1/projects/YOUR_PROJECT/locations/us/repositories/ga4-attribution-models/workflowInvocations" \
  --http-method=POST \
  --message-body='{"compilationResult":"projects/YOUR_PROJECT/locations/us/repositories/ga4-attribution-models/compilationResults/latest"}'
```

---

## 6. Understanding the Output

### 6.1 `attribution_mart`

The unified output table. One row per touchpoint per conversion per model.

| Column | Description |
|---|---|
| `user_pseudo_id` | GA4 user identifier |
| `conversion_id` | Unique conversion identifier |
| `conversion_ts` | Timestamp of conversion event |
| `conversion_event` | Event name (e.g. `purchase`, `begin_checkout`) |
| `transaction_id` | Ecommerce transaction ID (if available) |
| `conversion_value_local` | Revenue in local currency |
| `conversion_value_usd` | Revenue in USD |
| `path_length` | Number of sessions in the journey |
| `source` / `medium` / `campaign` / `channel` | Touchpoint dimensions |
| `model` | Attribution model name |
| `attributed_credit` | Fraction of credit (sums to 1.0 per conversion) |
| `attributed_value_usd` | Credit × conversion_value_usd |
| `attributed_value_local` | Credit × conversion_value_local |

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

### 6.2 `cross_channel_comparison`

Pre-aggregated for dashboards. One row per model × conversion_event × channel.

| Column | Description |
|---|---|
| `model` | Attribution model |
| `conversion_event` | Conversion event name |
| `channel` | Channel |
| `attributed_conversions` | Number of conversions |
| `total_value_local` | Sum of attributed local currency |
| `total_value_usd` | Sum of attributed USD |
| `avg_path_length` | Average path length for this segment |

### 6.3 `int_attribution_journeys`

Raw journey data for custom analysis.

```sql
-- Find the longest customer journeys
SELECT *
FROM `your-project.intermediate.int_attribution_journeys`
ORDER BY path_length DESC
LIMIT 10;
```

### 6.4 Dashboard Views

| View | Dataset | What It Contains | Who Cares |
|---|---|---|---|
| `attribution_dashboard` | `dashboard` | Every touchpoint for every conversion, with credit from all 8 models | Analysts building custom reports |
| `cross_channel_comparison` | `attribution_models` | One row per channel × model × conversion event, pre-aggregated | Stakeholders who want summaries |
| `paths_dashboard` | `dashboard` | Top conversion paths, path lengths, channel sequences | UX and CRO teams |
| `funnel_dashboard` | `dashboard` | Purchase funnel stages, drop-off rates, cart abandonment | Ecommerce managers |

### 6.5 Individual Model Tables

| Table | Model Philosophy | Best For |
|---|---|---|
| `attr_first_click` | First touch gets 100% credit | Brand awareness ROI |
| `attr_last_click` | Last touch gets 100% credit | Direct response campaigns |
| `attr_last_non_direct_click` | Last touch, ignoring Direct | Standard Google Analytics view |
| `attr_linear` | Equal credit to every touch | Long B2B sales cycles |
| `attr_time_decay` | More credit to recent touches | Promotional campaigns |
|| `attr_position_weighted` | 50% first, 30% last, 20% middle | Data-driven heuristic proxy |
|| `attr_u_shape` | 40% first, 40% last, 20% middle | Balanced first/last emphasis |
| `attr_data_driven_bqml` | ML-learned credit allocation | When you have enough data (1,000+ conversions) |

---

## 7. Attribution Models Explained

### 7.1 Rule-based models

| Model | Logic | Best for |
|---|---|---|
| **First Click** | 100% to first session | Brand awareness campaigns |
| **Last Click** | 100% to last session | Direct response, simple funnels |
| **Last Non-Direct Click** | 100% to last non-Direct session; falls back to Direct if none | Default GA4 logic |
| **Linear** | Equal credit to all sessions | Long consideration cycles |
| **Time Decay** | Credit decays with 7-day half-life | Recent-touch bias |
| **U-Shape** | 40% first, 40% last, 20% split among middle | Balanced first/last emphasis |
| **Position Weighted** | 50% first, 30% last, 20% split among middle | Data-driven heuristic proxy |

### 7.2 Data-driven (BQML)

Trains a logistic regression model on:
- **Positive class:** Users who converted (binary channel flags from their journey)
- **Negative class:** Users who had sessions but did NOT convert

Features: `conversion_event` (categorical) + 17 binary channel flags.

**Credit assignment:** For each touchpoint in a converted journey, the model's predicted conversion probability is compared with and without that channel. The difference is the marginal contribution.

**Known limitations:**
- Single model trained on all conversion events. If funnel stages have very different channel effects, consider per-conversion-event models (v2.1 roadmap).
- Requires sufficient training data (recommended: >1,000 conversions, >10,000 non-converters).
- Model training can take 2–5 minutes.

---

## 8. Looker Studio Dashboards

For detailed step-by-step visualisation instructions, see [`LOOKER_STUDIO_GUIDE.md`](LOOKER_STUDIO_GUIDE.md).

**Quick recipe:**
1. Connect `dashboard.attribution_dashboard` as a BigQuery custom query data source
2. Add scorecards for total conversions, revenue, and AOV
3. Add a clustered bar chart: `channel` × `model` with `SUM(attributed_value_usd)`
4. Add a pivot table heatmap: `channel` rows, `model` columns
5. Add filter controls for date range, model, and channel

**Three-page dashboard:**
- **Page 1:** Attribution Comparison (model vs channel)
- **Page 2:** Funnel & Abandonment (stages, drop-off, cart abandonment)
- **Page 3:** User Journeys (top paths, path length, device breakdown)

---

## 9. Cost Module (Optional ROAS)

> **Optional module.** The main attribution pipeline works without cost data. Enable this only when you have ad spend available in BigQuery.

### What This Module Gives You

| Metric | Formula | Use Case |
|---|---|---|
| **ROAS** | Revenue ÷ Cost | Which channel gives the best return per dollar spent? |
| **CPA** | Cost ÷ Conversions | How much do we pay per attributed conversion? |
| **RPC** | Revenue ÷ Conversions | Average order value per attributed conversion |
| **Marginal Revenue** | Data-driven − Last-click | Incremental revenue the ML model discovers beyond last-click |
| **Efficiency Score** | ROAS × Credit Ratio | Channels that get more attribution credit AND good ROAS rank higher |

### Prerequisites

1. **Ad spend data in BigQuery** from at least one platform:
   - Google Ads (via Data Transfer Service or API connector)
   - Meta Ads (via Supermetrics, Fivetran, manual CSV, or API)
   - TikTok, LinkedIn, programmatic, influencer — any platform

2. **Channel names must match** between cost tables and attribution output. The attribution pipeline produces 19 channels (see [Channel grouping](#42-channel-grouping)). Your cost data must use the **exact same names** for joins to work.

### Step 1 — Enable the Cost Sources You Have

Open each file in `definitions/cost/` and set `disabled: false` for the platforms you use.

**`stg_google_ads_cost.sqlx`:**
```yaml
config {
  disabled: false,  -- <-- change this
  ...
}
```

Replace the placeholder CTE with your actual Google Ads table:
```sql
WITH raw_google_ads AS (
  SELECT
    PARSE_DATE('%Y%m%d', _PARTITIONDATE) AS date,
    CASE
      WHEN campaign_advertising_channel_type = 'SEARCH' THEN 'Paid Search Non-Brand'
      WHEN campaign_advertising_channel_type = 'DISPLAY' THEN 'Display'
      WHEN campaign_advertising_channel_type = 'SHOPPING' THEN 'Paid Shopping'
      WHEN campaign_advertising_channel_type = 'VIDEO' THEN 'Paid Video'
      WHEN campaign_advertising_channel_type = 'PERFORMANCE_MAX' THEN 'Cross-network'
      ELSE 'Paid Search Non-Brand'
    END AS channel,
    campaign_name AS campaign,
    cost_micros / 1e6 AS cost_usd,
    impressions,
    clicks
  FROM `your-project.your_transfer_dataset.campaign_basic_stats`
  WHERE _PARTITIONDATE BETWEEN '2024-01-01' AND '2024-12-31'
)
```

**`stg_meta_ads_cost.sqlx`:** Same pattern — map your Meta placement to `Paid Social`.

**`stg_other_cost.sqlx`:** Add one CTE per additional platform and uncomment the `UNION ALL` blocks.

### Step 2 — Enable the Unified Cost Table

Open `definitions/cost/int_unified_cost.sqlx` and set `disabled: false`. This automatically aggregates all enabled cost sources to `date × channel × campaign` grain.

### Step 3 — Enable the ROAS Mart

Open `definitions/cost/attribution_with_roas.sqlx` and set `disabled: false`. This joins attribution results with cost data by `date × channel × conversion_event`, producing granular ROAS, CPA, marginal revenue, and efficiency scores per event type.

### Step 4 — Run the Pipeline

```bash
cd ga4-attribution-models
npx dataform run --default-database=YOUR_PROJECT --tags=cost
```

Or run everything including cost:
```bash
npx dataform run --default-database=YOUR_PROJECT
```

### What Happens If Cost Is Missing?

The `attribution_with_roas` table uses `LEFT JOIN` from attribution to cost. If a channel has attribution credit but no cost data for a given date:
- `cost_usd` → `NULL`
- `roas` → `NULL`
- `cpa` → `NULL`

For count-mode conversion events (`begin_checkout`, `add_to_cart`), `roas` and `rpc` are always `NULL` regardless of cost — there is no monetary value attached. Only CPA is computed for count-mode.

This is intentional — it distinguishes "no spend" from "zero return". Organic channels will naturally have `NULL` cost unless you model SEO/content costs separately.

### Common Pitfalls

| Problem | Cause | Fix |
|---|---|---|
| ROAS is NULL everywhere | Cost table is empty or channel names don't match | Check channel name mapping in cost CTEs |
| Organic channels missing from ROAS table | Expected — they have no ad spend | Optional: add estimated SEO/content costs to `stg_other_cost` |
| CPA is infinity | Zero conversions but positive cost | Filter with `WHERE attributed_conversions > 0` |
| Costs double-counted | Same platform in two CTEs | Ensure each cost source appears in only one `.sqlx` file |
| Marginal revenue is NULL | No data-driven model results | Make sure `attr_data_driven_bqml` ran successfully first |

---

## 10. Validation & Testing

### 10.1 Built-in assertions

The pipeline includes Dataform assertions on:

- `stg_ga4_sessions` — unique key on `(user_pseudo_id, session_id)`
- `stg_ga4_conversions` — unique key on `(user_pseudo_id, event_timestamp, event_name)`; row conditions on `conversion_value_usd >= 0`
- `int_attribution_journeys` — unique key on `(user_pseudo_id, conversion_ts, conversion_event)`; row conditions on `conversion_value_usd >= 0`, `path_length >= 1`, `ARRAY_LENGTH(path) = path_length`
- `int_attribution_path_rows` — unique key on `(user_pseudo_id, conversion_id, session_position_asc)`

### 10.2 Post-run validation queries

Run `standalone-sql/validation_queries.sql` after each execution:

```bash
bq query --use_legacy_sql=false < standalone-sql/validation_queries.sql
```

Key checks:
- Credit sums to 1.0 per conversion
- No unexpected conversion events
- Revenue conservation (attributed total = raw total)
- No duplicate sessions or journeys
- Channel coverage matches taxonomy

### 10.3 Testing on the public sample

The public sample (`bigquery-public-data.ga4_obfuscated_sample_ecommerce`) is pre-configured as the default. Use it to verify your setup before connecting to private data.

**Known public sample quirks:**
- Source/medium values are anonymised: `<Other>`, `(data deleted)` — mapped to `Direct`
- No consent mode v2 fields (2020 dataset)
- No `session_traffic_source_last_click` (use `event_params` mode)

---

## 11. Troubleshooting

### 11.1 Compilation errors

| Error | Cause | Fix |
|---|---|---|
| `Unrecognized name: session_traffic_source_last_click` | Using `session_stslc` mode on an old GA4 export | Switch to `event_params` mode |
| `No actions to run` | All tables already exist and are up-to-date | Use `--full-refresh` or delete tables |
| `Concurrent model update` | BQML model is being trained by another job | Wait or `DROP MODEL IF EXISTS` |
| `Permission denied` | Service account lacks BigQuery roles | Grant `bigquery.dataEditor` + `bigquery.jobUser` |

### 11.2 Runtime errors

| Error | Cause | Fix |
|---|---|---|
| `attr_data_driven_train` fails with "empty training data" | `int_attribution_path_rows` has no rows | Check `stg_ga4_conversions` has data; verify `_TABLE_SUFFIX` range |
| `int_attribution_journeys` is empty | No conversions in the date range | Extend `start_date`/`end_date`; check conversion events are configured |
| Attribution credit sums to <1.0 | Path-length edge case in U-shape/position_weighted | Already fixed in v2.0; update if on older version |
| `last_non_direct_click` drops conversions | Logic bug with `session_position_desc` | Already fixed in v2.0; update if on older version |
| Channel shows as "source / medium" | Catch-all triggered — unknown source/medium combination | Add channel mapping in `channel_grouping.js` |

### 11.3 Data quality issues

| Symptom | Diagnosis | Fix |
|---|---|---|
| All sessions are "Direct" | Source extraction mode doesn't match export schema | Check GA4 export version; switch mode |
| 0 conversions | Wrong `event_name` in config | Verify event names in `conversion_config.js` match GA4 |
| Revenue is NULL | `value_mode` set to `count` | Change to `revenue` in `conversion_config.js` |
| Duplicate sessions | Missing `ROW_NUMBER()` dedup | Already handled in `stg_ga4_sessions` |
| Very long paths (>20 sessions) | Bot traffic or returning users | Add bot filtering in `stg_ga4_sessions` WHERE clause |

### 11.4 Performance issues

| Symptom | Fix |
|---|---|
| Pipeline runs >30 minutes | Reduce `lookback_days`; narrow date range; use incremental models |
| High BigQuery costs | Use `_TABLE_SUFFIX` partitioning (already implemented); avoid full refreshes |
| BQML training fails | Ensure training table has >100 rows; check for NULL features |

---

## 12. Performance & Cost

### Public sample (default config)

| Stage | BigQuery Cost | Time |
|---|---|---|
| Staging (2 tables) | ~2.9 GiB | ~2 min |
| Intermediate (2 tables) | ~0.15 GiB | ~1 min |
| Attribution models (7 rule-based) | ~0.08 GiB | ~2 min |
| BQML training | ~0.05 GiB | ~3 min |
| Marts (2 tables) | ~0.2 GiB | ~1 min |
| **Total** | **~3.4 GiB** | **~9 min** |

**Cost estimate:** ~$0.02 USD per run (on-demand pricing).

### Production dataset (1B+ events)

| Optimization | Impact |
|---|---|
| Incremental models | 10–50x faster daily runs |
| Narrow date range | Linear cost reduction |
| Reduce `lookback_days` | Reduces partition scans |
| Materialised intermediate tables | Faster model re-runs |

---

## 13. Migration from v1.x

### Breaking changes

| v1.x | v2.0 | Action required |
|---|---|---|
| `purchase_revenue` | `conversion_value_local` | Update downstream queries |
| `purchase_revenue_in_usd` | `conversion_value_usd` | Update downstream queries |
| `attributed_revenue` | `attributed_value_usd` | Update downstream queries |
| `attributed_revenue_local` | `attributed_value_local` | Update downstream queries |
| Hardcoded `purchase` filter | Dynamic `conversion_config.js` | Edit `conversion_config.js` |
| 8 channels | 19 channels | Update cost module channel mapping |
| `source_resolution.js` inline | Mode-switchable via var | Set `source_extraction_mode` |

### Migration checklist

- [ ] Update downstream dashboards/queries with new column names
- [ ] Review `conversion_config.js` — ensure desired events are listed
- [ ] Set `source_extraction_mode` based on your GA4 export version
- [ ] Update cost module channel mappings (if using)
- [ ] Test on public sample before production
- [ ] Run validation queries

---

## 14. Appendix: File Reference

```
includes/
  channel_grouping.js      -- 19-channel CASE logic
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
    attribution_with_roas.sqlx    -- Cost enrichment (disabled by default)
  dashboard/
    attribution_dashboard.sqlx    -- Dashboard views
  user_journey/
    path_analysis.sqlx         -- Top 100 paths

standalone-sql/
  attribution_models/        -- Standalone BigQuery scripts
  dashboard/
  data-preparation/
  ecommerce_funnel/
  user_journey/
  setup_views.sql            -- Helper views for different GA4 schemas
  validation_queries.sql     -- Post-run checks
```

---

*For issues or feature requests, open a GitHub issue or submit a PR.*
