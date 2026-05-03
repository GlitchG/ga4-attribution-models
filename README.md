### GA4 Attribution Models

Eight attribution models in BigQuery SQL, runnable on Google's public GA4 sample dataset. No setup beyond a free Google Cloud account.

#### The eight models

| Model | What it does | When to reach for it |
|---|---|---|
| Last click | 100% credit to the final touchpoint | Default in most ad platforms; matches what they report |
| Last non-direct | 100% credit to the last non-direct touchpoint | Fixes last-click's habit of over-crediting "direct" traffic |
| First click | 100% credit to the first touchpoint | Brand-building / new acquisition reporting |
| Linear | Equal credit across all touchpoints | Unbiased baseline; doesn't reflect that some touchpoints matter more |
| Time decay | Closer to conversion = more credit (geometric decay) | Short cycles; rewards channels that close |
| Position-based | 40% first + 40% last + 20% middle | Balanced view; common middle ground |
| Data-driven (BQ ML) | Logistic regression learns weights from your data | When you have 500+ conversions and want something tailored |
| Cross-channel comparison | All eight side by side | The most useful one — shows where the choice of model changes the story |

There's also `/ecommerce_funnel` for view → cart → checkout → purchase drop-off, and `/user_journey` for top conversion paths.

#### Running it

The dataset is `bigquery-public-data.ga4_obfuscated_sample_ecommerce` — public, so you can query it from any Google Cloud project. The sample covers December 2020 to January 2021. Two months is small, so the conversion counts are tiny. That's fine for understanding the SQL, not enough for real model comparison.

```
git clone https://github.com/GlitchG/ga4-attribution-models.git
cd ga4-attribution-models
```

Open any `.sql` file, paste into the [BigQuery console](https://console.cloud.google.com/bigquery), and run. Each file uses `_TABLE_SUFFIX` for date partitioning, which is the BigQuery-native way to scan event tables.

To use it with your own GA4 export: change the dataset name at the top of each file from `bigquery-public-data.ga4_obfuscated_sample_ecommerce` to your own `your-project.analytics_NNNNNNNNN`, and adjust the date range.

#### What attribution modelling actually buys you

Most ad platforms report last-click by default. That's fine for direct-response performance marketing. It's misleading for anything where awareness matters — channels that introduce people to your product, or that assist conversions without ever being the final touch, get systematically undercredited.

The point of running multiple models is not to pick "the right one" but to see where the answer is robust across models and where it's sensitive to the choice. If a channel looks profitable under last-click but mediocre under linear and first-click, it's closing deals other channels brought in. If it looks the same across all models, the credit is genuinely yours.

#### What's missing

- Markov-chain attribution (probabilistic removal effect) — useful when you have enough sessions to support it. On the list.
- The data-driven model needs BigQuery ML enabled and at least a few hundred conversions to give useful weights.
- For incrementality (vs. correlational attribution), see [bigquery-meridian-mmm](https://github.com/GlitchG/bigquery-meridian-mmm).

#### Related

- [bigquery-meridian-mmm](https://github.com/GlitchG/bigquery-meridian-mmm) — when attribution isn't enough and you need incrementality
- [marketing_analytics_sample_reporting](https://github.com/GlitchG/marketing_analytics_sample_reporting) — dbt project to land paid ads spend in BigQuery first
- [landing-page-ab-testing](https://github.com/GlitchG/landing-page-ab-testing) — same dataset, experimentation rather than attribution

MIT
