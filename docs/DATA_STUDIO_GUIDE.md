# DATA Studio Visualization Guide — GA4 Attribution Models

**Project:** GA4 Attribution Models (Dataform Edition)
**Audience:** Marketing analysts comfortable with Data Studio's UI
**Prerequisites:** Dataform pipeline has been run successfully; tables exist in your BigQuery project
**Throughout this guide:** Replace `marketingdataanalyst` in the SQL snippets with your own GCP project ID (the value of `defaultProject` in `workflow_settings.yaml`).

---

## Dashboard Overview

This guide shows you how to build a three-page Data Studio dashboard from the Dataform output.

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
| `cross_channel_comparison` | ~64 |
| `paths_dashboard` | ~12,000 |
| `funnel_dashboard` | 6 (5 stages + 1 cart abandonment) |

### Cost Notes

- Data Studio queries BigQuery **live** every time someone opens the dashboard
- The dashboard views (`dashboard.*`) read from materialised tables, not raw GA4 events — trivial cost
- Set cache freshness to **4 hours** to reduce repeated queries
- For scheduled PDF delivery, the snapshot queries run once at schedule time

---

## 1. Connecting BigQuery to Data Studio

### 1.1 Create a New Report

1. Go to [Datastudio.google.com](https://Datastudio.google.com)
2. Click **+ Create** → **Report**
3. You'll be prompted to add a data source first

### 1.2 Add BigQuery Data Sources

You'll add **five** data sources. Each is purpose-built for one type of chart — picking the right one avoids 90% of the common visualization pitfalls listed in §12.

| Data source | View | Granularity | Use it for |
|---|---|---|---|
| Attribution (row-level) | `dashboard.attribution_dashboard` | One row per touchpoint per conversion per model | Path-level analysis, AOV calculated fields, model comparison when you can apply a `model` filter |
| Channel comparison (pre-agg) | `attribution_models.cross_channel_comparison` | One row per (model × conversion_event × channel) | Channel-level summaries — SUMs are correct as-is, no model filter needed |
| Daily traffic | `dashboard.daily_traffic_overview` | One row per (date × channel × source × medium) | Users / sessions / traffic-mix charts (top-of-funnel, not just converted journeys) |
| Funnel | `dashboard.funnel_dashboard` | One row per funnel stage | Ecommerce funnel, drop-off, cart abandonment |
| Paths | `dashboard.paths_dashboard` | One row per conversion journey | Top conversion paths, path length distribution |


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

Click **Add**. Data Studio will show a preview of ~58K rows with columns: `model`, `conversion_event`, `value_mode`, `channel`, `user_pseudo_id`, `conversion_id`, `conversion_ts`, `conversion_date`, `transaction_id`, `conversion_value_local`, `conversion_value_usd`, `path_length`, `source`, `medium`, `campaign`, `attributed_credit`, `attributed_value_usd`, `attributed_value_local`.

> **Granularity warning — read this before you build any chart.** `attribution_dashboard` is a **row-level** view: one row per touchpoint per conversion per model. Aggregate it in Data Studio with `SUM(attributed_credit)`, `SUM(attributed_value_usd)`, and `COUNT(DISTINCT conversion_id)`. If you just drag a dimension onto the canvas without an aggregated metric, Data Studio will show one row per touchpoint and the same source/channel will repeat many times. For channel-level summaries (e.g. "total revenue per channel per model") point Data Studio at `attribution_models.cross_channel_comparison` instead — that view is already aggregated and safe to chart without further GROUP BY.

#### Data Source 2: Daily Traffic (Users / Sessions)

| Step | Action |
|------|--------|
| Connector | BigQuery |
| Dataset | `dashboard` |
| Table | `daily_traffic_overview` |

This view is **pre-aggregated**. Each row is one `(session_date, channel, source, medium)` combination, with `unique_users`, `total_sessions`, and `sessions_per_user` already computed. You can drag any metric onto a chart without thinking about distinct counts or model filters.

Columns:

| Field | Type | Description |
|---|---|---|
| `session_date` | Date | Date of the session |
| `channel` | Text | 19-channel grouping |
| `source` / `medium` | Text | Raw GA4 source/medium |
| `unique_users` | Number | Distinct `user_pseudo_id` on that day on that channel |
| `total_sessions` | Number | Distinct `(user_pseudo_id, ga_session_id)` pairs |
| `sessions_per_user` | Number | `total_sessions / unique_users` |

**Use this for:** "Users by channel over time", "Sessions by traffic mix", "Sessions per user trend". **Do NOT** use it for attributed conversions — these counts include every visitor, not just converters.

#### Data Source 3: Funnel

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

#### Data Source 4: Paths

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
| Average Order Value (USD) | `SUM(attributed_value_usd) / SUM(attributed_credit)` (calculated field) | model = any single model |

*How to add:* Click **Add a chart** → **Scorecard**. Drag the metric from the data panel. For AOV, create a calculated field on the data source (**Resource → Manage added data sources → ADD A FIELD**) named `aov_usd` with the formula `SUM(attributed_value_usd) / SUM(attributed_credit)`, then drag it onto a scorecard. Add a `model` filter so the AOV reflects one model at a time — otherwise you'd be averaging across 8 different credit allocations for the same revenue.

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

Create a table showing how much more or less revenue each model attributes vs. Last Click.

Use the pre-computed `variance_from_last_click_usd` column from the **Channel comparison (pre-agg)** data source (`attribution_models.cross_channel_comparison`). This value is computed server-side via a window function in BigQuery — Data Studio calculated fields do not support window functions, so attempting to recreate this logic as a calculated field will fail.

| Setting | Value |
|---------|-------|
| Data source | `cross_channel_comparison` |
| Chart type | **Table** |
| Dimension | `channel`, `model` |
| Metric | `variance_from_last_click_usd` (aggregation: SUM) |

Use **conditional formatting**: green for positive (model gives MORE revenue than Last Click for this channel), red for negative.

> **Why server-side?** `variance_from_last_click_usd` requires `SUM(...) OVER (PARTITION BY channel)` to look up the last-click value for the same channel across model rows. Window functions are not available in Data Studio calculated fields — they are evaluated row-by-row without access to sibling rows in the same partition.

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

A third pivot using the calculated AOV field (`SUM(attributed_value_usd) / SUM(attributed_credit)`) as the metric. This reveals whether certain models attribute higher-value conversions to certain channels. Filter to a single `conversion_event` (e.g. `purchase`) to keep the AOV meaningful — mixing revenue events with count-mode events would give you a misleading number.

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

*Note:* Data Studio's Funnel chart requires stages to be in the correct order. If your stages appear out of order, create a calculated field:
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

*Data Studio does not have a native Sankey chart.* Options:

**Option A — Community Visualization (Recommended)**

1. Click **Add a chart** → scroll to **Community visualizations**
2. Search for "Sankey" — install a community Sankey visualization (e.g., "Sankey Diagram" by Data Studio team or a popular third-party one)
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
1. Create a table in Data Studio with `channel`, `model`, `SUM(attributed_value_usd)`
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

## 9. Users and Sessions

**Goal:** Chart raw users / sessions / traffic mix — independent of whether those users ultimately converted.

There are two views to choose from depending on what question you're answering:

| Question | Use this view | Why |
|---|---|---|
| "How many users / sessions did each channel bring me?" | `daily_traffic_overview` | Already aggregated to date × channel grain, includes every visitor |
| "How many users / sessions appear in conversion journeys (per attribution model)?" | `attribution_dashboard` | Row-level, requires a `model` filter and `COUNT(DISTINCT user_pseudo_id)` |

### 9.1 Daily Users by Channel (top-of-funnel)

Use the **Daily Traffic** data source.

| Setting | Value |
|---------|-------|
| Chart type | **Time Series Chart** (Line or Stacked Area) |
| Dimension | `session_date` |
| Metric | `unique_users` (already a distinct count — DO NOT wrap in `COUNT_DISTINCT`) |
| Breakdown | `channel` |

> **Important:** `unique_users` and `total_sessions` are pre-computed in the view. Set their aggregation to `SUM` in Data Studio (since each row is one channel/day combination, summing across the date dimension is correct). Do **not** wrap them in `COUNT_DISTINCT` — that would count the number of channel/day pairs, not users.

### 9.2 Sessions per User (engagement)

| Setting | Value |
|---------|-------|
| Chart type | **Scorecard** or **Time Series** |
| Metric | `sessions_per_user` (set aggregation to `AVG`) |

For a single scorecard summing the full period, use a calculated field on the data source: `SUM(total_sessions) / SUM(unique_users)` — this is more accurate than averaging the daily rate.

### 9.3 Traffic Mix (Channel Share of Sessions)

| Setting | Value |
|---------|-------|
| Chart type | **100% Stacked Bar** or **Donut Chart** |
| Dimension | `channel` |
| Metric | `total_sessions` (aggregation: `SUM`) |

### 9.4 Users Who Converted vs Total Users (conversion-rate proxy)

Combine two data sources:

1. **Total users** from `daily_traffic_overview` → `SUM(unique_users)` filtered to your channel / date.
2. **Converting users** from `attribution_dashboard` → `COUNT(DISTINCT user_pseudo_id)` filtered to a single `model` (last_click is the conventional choice) and the same channel / date.

Then create a calculated field for the rate. Note that this is an **approximate** conversion rate — `daily_traffic_overview` counts every visitor while `attribution_dashboard` counts every user who later converted via this channel, and the two views are joined manually in the BI tool rather than at SQL time.

### 9.5 Converting Users per Channel per Model

Use the **Attribution** data source.

| Setting | Value |
|---------|-------|
| Chart type | **Bar Chart** |
| Dimension | `channel` |
| Metric | `user_pseudo_id` (aggregation: `Count Distinct`) — rename to "Converting Users" |
| Filter | `model = last_click` (always filter to a single model) |

Without the `model` filter you'd add the same user up to 8 times (once per model in the union mart). This is the most common visualization bug — see §10 below.

---

## 10. Common Pitfalls and How to Avoid Them

A short list of every viz gotcha this dataset will throw at you, with the fix.

### 10.1 Forgetting the model filter — N× inflation

`attribution_dashboard` and `attribution_mart` contain **eight unioned models** (`first_click`, `last_click`, `last_non_direct_click`, `linear`, `time_decay`, `u_shape`, `position_weighted`, `data_driven_bqml`). Every conversion appears once per model.

| Wrong | Result |
|---|---|
| `SUM(attributed_value_usd)` with no filter | 8× revenue (one per model) |
| `COUNT(DISTINCT conversion_id)` with no filter | Correct, because conversion_id is shared across models |
| `COUNT(DISTINCT user_pseudo_id)` with no filter | Correct, same reason |

**Fix:** always add either a `model` filter control (default: one model selected) or restrict the chart's filter pane to a specific model.

### 10.2 Mixing currencies in `attributed_value_local`

`attributed_value_local` is in the **conversion's own currency** — for a single GA4 export this can be a mix of USD, EUR, GBP, etc. `SUM(attributed_value_local)` across currencies is meaningless.

**Fix:** either use `attributed_value_usd` (always USD), or add a currency filter to the chart (`event_currency` from `paths_dashboard` or join in your own currency table).

### 10.3 Count-mode events have NULL revenue

`begin_checkout`, `add_to_cart`, `add_shipping_info`, and `add_payment_info` are configured as `value_mode = 'count'`, so their `attributed_value_usd` is `NULL`. AOV and revenue charts that include these events will under-state metrics or show NULLs.

**Fix:** filter `conversion_event = 'purchase'` for any revenue / AOV chart. For conversion-count charts, leaving all events in is fine.

### 10.4 `conversion_ts` treated as Text

If your date-range filter doesn't work or your time-series chart shows a single bar, Data Studio likely parsed `conversion_ts` as Text.

**Fix:** Resource → Manage added data sources → click the field → change Type to **Date & Time** → **Date Time**. (The `conversion_date` column added in v2.0.4 is already a `DATE` type and is the safest dimension to use for daily aggregations.)

### 10.5 `source` and `channel` aren't the same granularity

`source` is the raw GA4 traffic-source string (e.g. `google`, `shop.googlemerchandisestore.com`, `(direct)`). `channel` is the normalized 19-channel grouping (e.g. `Organic Search`, `Paid Search Brand`, `Direct`). Putting both into a single chart dimension produces confusing rows because one channel maps to many sources.

**Fix:** pick one. For executive reporting, use `channel`. For ad-platform debugging, use `source` and `medium`.

### 10.6 `NULL transaction_id` for non-purchase events

`transaction_id` is only populated for `purchase` events. `COUNT(DISTINCT transaction_id)` will under-count if your chart includes `begin_checkout` / `add_to_cart`.

**Fix:** use `COUNT(DISTINCT conversion_id)` for conversion counts — it's populated for every event.

### 10.7 Many sessions show channel `Unknown` (public sample only)

The public GA4 sample anonymises traffic sources to `<Other>` / `(data deleted)`, which the pipeline maps to `Unknown` (the 19th channel). Don't be alarmed if `Unknown` is your biggest channel on the public sample — it isn't a bug. On real client data, this catch-all should be tiny.

### 10.8 BQML model rows missing or sparse

`attr_data_driven_bqml` requires enough training data to be meaningful (recommended: 1,000+ conversions). On the public sample, the BQML model produces directionally useful but noisy weights. If a chart filtered to `model = data_driven_bqml` looks empty or wild, switch to `last_click` or `linear` for the demo.

### 10.9 `funnel_dashboard` UNION mixes stage rows with cart-abandonment row

`funnel_dashboard` is a UNION ALL of `purchase_funnel` (5 rows: stages 1–5) and `cart_abandonment` (1 row: `stage_num = 99`). If you SUM across the whole view without a stage filter, you'll double-count add-to-cart users.

**Fix:** filter `stage_num < 99` for funnel-stage charts; filter `stage_num = 99` for the cart-abandonment scorecard.

### 10.10 `path_length` outliers from bot traffic

Real bot/scraper sessions can push `path_length` into the hundreds. A bar chart of `path_length` will show a long tail that drowns out the meaningful 1–5 bucket.

**Fix:** add a `path_length <= 10` filter to path-distribution charts, or use a calculated bucket field (`CASE WHEN path_length >= 10 THEN '10+' ELSE CAST(path_length AS STRING) END`).

---

## 11. Time Series of Conversions

**Goal:** Show how attributed conversions and revenue trend over time, by model and channel.

### 11.1 Line Chart: Daily Attributed Revenue by Model

| Setting | Value |
|---------|-------|
| Chart type | **Time Series Chart** (Line) |
| Dimension | `conversion_ts` (set granularity to **Date**) |
| Metric | `SUM(attributed_value_usd)` |
| Breakdown | `model` |

> **Important:** Make sure `conversion_ts` is recognized as a Date/Time field. If Data Studio treats it as text, click the field → **Type** → **Date & Time** → **Date**.

*What you'll see:* Eight lines tracking daily attributed revenue. On any given day, the 8 lines should be identical (same total revenue, different only in how it's split across channels within each model). Differences indicate data issues.

