# Data Studio Dashboard Kit

> **Naming note (April 2026):** Google renamed Looker Studio back to Data Studio on 11 April 2026. Existing reports, data sources, and shared links transition automatically. URLs moved from `lookerstudio.google.com` to `datastudio.google.com`.

This folder holds **`dashboard-config.json`** — a structured specification for the four-page dashboard built on top of the Dataform output. Data Studio does not support native JSON import, so the spec is a reference, not an installer.

## How to use this folder

| You want to… | Open this |
|---|---|
| Build the dashboard manually | [`docs/DATA_STUDIO_GUIDE.md`](../docs/DATA_STUDIO_GUIDE.md) (step-by-step UI instructions) |
| See the exact field names, filters, and chart settings for every chart | `dashboard-config.json` |
| Understand the underlying tables | [`docs/USAGE_GUIDE.md`](../docs/USAGE_GUIDE.md) §6 |

## Why no automation script?

Google's Data Studio REST API is a restricted partner API and is not available to the general public. An earlier `create_dashboard.py` script would raise `RuntimeError` for >99% of users, so it was removed. If you do have partner API access and want a starting point, the `dashboard-config.json` schema (data sources, dimensions, metrics, filters) maps directly onto Google's documented API resources.
