#!/usr/bin/env python3
from google.cloud import bigquery
import os

os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = os.path.expanduser('~/.config/gcloud/application_default_credentials.json')

client = bigquery.Client(project='bigquery-ai-hackathon-2025')

print("Testing BigQuery Python client connection...")
print(f"Project: {client.project}")

datasets = list(client.list_datasets())
print(f"\nFound {len(datasets)} datasets:")
for dataset in datasets:
    print(f"  - {dataset.dataset_id}")

query = """
    SELECT
        current_timestamp() as test_time,
        'Python client connected successfully' as status
"""

print("\nRunning test query...")
query_job = client.query(query)
results = query_job.result()

for row in results:
    print(f"Time: {row.test_time}")
    print(f"Status: {row.status}")

print("\n✓ All BigQuery connection tests passed!")