### 11.2 Time Series: Attributed Revenue by Channel

| Setting | Value |
|---------|-------|
| Chart type | **Time Series Chart** (Stacked Area) |
| Dimension | `conversion_ts` (Date) |
| Metric | `SUM(attributed_value_usd)` |
| Breakdown | `channel` |

Add a **Filter Control** for `model` so users can switch between models and see how channel composition changes over time.

### 11.3 Time Series: Attribution Model Differences Over Time

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

### 11.4 Week-over-Week Change

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

*Note:* The Data Studio `SUM(metric, -N)` function applies a time offset. `-7` means "7 days ago."

---

## 12. Filters and Controls

Good dashboards are interactive. Add these controls to help users explore the data.

### 12.1 Date Range Control

| Setting | Value |
|---------|-------|
| Control type | **Date range control** |
| Default | Last 30 days (or custom range matching your data) |
| Applies to | All charts on the page |

*How to add:* **Add a control** → **Date range control**. Position it at the top of the dashboard. No configuration needed — it auto-filters all charts using `conversion_ts`.

### 12.2 Model Selector

| Setting | Value |
|---------|-------|
| Control type | **Drop-down list** |
| Control field | `model` |
| Style | Multi-select (checkboxes) |

*Default selection:* All models. Users can deselect to focus on 2–3 models at a time.

