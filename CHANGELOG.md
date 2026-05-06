# Changelog — GA4 Attribution Models

All notable changes to this project are documented in this file.

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
