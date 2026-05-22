# Changelog — GA4 Attribution Models

All notable changes to this project are documented in this file.

## [Unreleased]

### Changed
- **Data Studio rebrand (April 2026).** Google reverted the Looker Studio rebrand on 11 April 2026; the product is "Data Studio" again. Folder `looker-studio/` → `data-studio/`. URL `lookerstudio.google.com` → `datastudio.google.com`. All user-facing strings in `README.md`, `data-studio/**`, `docs/**`, `standalone-sql/**`, `definitions/**` (description fields) updated. Historical CHANGELOG mentions of the rebrand kept verbatim — the only forward-looking phrase that names both is "Data Studio (formerly Looker Studio)" on first mention per file. The `Looker` enterprise BI product is unrelated and unchanged.
- **`data-studio/README.md`** — added a naming-note paragraph at the top explaining the April 2026 reversion (existing reports transition automatically, URLs moved).

### Fixed
- **Standalone SQL date range** — every `DECLARE start_date / end_date` in `standalone-sql/{attribution_models,dashboard,ecommerce_funnel,user_journey,data-preparation}/*.sql` was hardcoded to `20210101`/`20210131`. The public sample window used in `includes/constants.js` is `20201101`/`20201220`, so out-of-the-box runs scanned partitions with no data and produced empty result sets. Realigned all standalone SQL to `20201101`/`20201220` (verified via `grep -rn "20210101\|20210131" standalone-sql/` → no matches).
- **`standalone-sql/dashboard/funnel_dashboard.sql` removed.** Its output schema (`step, users, pct_of_start`) was incompatible with the Dataform `dashboard.funnel_dashboard` view schema (`stage_num, stage, unique_users, unique_sessions, total_events, stage_revenue_usd, pct_of_top_users, pct_of_top_sessions, abandonment_rate_pct`), so the Data Studio chart recipes in the README couldn't possibly work against the standalone copy. The Dataform pipeline is now the only path for the funnel dashboard; `data-studio/README.md` documents the removal.
- **`cross_channel_comparison.sqlx`** — added `variance_from_last_click_usd` column computed server-side via window function (`SUM(CASE model='last_click' …) OVER (PARTITION BY conversion_event, channel)`). Data Studio calculated fields don't support window functions, so the "Variance from Last Click" chart in the dashboard guide previously had no working implementation. With the column materialised, the chart binds to it directly with zero calculated-field logic.
- **`data-studio/dashboard-config.json`** — every chart referenced columns that don't exist in the actual schema. Realigned to the real Dataform output:
  - `cross_channel_comparison` charts used `attributed_value_usd` / `attributed_credit` / `aov_usd` / `event_date`; correct columns are `total_value_usd` / `total_credit` / `avg_attributed_value_usd` (and there's no date column on this view).
  - Funnel charts used `funnel_step` / `user_count` / `drop_off_rate` / `cart_abandonment_rate` / `funnel_step_order`; correct columns are `stage` / `unique_users` / `pct_of_top_users` / `abandonment_rate_pct` / `stage_num`. Cart-abandonment chart now filters `stage_num = 99`; funnel charts filter `stage_num < 99`.
  - Path charts used `path` (the ARRAY column, which won't render) and a non-existent `conversion_count`; correct dimension is `path_string`, count via Record Count.
  - BQML weights chart bound to `processed_input` but the custom query stripped that column via `EXCEPT(model, processed_input, expected_value)`. Replaced with `SELECT processed_input, weight FROM ML.WEIGHTS(...)`.
  - Removed the "Model Precision" scorecard that averaged ML.WEIGHTS values — weights aren't precision. Added a note pointing to `ML.EVALUATE()` for real accuracy metrics.
  - Removed `roas` / `cpa` calculated fields that referenced a non-existent `cost_usd` column on `cross_channel_comparison`. ROAS lives in the optional cost module (`attribution_with_roas`); added a `calculated_fields_note` explaining the correct setup.
  - Added `daily_traffic_overview` and the new `attribution_dashboard` columns (`user_pseudo_id`, `conversion_date`) to the data-source list, plus a `variance_from_last_click` table chart binding to the new server-side column.
- **`data-studio/create_dashboard.py` deleted.** Google's Data Studio REST API is a restricted partner API, so the script raised `RuntimeError` for >99% of users by design. Keeping broken-for-most code implied an automated path that doesn't exist for the public. The `dashboard-config.json` spec stays — it's still useful as a structured reference for manual recreation and QA, and as a starting point for anyone who does have partner access.

### Cleanup
- **`data-studio/README.md`** — slimmed from 47 lines duplicating the dashboard guide down to a brief pointer (table of "you want to… open this"). Removed duplicate Quick Start and dashboard-page descriptions that are now canonically in `docs/DATA_STUDIO_GUIDE.md` and `docs/USAGE_GUIDE.md`.
- **`docs/DATA_STUDIO_GUIDE.md`** —
  - Title typo (`DATA Studio` → `Data Studio`).
  - "three-page" overview → "four-page" to match the actual page layout (Attribution / Funnel / Paths / Top-of-Funnel Traffic).
  - Appendix A: replaced stale `purchase_revenue` field references (renamed to `conversion_value_local` in v2.0) in both the attribution and paths data-source tables. Added `user_pseudo_id`, `conversion_date`, and `value_mode` to the attribution table. Added new sections for `daily_traffic_overview` and `cross_channel_comparison` (including the new `variance_from_last_click_usd` column).
  - Appendix B "Quick-Start Dashboard Template" rewritten to use the real column names (`total_value_usd` instead of `attributed_value_usd` for `cross_channel_comparison` charts, etc.), to bind to the right data source per page, and to include the new Page 4 (Top-of-Funnel Traffic).

## [2.0.4] — 2026-05-13

### Added
- **`dashboard.daily_traffic_overview`** — new pre-aggregated view (date × channel × source × medium) with `unique_users`, `total_sessions`, and `sessions_per_user`. Sourced from `stg_ga4_sessions`, so it captures every visitor — not just users who converted. Use this for top-of-funnel traffic charts in Data Studio (formerly Looker Studio) without having to wrestle with distinct counts at row level.
- **`dashboard.attribution_dashboard`** — added `user_pseudo_id` (so BI tools can `COUNT(DISTINCT)` converting users per channel/model) and `conversion_date` (a `DATE` column derived from `conversion_ts`, safer than relying on Data Studio to parse the timestamp).
- **`docs/DATA_STUDIO_GUIDE.md`** — new §9 "Users and Sessions" with five recipes for users/sessions/traffic-mix charts spanning both the converted-journey view and the top-of-funnel view. New §10 "Common Pitfalls" enumerates the 10 most common visualization mistakes this dataset triggers (model filter, currency mixing, count-mode NULLs, timestamp type, source vs channel granularity, NULL transaction_id, public-sample `Unknown`, BQML sparsity, funnel UNION quirk, path_length outliers) with the fix for each.

## [2.0.3] — 2026-05-13

### Fixed
- **`attr_data_driven_bqml.sqlx`** — `pred_all` CTE referenced dimension columns (`conversion_event`, `conversion_value_usd`, etc.) in its outer SELECT, but the inner `ML.PREDICT` subquery only listed the 19 channel flags. BigQuery `ML.PREDICT` only emits columns present in its input, so the query failed at compile time with `Unrecognized name: conversion_event`. Added the dimension columns to the inner SELECT so they pass through.

### Changed (breaking for BI users)
- **`dashboard.attribution_dashboard`** — removed `channel_total_value_usd`, `channel_total_conversions`, and `aov_usd` columns. These were pre-aggregated channel-level totals duplicated onto every row-level fact, which made Data Studio (formerly Looker Studio) charts produce nonsensical numbers (either repeated identical rows with no aggregation, or N× inflated values when SUMmed). For channel-level totals, point your BI tool at `attribution_models.cross_channel_comparison` (which is correctly pre-aggregated). For AOV, create a calculated field `SUM(attributed_value_usd) / SUM(attributed_credit)` filtered to a single model — see `docs/DATA_STUDIO_GUIDE.md`.
- **`docs/DATA_STUDIO_GUIDE.md`** — added an explicit "Granularity warning" callout before any chart instructions, replaced the `AVG(aov_usd)` scorecard recipe with a calculated-field recipe that produces correct numbers, and removed the `channel_total_*` / `aov_usd` entries from the field reference table.

## [2.0.2] — 2026-05-12

### Fixed (pipeline)
- **`purchase_funnel.sqlx`** — window functions can't wrap aggregates at the same query level in BigQuery; split the aggregation into a `stage_agg` CTE and apply `MAX(...) OVER ()` in the outer SELECT. Funnel previously crashed at runtime.
- **`stg_ga4_conversions.sqlx`** & **`int_attribution_journeys.sqlx`** — `rowConditions` now use `IS NULL OR <expr> >= 0` instead of bare `>= 0`. BigQuery evaluates `NULL >= 0` as `NULL` (not `TRUE`), so non-purchase rows with `NULL` revenue were firing the assertion on every run.
- **`stg_ga4_sessions.sqlx`** — single source of truth for the lookback window: the `event_timestamp` filter now uses `conversion_config.getMaxLookback()` (same as the `_TABLE_SUFFIX` filter) instead of the separate `constants.LOOKBACK_DAYS` knob that could silently drift.
- **`int_attribution_journeys.sqlx`** & **`int_attribution_path_rows.sqlx`** — added `session_id` to the path `STRUCT` and switched the `uniqueKey` to `(user_pseudo_id, conversion_id, session_id)`. Previously keyed on `session_start` (a timestamp), which could collide for high-traffic seconds.
- **`attr_data_driven_bqml.sqlx`** — three bugs:
  - `GROUP BY 1,2,3,4,5` included `conversion_value_usd` and `conversion_value_local`, so float-precision divergence between value-columns of the same conversion could produce duplicate `conversion_id` rows that inflated all downstream attribution. Now `GROUP BY 1,2,3` with `ANY_VALUE()` on value columns.
  - Fallback credit `ROUND(1.0 / 19, 4) = 0.0526` summed across 19 channels to 0.9994, losing 0.06% of attribution per zero-effect conversion. Now carries full precision through the `credited` CTE and rounds to 6 decimals only at output.
  - Removed the redundant `WHERE credit_share > 0` in the final SELECT (already enforced upstream).
- **`attr_data_driven_train.sqlx`** — added `ASSERT (SELECT COUNT(*) FROM training_table) > 0` before `CREATE OR REPLACE MODEL` so an empty date window can't silently train a degenerate model. Removed the now-redundant `DROP MODEL IF EXISTS`.
- **`cart_abandonment.sqlx`** — removed trailing comma after the last `config` property (parse hazard on some Dataform runtime versions).
- **`channel_grouping.js`** — the catch-all `ELSE` returned a free-form `CONCAT(source, ' / ', medium)` string that never matched any of the 19 entries in `getChannelList()`, so unclassified traffic was effectively absent from BQML feature engineering. Now returns `'Unknown'`.
- **`cross_channel_comparison.sqlx`** — `avg_order_value_{usd,local}` renamed to `avg_attributed_value_{usd,local}`. "Order value" was misleading for count-mode events that carry `NULL` attributed value.

### Added
- **`add_shipping_info` and `add_payment_info`** registered as count-mode conversion events in `conversion_config.js`. Without them, stages 3 and 4 of `purchase_funnel.sqlx` silently produced zero rows because the events were never extracted into `stg_ga4_conversions`.
- **`attr_u_shape.sqlx`** — description now documents the actual behaviour: 1-session = 100%, 2-session = normalised 50/50, 3+-session = 40/40/20.

### Fixed (CI / scripts)
- **`.github/workflows/test-sql.yml`** — SQLFluff now lints only `standalone-sql/` (plain SQL). Dataform `.sqlx` files contain JS template expressions (`${ref(...)}`, etc.) that aren't valid BigQuery SQL and produced false positives that were swallowed by `|| true`. Dry-run job now runs automatically when `GCP_SERVICE_ACCOUNT_KEY` is configured instead of being hardcoded `if: false`. Triggers extended to `.sqlx` files.
- **`data-studio/create_dashboard.py`** — removed hardcoded `/home/hermes/...` service-account path; credentials now via ADC only. Added `RuntimeError` with documentation that the Data Studio REST API is partner-only (`--force` escape hatch for users who have partner access).

### Changed (docs / public-sample readiness)
- **`workflow_settings.yaml`** — `defaultProject` is now the placeholder `your-gcp-project-id` (was a personal project name that would fail for everyone else). End date extended from `20201220` → `20210131` so all public-sample partitions are available. Inline comments explain every var.
- **`README.md`** — fixed misleading claim that `auto` source extraction was the default (it's `event_params`; `auto` doesn't work on the public sample). Fixed `||` (double-pipe) artifacts in the comparison table. Quick Start now uses `npm install -g @dataform/cli` and explicitly requires editing `defaultProject` before running.
- **`docs/USAGE_GUIDE.md`** — rewrote the `CONVERSION_EVENTS` example to use the real field names (`value_field`, `fixed_value_usd`, `lookback_days`). Updated BQML section to describe the actual 19-flag model (not the stale "17 channels + conversion_event"). Refreshed §10.1 with the current assertion definitions. Documented every public-sample quirk users will hit. Removed `||` formatting artifacts.
- **`docs/LOOKER_STUDIO_GUIDE.md`** — added a header note that all `marketingdataanalyst` strings in SQL snippets must be replaced with the reader's own project ID. Updated the example custom query to use the renamed `avg_attributed_value_usd` column.

## [2.0.1] — 2026-05-08

### Fixed
- **`attribution_with_roas.sqlx`** — added `cost_daily` CTE to pre-aggregate `int_unified_cost` to date × channel grain, preventing duplicate rows from campaign-level granularity.
- **`stg_ga4_conversions.sqlx`** — removed lookback window from conversion timestamp filter. Conversions are now strictly within `[start_date, end_date]`. Previously, conversions before `start_date` were included with incomplete journeys, inflating counts.
- **`int_attribution_journeys.sqlx`** — added `transaction_id` to uniqueKey assertion to prevent false failures on same-timestamp purchases. Added tiebreaker (`conversion_event, COALESCE(transaction_id, '')`) to `user_conversion_seq` ORDER BY for deterministic `conversion_id` across runs. Added `transaction_id` to GROUP BY to satisfy BigQuery window-function scoping.
- **`attr_data_driven_bqml.sqlx`** — filtered out zero-credit rows (channels not present in the journey path) from output. Added fallback: when `total_effect = 0`, distributes `1/19` credit equally. Reduces mart row count without affecting attribution totals.
- **`funnel_dashboard.sqlx`** — corrected description: BigQuery UNION ALL matches by position, not column name.
- **`cross_channel_comparison.sqlx`** — simplified `COUNT(DISTINCT CONCAT(...))` to `COUNT(DISTINCT conversion_id)` since conversion_id is already globally unique.

## [Unreleased] — v2.0.0

### Locked decisions (v2.0 architecture)
1. **Target export:** Public sample by default; auto-detection of source extraction mode for private client GA4 exports.
2. **Conversion scope:** Purchases, leads, signups, micro-conversions. Three value modes: `revenue`, `fixed`, `count`.
3. **BQML approach:** Single model with 19 channel flags only. `conversion_event` intentionally excluded as a feature to avoid signal mixing across funnel stages (e.g. purchase vs add_to_cart have very different channel effects). Per-conversion-event split deferred to v2.1 if needed.
4. **Schema stability:** Breaking renames locked now (`purchase_revenue_in_usd` → `conversion_value_usd`, etc.). No downstream consumers assumed.
5. **Markov model:** Out of scope for v2.0. Deferred to v2.1.
6. **Lookback truncation fix:** `_TABLE_SUFFIX` replaced with `event_timestamp`-based filtering for exact lookback windows.
7. **Branded paid search:** Regex on campaign name via `includes/constants.js` `BRAND_TERMS_REGEX`.
8. **Privacy / consent mode v2:** Pass-through of `privacy_info` fields + runtime `exclude_modeled_events` flag.

### Added
- **Multi-conversion support** — pipeline now tracks any conversion event type (purchase, begin_checkout, add_to_cart, generate_lead, etc.) via `includes/conversion_config.js`. Add events by editing one file — no SQL changes needed.
- **Three value modes** per conversion event:
  - `revenue` — uses ecommerce revenue (purchase_revenue_in_usd)
  - `fixed` — assigns a fixed monetary value (e.g. €50/lead)
  - `count` — credit shares of 1.0, no monetary value (attributed_value_usd is NULL)
- **Auto source extraction mode** — `stg_ga4_sessions.sqlx` automatically detects best available source/medium field:
  - Priority 1: `session_traffic_source_last_click` (post-2024-07 exports — fixes google/cpc bug)
  - Priority 2: `collected_traffic_source` (post-2023-06 exports — event-level raw values)
  - Priority 3: `event_params` first-non-auto-event rule (fallback for all exports incl. public sample)
- **Expanded 19-channel taxonomy** — replaces 8-channel grouping:
  - Cross-network, Paid Search Brand, Paid Search Non-Brand, Paid Shopping, Paid Social,
    Paid Video, Display, Organic Search, Organic Shopping, Organic Social, Organic Video,
    Email, SMS, Affiliate, Audio, Mobile Push, Referral, Direct, Unknown
- **Deep UTM + click ID passthrough** — all session fields now flow through to attribution models:
  - Click IDs: gclid, dclid, srsltid, msclkid, fbclid, ttclid, twclid, li_fat_id
  - Page context: page_location, page_referrer, hostname
  - Device: browser, browser_version
  - Privacy: analytics_storage, ads_storage, uses_transient_token
- **`exclude_modeled_events` var** — set to `"true"` to exclude consent-mode v2 modeled events from analysis.
- **`brand_terms_regex` var** — per-client override for Paid Search Brand vs Non-Brand split (no code edits needed).
- **`source_extraction_mode` var** — explicit modes: `auto`, `session_stslc`, `collected`, `event_params`.
- **`validation/validation-queries.sql`** — 10 validation checks for post-run verification.
- **`getChannelList()`** in `includes/channel_grouping.js` — single source of truth for BQML feature engineering.

### Changed (breaking)
- **Schema renames** across all attribution models and marts:
  - `purchase_revenue` → `conversion_value_local`
  - `purchase_revenue_in_usd` → `conversion_value_usd`
  - `attributed_revenue` → `attributed_value_usd`
  - `attributed_revenue_local` → `attributed_value_local`
- **`cross_channel_comparison.sqlx`** now groups by `model, conversion_event, channel` and includes `value_mode` column.
- **`attribution_mart.sqlx`** now includes `conversion_event` in every row.
- **`_TABLE_SUFFIX` filtering** in staging models now extends backward by `max(lookback_days)` to prevent lookback truncation.

### Fixed
- **`int_attribution_journeys.sqlx`** — removed hardcoded `WHERE conversion_event = 'purchase'` filter. All conversion events now produce independent journeys.
- **`stg_ga4_conversions.sqlx`** — uses dynamic `getEventList()` from `conversion_config.js` instead of hardcoded event names.
- **BQML training** — updated to 19-channel flags (conversion_event intentionally excluded per decision #3).
- **BQML predictions** — 19 ablation CTEs replacing 8 hardcoded channels.

## [1.5.0] — 2026-05-05

### Added
- **Optional cost module** (`definitions/cost/`) for ROAS, CPA, and marginal revenue analysis:
  - `stg_google_ads_cost.sqlx` — Google Ads cost template (disabled by default)
  - `stg_meta_ads_cost.sqlx` — Meta Ads cost template (disabled by default)
  - `stg_other_cost.sqlx` — Other platforms template (TikTok, LinkedIn, etc.)
  - `int_unified_cost.sqlx` — Aggregated daily cost by channel
  - `attribution_with_roas.sqlx` — Attribution results joined with cost (ROAS, CPA, efficiency)
  - `docs/COST_MODULE_SETUP.md` — Platform-specific setup guide

### Fixed
- **BQML training fix** — `attr_data_driven_train.sqlx` now includes negative samples (non-converted user-paths from `stg_ga4_sessions`) unioned with positive samples (converted paths from `int_attribution_path_rows`). Previously trained on label=1 only, causing degenerate input and "Input data doesn't contain any rows" error.
- **Added `dependencies: ["attr_data_driven_train"]`** to `attr_data_driven_bqml.sqlx` — operations don't produce a `ref()`-able output, so Dataform couldn't infer this dependency. Without it, predictions could run before training.
- **Removed broken assertion** `session_position_asc + session_position_desc - 1 = path_length` from `int_attribution_path_rows.sqlx` — fails on NULL-session edge cases (conversion with no sessions in lookback window).
- **Removed BigQuery `partitionBy`/`clusterBy`** from all table configs — hits a project-level issue where `CREATE TABLE AS` with `PARTITION BY` silently creates 0-row tables. Tables are now unpartitioned (functionality identical, no performance impact on the public-sample scale).

### Changed
- **Run instructions** updated in README with Dataform CLI credential setup (`--default-database` flag, `.df-credentials.json` format).
- **Removed inaccurate claims** about BigQuery partitioning & clustering and incremental tables from README and CHANGELOG.

## [Previous Unreleased]

### Added
- **Complete Dataform project structure** (`workflow_settings.yaml`, `definitions/`, `includes/`).
- **`dataformCoreVersion: 3.0.55`** — pins to Dataform Core 3.x.
- **`stg_ga4_conversions`** — staging table with FULL ecommerce payload: `purchase_revenue`, `purchase_revenue_in_usd`, `total_item_quantity`, `transaction_id`, `shipping_value`, `tax_value`, `refund_value`, `unique_items`, `coupon`, `items` array, `event_value`, `event_currency`, `event_quantity`, plus device and geo context (`device_category`, `device_os`, `country`, `region`, `city`).
- **`int_attribution_journeys`** — deduplicated journey table: one row per conversion with no duplicate sessions, no duplicate conversions, and an ordered `ARRAY<STRUCT>` path.
- **`int_attribution_path_rows`** — row-level unnested paths with `session_position_asc` and `session_position_desc` for model consumption.
- **All attribution models rewritten as `.sqlx`** with `${ref()}` dependencies.
- **Revenue attribution in every model** — each model now outputs `attributed_revenue` (USD) and `attributed_revenue_local` (local currency), not just credit share.
- **`attribution_mart.sqlx`** — unified mart unioning all 8 models with full ecommerce data.
- **`cross_channel_comparison.sqlx`** — channel-level aggregation with `total_revenue_usd`, `total_credit` (conversions), and `avg_order_value`.
- **`attr_position_weighted.sqlx`** — honest relabel of the previous `data_driven` heuristic (50% first, 30% last, 20% middle).
- **`attr_data_driven_bqml.sqlx`** — BQML logistic regression with feature-ablation removal effects. Requires `ml/attr_data_driven_train.sqlx`.
- **Position-weighted edge cases** — 2-session paths use 60/40 split (first/last) instead of the documented 50/30/20, since there is no "middle" session to allocate 20% to. Single-session paths receive 100%. Documented in SQLX description.
- **`includes/channel_grouping.js`** — DRY 8-channel CASE logic, single source of truth.
- **`includes/source_resolution.js`** — DRY GA4-UI-style source resolution logic.
- **`includes/constants.js`** — Safe defaults for all workflow vars. Eliminates compilation failures when vars are omitted.
- **Assertions** on `stg_ga4_sessions`, `stg_ga4_conversions`, `int_attribution_journeys`, and `int_attribution_path_rows`.
- **Incremental tables** on `stg_ga4_sessions` and `stg_ga4_conversions` with 3-day partition overwrite.
- **Vars-driven configuration** — `start_date`, `end_date`, `ga4_project`, `ga4_dataset`, `lookback_days` in `workflow_settings.yaml`.
- **Dashboard views** (`attribution_dashboard.sqlx`, `paths_dashboard.sqlx`, `funnel_dashboard.sqlx`) reference the Dataform pipeline.

### Changed
- **Renamed model files** from standalone `.sql` to Dataform `.sqlx` with consistent naming.
- **`attr_last_non_direct_click.sqlx`** — now falls back to Direct when the entire path is Direct, instead of silently dropping the conversion.
- **`cross_channel_comparison.sqlx`** — fixed conversion counting to use `COUNT(DISTINCT CONCAT(user_pseudo_id, '-', conversion_id))` instead of `COUNT(DISTINCT conversion_id)` which undercounted due to per-user `ROW_NUMBER()`.
- **Removed all `dependencies` arrays** from `.sqlx` files — `${ref()}` establishes dependencies automatically; explicit lists were redundant or potentially breaking.

### Fixed
- **Duplicate elimination at three layers:**
  1. Sessions: `ROW_NUMBER() OVER (PARTITION BY user_pseudo_id, session_id)` in `stg_ga4_sessions`
  2. Conversions: `ROW_NUMBER() OVER (PARTITION BY user_pseudo_id, event_timestamp, event_name, COALESCE(transaction_id, ...))` in `stg_ga4_conversions`
  3. Path rows: `ROW_NUMBER() OVER (PARTITION BY ... session_id)` in journey join, filtered before aggregation
- **`path_length`** in `int_attribution_journeys.sqlx` — simplified from `ARRAY_LENGTH(ARRAY_AGG(...))` to `COUNT(*)`.
- **`conversion_id`** — now globally unique via `CONCAT(user_pseudo_id, '-', user_conversion_seq)`.
- **Attribution base table gap** — the old `utils/setup_views.sql` was traffic-source-only and did not include conversions. The Dataform pipeline now explicitly builds `stg_ga4_conversions` and joins it in `int_attribution_journeys`.

### Deprecated
- Standalone `.sql` files in root folders (`attribution_models/*.sql`, `data-preparation/*.sql`, `ecommerce_funnel/*.sql`, `dashboard/*.sql`) are retained for reference but no longer the primary interface. Use the Dataform pipeline for production deployments.

---

## [1.0.0] — 2026-05-04

### Changed
- **Source/medium extraction now uses GA4-UI-style first-non-auto-event rule** across all 15 SQL files. Replaces the previous `session_start`-only approach. Logic: the first non-`session_start`/`first_visit` event with source/medium in `event_params` becomes the session's traffic source; falls back to `session_start` params if no primary exists. This aligns with how the GA4 UI attributes session source/medium and reduces drift vs. the UI from 5–15% on production data. Fixes #7.
- **Time-decay constant changed** from `0.1/hour` (≈7-hour half-life, degenerated to last-click in practice) to `0.00412/hour` (≈7-day half-life, matching GA4's default). Affects `time-decay-model-attribution.sql`, `cross-channel-comparison.sql`, `attribution-mart.sql`, `attribution_dashboard.sql`. Fixes #3.
- **BQML probability extraction fixed** in `data_driven_attribution.sql`: `predicted_converted_probs[OFFSET(0)].prob` may return P(not converted) because BQML array order is not guaranteed. Replaced 5 occurrences with `(SELECT prob FROM UNNEST(predicted_converted_probs) WHERE label = 1)`. Fixes #1.
- **Data-driven model extended to 8-channel taxonomy** (was 4 channels: organic, cpc, social, email). Now includes display, referral, affiliate, and direct, matching the rule-based models' channel grouping. Fixes #5.
- **Linear attribution semantics aligned** between `attribution-mart.sql` and `linear-model-attribution.sql`. The mart's m4 CTE previously used `SELECT DISTINCT` (per-distinct-channel credit), while the standalone model used per-session credit. The mart now uses per-session credit. Fixes #4.
- **Path analysis and paths dashboard** now use the same `sessions` CTE as the attribution models. Path lengths and channel sequences now reconcile across the dashboard. Fixes #6.

### Documentation
- **Relabeled "Shapley-style" to "feature-ablation attribution"** in README, code comments, and `data_driven_attribution.sql`. The existing implementation does single-pass feature ablation (remove one feature at a time), not true Shapley values (which require evaluating all 2^N subsets). Fixes #2.
- Added this CHANGELOG.md.
- Added note about 30-day lookback truncation by `_TABLE_SUFFIX` filter in `data-preparation/google-analytics-4-data-preparation.sql`. Fixes #8.
- Added 8-channel taxonomy documentation and extension guidance for custom channels in `data_driven_attribution.sql`. Fixes #5.
- Updated `utils/setup_views.sql` to document the first-non-auto-event rule as the canonical approach for public dataset users.

### Fixed
- `validation-queries.sql` now uses the canonical sessions CTE for all validation checks, ensuring consistency with the models.

### Notes
- Files intentionally NOT modified: `LICENSE`, `CONTRIBUTING.md`, `.gitignore`, `.github/workflows/test-sql.yml`, `dashboard/funnel_dashboard.sql`, `ecommerce_funnel/*.sql`, `dashboard/README.md`.