### 12.3 Channel Selector

| Setting | Value |
|---------|-------|
| Control type | **Drop-down list** |
| Control field | `channel` |
| Style | Multi-select |

### 12.4 Path Length Filter (Slider)

| Setting | Value |
|---------|-------|
| Control type | **Slider** |
| Control field | `path_length` |
| Range | 1 to 20 (adjust based on your data's max path length) |

*Use case:* "Show me only conversions that took 3+ touchpoints."

### 12.5 Device Category Filter

| Setting | Value |
|---------|-------|
| Control type | **Drop-down list** |
| Control field | `device_category` |

### 12.6 Cross-Filtering (Chart Interactions)

Enable cross-filtering so clicking a bar in one chart filters all others:
1. Click any chart
2. Go to **Style** tab
3. Under **Cross-filtering**, toggle **ON**

Now clicking "Organic Search" in the bar chart will filter the time series and paths table to only Organic Search rows.

### 12.7 Control Layout Tips

- Place date range and model selector at the **top** (global controls)
- Place channel selector on the main comparison page
- Place device/path-length filters near the paths page
- Group controls visually with a light gray background rectangle (Insert → Shape → Rectangle)

---

## 13. Sharing and Refresh

### 13.1 Data Freshness

Data Studio uses **live connections** to BigQuery. Every time someone views the dashboard, it queries BigQuery.

| Refresh Setting | How to Set |
|-----------------|------------|
| Cache freshness | **Resource** → **Manage report data freshness** → Set to 1 hour, 4 hours, or 12 hours |
| Force refresh | Click the refresh icon (⟳) in the toolbar, or refresh the browser page |

*Recommendation:* Set cache to **4 hours** for daily reporting. For real-time dashboards, set to **15 minutes** (note: higher BigQuery query costs).

### 13.2 Sharing the Dashboard

1. Click **Share** (top-right) → **Invite people**
2. Enter email addresses
3. Set permissions:
   - **Viewer:** Can only view, cannot edit or see underlying data
   - **Editor:** Can modify charts but cannot change data sources
   - **Owner:** Full control (you)
4. **Link sharing:** Toggle to "Anyone with the link can view" for broad distribution

> **Important:** Viewers do NOT need BigQuery access. Data Studio uses the report owner's credentials to query BigQuery. Viewers see charts only — they cannot run arbitrary queries against your data.

### 13.3 Download Options

Users (and you) can download data from any chart:
1. Hover over the chart → click the three-dot menu (⋮)
2. Select **Export** → CSV, Google Sheets, or Excel

To download the full underlying dataset, use the **Data** tab → **Export**.

### 13.4 Scheduling PDF / Email Delivery

Data Studio supports scheduled email delivery:

1. Click the **dropdown arrow** next to the Share button → **Schedule delivery**
2. Set frequency: daily, weekly, monthly
3. Choose time and day
4. Add recipient emails
5. **Optional:** Check "Attach PDF" to send a static PDF snapshot

*Note:* PDF exports capture the dashboard as it appears at the scheduled time. Interactive filters are not active in PDFs.

### 13.5 Embedding

To embed the dashboard in a webpage or internal portal:
1. **File** → **Embed report**
2. Copy the iframe code
3. **Optional:** Check "Enable embedding" to restrict which domains can embed

### 13.6 BigQuery Cost Management

| Concern | Solution |
|---------|----------|
| Dashboard queries are expensive | Set cache freshness to 4+ hours; use aggregate tables |
| Too many viewers hitting BigQuery | Data Studio caches per-user — reasonable |
| Raw data scans are costly | Use the `dashboard.*` views (they read from materialized tables, not raw GA4 events) |

The `dashboard.attribution_dashboard` and `cross_channel_comparison` views query materialized tables (~58K rows for the mart, ~56 rows for the comparison). These are **trivially cheap** — expect cents per month even with frequent viewing.

### 13.7 Troubleshooting

| Problem | Likely Cause | Fix |
|---------|-------------|-----|
| "No data" on all charts | Dataform pipeline hasn't been run | Run `dataform run` in your project |
| Only 6 models appear (not 8) | `data_driven_bqml` and `position_weighted` may have 0 rows on small datasets | Expected on public sample; ignore or add `WHERE model IS NOT NULL` filter |
| Date filter shows wrong range | `conversion_ts` field type is Text | Edit data source → change `conversion_ts` type to Date & Time |
| Revenue totals differ between models | Normal — each model distributes the SAME total revenue differently across channels | Verify `SUM(attributed_value_usd)` per model matches; if not, check UNION in mart |
| Charts show "Data Studio can't display this field" | Aggregation conflict | Set field aggregation explicitly (SUM, AVG, etc.) in the Data tab |
| Funnel chart stages out of order | Data Studio sorts alphabetically | Set custom sort using `stage_num` field |

---

## Appendix A: Complete List of Available Fields

### `dashboard.attribution_dashboard` (Attribution data source)

| Field | Type | Description |
|-------|------|-------------|
| `model` | Text | Attribution model name: first_click, last_click, last_non_direct_click, linear, time_decay, u_shape, position_weighted, data_driven_bqml |
| `channel` | Text | Marketing channel (19-channel taxonomy): Cross-network, Paid Search Brand, Paid Search Non-Brand, Paid Shopping, Paid Social, Paid Video, Display, Organic Search, Organic Shopping, Organic Social, Organic Video, Email, SMS, Affiliate, Audio, Mobile Push, Referral, Direct, Unknown |
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

> For channel-level totals and average order value, do **not** look for them as columns on `attribution_dashboard` (they were removed in v2.0.3 — see CHANGELOG). Use `attribution_models.cross_channel_comparison` as a second data source for pre-aggregated `total_value_usd`, `attributed_conversions`, and `avg_attributed_value_usd`.

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
  attributed_conversions AS total_conversions,
  total_value_usd,
  total_credit,
  avg_attributed_value_usd AS avg_value_per_credit
  -- Calculate shares as derived fields in Data Studio instead
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
