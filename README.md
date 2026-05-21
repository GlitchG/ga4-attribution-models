### GA4 Attribution Models — Session-Based (Dataform Edition)

Eight attribution models in **Dataform** (BigQuery-native), runnable on Google's public GA4 sample dataset. No setup beyond a free Google Cloud account.

**Architecture:** Session-based, not event-based. The Dataform pipeline:
- Extracts sessions with a **configurable source-extraction mode** — `event_params` (default, works on every GA4 export including the public sample), `session_stslc` (post-2024-07 exports), `collected` (post-2023-06 exports), or `auto` (COALESCE chain that requires the newer fields)
- Extracts **all conversion events with full ecommerce data** (revenue, items, transaction_id, shipping, tax, refund, device, geo)
- Builds deduplicated ordered user journeys with `ARRAY_AGG`
- Applies a **per-conversion-type lookback window** (configurable per event)
- Supports **multi-conversion**: purchase, begin_checkout, add_to_cart, add_shipping_info, add_payment_info, leads, signups — add events in one config file
- Uses **19-channel normalization** including Paid Search Brand vs Non-Brand, Cross-network, Paid Video, Organic Shopping, Unknown
- **Zero duplicates**: sessions deduped by `user_pseudo_id + session_id`, conversions by `user_pseudo_id + timestamp + transaction_id`, paths by `(user_pseudo_id, conversion_id, session_id)`
- **Privacy-ready**: optional pass-through of consent mode v2 fields (gated by `has_privacy_info`) + optional modeled-events exclusion

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
├── channel_grouping.js                 -- 19-channel CASE logic
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

data-studio/                             -- Dashboard kit
├── dashboard-config.json                -- Structured spec
├── create_dashboard.py                  -- Programmatic creation via API
└── README.md

docs/
├── USAGE_GUIDE.md                       -- Full technical reference
└── DATA_STUDIO_GUIDE.md                 -- Visualisation build steps
```

---

#### Quick Start

```bash
git clone https://github.com/GlitchG/ga4-attribution-models.git
cd ga4-attribution-models

# Install the Dataform CLI (one-time, global)
npm install -g @dataform/cli

# Auth — Application Default Credentials work for local runs
gcloud auth application-default login

# REQUIRED: open workflow_settings.yaml and replace `your-gcp-project-id`
# with the GCP project you want to write the output tables to.

dataform compile
dataform run --default-database=YOUR_PROJECT_ID
```

The pipeline defaults to the **public GA4 sample dataset** (`bigquery-public-data.ga4_obfuscated_sample_ecommerce`, 2020-11-01 → 2021-01-31). First run: ~12 minutes, ~6 GiB processed, ~$0.04.

Running from the **Dataform UI in Google Cloud** (no local CLI needed)? See [docs/USAGE_GUIDE.md §2 — GCP Dataform UI](docs/USAGE_GUIDE.md#2-quick-start).

---

#### Documentation

| Document | What you'll find |
|---|---|
| [`docs/USAGE_GUIDE.md`](docs/USAGE_GUIDE.md) | Setup, configuration, architecture, running the pipeline, output tables, troubleshooting, validation, cost module, migration guide |
| [`docs/DATA_STUDIO_GUIDE.md`](docs/DATA_STUDIO_GUIDE.md) | Connecting BigQuery, building charts (model comparison, heatmaps, funnels, paths), filters, sharing, cost management |
| [`standalone-sql/README.md`](standalone-sql/README.md) | How to use the stand-alone BigQuery scripts without Dataform |
| [`CHANGELOG.md`](CHANGELOG.md) | Version history and breaking changes |

---

#### What Makes This Different

| Feature | This Project | Typical GA4 Attribution |
|---|---|---|
| Models compared | 8 side-by-side | 1 at a time |
| Conversion events | Any event, configurable | Purchase only |
| Value modes | Revenue / fixed / count | Revenue only |
| Channels | 19 (brand split + Unknown) | 8 |
| Source extraction | Configurable per export version | Manual, breaks on schema changes |
| Standalone SQL | Included | Not provided |
| Cost / ROAS | Optional module | Not included |

---

#### License

MIT — see [`LICENSE`](LICENSE).
