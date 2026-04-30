# GA4 Attribution Models

A collection of SQL queries for marketing attribution analysis using Google Analytics 4 (GA4) data in BigQuery. This portfolio project demonstrates different attribution models applied to the public `ga4_obfuscated_sample_ecommerce` dataset.


---

## 📊 What's Included

This repository contains **5 attribution models** and **ecommerce funnel analyses** using the `bigquery-public-data.ga4_obfuscated_sample_ecommerce` dataset:

### Attribution Models (`/attribution_models`)
| Model | Description | Use Case |
|-------|-------------|----------|
| **Last Click** | 100% credit to final touchpoint before conversion | Direct response campaigns |
| **Last Non-Direct** | 100% credit to last NON-DIRECT touchpoint (ignores direct/none) | Filter out direct traffic |
| **First Click** | 100% credit to first touchpoint | Brand awareness measurement |
| **Linear** | Equal credit across all touchpoints | Simple, unbiased view |
| **Time Decay** | Exponential decay weighting (closer = more credit) | Short sales cycles |
| **Position-Based** | 40% first + 40% last + 20% middle | Balanced B2B/B2C approach |
| **Data-Driven (BQ ML)** | ML model learns attribution weights from data | Advanced, data-backed decisions |
| **Cross-Channel Comparison** | Compare all models side-by-side | Find over/under-valued channels |

### Ecommerce Analysis (`/ecommerce_funnel`)
- **Purchase Funnel** - View → Cart → Checkout → Purchase with drop-off rates
- **Cart Abandonment** - Identifies abandonment rate and recovery opportunities

### User Journey (`/user_journey`)
- **Path Analysis** - Most common conversion paths visualization
- **Touchpoint Analysis** - Channel interaction patterns

---

## 🚀 Quick Start (No GCP Keys Required!)

The `bigquery-public-data.ga4_obfuscated_sample_ecommerce` dataset is **public** — anyone with a Google account can query it for free (10GB free tier).

### Option 1: BigQuery Console (Fastest - 2 minutes)
1. **Open BigQuery Console:** https://console.cloud.google.com/bigquery
2. **Copy any SQL file** from this repo (e.g., `attribution_models/last_click_attribution.sql`)
3. **Paste into Query Editor** and click "Run"
4. **View results** — attribution by channel with conversion counts

### Option 2: Clone & Explore Locally
```bash
git clone https://github.com/GlitchG/ga4-attribution-models.git
cd ga4-attribution-models
```

Open any `.sql` file in your favorite editor and run in BigQuery Console.

### Sample Data Info
- **Dataset:** `bigquery-public-data.ga4_obfuscated_sample_ecommerce`
- **Date Range:** December 2020 - January 2021 (modify `DECLARE` statements to explore)
- **Events:** `purchase`, `page_view`, `begin_checkout`, etc.
- **No setup required** — just run queries!

### Try These Queries First:
1. `attribution_models/last_click_attribution.sql` — Classic attribution model
2. `ecommerce_funnel/purchase_funnel.sql` — See conversion drop-offs
3. `attribution_models/cross_channel_comparison.sql` — Compare all models

---

## 📈 Example: Last Click Attribution

```sql
-- Results show which channels get credit for conversions
+---------+---------+-----------+-------------+-------------------+
| source  | medium  | campaign  | conversions | attribution_pct   |
+---------+---------+-----------+-------------+-------------------+
| google  | organic | (null)    | 1234        | 45.2%             |
| facebook| cpc     | summer23  | 567         | 20.8%             |
| (direct)| (none)  | (null)    | 432         | 15.8%             |
+---------+---------+-----------+-------------+-------------------+
```

---

## 🎯 Why Attribution Modeling Matters

Attribution modeling helps marketers:
- **Understand true channel value** beyond last-click reporting
- **Optimize budget allocation** across touchpoints
- **Identify assisting channels** that support conversions
- **Measure full customer journey** from awareness to purchase

---

## 🛠️ Technical Details

- **Dataset:** `bigquery-public-data.ga4_obfuscated_sample_ecommerce`
- **Time Period:** January 2021 (modify in DECLARE statements)
- **Event Scope:** Uses `events_*` tables with table suffix filtering
- **No PII:** Uses obfuscated public sample data

---

## 📚 Attribution Models Explained

### Last Click Attribution
Traditional model that gives all credit to the final touchpoint. Simple but often undervalues awareness and consideration channels.

### First Click Attribution
Values the channel that introduced the customer. Best for measuring brand awareness campaigns.

### Linear Attribution
Distributes credit equally. Fair but doesn't account for varying impact at different journey stages.

### Time Decay Attribution
Exponential decay formula: `weight = 0.5^(days_before_conversion)`. Rewards touchpoints closer to conversion.

### Position-Based (U-Shaped)
- 40% to first touch (awareness)
- 40% to last touch (conversion)
- 20% distributed across middle touches

---

## 🔗 Related Projects

- [Marketing Analytics Sample Reporting](https://github.com/GlitchG/marketing_analytics_sample_reporting) - dbt project for multi-channel ads
