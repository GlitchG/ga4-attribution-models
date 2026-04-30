# Architecture Decisions — ga4-attribution-models

> Every decision with rationale and trade-offs.

## Decision Log

| Date | Decision | Rationale | Trade-offs |
|------|----------|-----------|------------|
| 2026-04 | BigQuery-only (no Python) | Portfolio target is SQL-literate analysts. Pure SQL is more accessible and runs directly in BigQuery console. | Less flexibility for complex statistical models. Data-driven model limited to BQ ML's capabilities. |
| 2026-04 | One SQL file per model | Each model is independently runnable and reviewable. Hiring managers can read one file and understand the logic. | Some SQL duplication across models (sessionisation, touchpoint extraction). Mitigated by shared setup_views.sql. |
| 2026-04 | VIEW-based architecture | setup_views.sql creates reusable views. Models query views, not raw tables. Clean separation of data prep and model logic. | Views add a layer of indirection. If GA4 schema changes, views need updating. |
| 2026-04 | dbt project structure | Professional standard for analytics engineering. `dbt_project.yml` signals production-ready thinking to recruiters. | Not actually needed for running SQL directly. Adds a file that could be confusing if not using dbt CLI. |
| 2026-04 | CI/CD via GitHub Actions | Every push validates SQL syntax. Catches errors before they reach a hiring manager's review. | Minimal — just syntax; no functional tests without live BigQuery connection. |
| 2026-04-30 | .brain/ folder added | Per @samflipppy's pattern on Karpathy gist: AI agents that work on this repo read .brain/index.md first. No context back-and-forth. | Extra files in repo root. Worth it for faster agent onboarding. |
