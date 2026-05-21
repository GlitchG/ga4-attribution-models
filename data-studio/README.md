# Data Studio Dashboard Kit

> **Naming note (April 2026):** Google renamed Looker Studio back to Data Studio on 11 April 2026. Existing reports, data sources, and shared links transition automatically. URLs moved from `lookerstudio.google.com` to `datastudio.google.com`. This guide uses the current name throughout.

This directory contains tools for building Data Studio (formerly Looker Studio) dashboards on top of the GA4 Attribution Models pipeline.

## What's Here

| File | Purpose |
|---|---|
| `dashboard-config.json` | Structured spec for a 4-page dashboard with 5 data sources and 10+ charts |
| `create_dashboard.py` | Python script for programmatic dashboard creation via the Data Studio API |
| `README.md` | This file |

## Three Ways to Build

1. **Manual** — Follow [`docs/DATA_STUDIO_GUIDE.md`](../docs/DATA_STUDIO_GUIDE.md) for step-by-step UI instructions
2. **JSON reference** — Use `dashboard-config.json` as a blueprint for manual recreation
3. **API (advanced)** — Run `create_dashboard.py` (requires service account + domain-wide delegation)

## API Limitations

Data Studio's API is **read-only for most resources**. The Python script creates **data sources** programmatically, but charts and pages must still be built manually in the UI. Google has not exposed chart/page creation endpoints.

## Quick Start

```bash
# 1. Run the pipeline so tables exist
dataform run

# 2. Open Data Studio and connect to BigQuery
#    See ../docs/DATA_STUDIO_GUIDE.md for detailed steps

# 3. (Optional) Create data sources via API
python data-studio/create_dashboard.py --project YOUR_PROJECT
```

## Dashboard Pages

- **Attribution Comparison** — Model × channel bar charts, heatmaps, variance tables
- **Funnel & Abandonment** — Purchase funnel, drop-off rates, cart abandonment
- **User Journeys** — Top paths, path length, device breakdown
- **Data-Driven Deep-Dive** — BQML feature importance, predicted vs actual

## Funnel Dashboard

The `funnel_dashboard` view requires the Dataform pipeline. There is no standalone SQL equivalent — `standalone-sql/dashboard/funnel_dashboard.sql` has been removed because its output schema (`step, users, pct_of_start`) was incompatible with the Dataform view schema (`stage_num, stage, unique_users, …`). Run `dataform run --tags=dashboard` to materialise the view before connecting Data Studio.
