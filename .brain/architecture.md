# Architecture — ga4-attribution-models

## Stack
BigQuery, SQL (Standard SQL dialect), dbt 1.8+, GitHub Actions CI

## Data Flow
```
GA4 raw events (BigQuery export)
    → setup_views.sql (flatten + sessionise)
        → attribution_models/*.sql (8 models, each reads the same views)
            → user_journey/path_analysis.sql (multi-touch path analysis)
                → ecommerce_funnel/*.sql (purchase funnel + cart abandonment)
```

Each SQL file is self-contained: it reads from the base views and outputs a standalone result table. No dependencies between models — run any model independently.

## File Map
- `attribution_models/` — 8 SQL files, one per attribution model: last_click, last_non_direct, first_click, linear, time_decay, position_based, data_driven (BQ ML), cross_channel_comparison
- `user_journey/` — path_analysis.sql for multi-touch journey mapping
- `ecommerce_funnel/` — purchase_funnel.sql, cart_abandonment.sql
- `utils/setup_views.sql` — flattens GA4 nested event_params into session-level views (prerequisite for all models)
- `dbt_project.yml` — dbt project configuration
- `.github/workflows/test-sql.yml` — CI: validates SQL syntax on every push

## Design Patterns
- **Self-contained SQL**: every model file can run independently — no chained dependencies
- **BigQuery-native**: no external libraries, pure Standard SQL with BQ ML for data-driven model
- **VIEW-first**: setup_views.sql creates reusable flattened views, all models read from views
- **No hardcoded dates**: all models use `CURRENT_DATE()` or parameters
