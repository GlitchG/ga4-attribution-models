# Looker Studio Dashboard Setup

Three dashboard queries are ready to paste directly into Looker Studio as Custom Query data sources. No views, tables, or scheduled queries needed — everything runs live against BigQuery.

## Quick Start

1. Open [Looker Studio](https://lookerstudiogoogle.com)
2. Create a new report
3. Add data → **BigQuery** → **Custom Query**
4. Paste one of the queries below into the query editor
5. Choose your billing project (any GCP project with BigQuery enabled — free tier is fine)
6. Click **Add**

Repeat for each query to build a multi-page dashboard.

## Dashboard Queries

| Query file | What it returns | Use for |
|---|---|---|
| `dashboard/attribution_dashboard.sql` | 6 attribution models × channel matrix | Bar charts, heatmaps, channel comparison |
| `dashboard/funnel_dashboard.sql` | Ecommerce funnel stages with drop-off | Funnel chart, scorecards |
| `dashboard/paths_dashboard.sql` | Top conversion paths with frequency | Table, treemap, sankey (if available) |

---

## Recommended Dashboard Layout

### Page 1: Attribution Overview

**Chart 1 — Bar chart: Conversions by Channel (side-by-side)**
- Dimension: `channel`
- Metric: `attributed_conversions`
- Breakdown dimension: `model`
- Chart type: Clustered bar chart
- Sort: Descending by Last Click
- This shows which channels get over/under-credited depending on the model

**Chart 2 — Heatmap Table: Channel × Model matrix**
- Rows: `channel`
- Columns: `model`
- Metric: `attribution_pct`
- Colour scale: white → dark blue
- Makes it instantly obvious where models disagree

**Chart 3 — Scorecard: Total Conversions**
- Metric: `SUM(model_total_conversions)` (or pick one model's total)
- Filter: model = 'Last Click'

**Chart 4 — Bar chart: Variance from Last Click**
- Create a calculated field: `attribution_pct - SUM(CASE WHEN model = 'Last Click' THEN attribution_pct ELSE 0 END) OVER (PARTITION BY channel)`
- Shows how much each model diverges from the default

### Page 2: Conversion Funnel

**Chart 5 — Funnel chart**
- Dimension: `step` (sorted: View Item → Add to Cart → Begin Checkout → Purchase)
- Metric: `users`
- Chart type: Funnel (or bar chart if funnel widget unavailable)

**Chart 6 — Scorecards for drop-off rates**
- Metric: `1 - (purchase_users / view_item_users)` as overall abandonment rate
- Metric: `cart_abandonment_rate` from `cart_abandonment.sql`

### Page 3: Conversion Paths

**Chart 7 — Table: Top Conversion Paths**
- Rows: `conversion_path`
- Metrics: `conversions`, `pct_of_total`, `avg_touchpoints`
- Sort: by conversions descending

**Chart 8 — Scorecard: Average touchpoints to conversion**
- Metric: `AVG(avg_touchpoints)`

---

## Notes

- The public GA4 sample has very few purchases (~100 over 2 months). Most charts will show sparse data. The dashboard proves the pipeline works — to see meaningful patterns, point it at your own GA4 export.
- To switch datasets, replace `bigquery-public-data.ga4_obfuscated_sample_ecommerce` with your own `your-project.analytics_NNNNNNNNN` in all three query files.
- Change the `DECLARE` dates at the top of each query to adjust the reporting period.
- For production use, create BigQuery views from these queries and schedule a daily refresh. Connect Looker Studio to the views instead of custom queries for faster load times.
