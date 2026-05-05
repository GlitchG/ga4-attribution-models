### GA4 Attribution Models — Session-Based (Dataform Edition)

Eight attribution models in **Dataform** (BigQuery-native), runnable on Google's public GA4 sample dataset. No setup beyond a free Google Cloud account. The project includes a complete Dataform pipeline with staging, intermediate, and mart layers.

**Architecture:** Session-based, not event-based. The Dataform pipeline:
- Extracts sessions using **auto source extraction** (session_stslc > collected > event_params)
- Extracts **all conversion events with full ecommerce data** (revenue, items, transaction_id, shipping, tax, refund, coupon, device, geo)
- Builds deduplicated ordered user journeys with `ARRAY_AGG`
- Applies a **per-conversion-type lookback window** (configurable per event)
- Supports **multi-conversion**: purchase, begin_checkout, add_to_cart, leads, signups — add events in one config file
- Uses **17-channel normalization** including Paid Search Brand vs Non-Brand, Cross-network, Paid Video, Organic Shopping
- **Zero duplicates**: sessions deduped by `user_pseudo_id + session_id`, conversions by `user_pseudo_id + timestamp + transaction_id`, paths by journey aggregation
- **Privacy-ready**: pass-through of consent mode v2 fields + optional modeled-events exclusion

---

#### Dataform Project Structure

```
definitions/
├── sources/
│   └── ga4_events.sqlx                 -- External GA4 table declaration
├── staging/
│   ├── stg_ga4_sessions.sqlx           -- Deduplicated sessions (incremental)
│   └── stg_ga4_conversions.sqlx        -- Deduplicated conversions (incremental)
├── intermediate/
│   ├── int_attribution_journeys.sqlx   -- One row per conversion, path array
│   └── int_attribution_path_rows.sqlx  -- Unnested paths
├── attribution_models/
│   ├── attr_first_click.sqlx
│   ├── attr_last_click.sqlx
│   ├── attr_last_non_direct_click.sqlx
│   ├── attr_linear.sqlx
│   ├── attr_time_decay.sqlx
│   ├── attr_u_shape.sqlx
│   ├── attr_position_weighted.sqlx     -- Position-based heuristic
│   ├── attr_data_driven_bqml.sqlx      -- BQML feature ablation
│   ├── attribution_mart.sqlx           -- Union of all 8 models
│   └── cross_channel_comparison.sqlx   -- Channel-level comparison
├── ecommerce_funnel/
│   ├── purchase_funnel.sqlx
│   └── cart_abandonment.sqlx
├── user_journey/
│   └── path_analysis.sqlx
├── dashboard/
│   ├── attribution_dashboard.sqlx
│   ├── paths_dashboard.sqlx
│   └── funnel_dashboard.sqlx
└── ml/
    └── attr_data_driven_train.sqlx     -- BQML model training

includes/
├── channel_grouping.js               -- DRY 17-channel CASE logic (single source of truth)
├── source_resolution.js              -- Auto source extraction (session_stslc > collected > event_params)
├── conversion_config.js              -- Conversion event definitions (revenue/fixed/count modes)
└── constants.js                      -- Safe defaults for vars (ga4_project, ga4_dataset, start_date, end_date, lookback_days, BRAND_TERMS_REGEX)
```

#### The eight models

| Model | File | What it does |
|---|---|---|
| Last Click | `attr_last_click.sqlx` | 100% credit to the last session before conversion |
| Last Non-Direct | `attr_last_non_direct_click.sqlx` | 100% credit to the last non-Direct session; falls back to Direct if entire path is Direct |
| First Click | `attr_first_click.sqlx` | 100% credit to the first session in the journey |
| Linear | `attr_linear.sqlx` | Equal credit split across all sessions |
| Time Decay | `attr_time_decay.sqlx` | Exponential decay: closer sessions get more credit (7-day half-life) |
| U-Shaped | `attr_u_shape.sqlx` | 40% first + 40% last + 20% middle |
| Position Weighted | `attr_position_weighted.sqlx` | Calibrated heuristic (50% first, 30% last, 20% middle) |
| Data-Driven (BQML) | `attr_data_driven_bqml.sqlx` | Feature-ablation marginal contribution via BQML logistic regression |
| Cross-Channel Comparison | `cross_channel_comparison.sqlx` | All eight models side by side with revenue |

