### GA4 Attribution Models — Session-Based (Dataform Edition)

Eight attribution models in **Dataform** (BigQuery-native), runnable on Google's public GA4 sample dataset. No setup beyond a free Google Cloud account.

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
│   ├── attr_position_weighted.sqlx
│   ├── attr_u_shape.sqlx
│   ├── attr_data_driven_bqml.sqlx      -- BQML logistic regression
│   ├── attribution_mart.sqlx           -- Unified output
│   └── cross_channel_comparison.sqlx   -- Pre-aggregated comparison
├── ml/
│   └── attr_data_driven_train.sqlx     -- BQML training job
├── dashboard/
│   ├── attribution_dashboard.sqlx
│   ├── funnel_dashboard.sqlx
│   └── paths_dashboard.sqlx
├── ecommerce_funnel/
│   ├── cart_abandonment.sqlx
│   └── purchase_funnel.sqlx
├── user_journey/
│   └── path_analysis.sqlx
└── cost/                                -- Optional ROAS module (disabled by default)
    ├── stg_google_ads_cost.sqlx
    ├── stg_meta_ads_cost.sqlx
    ├── stg_other_cost.sqlx
    ├── int_unified_cost.sqlx
    └── attribution_with_roas.sqlx

includes/
├── channel_grouping.js                 -- 17-channel CASE logic
├── conversion_config.js                -- Conversion events + value modes
├── constants.js                        -- Project vars + safe defaults
└── source_resolution.js                -- Source extraction mode switch

standalone-sql/                          -- Copy-paste BigQuery scripts (no Dataform needed)
├── attribution_models/
├── dashboard/
├── data-preparation/
├── ecommerce_funnel/
├── user_journey/
├── setup_views.sql
└── validation_queries.sql

looker-studio/                           -- Dashboard kit
├── dashboard-config.json                -- Structured spec
├── create_dashboard.py                  -- Programmatic creation via API
└── README.md

docs/
├── USAGE_GUIDE.md                       -- Full technical reference
└── LOOKER_STUDIO_GUIDE.md               -- Visualisation build steps
```

---

#### Quick Start

```bash
git clone https://github.com/GlitchG/ga4-attribution-models.git
cd ga4-attribution-models
npm install

# Auth (pick one)
gcloud auth application-default login
echo '{"projectId":"YOUR_PROJECT","location":"US","credentials":"BASE64_JSON"}' > .df-credentials.json

# Configure workflow_settings.yaml, then:
dataform compile
dataform run --default-database=YOUR_PROJECT
```

The pipeline defaults to the **public GA4 sample dataset** (`bigquery-public-data.ga4_obfuscated_sample_ecommerce`). First run: ~9 minutes, ~3.4 GiB processed, ~$0.02.

---

#### Documentation

| Document | What you'll find |
|---|---|
| [`docs/USAGE_GUIDE.md`](docs/USAGE_GUIDE.md) | Setup, configuration, architecture, running the pipeline, output tables, troubleshooting, validation, cost module, migration guide |
| [`docs/LOOKER_STUDIO_GUIDE.md`](docs/LOOKER_STUDIO_GUIDE.md) | Connecting BigQuery, building charts (model comparison, heatmaps, funnels, paths), filters, sharing, cost management |
| [`standalone-sql/README.md`](standalone-sql/README.md) | How to use the stand-alone BigQuery scripts without Dataform |
| [`CHANGELOG.md`](CHANGELOG.md) | Version history and breaking changes |

---

#### What Makes This Different

| Feature | This Project | Typical GA4 Attribution |
|---|---|---|
| Models compared | 8 side-by-side | 1 at a time |
| Conversion events | Any event, configurable | Purchase only |
| Value modes | Revenue / fixed / count | Revenue only |
| Channels | 17 (brand split) | 8 |
| Source extraction | Auto-adapts to export version | Manual, breaks on schema changes |
| Standalone SQL | Included | Not provided |
| Cost / ROAS | Optional module | Not included |

---

#### License

MIT — see [`LICENSE`](LICENSE).
