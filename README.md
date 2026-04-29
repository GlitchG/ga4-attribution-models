# GA4 Attribution Models

A collection of SQL queries for marketing attribution analysis using Google Analytics 4 (GA4) data in BigQuery. This portfolio project demonstrates different attribution models applied to the public `ga4_obfuscated_sample_ecommerce` dataset.

![GA4 BigQuery](https://i.postimg.cc/zX5DjtcJ/GA4-Big-Query.png)

---

## 📊 What's Included

This repository contains **5 attribution models** and **ecommerce funnel analyses** using the `bigquery-public-data.ga4_obfuscated_sample_ecommerce` dataset:

### Attribution Models (`/attribution_models`)
| Model | Description | Use Case |
|-------|-------------|----------|
| **Last Click** | 100% credit to final touchpoint before conversion | Direct response campaigns |
| **First Click** | 100% credit to first touchpoint | Brand awareness measurement |
| **Linear** | Equal credit across all touchpoints | Simple, unbiased view |
| **Time Decay** | Exponential decay weighting (closer = more credit) | Short sales cycles |
| **Position-Based** | 40% first + 40% last + 20% middle | Balanced B2B/B2C approach |

### Ecommerce Analysis (`/ecommerce_funnel`)
- **Purchase Funnel** - View → Cart → Checkout → Purchase with drop-off rates
- **Cart Abandonment** - Identifies abandonment rate and recovery opportunities

### User Journey (`/user_journey`)
- **Path Analysis** - Most common conversion paths visualization
- **Touchpoint Analysis** - Channel interaction patterns

---

## 🚀 Quick Start

### 1. Prerequisites
- Google Cloud account with BigQuery enabled
- Access to `bigquery-public-data.ga4_obfuscated_sample_ecommerce` (public dataset)

### 2. Usage

1. **Clone this repo:**
   ```bash
   git clone https://github.com/GlitchG/ga4-attribution-models.git
   ```

2. **Open any SQL file** in BigQuery Console

3. **Update date range** (if needed):
   ```sql
   DECLARE start_date STRING DEFAULT '20210101';
   DECLARE end_date STRING DEFAULT '20210131';
   ```

4. **Run the query** - results show attribution by channel

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
- [BigQuery GA4 Queries](https://github.com/aliasoblomov/Bigquery-GA4-Queries) - Comprehensive GA4 query collection

---

## 👤 Author

**Gleb Baraniuk**  
Marketing Analytics Consultant  
📍 Calheta, Madeira, Portugal  
🔗 [GitHub](https://github.com/GlitchG) | [LLM Wiki](https://github.com/GlitchG/llm_wiki)

---

## 📄 License

MIT License - feel free to use and adapt for your own projects!

---

## ⭐ If you find this useful, give it a star!
