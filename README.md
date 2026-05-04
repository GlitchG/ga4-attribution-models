### GA4 Attribution Models — Session-Based (Dataform Edition)

Eight attribution models in **Dataform** (BigQuery-native), runnable on Google's public GA4 sample dataset. No setup beyond a free Google Cloud account. The project includes a complete Dataform pipeline with staging, intermediate, and mart layers.

**Architecture:** Session-based, not event-based. The Dataform pipeline:
- Extracts sessions using the GA4-UI-style "first non-auto event" rule
- Extracts **all conversion events with full ecommerce data** (revenue, items, transaction_id, shipping, tax, refund, coupon, device, geo)
- Builds deduplicated ordered user journeys with `ARRAY_AGG`
- Applies a 30-day lookback window before each conversion
- Handles multi-conversion: repeat purchasers get separate journeys
- Uses consistent 8-channel normalization across all models
- **Zero duplicates**: sessions deduped by `user_pseudo_id + session_id`, conversions by `user_pseudo_id + timestamp + transaction_id`, paths by journey aggregation

---

#### Dataform Project Structure

```
definitions/
├── staging/
│   ├── stg_ga4_sessions.sqlx          -- Deduplicated sessions with source/medium/channel
│   └── stg_ga4_conversions.sqlx       -- Deduplicated conversions with FULL ecommerce payload
├── intermediate/
│   ├── int_attribution_journeys.sqlx  -- One row per conversion, session path as ARRAY
│   └── int_attribution_path_rows.sqlx -- Unnested paths (row per session-conversion pair)
├── attribution_models/
│   ├── attr_first_click.sqlx
│   ├── attr_last_click.sqlx
│   ├── attr_last_non_direct_click.sqlx
│   ├── attr_linear.sqlx
│   ├── attr_time_decay.sqlx
│   ├── attr_u_shape.sqlx
│   ├── attr_data_driven.sqlx
│   ├── attribution_mart.sqlx          -- Union of all models
│   └── cross_channel_comparison.sqlx  -- Channel-level ROAS/CPA comparison
├── ecommerce_funnel/
│   ├── purchase_funnel.sqlx           -- Stage-by-stage funnel metrics
│   └── cart_abandonment.sqlx          -- Cart abandonment rate
├── user_journey/
│   └── path_analysis.sqlx             -- Top 100 journey patterns
└── dashboard/
    ├── attribution_dashboard.sqlx     -- Looker Studio-ready attribution view
    ├── paths_dashboard.sqlx           -- Journey paths for tables
    └── funnel_dashboard.sqlx          -- Ecommerce funnel for charts
```

#### The eight models

| Model | File | What it does |
|---|---|---|
| Last Click | `attr_last_click.sqlx` | 100% credit to the last session before conversion |
| Last Non-Direct | `attr_last_non_direct_click.sqlx` | 100% credit to the last non-Direct session |
| First Click | `attr_first_click.sqlx` | 100% credit to the first session in the journey |
| Linear | `attr_linear.sqlx` | Equal credit split across all sessions |
| Time Decay | `attr_time_decay.sqlx` | Exponential decay: closer sessions get more credit (7-day half-life) |
| U-Shaped | `attr_u_shape.sqlx` | 40% first + 40% last + 20% middle |
| Data-Driven | `attr_data_driven.sqlx` | Removal-effect heuristic (SQL-only approximation) |
| Cross-Channel Comparison | `cross_channel_comparison.sqlx` | All models side by side with revenue |

#### Running it (Dataform)

```bash
git clone https://github.com/GlitchG/ga4-attribution-models.git
cd ga4-attribution-models

# Install Dataform CLI if needed
npm install -g @dataform/cli

# Set your GCP project in workflow_settings.yaml, then:
dataform compile
dataform run
```

All tables are created in the `attribution_models` dataset (configurable in `workflow_settings.yaml`).

To use with your own GA4 export: replace the source table in `definitions/staging/*.sqlx` from `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` to `your-project.your_dataset.events_*`.

#### Legacy SQL (standalone queries)

The original standalone `.sql` files remain in the root folders for reference and quick copy-paste:
- `attribution_models/*.sql`
- `data-preparation/*.sql`
- `ecommerce_funnel/*.sql`
- `dashboard/*.sql`

These do **not** include the full ecommerce enrichment or deduplication logic from the Dataform pipeline.

