### GA4 Attribution Models

Eight attribution models in BigQuery SQL, runnable on Google's public GA4 sample dataset. No setup beyond a free Google Cloud account. All queries are standalone — copy, paste, run. No dbt, no Python, no dependencies.

Each model includes user stitching (pseudo_id to user_id), multi-conversion cycle tracking, and a 30-day attribution lookback window — production patterns, not simplified demos.

#### The eight models

| Model | What it does | When to reach for it |
|---|---|---|
| Last click | 100% credit to the final touchpoint | Default in most ad platforms; matches what they report |
| Last non-direct | 100% credit to the last non-direct touchpoint | Fixes last-click's habit of over-crediting "direct" traffic |
| First click | 100% credit to the first touchpoint | Brand-building / new acquisition reporting |
| Linear | Equal credit across all touchpoints | Unbiased baseline; doesn't reflect that some touchpoints matter more |
| Time decay | Closer to conversion = more credit (half-life 7 days) | Short cycles; rewards channels that close |
| Position-based | 40% first + 40% last + 20% middle | Balanced view; common middle ground |
| Data-driven (BQ ML) | Shapley-style marginal contribution — trains model, then removes each channel to measure impact | When you have 500+ conversions and want model-driven attribution, not rules-based |
| Cross-channel comparison | Six models side by side | The most useful one — shows where the choice of model changes the story |

There's also `/ecommerce_funnel` for view, cart, checkout, purchase drop-off, and `/user_journey` for top conversion paths.

A full Looker Studio dashboard setup is in `/dashboard` — three custom queries and a setup guide with recommended charts.

#### Running it

The dataset is `bigquery-public-data.ga4_obfuscated_sample_ecommerce` — public, so you can query it from any Google Cloud project. The sample covers December 2020 to January 2021. Two months is small, so the conversion counts are tiny. That's fine for understanding the SQL, not enough for real model comparison.

```
git clone https://github.com/GlitchG/ga4-attribution-models.git
cd ga4-attribution-models
```

Open any `.sql` file, paste into the [BigQuery console](https://console.cloud.google.com/bigquery), and run. Each query is self-contained with `DECLARE` date variables at the top. Uses `_TABLE_SUFFIX` for date partitioning, the BigQuery-native way to scan event tables.

To use it with your own GA4 export: change the dataset name from `bigquery-public-data.ga4_obfuscated_sample_ecommerce` to your own `your-project.analytics_NNNNNNNNN`, and adjust the date range.

#### Production features

Beyond the attribution logic, every model includes patterns you would use in a production pipeline:

- **User stitching** — maps `user_pseudo_id` to `user_id` via `LAST_VALUE(... IGNORE NULLS)`, so signed-in users are tracked across devices
- **Multi-conversion cycles** — tracks repeat purchasers correctly: touchpoints between conversion N and N+1 are attributed to cycle N+1
- **30-day lookback** — prevents stale touchpoints from influencing attribution

#### What attribution modelling actually buys you

Most ad platforms report last-click by default. That's fine for direct-response performance marketing. It's misleading for anything where awareness matters — channels that introduce people to your product, or that assist conversions without ever being the final touch, get systematically undercredited.

The point of running multiple models is not to pick "the right one" but to see where the answer is robust across models and where it's sensitive to the choice. If a channel looks profitable under last-click but mediocre under linear and first-click, it's closing deals other channels brought in. If it looks the same across all models, the credit is genuinely yours.

#### What's missing

- Markov-chain attribution (probabilistic removal effect) — needs more session volume than the public sample provides. On the list.
- The data-driven model needs BigQuery ML enabled and at least a few hundred conversions to give useful weights. With the public sample it will train but the weights won't be reliable.
- For incrementality (vs. correlational attribution), see [bigquery-meridian-mmm](https://github.com/GlitchG/bigquery-meridian-mmm).

#### Related

- [bigquery-meridian-mmm](https://github.com/GlitchG/bigquery-meridian-mmm) — when attribution isn't enough and you need incrementality
- [marketing_analytics_sample_reporting](https://github.com/GlitchG/marketing_analytics_sample_reporting) — dbt project to land paid ads spend in BigQuery first
- [landing-page-ab-testing](https://github.com/GlitchG/landing-page-ab-testing) — same dataset, experimentation rather than attribution

MIT
