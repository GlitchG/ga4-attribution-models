# Stand-Alone SQL Queries

This directory contains **copy-paste-ready BigQuery SQL scripts** that implement the same attribution logic as the Dataform pipeline in `definitions/`, but without any Dataform dependency.

Use these when:
- You want to run a single model directly in the BigQuery console
- You are evaluating the logic before adopting Dataform
- You need to adapt the queries to a different orchestration tool (dbt, Airflow, etc.)

## Structure

| Directory | Purpose |
|---|---|
| `data-preparation/` | Foundation queries: extract sessions, build ordered journeys from raw GA4 events |
| `attribution_models/` | Eight rule-based models + data-driven (BQML) + cross-channel comparison |
| `dashboard/` | SQL views that power Data Studio dashboards |
| `ecommerce_funnel/` | Cart abandonment and purchase funnel analysis |
| `user_journey/` | Path analysis (common paths, path length distribution) |
| `setup_views.sql` | Create helper views for different GA4 export schemas (pre/post July 2024) |
| `validation-queries.sql` | Run after pipeline execution to verify credit sums, revenue integrity, etc. |

## How to Use

1. Open any `.sql` file in the BigQuery console.
2. Update the `DECLARE` variables at the top (project ID, dataset, date range).
3. Run.

> **Note:** These scripts query `bigquery-public-data.ga4_obfuscated_sample_ecommerce` by default. Change the table reference to your own GA4 export dataset.

## Relationship to Dataform Pipeline

The Dataform pipeline (`definitions/`) compiles to SQL very similar to these scripts, but adds:
- Incremental materialisation
- Dependency management via `${ref()}`
- Built-in assertions and tags
- Config-driven conversion events and channel grouping

If you are setting up production attribution, use the Dataform pipeline. If you are experimenting or debugging, use these stand-alone scripts.
