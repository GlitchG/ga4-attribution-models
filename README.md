### GA4 Attribution Models — Session-Based

Eight attribution models in BigQuery SQL, runnable on Google's public GA4 sample dataset. No setup beyond a free Google Cloud account. All queries are standalone — copy, paste, run.

**Architecture:** Session-based, not event-based. Each query:
- Extracts sessions using the GA4-UI-style "first non-auto event" rule (source/medium from the first non-`session_start`/`first_visit` event that has traffic params, falling back to `session_start` params)
- Builds ordered user journeys with `ARRAY_AGG`
- Applies a 30-day lookback window before each conversion
- Handles multi-conversion: repeat purchasers get separate journeys
- Uses consistent 8-channel normalization across all models

#### The eight models

| Model | File | What it does |
|---|---|---|
| Last Click | `last-click-model-attribution.sql` | 100% credit to the last session before conversion |
| Last Non-Direct | `last-non-direct-click-model-attribution.sql` | 100% credit to the last non-Direct session |
| First Click | `first-click-model-attribution.sql` | 100% credit to the first session in the journey |
| Linear | `linear-model-attribution.sql` | Equal credit split across all sessions |
| Time Decay | `time-decay-model-attribution.sql` | Exponential decay: closer sessions get more credit (7-day half-life) |
| U-Shaped | `u-shape-model-attribution.sql` | 40% first + 40% last + 20% middle |
| Data-Driven (BQ ML) | `data_driven_attribution.sql` | Feature-ablation marginal contribution via logistic regression |
| Cross-Channel Comparison | `cross-channel-comparison.sql` | All six rule-based models side by side |

Plus: `/ecommerce_funnel` (funnel analysis), `/user_journey` (conversion paths), `/dashboard` (Looker Studio setup).

#### Production features

Every model includes patterns you would use in production:
- **Session-based touchpoints** — source/medium from `event_params` using the first-non-auto-event rule (aligns with GA4 UI Session Acquisition, reduces drift by 5-15% on real data)
- **Channel normalization** — 8-channel grouping: Paid Search, Organic Search, Social, Email, Display, Referral, Affiliate, Direct
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
