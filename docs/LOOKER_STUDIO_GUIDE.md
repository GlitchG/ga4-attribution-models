# Looker Studio Visualization Guide — GA4 Attribution Models

**Project:** GA4 Attribution Models (Dataform Edition)  
**Audience:** Marketing analysts comfortable with Looker Studio's UI  
**Prerequisites:** Dataform pipeline has been run successfully; tables exist in your BigQuery project

---

## Dashboard Overview

This guide shows you how to build a three-page Looker Studio dashboard from the Dataform output.

**Page 1 — Attribution Comparison:** The "CEO slide". Compare how channel importance shifts across all 8 models.  
**Page 2 — Funnel & Abandonment:** Visualise drop-off from add_to_cart to purchase.  
**Page 3 — User Journeys:** Top conversion paths, path length distribution, device breakdown.

### Build Order (Dataform)

Run these tags in order if you want to build incrementally:

1. `dataform run --tags=staging` — Sessions and conversions
2. `dataform run --tags=attribution,model` — Rule-based models + mart
3. `dataform run --tags=ml` — BQML data-driven model
4. `dataform run --tags=dashboard` — Dashboard views

Or run everything at once: `dataform run`.

### Row Counts to Expect (Public Dataset)

| Table | Approximate Rows |
|---|---|
| `attribution_mart` | ~58,000 |
| `cross_channel_comparison` | ~56 |
| `paths_dashboard` | ~12,000 |
| `funnel_dashboard` | 6 (5 stages + 1 cart abandonment) |

### Cost Notes

- Looker Studio queries BigQuery **live** every time someone opens the dashboard
- The dashboard views (`dashboard.*`) read from materialised tables, not raw GA4 events — trivial cost
- Set cache freshness to **4 hours** to reduce repeated queries
- For scheduled PDF delivery, the snapshot queries run once at schedule time

---

## 1. Connecting BigQuery to Looker Studio

### 1.1 Create a New Report