#### Running it (Dataform)

```bash
git clone https://github.com/GlitchG/ga4-attribution-models.git
cd ga4-attribution-models

# Install Dataform CLI
npm install -g @dataform/cli

# 1. Set up credentials: create .df-credentials.json in the project root:
#    {
#      "projectId": "YOUR_GCP_PROJECT_ID",
#      "location": "US",
#      "credentials": "<your base64-encoded service account JSON or gcloud ADC>"
#    }
#    See: https://docs.dataform.co/dataform-cli#authentication

# 2. Edit workflow_settings.yaml:
#    - Set defaultProject to your GCP project ID
#    - Set defaultLocation to match your BigQuery region
#    - The public GA4 dataset is US-based; cross-region reads may incur costs

# 3. Compile and run
dataform compile --default-database=YOUR_PROJECT_ID
dataform run   --default-database=YOUR_PROJECT_ID
```

All tables are created in the `attribution_models` dataset (configurable in `workflow_settings.yaml`). Dataform auto-creates datasets if they do not exist.

To use with your own GA4 export: change `vars.ga4_project` and `vars.ga4_dataset` in `workflow_settings.yaml` — no SQL edits needed.

**Public dataset date range:** The sample tables cover **2020-11-01 to 2020-12-20**. The default `start_date`/`end_date` vars are set accordingly. If you change to your own GA4 export, update these dates to match your data.

#### Legacy SQL (standalone queries)

The original standalone `.sql` files remain in the root folders for reference and quick copy-paste:
- `attribution_models/*.sql`
- `data-preparation/*.sql`
- `ecommerce_funnel/*.sql`
- `dashboard/*.sql`

These do **not** include the full ecommerce enrichment, deduplication, assertions, or incremental logic from the Dataform pipeline.

#### Production features

- **Deduplication at every layer** — no duplicate sessions, conversions, or path rows
- **Multi-conversion support** — configure any event type in `includes/conversion_config.js` with `revenue`, `fixed`, or `count` value mode
- **Full ecommerce payload** — `conversion_value_usd`, `conversion_value_local`, `total_item_quantity`, `transaction_id`, `shipping_value`, `tax_value`, `refund_value`, `coupon`, `items` array, `event_value`, `event_currency`
- **Context enrichment** — `device_category`, `device_os`, `browser`, `browser_version`, `country`, `region`, `city`
- **Deep UTM + click IDs** — `gclid`, `dclid`, `srsltid`, `msclkid`, `fbclid`, `ttclid`, `twclid`, `li_fat_id`, `page_location`, `page_referrer`, `hostname`
- **Auto source extraction** — `session_traffic_source_last_click` (post-2024) → `collected_traffic_source` (post-2023) → `event_params` (all exports)
- **Channel normalization** — 17-channel grouping via `includes/channel_grouping.js` with Brand vs Non-Brand Paid Search split
- **Per-conversion lookback** → configurable per event type (purchase=30d, add_to_cart=7d, etc.)
- **Exact lookback windows** — `_TABLE_SUFFIX` extended by `max(lookback_days)` + `event_timestamp` filtering
- **Multi-conversion cycles** — `ROW_NUMBER()` per user, each conversion gets its own journey
- **Ordered paths** — sessions sorted by `session_start`, with position numbering
- **Direct traffic handling** — `IFNULL(source, '(direct)')`, non-Direct fallback logic
- **Data-Driven BQML** — logistic regression on 17 binary channel features with `conversion_event` as categorical feature
- **Privacy / consent mode v2** — pass-through of `privacy_info` fields + `exclude_modeled_events` runtime flag
- **Assertions** — Dataform-native data quality checks on unique keys, non-nulls, and row conditions
- **Vars-driven** — `start_date`, `end_date`, `ga4_project`, `ga4_dataset`, `lookback_days`, `source_extraction_mode`, `exclude_modeled_events` centralised in `workflow_settings.yaml`
- **Includes/DRY** — `channel_grouping.js`, `source_resolution.js`, `conversion_config.js` eliminate duplicated logic
- **Validation queries** — 10 post-run checks in `validation/validation-queries.sql`

#### GA4 BigQuery Export Compatibility (2026 Research)

The public sample uses `event_params` extraction (works on all GA4 exports). For your own data, the correct source/medium field depends on your export date:

