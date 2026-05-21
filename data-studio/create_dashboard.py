#!/usr/bin/env python3
"""
Create Data Studio Dashboard for GA4 Attribution Models via API.

Prerequisites:
  pip install google-api-python-client google-auth-httplib2 google-auth-oauthlib
  gcloud auth application-default login

Usage:
  python create_dashboard.py --project YOUR_GCP_PROJECT --dataset-prefix attribution_models

IMPORTANT — Data Studio API availability:
  The Data Studio REST API ("datastudio" v1) is a restricted partner API and is
  NOT available to the general public. Calling build("datastudio", "v1", ...) will
  raise an HttpError 404 for most users.

  Alternatives:
    • Manual UI: open https://datastudio.google.com, connect to BigQuery, and
      create the report by hand. See docs/DATA_STUDIO_GUIDE.md for step-by-step
      instructions.
    • dscc-scripts: Google's community-supported framework for programmatic report
      creation — https://github.com/googledatastudio/tooling-samples

  If you have been granted Data Studio API partner access, remove the RuntimeError
  below and this script will work as-is.
"""

import argparse
import sys

import google.auth
from googleapiclient.discovery import build


SCOPES = ["https://www.googleapis.com/auth/datastudio"]


def get_credentials():
    """Return Application Default Credentials (gcloud auth application-default login)."""
    creds, _ = google.auth.default(scopes=SCOPES)
    return creds


def create_report(service, title: str):
    """Create an empty Data Studio report."""
    body = {"name": title}
    report = service.reports().create(body=body).execute()
    report_id = report["id"]
    print(f"Created report: {report_id}")
    return report_id


def add_bigquery_datasource(service, report_id: str, project: str, dataset: str, table: str, ds_name: str):
    """Add a BigQuery table-backed data source to the report."""
    body = {
        "type": "BIGQUERY",
        "name": ds_name,
        "bigQuery": {
            "projectId": project,
            "datasetId": dataset,
            "tableId": table,
        },
    }
    ds = service.reports().datasources().create(reportId=report_id, body=body).execute()
    ds_id = ds["id"]
    print(f"  Data source '{ds_name}' -> {ds_id}")
    return ds_id


def add_custom_query_datasource(service, report_id: str, project: str, query: str, ds_name: str):
    """Add a BigQuery custom-query data source."""
    body = {
        "type": "BIGQUERY",
        "name": ds_name,
        "bigQuery": {
            "projectId": project,
            "query": query,
        },
    }
    ds = service.reports().datasources().create(reportId=report_id, body=body).execute()
    ds_id = ds["id"]
    print(f"  Custom query DS '{ds_name}' -> {ds_id}")
    return ds_id


def add_table_chart(service, report_id: str, ds_id: str, title: str, dims: list, metrics: list, page_id: str):
    """Add a table chart to a page."""
    body = {
        "type": "TABLE",
        "title": title,
        "dataSourceId": ds_id,
        "dimensions": [{"name": d} for d in dims],
        "metrics": [{"name": m, "type": "SUM"} for m in metrics],
    }
    chart = service.reports().pages().charts().create(
        reportId=report_id, pageId=page_id, body=body
    ).execute()
    print(f"    Chart '{title}' -> {chart['id']}")
    return chart["id"]


def main():
    parser = argparse.ArgumentParser(description="Create Data Studio dashboard for GA4 Attribution Models")
    parser.add_argument("--project", required=True, help="Your GCP project ID")
    parser.add_argument("--dataset-prefix", default="attribution_models", help="BigQuery dataset name")
    parser.add_argument("--report-title", default="GA4 Attribution Models v2.0", help="Dashboard title")
    parser.add_argument(
        "--force",
        action="store_true",
        help="Skip the Data Studio API availability check (only use if you have partner API access)",
    )
    args = parser.parse_args()

    if not args.force:
        raise RuntimeError(
            "The Data Studio REST API is not publicly available.\n"
            "See the module docstring for alternatives, or re-run with --force if you have partner access."
        )

    creds = get_credentials()
    service = build("datastudio", "v1", credentials=creds, cache_discovery=False)

    print(f"Creating report: {args.report_title}")
    report_id = create_report(service, args.report_title)

    print("\nAdding data sources...")
    ds_cross = add_bigquery_datasource(
        service, report_id, args.project, args.dataset_prefix, "cross_channel_comparison", "Cross Channel"
    )
    ds_mart = add_bigquery_datasource(
        service, report_id, args.project, args.dataset_prefix, "attribution_mart", "Attribution Mart"
    )
    ds_paths = add_bigquery_datasource(
        service, report_id, args.project, "dashboard", "paths_dashboard", "Paths"
    )
    ds_funnel = add_bigquery_datasource(
        service, report_id, args.project, "dashboard", "funnel_dashboard", "Funnel"
    )
    ds_bqml = add_custom_query_datasource(
        service,
        report_id,
        args.project,
        f"SELECT * EXCEPT(model, processed_input, expected_value) FROM ML.WEIGHTS(MODEL `{args.project}.{args.dataset_prefix}.attr_data_driven_model`) ORDER BY ABS(weight) DESC",
        "BQML Weights",
    )

    print("\nAdding pages and charts...")
    # Page 1: Attribution Comparison
    page1 = service.reports().pages().create(reportId=report_id, body={"name": "Attribution"}).execute()
    print(f"  Page: Attribution -> {page1['id']}")
    add_table_chart(
        service, report_id, ds_cross, "Model Summary", ["model"], ["attributed_value_usd"], page1["id"]
    )

    # Page 2: Funnel
    page2 = service.reports().pages().create(reportId=report_id, body={"name": "Funnel"}).execute()
    print(f"  Page: Funnel -> {page2['id']}")
    add_table_chart(
        service, report_id, ds_funnel, "Funnel Steps", ["funnel_step"], ["user_count"], page2["id"]
    )

    # Page 3: Paths
    page3 = service.reports().pages().create(reportId=report_id, body={"name": "Paths"}).execute()
    print(f"  Page: Paths -> {page3['id']}")
    add_table_chart(
        service, report_id, ds_paths, "Top Paths", ["path"], ["conversion_count"], page3["id"]
    )

    # Page 4: BQML
    page4 = service.reports().pages().create(reportId=report_id, body={"name": "Data-Driven ML"}).execute()
    print(f"  Page: Data-Driven ML -> {page4['id']}")
    add_table_chart(
        service, report_id, ds_bqml, "Feature Weights", ["processed_input"], ["weight"], page4["id"]
    )

    print(f"\nDone. Open your dashboard:")
    print(f"  https://datastudio.google.com/reporting/{report_id}/page/1")
    print("\nNext steps:")
    print("  1. Open the report in Data Studio")
    print("  2. Resize and style charts (API does not support full styling)")
    print("  3. Add filter controls (model selector, date range)")
    print("  4. Set field types: event_date -> Date, revenue -> Currency")
    print(f"  5. Share with your client/recruiter")


if __name__ == "__main__":
    main()
