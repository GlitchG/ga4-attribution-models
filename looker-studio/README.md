# Looker Studio Dashboard Kit

This directory contains tools for building Looker Studio dashboards on top of the GA4 Attribution Models pipeline.

## What's Here

| File | Purpose |
|---|---|
| `dashboard-config.json` | Structured spec for a 4-page dashboard with 5 data sources and 10+ charts |
| `create_dashboard.py` | Python script for programmatic dashboard creation via the Looker Studio API |
| `README.md` | This file |

## Three Ways to Build

1. **Manual** — Follow [`docs/LOOKER_STUDIO_GUIDE.md`](../docs/LOOKER_STUDIO_GUIDE.md) for step-by-step UI instructions
2. **JSON reference** — Use `dashboard-config.json` as a blueprint for manual recreation
3. **API (advanced)** — Run `create_dashboard.py` (requires service account + domain-wide delegation)

## API Limitations

Looker Studio's API is **read-only for most resources**. The Python script creates **data sources** programmatically, but charts and pages must still be built manually in the UI. Google has not exposed chart/page creation endpoints.

## Quick Start

```bash
# 1. Run the pipeline so tables exist
dataform run

# 2. Open Looker Studio and connect to BigQuery
#    See ../docs/LOOKER_STUDIO_GUIDE.md for detailed steps

# 3. (Optional) Create data sources via API
python looker-studio/create_dashboard.py --project YOUR_PROJECT
```

## Dashboard Pages

- **Attribution Comparison** — Model × channel bar charts, heatmaps, variance tables
- **Funnel & Abandonment** — Purchase funnel, drop-off rates, cart abandonment
- **User Journeys** — Top paths, path length, device breakdown
- **Data-Driven Deep-Dive** — BQML feature importance, predicted vs actual
