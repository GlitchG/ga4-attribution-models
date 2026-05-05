# Cost Module Setup Guide — GA4 Attribution Models

> **Optional module.** The main attribution pipeline works without cost data. Enable this only when you have ad spend available in BigQuery.

---

## What This Module Gives You

| Metric | Formula | Use Case |
|---|---|---|
| **ROAS** | Revenue ÷ Cost | Which channel gives the best return per dollar spent? |
| **CPA** | Cost ÷ Conversions | How much do we pay per attributed conversion? |
| **RPC** | Revenue ÷ Conversions | Average order value per attributed conversion |
| **Marginal Revenue** | Data-driven − Last-click | Incremental revenue the ML model discovers beyond last-click |
| **Efficiency Score** | ROAS × Credit Ratio | Channels that get more attribution credit AND good ROAS rank higher |

---

## Prerequisites

1. **Ad spend data in BigQuery** from at least one platform:
   - Google Ads (via Data Transfer Service or API connector)
   - Meta Ads (via Supermetrics, Fivetran, manual CSV, or API)
   - TikTok, LinkedIn, programmatic, influencer — any platform

2. **Channel names must match** between cost tables and attribution output. The attribution pipeline produces channels like:
   - `Paid Search`
   - `Paid Social`
   - `Organic Search`
   - `Direct`
   - `Referral`
   - `Email`
   - `Display`

   Your cost data must use the **exact same names** for joins to work.

---

## Step 1 — Enable the Cost Sources You Have

Open each file in `definitions/cost/` and set `disabled: false` for the platforms you use.

### `stg_google_ads_cost.sqlx`

```yaml
config {
  disabled: false,  -- <-- change this
  ...
}
```

Replace the placeholder CTE with your actual Google Ads table:

```sql
WITH raw_google_ads AS (
  SELECT
    PARSE_DATE('%Y%m%d', _PARTITIONDATE) AS date,
    -- Map campaign types to attribution channels
    CASE
      WHEN campaign_advertising_channel_type = 'SEARCH' THEN 'Paid Search'
      WHEN campaign_advertising_channel_type = 'DISPLAY' THEN 'Display'
      WHEN campaign_advertising_channel_type = 'SHOPPING' THEN 'Paid Search'
      ELSE 'Paid Search'
    END AS channel,
    campaign_name AS campaign,
    cost_micros / 1e6 AS cost_usd,
    impressions,
    clicks
  FROM `your-project.your_transfer_dataset.campaign_basic_stats`
  WHERE _PARTITIONDATE BETWEEN '2024-01-01' AND '2024-12-31'
)
```

### `stg_meta_ads_cost.sqlx`

```yaml
config {
  disabled: false,
  ...
}
```

Replace the CTE with your Meta Ads data:

```sql
WITH raw_meta_ads AS (
  SELECT
    DATE(date_start) AS date,
    -- Map placement to channel
    CASE
      WHEN publisher_platform = 'facebook' THEN 'Paid Social'
      WHEN publisher_platform = 'instagram' THEN 'Paid Social'
      WHEN publisher_platform = 'messenger' THEN 'Paid Social'
      ELSE 'Paid Social'
    END AS channel,
    campaign_name AS campaign,
    spend AS cost_usd,
    impressions,
    clicks
  FROM `your-project.your_dataset.meta_ads_insights`
)
```

### `stg_other_cost.sqlx`

Add one CTE per additional platform and uncomment the `UNION ALL` blocks.

---

## Step 2 — Enable the Unified Cost Table

Open `definitions/cost/int_unified_cost.sqlx` and set:

```yaml
config {
  disabled: false,
  ...
}
```

This automatically aggregates all enabled cost sources to `date × channel × campaign` grain.

---

## Step 3 — Enable the ROAS Mart

Open `definitions/cost/attribution_with_roas.sqlx` and set:

```yaml
config {
  disabled: false,
  ...
}
```

This joins attribution results with cost data and computes ROAS, CPA, marginal revenue, and efficiency scores.

---

## Step 4 — Run the Pipeline

```bash
cd ga4-attribution-models
npx dataform run --default-database=YOUR_PROJECT --tags=cost
```

Or run everything including cost:

```bash
npx dataform run --default-database=YOUR_PROJECT
```

---

## What Happens If Cost Is Missing?

The `attribution_with_roas` table uses `LEFT JOIN` from attribution to cost. If a channel has attribution credit but no cost data for a given date:

- `cost_usd` → `NULL`
- `roas` → `NULL`
- `cpa` → `NULL`

This is intentional — it distinguishes "no spend" from "zero return". Organic channels (Organic Search, Direct, Referral) will naturally have `NULL` cost unless you model SEO/content costs separately.

---

## Common Pitfalls

| Problem | Cause | Fix |
|---|---|---|
| ROAS is NULL everywhere | Cost table is empty or channel names don't match | Check channel name mapping in cost CTEs |
| Organic channels missing from ROAS table | Expected — they have no ad spend | Optional: add estimated SEO/content costs to `stg_other_cost` |
| CPA is infinity | Zero conversions but positive cost | Filter with `WHERE attributed_conversions > 0` in your queries |
| Costs double-counted | Same platform in two CTEs | Ensure each cost source appears in only one `.sqlx` file |
| Marginal revenue is NULL | No data-driven model results | Make sure `attr_data_driven_bqml` ran successfully first |

---

## Next Steps

- **Upload manual CSV**: If you only have spreadsheets, create a native BigQuery table via the console (Create Table → Upload → CSV) and point the CTE to it.
- **Automate ingestion**: Set up Google Ads Data Transfer Service (free, daily auto-sync) or a connector like Supermetrics/Fivetran.
- **Add estimated costs**: For organic channels, add rough estimates (content spend, agency fees) to `stg_other_cost` for full-funnel ROAS.