1. Go to [lookerstudio.google.com](https://lookerstudio.google.com)
2. Click **+ Create** → **Report**
3. You'll be prompted to add a data source first

### 1.2 Add BigQuery Data Sources

You'll add **three** data sources, each pointing to a dashboard view:

#### Data Source 1: Attribution

| Step | Action |
|------|--------|
| Connector | **BigQuery** (Google connector, not a third-party one) |
| Project | Your GCP project ID (e.g., `marketingdataanalyst`) |
| Dataset | `dashboard` |
| Table | `attribution_dashboard` |

> **Alternative — Custom Query:** Instead of pointing at the view directly, choose **Custom Query** and paste:
> ```sql
> SELECT * FROM `marketingdataanalyst.dashboard.attribution_dashboard`
> ```
> Custom queries let you add WHERE clauses later without modifying the pipeline. Replace `marketingdataanalyst` with your GCP project ID.

Click **Add**. Looker Studio will show a preview of ~58K rows with columns: `model`, `channel`, `conversion_id`, `conversion_event`, `conversion_ts`, `value_mode`, `transaction_id`, `attributed_credit`, `attributed_value_usd`, `attributed_value_local`, `aov_usd`, `source`, `medium`, `campaign`, `path_length`, etc.

#### Data Source 2: Funnel

| Step | Action |
|------|--------|
| Connector | BigQuery |
| Dataset | `dashboard` |
| Table | `funnel_dashboard` |

Or custom query:
```sql
SELECT * FROM `marketingdataanalyst.dashboard.funnel_dashboard`
```

Preview shows 6 rows (5 funnel stages + 1 cart abandonment row).

#### Data Source 3: Paths

| Step | Action |
|------|--------|
| Connector | BigQuery |
| Dataset | `dashboard` |
| Table | `paths_dashboard` |

Or custom query:
```sql
SELECT * FROM `marketingdataanalyst.dashboard.paths_dashboard`
```

### 1.3 Direct Table Access (Advanced)

You can also connect directly to the underlying tables for more flexibility:

```sql
-- Model mart: all 8 models, row-level touchpoint detail
SELECT * FROM `marketingdataanalyst.attribution_models.attribution_mart`

-- Channel comparison: pre-aggregated channel × model × conversion_event metrics
SELECT * FROM `marketingdataanalyst.attribution_models.cross_channel_comparison`

-- Ecommerce funnel: raw funnel steps
SELECT * FROM `marketingdataanalyst.ecommerce_funnel.purchase_funnel`

-- Path analysis: top conversion paths
SELECT * FROM `marketingdataanalyst.user_journey.path_analysis`
```

---

## 2. Model Comparison Dashboard

**Goal:** Compare how the 8 attribution models distribute credit and revenue across marketing channels.

### 2.1 KPI Scorecards (Top Row)

Add four scorecards at the top of your page for an at-a-glance summary:

| Scorecard | Metric | Filter |
|-----------|--------|--------|
| Total Conversions | `SUM(attributed_credit)` | — |
| Total Revenue (USD) | `SUM(attributed_value_usd)` | — |
| Total Revenue (Local) | `SUM(attributed_value_local)` | — |
| Average Order Value | `AVG(aov_usd)` | — |

*How to add:* Click **Add a chart** → **Scorecard**. Drag the metric from the data panel. For AOV, click the scorecard, go to Data tab, and select `aov_usd` → `AVG`.

### 2.2 Bar Chart: Attributed Revenue by Channel × Model

**Purpose:** See which channels get the most credit, and how that changes across models.

| Setting | Value |
|---------|-------|
| Chart type | **Clustered Bar Chart** |
| Dimension | `channel` |
| Metric | `SUM(attributed_value_usd)` |
| Breakdown Dimension | `model` |
| Sort | `SUM(attributed_value_usd)` → Descending |

*What you'll see:* Eight bars per channel (one per model). Typically, Last Click concentrates revenue on the final channel, while Linear and Time Decay spread it across all channels in the journey.

**Add a Filter Control** for `model` so users can toggle individual models on/off:
- Click **Add a control** → **Drop-down list**
- Control field: `model`
- Style: Multi-select

### 2.3 Bar Chart: Attributed Credit (Conversions) by Channel × Model

Duplicate the chart above (right-click → Duplicate) and change the metric:

| Setting | Value |
|---------|-------|
| Metric | `SUM(attributed_credit)` |

**Calculated Field — Share of Conversions:**  
Go to **Resource** → **Manage added data sources** → your attribution source → **ADD A FIELD**. Name it `share_of_conversions`:
```
SUM(attributed_credit) / SUM(SUM(attributed_credit))
```
This gives each channel-model combination's percentage of total credited conversions. Display as a table or use in a scorecard.

### 2.4 Table: Variance from Last Click

Create a table showing how much more or less credit each model gives vs. Last Click.

**Calculated Field — `variance_from_last_click`:**
```
attributed_value_usd - 
SUM(CASE WHEN model = 'last_click' THEN attributed_value_usd ELSE 0 END) 
  / SUM(CASE WHEN model = 'last_click' THEN attributed_credit ELSE 0 END) 
  * attributed_credit
```

Simpler alternative — two calculated fields:

**`revenue_last_click`** (per channel):
```
SUM(CASE WHEN model = 'last_click' THEN attributed_value_usd ELSE 0 END)
```

**`revenue_vs_last_click_pct`:**
```
(SUM(attributed_value_usd) - SUM(revenue_last_click)) / NULLIF(SUM(revenue_last_click), 0)
```

Chart settings:

| Setting | Value |
|---------|-------|
| Chart type | **Table** |
| Dimension | `channel`, `model` |
| Metrics | `revenue_vs_last_click_pct` (as percentage) |

Use **conditional formatting**: green for positive (>0 means model gives MORE credit than Last Click), red for negative.

### 2.5 Scorecard Grid: Top Channels (Executive Summary)

For a "CEO slide" — instant hero channels without scrolling:

| Setting | Value |
|---------|-------|
| Chart type | **Scorecard** (one per channel) |
| Metric | `SUM(attributed_value_usd)` |
| Filter | One scorecard per `channel` |

Arrange 4–6 scorecards in a row at the top of the dashboard. Add a filter control on `model` so switching models updates all scorecards simultaneously.

---

## 3. Data-Driven Model Deep-Dive

For `attr_data_driven_bqml`, create a separate page with BQML-specific charts.

### 3.1 Feature Importance (Bar Chart)

Run this query in BigQuery, save as table, connect:
```sql
SELECT
  * EXCEPT(model, processed_input, expected_value)
FROM
  ML.WEIGHTS(MODEL `your-project.attribution_models.attr_data_driven_model`)
ORDER BY ABS(weight) DESC
```

| Setting | Value |
|---------|-------|
| Chart type | **Bar Chart** |
| Dimension | `input` (channel name) |
| Metric | `weight` |
| Sort | `ABS(weight)` descending |

### 3.2 Predicted vs Actual Conversion Rate (Scatter)

```sql
SELECT
  predicted_converted_label,
  AVG(converted) AS actual_conversion_rate
FROM
  ML.EVALUATE(MODEL `your-project.attribution_models.attr_data_driven_model`)
GROUP BY predicted_converted_label
```

| Setting | Value |
|---------|-------|
| Chart type | **Scatter Chart** |
| Dimension | `predicted_converted_label` |
| Metric | `actual_conversion_rate` |

---

## 4. Channel Performance Heatmap

**Goal:** Matrix view of model × channel to spot over/under-attribution at a glance.

### 4.1 Pivot Table Heatmap

| Setting | Value |
|---------|-------|
| Chart type | **Pivot Table** |
| Rows | `channel` |
| Columns | `model` |
| Metric | `SUM(attributed_value_usd)` |

*How to add the pivot:*
1. Click **Add a chart** → **Pivot Table** (under Table section)
2. Drag `channel` to **Row Dimension**
3. Drag `model` to **Column Dimension**
4. Drag `attributed_value_usd` to **Metrics** (click its aggregation icon, set to SUM)

*Formatting:*
- Click the pivot table → **Style** tab
- Under **Conditional formatting**, add a color scale:
  - Min: white or light blue
  - Max: dark blue
  - Apply to: `SUM(attributed_value_usd)`

*What you'll see:* A channel × model grid. "Referral" under Last Click might be dark (high revenue), but under First Click it could be lighter — revealing how credit shifts based on position.

### 4.2 Heatmap Variant — Attributed Credit

Duplicate the pivot table and change the metric to `SUM(attributed_credit)`. This shows conversion credit distribution rather than revenue. Use a different color scale (e.g., green) to distinguish from the revenue heatmap.

### 4.3 Heatmap Variant — Average Order Value

A third pivot using `AVG(aov_usd)` as the metric. This reveals whether certain models attribute higher-value conversions to certain channels.

---

## 5. Conversion Path Analysis

**Goal:** Show the most common user journey paths leading to purchase.

### 5.1 Table: Top Conversion Paths

Use the **Paths** data source.

| Setting | Value |
|---------|-------|
| Data source | `paths_dashboard` |
| Chart type | **Table** |
| Dimension | `path_string` |
| Metrics | `conversion_value_usd` (SUM), `path_length` (AVG), Record Count |
| Sort | `SUM(conversion_value_usd)` → Descending |
| Rows per page | 25 |

*What you'll see:* Paths like "Organic Search > Direct > Referral > Purchase" with revenue and path length. The `path_string` column shows the full sequence using `>` as a separator.

### 5.2 Path Length Distribution

**Calculated Field — `path_length` (already in data):** Use directly.

| Setting | Value |
|---------|-------|
| Chart type | **Column Chart** or **Bar Chart** |
| Dimension | `path_length` |
| Metric | `Record Count` (rename to "Conversions") |
| Sort | `path_length` → Ascending |

This shows how many conversions happen at each path length. Most conversions typically cluster at paths of 1–3 touchpoints.

### 5.3 Revenue by Path Length

| Setting | Value |
|---------|-------|
| Chart type | **Bar Chart** |
| Dimension | `path_length` |
| Metric | `SUM(conversion_value_usd)` |

Compare this with chart 4.2: longer paths may represent higher-value purchases.

### 5.4 Device Breakdown of Paths

| Setting | Value |
|---------|-------|
| Chart type | **Pie Chart** or **Donut Chart** |
| Dimension | `device_category` |
| Metric | Record Count |

Add a filter control for `path_length` so users can see how mobile vs. desktop differs for short vs. long paths.

---

## 6. Ecommerce Funnel Visualization

**Goal:** Visualize drop-off through the ecommerce funnel: Sessions → Product Views → Add to Cart → Checkout → Purchase.

### 6.1 Funnel Chart

| Setting | Value |
|---------|-------|
| Data source | `funnel_dashboard` |
| Chart type | **Funnel Chart** |
| Dimension | `stage` |
| Metric | `unique_users` |
| Sort | `stage_num` → Ascending |
| Optional metric | `pct_of_top_users` (as tooltip/secondary) |

*How to sort by stage_num:*
1. Click the funnel chart
2. In the **Data** tab, find the `stage` dimension
3. Click the dimension, select **Sort** → `stage_num` → Ascending
4. This ensures the funnel reads top-to-bottom in logical order (add_to_cart → begin_checkout → add_shipping_info → add_payment_info → purchase)

*Note:* Looker Studio's Funnel chart requires stages to be in the correct order. If your stages appear out of order, create a calculated field:
```
CASE 
  WHEN stage = 'add_to_cart' THEN 1
  WHEN stage = 'begin_checkout' THEN 2
  WHEN stage = 'add_shipping_info' THEN 3
  WHEN stage = 'add_payment_info' THEN 4
  WHEN stage = 'purchase' THEN 5
  ELSE 99
END
```
Name it `stage_order`. Then sort `stage` by `stage_order`.

*What you'll see:* A funnel narrowing from Add to Cart (widest) down to Purchase (narrowest). Each stage shows user count and drop-off percentage.

### 6.2 Drop-off Bar Chart

| Setting | Value |
|---------|-------|
| Chart type | **Bar Chart** |
| Dimension | `stage` (sorted by `stage_num`) |
| Metric | `unique_users` |
| Sort | `stage_num` → Ascending |

Add a secondary metric if desired: `stage_revenue_usd` (revenue generated at each step, only meaningful at Purchase).

### 6.3 Cart Abandonment Scorecard

Cart abandonment data is in the same `funnel_dashboard` source with `stage_num = 99`.

| Setting | Value |
|---------|-------|
| Chart type | **Scorecard** |
| Filter | `stage_num` = 99 |
| Metric | `abandonment_rate_pct` (set aggregation to AVG) |

Display this prominently — it shows the percentage of users who added to cart but never purchased.

### 6.4 Funnel Stage Conversion Rates

**Calculated Field — `stage_conversion_rate`:**  
If using the raw `purchase_funnel` table (not `funnel_dashboard`):
```
unique_users / MAX(unique_users)
```

With `funnel_dashboard`, use the pre-calculated `pct_of_top_users` field instead.

| Setting | Value |
|---------|-------|
| Chart type | **Table** |
| Dimension | `stage` |
| Metric | `pct_of_top_users` (AVG) |
| Metric 2 | `unique_users` (SUM) |

---

## 7. Revenue Attribution Sankey / Flow (Advanced)

**Goal:** Show how revenue flows from channels to conversion credit under different models.

### 7.1 Sankey Diagram

*Looker Studio does not have a native Sankey chart.* Options:

**Option A — Community Visualization (Recommended)**

1. Click **Add a chart** → scroll to **Community visualizations**
2. Search for "Sankey" — install a community Sankey visualization (e.g., "Sankey Diagram" by Looker Studio team or a popular third-party one)
3. Configure:

| Setting | Value |
|---------|-------|
| Data source | Custom query (see below) |
| Source dimension (Level 1) | `channel` |
| Target dimension (Level 2) | `model` |
| Value metric | `SUM(attributed_value_usd)` |

**Custom Query for Sankey:**
```sql
SELECT
  channel as source,
  model as target,
  SUM(attributed_value_usd) as revenue_usd
FROM `marketingdataanalyst.attribution_models.attribution_mart`
GROUP BY 1, 2
```

*What you'll see:* Channels on the left, models on the right, with flow thickness proportional to attributed revenue.

**Option B — Use Cross-Channel Comparison Table**

Use `cross_channel_comparison` for a table-based flow:

| Setting | Value |
|---------|-------|
| Data source | custom query → `cross_channel_comparison` |
| Chart type | **Table** with heatmap |
| Rows | `channel` |
| Columns | `model` |
| Metric | `total_value_usd` |

Apply conditional formatting (gradient) — this gives a similar visual result to a Sankey.

**Option C — Export to Flourish / Datawrapper**

For publication-quality Sankeys:
1. Create a table in Looker Studio with `channel`, `model`, `SUM(attributed_value_usd)`
2. Export as CSV
3. Import into [Flourish](https://flourish.studio/) or [SankeyMATIC](https://sankeymatic.com/)

### 7.2 Flow Visualization: Channel → Attribution Model Revenue

Create a stacked bar alternative:

| Setting | Value |
|---------|-------|
| Chart type | **100% Stacked Bar** |
| Dimension | `channel` |
| Metric | `SUM(attributed_value_usd)` |
| Breakdown | `model` |

This shows how each model distributes revenue across channels as proportions.

---

## 8. Cross-Model Revenue Comparison

**Goal:** Compare total attributed revenue across models to see which models give more/less revenue to each channel.

### 8.1 Stacked Bar: Revenue by Model

| Setting | Value |
|---------|-------|
| Chart type | **Stacked Bar Chart** |
| Dimension | `model` |
| Metric | `SUM(attributed_value_usd)` |
| Breakdown | `channel` |

*What you'll see:* Eight bars, one per model. The total height of each bar should be identical (total revenue is the same regardless of model — only the distribution across channels changes). If bar heights differ, data may have a `UNION ALL` issue.

*How to read:* A stacked bar for "first_click" with a large "Organic Search" segment means First Click attributes most revenue to Organic Search. The "last_click" bar will likely have a larger "Direct" segment.

### 8.2 Table: Model Comparison Summary

Use the `cross_channel_comparison` table via custom query:

```sql
SELECT
  model,
  SUM(total_value_usd) as total_revenue,
  SUM(attributed_conversions) as total_conversions,
  ROUND(SUM(total_value_usd) / NULLIF(SUM(attributed_conversions), 0), 2) as overall_aov
FROM `marketingdataanalyst.attribution_models.cross_channel_comparison`
GROUP BY model
ORDER BY model
```

| Setting | Value |
|---------|-------|
| Chart type | **Table** |
| Data source | Custom query (above) |
| Dimensions | `model` |
| Metrics | `total_revenue`, `total_conversions`, `overall_aov` |

**Calculated Field — `share_of_total_revenue`:**
```
total_revenue / SUM(total_revenue)
```
Add this as a percentage column to confirm each model accounts for 12.5% (1/8) of total revenue.

### 8.3 Radar / Spider Chart: Channel Profiles per Model

| Setting | Value |
|---------|-------|
| Chart type | **Radar Chart** |
| Dimension | `channel` |
| Metric | `SUM(attributed_value_usd)` |
| Breakdown | `model` (limit to 3–4 models for readability) |

*What you'll see:* Overlapping polygons showing channel attribution profiles. First Click will spike on early-journey channels; Last Click will spike on late-journey channels.

---

## 9. Time Series of Conversions

**Goal:** Show how attributed conversions and revenue trend over time, by model and channel.

### 9.1 Line Chart: Daily Attributed Revenue by Model

| Setting | Value |
|---------|-------|
| Chart type | **Time Series Chart** (Line) |
| Dimension | `conversion_ts` (set granularity to **Date**) |
| Metric | `SUM(attributed_value_usd)` |
| Breakdown | `model` |

> **Important:** Make sure `conversion_ts` is recognized as a Date/Time field. If Looker Studio treats it as text, click the field → **Type** → **Date & Time** → **Date**.

*What you'll see:* Eight lines tracking daily attributed revenue. On any given day, the 8 lines should be identical (same total revenue, different only in how it's split across channels within each model). Differences indicate data issues.

### 9.2 Time Series: Attributed Revenue by Channel

| Setting | Value |
|---------|-------|
| Chart type | **Time Series Chart** (Stacked Area) |
| Dimension | `conversion_ts` (Date) |
| Metric | `SUM(attributed_value_usd)` |
| Breakdown | `channel` |

Add a **Filter Control** for `model` so users can switch between models and see how channel composition changes over time.

### 9.3 Time Series: Attribution Model Differences Over Time

Create a calculated field that measures the delta between two models:

**`delta_first_vs_last`:**
```
SUM(CASE WHEN model = 'first_click' THEN attributed_value_usd ELSE 0 END) 
- SUM(CASE WHEN model = 'last_click' THEN attributed_value_usd ELSE 0 END)
```

| Setting | Value |
|---------|-------|
| Chart type | **Bar Chart** or **Column Chart** |
| Dimension | `conversion_ts` (Date) |
| Metric | `delta_first_vs_last` |

This shows whether the "attribution gap" between First Click and Last Click widens or narrows over time.

### 9.4 Week-over-Week Change

**Calculated Field — `wow_revenue_change`:**
```
(SUM(attributed_value_usd) - SUM(attributed_value_usd, -7)) 
  / NULLIF(SUM(attributed_value_usd, -7), 0)
```

| Setting | Value |
|---------|-------|
| Chart type | **Table** or **Scorecard** |
| Dimension | `conversion_ts` (ISO Week) |
| Metric | `wow_revenue_change` (formatted as %) |

*Note:* The Looker Studio `SUM(metric, -N)` function applies a time offset. `-7` means "7 days ago."

---

## 10. Filters and Controls

Good dashboards are interactive. Add these controls to help users explore the data.

### 10.1 Date Range Control

| Setting | Value |
|---------|-------|
| Control type | **Date range control** |
| Default | Last 30 days (or custom range matching your data) |
| Applies to | All charts on the page |

*How to add:* **Add a control** → **Date range control**. Position it at the top of the dashboard. No configuration needed — it auto-filters all charts using `conversion_ts`.

### 10.2 Model Selector

| Setting | Value |
|---------|-------|
| Control type | **Drop-down list** |
| Control field | `model` |
| Style | Multi-select (checkboxes) |

*Default selection:* All models. Users can deselect to focus on 2–3 models at a time.

### 10.3 Channel Selector

| Setting | Value |
|---------|-------|
| Control type | **Drop-down list** |
| Control field | `channel` |
| Style | Multi-select |

### 10.4 Path Length Filter (Slider)

| Setting | Value |
|---------|-------|
| Control type | **Slider** |
| Control field | `path_length` |
| Range | 1 to 20 (adjust based on your data's max path length) |

*Use case:* "Show me only conversions that took 3+ touchpoints."

### 10.5 Device Category Filter

| Setting | Value |
|---------|-------|
| Control type | **Drop-down list** |
| Control field | `device_category` |

### 10.6 Cross-Filtering (Chart Interactions)

Enable cross-filtering so clicking a bar in one chart filters all others:
1. Click any chart
2. Go to **Style** tab
3. Under **Cross-filtering**, toggle **ON**

Now clicking "Organic Search" in the bar chart will filter the time series and paths table to only Organic Search rows.

### 10.7 Control Layout Tips

- Place date range and model selector at the **top** (global controls)
- Place channel selector on the main comparison page
- Place device/path-length filters near the paths page
- Group controls visually with a light gray background rectangle (Insert → Shape → Rectangle)

---

## 11. Sharing and Refresh

### 11.1 Data Freshness

Looker Studio uses **live connections** to BigQuery. Every time someone views the dashboard, it queries BigQuery.

| Refresh Setting | How to Set |
|-----------------|------------|
| Cache freshness | **Resource** → **Manage report data freshness** → Set to 1 hour, 4 hours, or 12 hours |
| Force refresh | Click the refresh icon (⟳) in the toolbar, or refresh the browser page |

*Recommendation:* Set cache to **4 hours** for daily reporting. For real-time dashboards, set to **15 minutes** (note: higher BigQuery query costs).

### 11.2 Sharing the Dashboard

1. Click **Share** (top-right) → **Invite people**
2. Enter email addresses
3. Set permissions:
   - **Viewer:** Can only view, cannot edit or see underlying data
   - **Editor:** Can modify charts but cannot change data sources
   - **Owner:** Full control (you)
4. **Link sharing:** Toggle to "Anyone with the link can view" for broad distribution

> **Important:** Viewers do NOT need BigQuery access. Looker Studio uses the report owner's credentials to query BigQuery. Viewers see charts only — they cannot run arbitrary queries against your data.

### 11.3 Download Options

Users (and you) can download data from any chart:
1. Hover over the chart → click the three-dot menu (⋮)
2. Select **Export** → CSV, Google Sheets, or Excel

To download the full underlying dataset, use the **Data** tab → **Export**.

### 11.4 Scheduling PDF / Email Delivery

Looker Studio supports scheduled email delivery:

1. Click the **dropdown arrow** next to the Share button → **Schedule delivery**
2. Set frequency: daily, weekly, monthly
3. Choose time and day
4. Add recipient emails
5. **Optional:** Check "Attach PDF" to send a static PDF snapshot

*Note:* PDF exports capture the dashboard as it appears at the scheduled time. Interactive filters are not active in PDFs.

### 11.5 Embedding

To embed the dashboard in a webpage or internal portal:
1. **File** → **Embed report**
2. Copy the iframe code
3. **Optional:** Check "Enable embedding" to restrict which domains can embed

### 11.6 BigQuery Cost Management

| Concern | Solution |
|---------|----------|
| Dashboard queries are expensive | Set cache freshness to 4+ hours; use aggregate tables |
| Too many viewers hitting BigQuery | Looker Studio caches per-user — reasonable |
| Raw data scans are costly | Use the `dashboard.*` views (they read from materialized tables, not raw GA4 events) |

The `dashboard.attribution_dashboard` and `cross_channel_comparison` views query materialized tables (~58K rows for the mart, ~56 rows for the comparison). These are **trivially cheap** — expect cents per month even with frequent viewing.

### 11.7 Troubleshooting

| Problem | Likely Cause | Fix |
|---------|-------------|-----|
| "No data" on all charts | Dataform pipeline hasn't been run | Run `dataform run` in your project |
| Only 6 models appear (not 8) | `data_driven_bqml` and `position_weighted` may have 0 rows on small datasets | Expected on public sample; ignore or add `WHERE model IS NOT NULL` filter |
| Date filter shows wrong range | `conversion_ts` field type is Text | Edit data source → change `conversion_ts` type to Date & Time |
| Revenue totals differ between models | Normal — each model distributes the SAME total revenue differently across channels | Verify `SUM(attributed_value_usd)` per model matches; if not, check UNION in mart |
| Charts show "Data Studio can't display this field" | Aggregation conflict | Set field aggregation explicitly (SUM, AVG, etc.) in the Data tab |
| Funnel chart stages out of order | Looker Studio sorts alphabetically | Set custom sort using `stage_num` field |

---

## Appendix A: Complete List of Available Fields

### `dashboard.attribution_dashboard` (Attribution data source)

| Field | Type | Description |
|-------|------|-------------|
| `model` | Text | Attribution model name: first_click, last_click, last_non_direct_click, linear, time_decay, u_shape, position_weighted, data_driven_bqml |
| `channel` | Text | Marketing channel (17-channel taxonomy): Cross-network, Paid Search Brand, Paid Search Non-Brand, Paid Shopping, Paid Social, Paid Video, Display, Organic Search, Organic Shopping, Organic Social, Organic Video, Email, SMS, Affiliate, Audio, Mobile Push, Referral, Direct, Unknown |
| `conversion_id` | Text | Globally unique conversion identifier |
| `conversion_ts` | DateTime | Timestamp of the conversion event |
| `conversion_event` | Text | Event name (e.g., 'purchase', 'generate_lead', 'subscribe') |
| `transaction_id` | Text | Ecommerce transaction ID (may be NULL for non-purchase conversions) |
| `purchase_revenue` | Number | Revenue in local currency |
| `conversion_value_usd` | Number | Revenue converted to USD |
| `value_mode` | Text | Value interpretation mode: revenue, fixed, or count |
| `path_length` | Number | Number of touchpoints in the conversion journey |
| `source` | Text | Traffic source (e.g., google, bing, direct) |
| `medium` | Text | Traffic medium (e.g., organic, cpc, referral) |
| `campaign` | Text | Campaign name (if tagged) |
| `attributed_credit` | Number (0–1) | Fractional credit assigned by the model (1.0 = 100%) |
| `attributed_value_usd` | Number | Revenue in USD × attributed_credit |
| `attributed_value_local` | Number | Revenue in local currency × attributed_credit |
| `channel_total_value_usd` | Number | Total value for this channel across all conversions (from cross_channel_comparison) |
| `channel_total_conversions` | Number | Total credited conversions for this channel |
| `aov_usd` | Number | Average order value = attributed_value_usd / attributed_credit |

### `dashboard.funnel_dashboard` (Funnel data source)

| Field | Type | Description |
|-------|------|-------------|
| `stage_num` | Number | Stage ordering: 1=add_to_cart, 2=begin_checkout, 3=add_shipping_info, 4=add_payment_info, 5=purchase, 99=cart_abandonment |
| `stage` | Text | Human-readable stage name |
| `unique_users` | Number | Distinct users at this stage |
| `unique_sessions` | Number | Distinct sessions at this stage |
| `total_events` | Number | Total event count at this stage |
| `stage_revenue_usd` | Number | Revenue at this stage (meaningful only for purchase) |
| `pct_of_top_users` | Number | Percentage of users who reach this stage vs. total |
| `pct_of_top_sessions` | Number | Percentage of sessions |
| `abandonment_rate_pct` | Number | Cart abandonment rate (stage_num=99 only) |

### `dashboard.paths_dashboard` (Paths data source)

| Field | Type | Description |
|-------|------|-------------|
| `user_pseudo_id` | Text | Anonymous user identifier |
| `conversion_id` | Text | Conversion identifier |
| `conversion_ts` | DateTime | Conversion timestamp |
| `conversion_event` | Text | Event name (e.g., 'purchase') |
| `transaction_id` | Text | Ecommerce transaction ID |
| `purchase_revenue` | Number | Revenue in local currency |
| `conversion_value_usd` | Number | Revenue in USD |
| `path_length` | Number | Number of touchpoints |
| `path` | Array / JSON | Full path as array of touchpoint structs |
| `path_string` | Text | Channel path as string ("Organic Search > Direct > Referral") |
| `device_category` | Text | Device: mobile, desktop, tablet |
| `device_os` | Text | Operating system |
| `country` | Text | Country name |
| `city` | Text | City name |

---

## Appendix B: Quick-Start Dashboard Template

To build a complete dashboard in ~20 minutes, follow this minimal recipe:

**Page 1 — Attribution Overview:**
1. 4 scorecards (total conversions, revenue USD, revenue local, AOV) — top row
2. Clustered bar chart: `channel` × `model` with `SUM(attributed_value_usd)` — center
3. Pivot table: `channel` rows, `model` columns, `SUM(attributed_value_usd)` — bottom
4. Controls: Date range + Model selector — top

**Page 2 — Funnel & Conversion:**
1. Funnel chart: `stage` → `unique_users` — center
2. Cart abandonment scorecard — top
3. Drop-off bar chart — bottom
4. Controls: Date range — top

**Page 3 — User Journeys:**
1. Table: `path_string` + `conversion_value_usd` — center
2. Path length bar chart — right sidebar
3. Device pie chart — left sidebar
4. Controls: Date range + Path length slider — top

---

## Appendix C: SQL Queries for Custom Data Sources

### C.1 Attribution Model Summary (for scorecards)

```sql
-- Total metrics per model — verifies all models have same total revenue
SELECT
  model,
  COUNT(DISTINCT conversion_id) as conversion_count,
  SUM(attributed_credit) as total_credited_conversions,
  SUM(attributed_value_usd) as total_revenue_usd,
  ROUND(AVG(attributed_value_usd / NULLIF(attributed_credit, 0)), 2) as avg_aov,
  COUNT(DISTINCT channel) as channels_used
FROM `marketingdataanalyst.attribution_models.attribution_mart`
GROUP BY model
ORDER BY model
```

### C.2 Channel-Level Attribution (already materialized, use for performance)

```sql
-- This is the cross_channel_comparison table — already exists
SELECT
  model,
  conversion_event,
  channel,
  attributed_conversions as total_conversions,
  total_value_usd,
  total_credit,
  avg_order_value_usd as avg_order_value,
  -- Calculate shares as derived fields in Looker Studio instead
FROM `marketingdataanalyst.attribution_models.cross_channel_comparison`
ORDER BY model, conversion_event, total_value_usd DESC
```

### C.3 Top Converting Paths (already materialized as path_analysis)

```sql
-- Pre-aggregated top paths for faster table rendering
SELECT
  path_string,
  unique_users,
  total_conversions,
  avg_revenue_usd,
  total_revenue_usd,
  avg_path_length
FROM `marketingdataanalyst.user_journey.path_analysis`
ORDER BY total_conversions DESC
LIMIT 50
```

### C.4 Daily Revenue by Model (for time series)

```sql
SELECT
  DATE(conversion_ts) as conversion_date,
  model,
  channel,
  SUM(attributed_credit) as daily_credit,
  SUM(attributed_value_usd) as daily_revenue
FROM `marketingdataanalyst.attribution_models.attribution_mart`
GROUP BY 1, 2, 3
ORDER BY 1, 2
```

### C.5 Path Length Revenue Analysis

```sql
SELECT
  path_length,
  COUNT(DISTINCT conversion_id) as conversions,
  SUM(conversion_value_usd) as total_revenue,
  ROUND(AVG(conversion_value_usd), 2) as avg_revenue
FROM `marketingdataanalyst.attribution_models.attribution_mart`
WHERE model = 'last_click'  -- pick one model; path_length is the same for all
GROUP BY path_length
ORDER BY path_length
```

---

*Last updated: 2026-05-05. Questions or improvements? Open an issue on the [GitHub repository](https://github.com/GlitchG/ga4-attribution-models).*
