# Looker Studio Dashboard Setup (Session-Based)

Three dashboard queries ready to paste directly into Looker Studio as Custom Query data sources. No views, tables, or scheduled queries needed — everything runs live against BigQuery.

## Quick Start

1. Open [Looker Studio](https://lookerstudiogoogle.com)
2. Create a new report
3. Add data → **BigQuery** → **Custom Query**
4. Paste one of the queries below into the query editor
5. Choose your billing project (any GCP project with BigQuery enabled)
6. Click **Add**

Repeat for each query to build a multi-page dashboard.

## Dashboard Queries

| Query file | What it returns | Use for |
|---|---|---|
| `attribution_dashboard.sql` | 6 attribution models × channel matrix | Bar charts, heatmaps, channel comparison |
| `funnel_dashboard.sql` | Ecommerce funnel stages with drop-off | Funnel chart, scorecards |
| `paths_dashboard.sql` | Top 20 conversion paths with frequency | Table, treemap |

## Recommended Dashboard Layout

### Page 1: Attribution Overview

**Chart 1 — Clustered Bar: Conversions by Channel**
- Dimension: `channel`
- Metric: `attributed_conversions`
- Breakdown dimension: `model`
- Sort: descending by Last Click
- Shows which channels get over/under-credited by different models

**Chart 2 — Heatmap Table: Channel × Model matrix**
- Rows: `channel`
- Columns: `model`
- Metric: `attribution_pct`
- Colour scale: white → dark blue
- Instantly shows where models disagree

**Chart 3 — Scorecard: Total Conversions**
- Metric: `SUM(attributed_conversions)` with filter `model = 'Last Click'`

**Chart 4 — Bar chart: Variance from Last Click**
- Calculated field: `attribution_pct - SUM(CASE WHEN model = 'Last Click' THEN attribution_pct ELSE 0 END) OVER (PARTITION BY channel)`
- Red bars = model gives less credit than last click; blue = more credit

### Page 2: Conversion Funnel

**Chart 5 — Funnel chart**
- Dimension: `step` (sorted: View Item → Add to Cart → Begin Checkout → Purchase)
- Metric: `users`
- Chart type: Funnel or bar chart

**Chart 6 — Scorecards**
- Overall conversion rate: `purchase_users / view_item_users`
- Cart abandonment: from `ecommerce_funnel/cart_abandonment.sql`

### Page 3: Conversion Paths

**Chart 7 — Table: Top Paths**
- Rows: `conversion_path`
- Metrics: `conversions`, `pct_of_total`, `avg_touchpoints`

**Chart 8 — Scorecard**
- Average sessions to conversion: `AVG(avg_touchpoints)`

## Notes

- The public GA4 sample is sparse (~100 purchases over 2 months). Charts will show limited data. To see meaningful patterns, point at your own GA4 export.
- To switch datasets, replace `bigquery-public-data.ga4_obfuscated_sample_ecommerce` with your own `your-project.analytics_NNNNNNNNN`.
- Change `DECLARE` dates at the top of each query to adjust the reporting period.
- For production: run `data-preparation/google-analytics-4-data-preparation.sql` first, then connect Looker Studio to the resulting `attribution_mart` table for faster loads.
