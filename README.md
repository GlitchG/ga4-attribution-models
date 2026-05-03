### GA4 Attribution Models — Session-Based

Eight attribution models in BigQuery SQL, runnable on Google's public GA4 sample dataset. No setup beyond a free Google Cloud account. All queries are standalone — copy, paste, run.

**Architecture:** Session-based, not event-based. Each query:
- Extracts sessions from `session_start` events using `traffic_source` (not `event_params`)
- Builds ordered user journeys with `ARRAY_AGG`
- Applies a 30-day lookback window before each conversion
- Handles multi-conversion: repeat purchasers get separate journeys
- Uses consistent channel normalization across all models

#### The eight models

| Model | File | What it does |
|---|---|---|
| Last Click | `last-click-model-attribution.sql` | 100% credit to the last session before conversion |
| Last Non-Direct | `last-non-direct-click-model-attribution.sql` | 100% credit to the last non-Direct session |
| First Click | `first-click-model-attribution.sql` | 100% credit to the first session in the journey |
| Linear | `linear-model-attribution.sql` | Equal credit split across all sessions |
| Time Decay | `time-decay-model-attribution.sql` | Exponential decay: closer sessions get more credit |
| U-Shaped | `u-shape-model-attribution.sql` | 40% first + 40% last + 20% middle |
| Data-Driven (BQ ML) | `data_driven_attribution.sql` | Shapley-style marginal contribution via logistic regression |
| Cross-Channel Comparison | `cross-channel-comparison.sql` | All six rule-based models side by side |

Plus: `/ecommerce_funnel` (funnel analysis), `/user_journey` (conversion paths), `/dashboard` (Looker Studio setup).

#### Production features

Every model includes patterns you would use in production:
- **Session-based touchpoints** — source/medium from `traffic_source`, not `event_params`
- **Channel normalization** — consistent grouping across all models
- **30-day lookback** — `TIMESTAMP_SUB(conversion_ts, INTERVAL 30 DAY)`
- **Multi-conversion cycles** — `ROW_NUMBER()` per user, each conversion gets its own journey
- **Ordered paths** — sessions sorted by `session_start`, with position numbering
- **Direct traffic handling** — `IFNULL(source, '(direct)')`, non-Direct fallback logic

#### Running it

```
git clone https://github.com/GlitchG/ga4-attribution-models.git
cd ga4-attribution-models
```

Open any `.sql` file, paste into the [BigQuery console](https://console.cloud.google.com/bigquery), and run. Each query is self-contained with `DECLARE` date variables. Uses the public dataset `bigquery-public-data.ga4_obfuscated_sample_ecommerce`.

To use with your own GA4 export: replace the dataset name with your own `your-project.analytics_NNNNNNNNN`.

For a production pipeline: run `data-preparation/google-analytics-4-data-preparation.sql` first to create base tables, then query from the resulting views.

#### GA4 Export Compatibility

The public sample uses `event_params` extraction (works on all GA4 exports). For your own data, the preferred source/medium field depends on your export date:

| Export date | Best field to use |
|---|---|
| After 2024-07-17 | `session_traffic_source_last_click.source/medium` — session-level, matches GA4 UI |
| After June 2023 | `collected_traffic_source.source/medium` — event-level struct, cleaner than UNNEST |
| Any date | `event_params` extraction — the approach used in all queries here |

**Never use `traffic_source`** — it contains user-level first-touch data, not session-level attribution data.

See `data-preparation/google-analytics-4-data-preparation.sql` header for detailed documentation with references to the official GA4 BigQuery Export schema.

#### What's in `/dashboard`

Three custom queries + setup guide for Looker Studio:
- `attribution_dashboard.sql` — unified 6-model output for bar charts and heatmaps
- `funnel_dashboard.sql` — ecommerce funnel for funnel chart widget
- `paths_dashboard.sql` — top conversion paths for tables
- `README.md` — 8 chart specs across 3 dashboard pages

#### Related

- [bigquery-meridian-mmm](https://github.com/GlitchG/bigquery-meridian-mmm) — Bayesian MMM for incrementality
- [marketing_analytics_sample_reporting](https://github.com/GlitchG/marketing_analytics_sample_reporting) — dbt project for paid ads reporting
- [landing-page-ab-testing](https://github.com/GlitchG/landing-page-ab-testing) — experimentation, same dataset

MIT
