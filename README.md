# GA4 Attribution Models (2026 Portfolio)

A collection of **8 SQL-based attribution models** for marketing analytics using Google Analytics 4 (GA4) data in BigQuery. This portfolio project is designed for **marketing analysts, data scientists, and hiring managers** to understand attribution modeling with **zero prerequisites** — just a free Google account.

---

## 🎯 **What is Attribution Modeling? (For Rookies)**

Imagine a customer journey:
1. **Day 1:** Customer sees your Facebook ad → clicks through
2. **Day 3:** Customer Googles your brand → finds organic result → clicks
3. **Day 5:** Customer receives your email → clicks
4. **Day 7:** Customer buys your product

**Question:** Which channel gets credit for the sale?
- **Facebook** (first touch)?
- **Google Organic** (middle touch)?
- **Email** (last touch)?
- **All of them**?

**Attribution modeling** answers this question. Different models give different answers, and smart marketers use **multiple models** to understand true channel value.

---

## 📊 **What's Included (8 Attribution Models)**

### Attribution Models (`/attribution_models`)

| Model | How It Works | When to Use | Why Choose It |
|-------|-------------|-------------|---------------|
| **Last Click** | 100% credit to FINAL touchpoint before conversion | Direct response campaigns, short sales cycles | Simple, matches what most platforms report by default |
| **Last Non-Direct** | 100% credit to last NON-DIRECT touchpoint (ignores direct/none traffic) | Filter out "direct" visits that likely came from other channels | Fixes Last Click's flaw of over-crediting "direct" traffic |
| **First Click** | 100% credit to FIRST touchpoint | Brand awareness measurement, new customer acquisition | Values channels that introduce customers to your brand |
| **Linear** | Equal credit across ALL touchpoints | Simple, unbiased view when you're unsure | Fair to all channels, but doesn't account for varying impact |
| **Time Decay** | Exponential decay: closer to conversion = more credit | Short sales cycles (1-7 days) | Rewards channels that close the deal |
| **Position-Based** | 40% first + 40% last + 20% middle | Balanced B2B (long cycles) or B2C | Values both introduction AND conversion |
| **Data-Driven (BQ ML)** | Machine Learning learns attribution weights from YOUR data | Advanced analysis when you have enough conversion data | Most accurate — tailored to your specific customer journey |
| **Cross-Channel Comparison** | Compare ALL models side-by-side | Find which channels are over/under-valued | Reveals how different models change the story |

### Ecommerce Analysis (`/ecommerce_funnel`)
- **Purchase Funnel** - View → Cart → Checkout → Purchase with drop-off rates (find WHERE you lose customers)
- **Cart Abandonment** - Identifies abandonment rate and recovery opportunities

### User Journey (`/user_journey`)
- **Path Analysis** - Most common conversion paths (see HOW customers actually convert)
- **Touchpoint Analysis** - Channel interaction patterns

---

## 🚀 **Quick Start (No GCP Keys Required!)**

The `bigquery-public-data.ga4_obfuscated_sample_ecommerce` dataset is **public** — anyone with a Google account can query it for free (Google gives you 10GB free tier monthly).

### **Option 1: BigQuery Console (Fastest — 2 minutes, zero setup)**

1. **Open BigQuery Console:** https://console.cloud.google.com/bigquery
   - Sign in with any Google account
   - Create a project if prompted (free, takes 10 seconds)
   
2. **Copy any SQL file** from this repo:
   - Go to: https://github.com/GlitchG/ga4-attribution-models
   - Click any `.sql` file (e.g., `attribution_models/last_click_attribution.sql`)
   - Click "Raw" button → Copy entire content
   
3. **Paste into BigQuery Query Editor** and click "Run"
   - Results appear in seconds
   - You'll see attribution by channel with conversion counts

4. **Understand your results:**
   - `source` = where traffic came from (google, facebook, etc.)
   - `medium` = type of traffic (organic, cpc, email, etc.)
   - `conversions` = how many purchases credited to that channel
   - `conversion_rate_pct` = that channel's share of total conversions

### **Option 2: Clone & Explore Locally**
```bash
git clone https://github.com/GlitchG/ga4-attribution-models.git
cd ga4-attribution-models
```
Open any `.sql` file in your favorite editor and paste into BigQuery Console.

---

## 📈 **Sample Data Explained (For Beginners)**

### What is `ga4_obfuscated_sample_ecommerce`?
- **Public dataset** provided by Google for learning
- Contains **fake ecommerce data** (no real customer PII)
- **Time period:** December 2020 - January 2021 (modify `DECLARE` statements to explore other dates)
- **Events tracked:** `page_view`, `view_item`, `add_to_cart`, `begin_checkout`, `purchase`
- **Why use it?** You don't need your own GA4 data to learn attribution!

### How to Change Date Range:
```sql
-- In any SQL file, modify these lines:
DECLARE start_date STRING DEFAULT '20210101';  -- Change to: '20201201' for December 2020
DECLARE end_date STRING DEFAULT '20210131';    -- Change to: '20201231' for December 2020
```
- Format: `YYYYMMDD` (Year-Month-Day, no spaces or dashes)
- The sample data has dates from 2020-12-01 to 2021-01-31

