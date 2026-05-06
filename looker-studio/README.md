# Looker Studio Dashboard Kit for GA4 Attribution Models

Looker Studio does **not** support native JSON import/export for full dashboards. This directory provides three workarounds:

---

## Option 1: dashboard-config.json (Reference / Manual Build)

A machine-readable specification of the complete dashboard. Use it as:

- **A checklist** while manually recreating charts in the Looker Studio UI
- **A handoff document** for a VA or junior analyst to build the dashboard
- **QA reference** to verify an existing dashboard has all required charts

### Structure
- `data_sources` — 5 BigQuery connections with field type overrides
- `pages` — 4 tabs (Attribution, Funnel, Paths, Data-Driven ML)
- `charts` — per-page chart definitions with exact dimensions, metrics, filters, and positions
- `interactions` — filter control bindings
- `calculated_fields` — ROAS and CPA formulas

Replace `${YOUR_PROJECT_ID}` with your actual GCP project ID before using.

---

## Option 2: create_dashboard.py (Programmatic)

A Python script using the Looker Studio REST API to create the report shell, data sources, and chart placeholders automatically.

### Prerequisites
```bash
pip install google-api-python-client google-auth-httplib2 google-auth-oauthlib
gcloud auth application-default login
```

### Run
```bash
python create_dashboard.py \
  --project marketingdataanalyst \
  --dataset-prefix attribution_models \
  --report-title "GA4 Attribution Models v2.0"
```

### What it creates
- 1 report with 4 pages
- 5 BigQuery data sources (cross_channel, mart, paths, funnel, BQML weights)
- Table-chart placeholders on each page

### What you still do manually in the UI
- Resize and position charts (API doesn't support precise layout)
- Switch chart types (stacked bar, scorecard grid, line chart, etc.)
- Apply styling (colours, fonts, legends)
- Add filter controls (dropdowns, date ranges)
- Set field types (Date, Currency, Text)

### API Limitations
The Looker Studio API is **read-heavy**. Full chart configuration (dimensions, metrics, styles) is supported but complex. This script creates the scaffold; expect 10–15 minutes of manual polish afterward.

---

## Option 3: Manual Step-by-Step (Fastest for One-Off)

If you only need this dashboard once, skip both files above and follow the **LOOKER_STUDIO_GUIDE.md** in `docs/`. It has copy-paste SQL and exact click-through instructions.

---

## File Mapping

| File | Purpose |
|---|---|
| `dashboard-config.json` | Machine-readable spec for reference or automation input |
| `create_dashboard.py` | Python script to create dashboard via API |
| `README.md` | This file — explains all three options |

---

## FAQ

**Q: Can I just import the JSON into Looker Studio?**
A: No. Looker Studio has no native import format. Use the JSON as a build reference or run the Python script.

**Q: Can you host a public template I can copy?**
A: Not without sharing a live Google account. The Python script is the closest automation.

**Q: Will the API script create styled charts?**
A: No. It creates placeholders. You style them in the UI. Google has not exposed full styling via API.

---

*Last updated: 2026-05-06*