#### Production features

- **Deduplication at every layer** — no duplicate sessions, conversions, or path rows
- **Full ecommerce payload** — `purchase_revenue`, `purchase_revenue_in_usd`, `total_item_quantity`, `transaction_id`, `shipping_value`, `tax_value`, `refund_value`, `coupon`, `items` array, `event_value`, `event_currency`
- **Context enrichment** — `device_category`, `device_os`, `country`, `region`, `city`
- **Session-based touchpoints** — source/medium from `event_params` using the first-non-auto-event rule (aligns with GA4 UI Session Acquisition, reduces drift by 5-15% on real data)
- **Channel normalization** — 8-channel grouping: Paid Search, Organic Search, Social, Email, Display, Referral, Affiliate, Direct
- **30-day lookback** — `TIMESTAMP_SUB(conversion_ts, INTERVAL 30 DAY)`
- **Multi-conversion cycles** — `ROW_NUMBER()` per user, each conversion gets its own journey
- **Ordered paths** — sessions sorted by `session_start`, with position numbering
- **Direct traffic handling** — `IFNULL(source, '(direct)')`, non-Direct fallback logic
- **BigQuery partitioning** — staging and mart tables partitioned by `DATE(conversion_ts)` for cost control

#### GA4 BigQuery Export Compatibility (2026 Research)

The public sample uses `event_params` extraction (works on all GA4 exports). For your own data, the correct source/medium field depends on your export date:

| Export date | Best field | Scope |
|---|---|---|
| After mid-2024 | `session_traffic_source_last_click.cross_channel_campaign.source` / `.medium` | Session-level, last non-direct. Matches GA4 UI. Fixes google/cpc bug. |
| After June 2023 | `collected_traffic_source.manual_source` / `.manual_medium` | Event-level raw values. Cleaner than UNNEST, but no session scoping. |
| Any date | `event_params` extraction with first-non-auto-event rule | The approach used in all queries here. Works on ALL exports including the public sample. Aligns with GA4 UI attribution. |

**Critical: Never use `traffic_source.source` / `.medium`** — it is user-level first-touch that persists across all sessions. Using it makes every attribution model produce identical results. The official docs confirm: "traffic_source values do not change if the user interacts with subsequent campaigns."

**The google/cpc misattribution bug:** When Google Ads auto-tagging is enabled, ad clicks carry a `gclid` but no `utm_source`/`utm_medium`. Extracting from `event_params` alone shows these as `google / organic` instead of `google / cpc`, undercounting paid search by 20-40%. The `cross_channel_campaign` field resolves this by linking gclid to campaign data. For pre-2024 exports, the PROANALYTICS 15-project study found that a custom `event_params`-based script identified sources better than both the GA4 UI and early STSLC in 5 out of 6 projects.

See `data-preparation/google-analytics-4-data-preparation.sql` header for detailed documentation.

**Sources:** [Google GA4 Export Schema](https://support.google.com/analytics/answer/7029846), [PROANALYTICS 15-project study](https://proanalytics.team/blog/comparison-of-traffic-sources-between-ga4-and-session_traffic_source_last_click-in-bigquery), [Adswerve Traffic Flavors](https://adswerve.com/technical-insights/four-different-ga4-traffic-flavors-in-the-bigquery-export), [Hookflash GA4 Traffic Part II](https://www.hookflash.co.uk/blog/ga4-traffic-allocation-and-conversion-attribution-part-ii-ga4-bigquery)

#### What's in `/dashboard`

Three Dataform views + setup guide for Looker Studio:
- `attribution_dashboard.sqlx` — unified 7-model output for bar charts and heatmaps
- `funnel_dashboard.sqlx` — ecommerce funnel for funnel chart widget
- `paths_dashboard.sqlx` — top conversion paths for tables

#### Related

- [bigquery-meridian-mmm](https://github.com/GlitchG/bigquery-meridian-mmm) — Bayesian MMM for incrementality
- [ga4-bigquery-incremental](https://github.com/GlitchG/ga4-bigquery-incremental) — Dataform-native GA4 incremental refresh pipeline
- [marketing_analytics_sample_reporting](https://github.com/GlitchG/marketing_analytics_sample_reporting) — dbt project for paid ads reporting
- [landing-page-ab-testing](https://github.com/GlitchG/landing-page-ab-testing) — experimentation, same dataset

MIT
