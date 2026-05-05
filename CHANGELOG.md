# Changelog — GA4 Attribution Models

All notable changes to this project are documented in this file.

## [Unreleased] — 2026-05-05

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
- **`dataformCoreVersion: 3.0.20`** — pins to Dataform Core 3.x.
- **`stg_ga4_conversions`** — staging table with FULL ecommerce payload: `purchase_revenue`, `purchase_revenue_in_usd`, `total_item_quantity`, `transaction_id`, `shipping_value`, `tax_value`, `refund_value`, `unique_items`, `coupon`, `items` array, `event_value`, `event_currency`, `event_quantity`, plus device and geo context (`device_category`, `device_os`, `country`, `region`, `city`).
- **`int_attribution_journeys`** — deduplicated journey table: one row per conversion with no duplicate sessions, no duplicate conversions, and an ordered `ARRAY<STRUCT>` path.
- **`int_attribution_path_rows`** — row-level unnested paths with `session_position_asc` and `session_position_desc` for model consumption.
- **All attribution models rewritten as `.sqlx`** with `${ref()}` dependencies.
- **Revenue attribution in every model** — each model now outputs `attributed_revenue` (USD) and `attributed_revenue_local` (local currency), not just credit share.
- **`attribution_mart.sqlx`** — unified mart unioning all 8 models with full ecommerce data.
- **`cross_channel_comparison.sqlx`** — channel-level aggregation with `total_revenue_usd`, `total_credit` (conversions), and `avg_order_value`.
- **`attr_position_weighted.sqlx`** — honest relabel of the previous `data_driven` heuristic (50% first, 30% last, 20% middle).
- **`attr_data_driven_bqml.sqlx`** — BQML logistic regression with feature-ablation removal effects. Requires `ml/attr_data_driven_train.sqlx`.
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