---

## 🎓 **Why Attribution Modeling Matters (Real-World Example)**

### Scenario: You're Spending $10,000/month on ads
- **Facebook Ads:** $5,000 → 100 conversions (Last Click report says)
- **Google Ads:** $3,000 → 60 conversions
- **Email Marketing:** $2,000 → 10 conversions

**Last Click says:** Kill Email, it's underperforming!

**But with Multi-Touch Attribution:**
- **Linear model reveals:** Email assists 40% of Facebook conversions
- **First Click shows:** Email introduces 30% of customers who later convert via Google
- **Truth:** Email is actually your #1 awareness channel!

**Without attribution modeling, you'd cut your most valuable channel.** This repository shows you how to avoid that mistake.

---

## 🛠️ **Technical Details (For Analysts)**

- **Dataset:** `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
- **Table Suffix:** Uses `_TABLE_SUFFIX` for date-partitioned tables (BigQuery best practice)
- **SQL Dialect:** Standard SQL (BigQuery)
- **No PII:** Uses obfuscated public sample data
- **Attribution Logic:** All models use `user_pseudo_id` to track user journeys across sessions

### How the SQL Works (Simplified):
1. **Identify conversions** (users who made a `purchase` event)
2. **Collect all touchpoints** (all events with source/medium/campaign)
3. **Apply attribution rule** (last click, first click, etc.)
4. **Aggregate by channel** and calculate percentages

---

## 📚 **Attribution Models Explained (Deep Dive)**

### Last Click Attribution
**How it works:** Finds the FINAL touchpoint before each conversion and gives it 100% credit.
**Why use it:** It's simple and matches what most ad platforms report by default.
**Limitation:** Ignores assisting channels (undervalues awareness campaigns).

### First Click Attribution
**How it works:** Finds the FIRST touchpoint and gives it 100% credit.
**Why use it:** Measures which channels introduce customers to your brand.
**Limitation:** Overvalues awareness channels, ignores closing channels.

### Linear Attribution
**How it works:** Gives equal credit (e.g., 25% each) to all touchpoints in the journey.
**Why use it:** Fair and unbiased — doesn't favor any stage of the funnel.
**Limitation:** Doesn't account for the fact that some touchpoints matter more than others.

### Time Decay Attribution
**How it works:** Uses exponential decay formula: `weight = 0.5^(days_before_conversion / half_life)`
- Touchpoints 1 day before conversion get ~50% weight
- Touchpoints 2 days before get ~25% weight
- etc.
**Why use it:** Rewards channels closer to the conversion (they "closed the deal").
**Limitation:** Not ideal for long B2B sales cycles (30+ days).

### Position-Based (U-Shaped)
**How it works:** 
- 40% credit to FIRST touchpoint (awareness)
- 40% credit to LAST touchpoint (conversion)
- 20% distributed across MIDDLE touchpoints
**Why use it:** Balances awareness and conversion — great for B2B or complex B2C.
**Limitation:** Arbitrary 40/40/20 split may not match your business reality.

### Data-Driven Attribution (BigQuery ML)
**How it works:** Uses machine learning (logistic regression) to learn which touchpoints actually predict conversions.
**Why use it:** Most accurate — tailored to YOUR specific customer journey and business.
**Limitation:** Requires BigQuery ML enabled + enough conversion data (usually 500+ conversions).

### Cross-Channel Comparison
**How it works:** Runs ALL attribution models side-by-side so you can compare.
**Why use it:** Reveals how different models tell different stories about channel value.
**Limitation:** More complex to interpret — requires analytical thinking.

---

## 🔗 **Related Projects**

- [Landing Page AB Testing](https://github.com/GlitchG/landing-page-ab-testing) - Statistical rigor in AB testing (hypothesis templates, guardrails, SRM detection)
- [Marketing Analytics Sample Reporting](https://github.com/GlitchG/marketing_analytics_sample_reporting) - dbt project for multi-channel ads

---

## ❓ **Troubleshooting (For Beginners)**

### "I get zero results!"
- **Cause:** Date range doesn't match sample data
- **Fix:** Ensure `start_date` and `end_date` are between `20201201` and `20210131`

### "Table not found" error
- **Cause:** Dataset name typo
- **Fix:** Ensure you're using: `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

### "Permission denied" error
- **Cause:** Not authenticated to BigQuery
- **Fix:** Sign in to Google Cloud Console with a Google account

### Results look weird (too few conversions)
- **Cause:** Sample data is small (only 2 months of obfuscated data)
- **Fix:** This is expected! Use your own GA4 data for real analysis.

---

## 📋 **Next Steps (For Portfolio Viewers)**

1. **Run Last Click model** → See default attribution
2. **Run Cross-Channel Comparison** → See how models differ
3. **Check out [AB Testing repo](https://github.com/GlitchG/landing-page-ab-testing)** → See statistical rigor in action
4. **Connect on LinkedIn:** [Gleb Baraniuk](https://linkedin.com/in/glitchg) for freelance marketing analytics work

---

**© 2026 Gleb Baraniuk | MIT License | Portfolio Project**