| Export date | Best field | Scope |
|---|---|---|
| After mid-2024 | `session_traffic_source_last_click.cross_channel_campaign.source` / `.medium` | Session-level, last non-direct. Matches GA4 UI. Fixes google/cpc bug. |
| After June 2023 | `collected_traffic_source.manual_source` / `.manual_medium` | Event-level raw values. Cleaner than UNNEST, but no session scoping. |
| Any date | `event_params` extraction with first-non-auto-event rule | The approach used in all queries here. Works on ALL exports including the public sample. Aligns with GA4 UI attribution. |

**Critical: Never use `traffic_source.source` / `.medium`** — it is user-level first-touch that persists across all sessions. Using it makes every attribution model produce identical results. The official docs confirm: "traffic_source values do not change if the user interacts with subsequent campaigns."

**The google/cpc misattribution bug:** When Google Ads auto-tagging is enabled, ad clicks carry a `gclid` but no `utm_source`/`utm_medium`. Extracting from `event_params` alone shows these as `google / organic` instead of `google / cpc`, undercounting paid search by 20-40%. The `cross_channel_campaign` field resolves this by linking gclid to campaign data. For pre-2024 exports, the PROANALYTICS 15-project study found that a custom `event_params`-based script identified sources better than both the GA4 UI and early STSLC in 5 out of 6 projects.

See `definitions/staging/stg_ga4_sessions.sqlx` and `definitions/staging/stg_ga4_conversions.sqlx` for the 30-day lookback implementation and the `_TABLE_SUFFIX` caveat.

**Sources:** [Google GA4 Export Schema](https://support.google.com/analytics/answer/7029846), [PROANALYTICS 15-project study](https://proanalytics.team/blog/comparison-of-traffic-sources-between-ga4-and-session_traffic_source_last_click-in-bigquery), [Adswerve Traffic Flavors](https://adswerve.com/technical-insights/four-different-ga4-traffic-flavors-in-the-bigquery-export), [Hookflash GA4 Traffic Part II](https://www.hookflash.co.uk/blog/ga4-traffic-allocation-and-conversion-attribution-part-ii-ga4-bigquery)

#### What's in `/dashboard`

Three Dataform views + setup guide for Looker Studio:
- `attribution_dashboard.sqlx` — unified 8-model output for bar charts and heatmaps
- `funnel_dashboard.sqlx` — ecommerce funnel for funnel chart widget
- `paths_dashboard.sqlx` — top conversion paths for tables

#### Cost data and ROAS (optional)

If you have ad spend in BigQuery (Google Ads, Meta, TikTok, etc.), enable the optional `definitions/cost/` module:

- **ROAS** — Return on Ad Spend by channel and attribution model
- **CPA** — Cost Per Acquisition
- **Marginal Revenue** — Incremental value the data-driven model finds over last-click
- **Efficiency Score** — ROAS weighted by attribution credit share

See `docs/COST_MODULE_SETUP.md` for platform-specific setup (Google Ads Transfer Service, Meta API, manual CSV upload).

#### Configuring conversion events

Edit `includes/conversion_config.js` to add or remove conversion events:

```javascript
const CONVERSION_EVENTS = [
  { event: 'purchase', value_mode: 'revenue', value_field: 'purchase_revenue_in_usd', lookback_days: 30 },
  { event: 'generate_lead', value_mode: 'fixed', fixed_value_usd: 50.0, lookback_days: 7 },
  { event: 'begin_checkout', value_mode: 'count', lookback_days: 14 },
];
```

No SQL files need editing. The pipeline automatically picks up new events.

#### Configuring brand terms

Edit `includes/constants.js` to split Paid Search into Brand vs Non-Brand:

```javascript
const BRAND_TERMS_REGEX = 'mybrand|my-brand|brandcampaign';
```

#### Related

- [bigquery-meridian-mmm](https://github.com/GlitchG/bigquery-meridian-mmm) — Bayesian MMM for incrementality
- [ga4-bigquery-incremental](https://github.com/GlitchG/ga4-bigquery-incremental) — Dataform-native GA4 incremental refresh pipeline
- [marketing_analytics_sample_reporting](https://github.com/GlitchG/marketing_analytics_sample_reporting) — dbt project for paid ads reporting
- [landing-page-ab-testing](https://github.com/GlitchG/landing-page-ab-testing) — experimentation, same dataset

MIT
