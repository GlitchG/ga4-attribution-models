# GA4 Attribution Models — Real-World Usage & Visualisation Guide

**Version:** 2.0  
**Audience:** Marketing analysts, freelancers, consultants presenting to clients  
**Goal:** Turn raw GA4 BigQuery data into actionable attribution insights and client-ready dashboards  

---

## What This Project Actually Does (In Plain English)

Your GA4 export contains millions of events. This pipeline turns them into **one clear question answered eight different ways**:

> *"Which marketing channels deserve credit for each conversion?"*

It does this by:
1. Reconstructing every user's session history before they converted
2. Applying 8 different attribution philosophies (models)
3. Comparing the results so you can pick the right lens for the right decision

**Why 8 models?** Because no single model tells the whole truth. A CFO wants different evidence than a performance marketer.

---

## Part 1: From Zero to First Dashboard (30 Minutes)

### Step 1: Get the Pipeline Running

You have three options, ordered by effort:

#### Option A: GCP Dataform UI (Recommended for First-Timers)

1. Go to [console.cloud.google.com/bigquery/dataform](https://console.cloud.google.com/bigquery/dataform)
2. Create a repository in your GCP project
3. Link this GitHub repo via HTTPS (generate a fine-grained PAT with `Contents: Read-only`)
4. Create a workspace on `main`
5. Edit `workflow_settings.yaml`:
   ```yaml
   defaultProject: "your-gcp-project-id"
   defaultLocation: "US"  # or EU region; use US for public dataset
   vars:
     ga4_project: "bigquery-public-data"
     ga4_dataset: "ga4_obfuscated_sample_ecommerce"
     start_date: "20201101"
     end_date: "20210131"
     source_extraction_mode: "auto"
   ```
6. Click **Compile**, then **Run**
7. Wait 5–10 minutes. You now have ~15 tables in BigQuery.

#### Option B: Dataform CLI (For Developers)

```bash
git clone https://github.com/GlitchG/ga4-attribution-models.git
cd ga4-attribution-models
npm install

# Auth
gcloud auth application-default login

# Compile and run
dataform compile
dataform run --default-database=your-gcp-project-id
```

#### Option C: Private GA4 Export (Your Real Data)

Change these two lines in `workflow_settings.yaml`:
```yaml
vars:
  ga4_project: "your-ga4-project"
  ga4_dataset: "analytics_xxxxxx"  # your GA4 property ID
  start_date: "20240101"
  end_date: "20241231"
```

Re-run. The pipeline is now analysing your actual customers.

> **Cost warning:** Public dataset is free. Private GA4 exports incur BigQuery storage and query costs. The pipeline processes ~30 days of data per run. Set `start_date` and `end_date` to limit scope.

---

## Part 2: Understanding Your Output Tables

After the pipeline runs, these tables exist in your BigQuery project:

### Core Tables

| Table | Dataset | What It Contains | Who Cares |
|---|---|---|---|
| `attribution_mart` | `attribution_models` | Every touchpoint for every conversion, with credit from all 8 models | Analysts building custom reports |
| `cross_channel_comparison` | `attribution_models` | One row per channel × model × conversion event, pre-aggregated | Stakeholders who want summaries |
| `paths_dashboard` | `dashboard` | Top conversion paths, path lengths, channel sequences | UX and CRO teams |
| `funnel_dashboard` | `dashboard` | Purchase funnel stages, drop-off rates, cart abandonment | Ecommerce managers |

### Individual Model Tables

| Table | Model Philosophy | Best For |
|---|---|---|
| `attr_first_click` | First touch gets 100% credit | Brand awareness ROI |
| `attr_last_click` | Last touch gets 100% credit | Direct response campaigns |
| `attr_last_non_direct_click` | Last touch, ignoring Direct | Standard Google Analytics view |
| `attr_linear` | Equal credit to every touch | Long B2B sales cycles |
| `attr_time_decay` | More credit to recent touches | Promotional campaigns |
| `attr_position_based` | 40% first, 40% last, 20% middle | Balanced view |
| `attr_data_driven_bqml` | ML-learned credit allocation | When you have enough data (1,000+ conversions) |

---

## Part 3: Visualisation in Looker Studio

### 3.1 Connect Your Data

1. Go to [lookerstudio.google.com](https://lookerstudio.google.com)
2. **+ Create → Report**
3. Add a **BigQuery** data source
4. Choose **Custom Query** and paste:
   ```sql
   SELECT * FROM `your-project.attribution_models.cross_channel_comparison`
   ```
5. Click **Add**, then **Add to Report**

### 3.2 The Attribution Comparison Dashboard

This is your "CEO slide". It shows how channel importance shifts depending on which model you believe.

**Chart 1: Channel Credit by Model (Stacked Bar)**
- Dimension: `channel`
- Breakdown dimension: `model`
- Metric: `SUM(attributed_value_usd)`
- Why it matters: See how "Organic Search" looks tiny in Last Click but massive in First Click

**Chart 2: Model Selector Table**
- Dimension: `model`
- Metric: `SUM(attributed_value_usd)`
- Add a filter control on `model` so users can switch views

**Chart 3: Top Channels (Scorecard Grid)**
- One scorecard per channel
- Metric: `SUM(attributed_value_usd)`
- Filter each scorecard to a different `channel`
- Why: Instant "hero channels" for executive summaries

### 3.3 The Funnel Dashboard

**Chart 1: Funnel Steps (Bar Chart)**
- Dimension: `funnel_step`
- Metric: `user_count`
- Sort: `funnel_step_order` (create a calculated field: 1=session, 2=view_item, etc.)

**Chart 2: Drop-off Rate (Line Chart)**
- Dimension: `funnel_step`
- Metric: `drop_off_rate`
- Why it matters: Spot where users abandon. If 70% drop at "add_to_cart", your checkout flow is broken.

**Chart 3: Cart Abandonment Recovery (Scorecard)**
- Metric: `cart_abandonment_rate`
- Add a comparison to industry benchmark (~70%)

### 3.4 The Path Analysis Dashboard

**Chart 1: Top Conversion Paths (Table)**
- Dimension: `path` (string like "Paid Social → Organic Search → Direct")
- Metric: `conversion_count`
- Why it matters: See the actual journeys. If "Paid Social → Organic Search" is common, your social ads drive research behaviour.

**Chart 2: Path Length Distribution (Histogram)**
- Dimension: `path_length`
- Metric: `COUNT(conversion_id)`
- Why it matters: Short paths = impulse buyers. Long paths = considered purchases. Adjust ad frequency accordingly.

### 3.5 The Data-Driven Model Deep-Dive

For `attr_data_driven_bqml`, create a separate page:

**Chart 1: Feature Importance (Bar Chart)**
Run this query in BigQuery, save as table, connect:
```sql
SELECT
  * EXCEPT(model, processed_input, expected_value)
FROM
  ML.WEIGHTS(MODEL `your-project.attribution_models.attr_data_driven_model`)
ORDER BY ABS(weight) DESC
```

**Chart 2: Predicted vs Actual Conversion Rate (Scatter)**
```sql
SELECT
  predicted_converted_label,
  AVG(converted) AS actual_conversion_rate
FROM
  ML.EVALUATE(MODEL `your-project.attribution_models.attr_data_driven_model`)
GROUP BY predicted_converted_label
```

---

## Part 4: How to Present to Clients (or Recruiters)

### The 5-Minute Pitch Structure

**Slide 1: The Problem**
> "Most companies use Last Click attribution. This gives 100% credit to the final touchpoint and ignores everything that happened before. It systematically undervalues brand awareness and overvalues retargeting."

**Slide 2: The Solution**
> "This pipeline runs 8 attribution models in parallel, from simple rules to machine learning. We compare them to find the truth that matches your business context."

**Slide 3: The Insight (Pick One)**

*For a B2B SaaS client:*
> "First Click shows LinkedIn drives 35% of pipeline value. Last Click gives it 8%. Your LinkedIn budget is underfunded by 4×."

*For an ecommerce client:*
> "Time Decay reveals that email campaigns within 24 hours of purchase recover 12% of cart abandoners. That's £47K/month in recovered revenue."

*For a recruiter:*
> "I built a full attribution pipeline with 8 models, BigQuery ML, and automated Looker Studio dashboards. It processes real GA4 data and answers strategic questions like 'should we cut brand spend?' with evidence, not gut feel."

**Slide 4: The Dashboard**
Show the Looker Studio dashboard live. Click through models. Let them see the numbers shift.

**Slide 5: Next Steps**
> "This takes 30 minutes to deploy on your GA4 export. We can have your first insights this week."

### What Each Model Tells a Different Stakeholder

| Stakeholder | Show Them | Because |
|---|---|---|
| CFO / Finance | `attr_data_driven_bqml` + `cross_channel_comparison` | ML feels rigorous; side-by-side comparison shows you're not cherry-picking |
| Performance Marketer | `attr_last_click` + `attr_time_decay` | They optimise for immediate ROI; Time Decay rewards recent campaigns |
| Brand Manager | `attr_first_click` + `attr_linear` | Proves awareness investment works; Linear gives credit to mid-funnel |
| CRO / UX Lead | `paths_dashboard` + `funnel_dashboard` | Shows where users struggle, not just which channel won |
| CEO (5-minute version) | Scorecards from `cross_channel_comparison` | Big numbers, clear winners, no jargon |

---

## Part 5: Adapting for Real Client Data

### Changing the GA4 Source

Edit `workflow_settings.yaml`:
```yaml
vars:
  ga4_project: "client-ga4-project"
  ga4_dataset: "analytics_123456789"
  start_date: "20240101"
  end_date: "20241231"
```

### Customising Conversion Events

Edit `includes/conversion_config.js`:
```javascript
const conversionEvents = [
  { eventName: "purchase", mode: "revenue", lookbackDays: 30 },
  { eventName: "begin_checkout", mode: "count", lookbackDays: 14 },
  { eventName: "generate_lead", mode: "fixed", fixedValue: 50, lookbackDays: 60 },
];
```

| Mode | Use Case |
|---|---|
| `revenue` | Ecommerce purchases (uses `purchase_revenue`) |
| `count` | Any conversion where value = 1 (form fills, sign-ups) |
| `fixed` | Lead gen where every conversion is worth a set amount (e.g., £50 CPA) |

### Customising Channels

Edit `includes/channel_grouping.js`:
```javascript
function getChannel(source, medium, campaign) {
  if (medium === "cpc" && source === "google") return "Paid Search — Google";
  if (medium === "paid-social" && source === "meta") return "Paid Social — Meta";
  // ... your logic
  return "Other";
}
```

### Adding Cost Data (ROAS / CPA)

1. Enable the cost module: uncomment the files in `definitions/cost/`
2. Create `stg_google_ads_cost.sqlx` with your Google Ads cost data
3. Re-run. `attribution_with_roas` now includes:
   - `attributed_credit` (from attribution model)
   - `attributed_value_usd` (revenue)
   - `cost_usd` (ad spend)
   - `roas` = attributed_value / cost
   - `cpa` = cost / attributed_conversions

See `COST_MODULE_SETUP.md` for full schema and import patterns.

---

## Part 6: Common Real-World Issues & Fixes

| Symptom | Cause | Fix |
|---|---|---|
| "Input data doesn't contain any rows" (BQML) | All training samples have `converted = 1` | Union negative samples (`converted = 0`) from non-converting sessions. See `references/dataform-production-pitfalls.md` #29 |
| Staging tables empty | `type: "incremental"` on public dataset | Change to `type: "table"` for staging models |
| "Unrecognized name: session_id" | Column used in PARTITION BY but not SELECTed | Already fixed in v2.0.1 — pull latest `main` |
| "Column contains an aggregation function, which is not allowed in GROUP BY" | Aggregating a column that's also in GROUP BY | Remove `MAX()` wrapper — already fixed in v2.0.1 |
| Attribution models all zero | `int_attribution_journeys` filtered out all rows | Check `session_start IS NOT NULL` filter; verify GA4 export has sessions in lookback window |
| BQML model never trains | Not enough conversions (need 1,000+ with both 0 and 1 labels) | Increase date range or reduce `lookbackDays` |
| Looker Studio shows "No data" | Table is a view referencing wrong project | Check custom query has your actual GCP project ID |

---

## Part 7: Validation Checklist (Before Showing Anyone)

Run these queries in BigQuery console:

```sql
-- 1. Do we have conversions?
SELECT COUNT(*) FROM `your-project.attribution_models.attribution_mart`;
-- Expected: > 0

-- 2. Do all models have data?
SELECT model, COUNT(*) FROM `your-project.attribution_models.attribution_mart` GROUP BY model;
-- Expected: 8 rows, all with counts > 0

-- 3. Does cross-channel comparison sum to 100% per model?
SELECT model, SUM(attributed_credit) FROM `your-project.attribution_models.cross_channel_comparison` GROUP BY model;
-- Expected: each row = 1.0 (or very close)

-- 4. Are there sessionless conversions?
SELECT COUNT(*) FROM `your-project.intermediate.int_attribution_journeys` WHERE path_length = 0;
-- Expected: 0

-- 5. BQML model exists?
SELECT * FROM `your-project.attribution_models.__MODELS__` WHERE model_name = 'attr_data_driven_model';
-- Expected: 1 row
```

All pass? Your dashboard is client-ready.

---

## Quick Reference: Table → Visualisation Mapping

| BigQuery Table | Looker Studio Chart Type | Business Question |
|---|---|---|
| `cross_channel_comparison` | Stacked bar, scorecards | "Which channels drive value?" |
| `attribution_mart` | Pivot table, heatmap | "Which touchpoints deserve credit?" |
| `paths_dashboard` | Table, histogram | "What do user journeys look like?" |
| `funnel_dashboard` | Funnel bar chart, line chart | "Where do users drop off?" |
| `attr_data_driven_bqml` | Scatter plot, feature importance bar | "What does ML think matters?" |
| `ecommerce_funnel.purchase_funnel` | Bar chart, scorecard | "How healthy is my purchase flow?" |

---

*Last updated: 2026-05-06*  
*For bugs or questions: open an issue at github.com/GlitchG/ga4-attribution-models*
