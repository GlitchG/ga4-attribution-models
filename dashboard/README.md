# Dashboard Setup — Dataform Edition

The Dataform pipeline creates three dashboard-ready views in your BigQuery dataset. Connect them to Looker Studio, Metabase, Tableau, or any BI tool.

## Build Order (Dataform)

```
staging/
  stg_ga4_sessions          → builds first
  stg_ga4_conversions       → builds second (depends on nothing)

intermediate/
  int_attribution_journeys  → depends on staging
  int_attribution_path_rows → depends on journeys

attribution_models/
  attr_* (7 models)         → depends on path_rows
  attribution_mart          → depends on all 7 models
  cross_channel_comparison  → depends on mart

ecommerce_funnel/
  purchase_funnel           → depends on staging
  cart_abandonment          → depends on staging

dashboard/
  attribution_dashboard     → depends on mart + comparison
  paths_dashboard           → depends on journeys
  funnel_dashboard          → depends on funnel tables
```

Run once:
```bash
dataform run
```

All views are created automatically. You do not need scheduled queries or manual view creation.

---

## Option A: Looker Studio (Recommended for GA4)

### 1. Connect Data Sources

Add three **BigQuery → Custom Query** data sources:

| Data Source Name | SQL to paste |
|---|---|
| Attribution | `SELECT * FROM `your_project.attribution_models.attribution_dashboard`` |
| Paths | `SELECT * FROM `your_project.user_journey.paths_dashboard`` |
| Funnel | `SELECT * FROM `your_project.ecommerce_funnel.funnel_dashboard`` |

Replace `your_project` with your GCP project ID from `workflow_settings.yaml`.

### 2. Page 1: Attribution Comparison

**Chart 1 — Clustered Bar: Revenue by Channel × Model**
- Dimension: `channel`
- Metric: `attributed_revenue`
- Breakdown dimension: `model`
- Sort: `attributed_revenue` descending
- Why: Shows which channels get over/under-credited

**Chart 2 — Heatmap Table: Model × Channel**
- Rows: `channel`
- Columns: `model`
- Metric: `attributed_credit`
- Conditional formatting: blue gradient

**Chart 3 — Scorecards (Top Row)**
- Total Revenue (USD): `SUM(attributed_revenue)`
- Total Conversions: `SUM(attributed_credit)`
- AOV: `AVG(aov_usd)`
- Filter by model = `last_click` or whichever you treat as baseline

**Chart 4 — Variance from Last Click**
- Create calculated field:
  ```
  attributed_revenue - (SUM(CASE WHEN model = 'last_click' THEN attributed_revenue ELSE 0 END) OVER (PARTITION BY channel))
  ```
- Bar chart, dimension = `channel`, breakdown = `model`
- Positive = model gives MORE credit than last click

### 3. Page 2: Funnel & Abandonment

**Chart 5 — Funnel Chart**
- Dimension: `stage` (sort by `stage_num` ascending)
- Metric: `unique_users`
- Chart type: Funnel

**Chart 6 — Scorecards**
- Cart-to-Purchase Rate: filter stage = `purchase`, metric = `pct_of_top_users`
- Cart Abandonment: filter `stage_num = 99`, metric = `abandonment_rate_pct`

**Chart 7 — Drop-off Bar Chart**
- Dimension: `stage`
- Metric: `unique_users`
- Sort: `stage_num`

### 4. Page 3: User Journeys

**Chart 8 — Table: Top Paths**
- Dimension: `path_string`
- Metrics: `path_length`, `purchase_revenue_in_usd`
- Sort: `purchase_revenue_in_usd` descending
- Row limit: 50

**Chart 9 — Scorecards**
- Avg Path Length: `AVG(path_length)`
- Top Country: mode of `country`
- Mobile %: `COUNTIF(device_category = 'mobile') / COUNT(device_category)`

**Chart 10 — Treemap: Channel Transitions**
- Use `paths_dashboard` → split `path_string` on `>` in a calculated field, or build a separate "transition" query.

---

## Option B: Metabase (Open Source)

1. Add BigQuery database connection in Admin → Databases
2. Sync schema → you will see datasets: `staging`, `intermediate`, `attribution_models`, `ecommerce_funnel`, `user_journey`, `dashboard`
3. Build questions from the `dashboard.*` views:
   - **Attribution**: `dashboard.attribution_dashboard` grouped by `model` and `channel`
   - **Funnel**: `dashboard.funnel_dashboard` filtered `stage_num < 99`, sorted ascending
   - **Paths**: `dashboard.paths_dashboard` sorted by `purchase_revenue_in_usd` desc

Metabase handles the SQL — no custom queries needed if you point it at the views.

---

## Option C: Tableau / Power BI

Use the **BigQuery connector** (native OAuth):
- Project: your GCP project
- Dataset: `attribution_models`, `ecommerce_funnel`, `user_journey`, `dashboard`
- Tables: `attribution_dashboard`, `paths_dashboard`, `funnel_dashboard`

Tableau: use `dashboard.attribution_dashboard` as an extract. Refresh nightly via Tableau Server schedule.
Power BI: DirectQuery mode works; Import mode is faster for <1M rows.

---

## Row Counts to Expect (Public Dataset)

| View | Approx Rows |
|---|---|
| `stg_ga4_sessions` | ~50,000 |
| `stg_ga4_conversions` | ~500 |
| `int_attribution_journeys` | ~100 (purchases) |
| `attribution_mart` | ~700 (100 conversions × 7 models) |
| `cross_channel_comparison` | ~56 (8 channels × 7 models) |
| `funnel_dashboard` | 6 |
| `paths_dashboard` | ~100 |

The public dataset is sparse. With your own GA4 export you will see thousands of conversions and richer path diversity.

---

## Cost Notes

- The `dashboard.*` views are **zero-cost** on query — they read from already-materialised tables.
- `stg_ga4_sessions` and `stg_ga4_conversions` scan the raw GA4 export on each `dataform run`. Use BigQuery date partitioning to limit cost.
- For production: schedule `dataform run` daily via Cloud Scheduler or GitHub Actions. Dashboards read from views, not raw events.
