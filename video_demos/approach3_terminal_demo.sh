#!/bin/bash

set -euo pipefail

# Approach 3: Multimodal Pioneer (Object Tables + ObjectRef)
# Region normalized to us-central1

PROJECT_ID=${PROJECT_ID:-"bigquery-ai-hackathon-2025"}
LOCATION=${LOCATION:-"us-central1"}
DATASET_ID=${DATASET_ID:-"multimodal_demo"}
CONNECTION_ID="$PROJECT_ID.$LOCATION.gemini_connection"
DEMO_BUCKET=${DEMO_BUCKET:-""}  # e.g., gs://your-bucket
# Ensure envsubst can see these
export PROJECT_ID LOCATION DATASET_ID CONNECTION_ID DEMO_BUCKET

echo "\n=== Approach 3: Multimodal Pioneer (us-central1) ==="
echo "Project:    $PROJECT_ID"
echo "Dataset:    $DATASET_ID"
echo "Location:   $LOCATION"
echo "Connection: $CONNECTION_ID"

if [ -z "$DEMO_BUCKET" ]; then
  echo "\nSet DEMO_BUCKET to your GCS bucket path (e.g., gs://my-bucket)."
  echo "It should contain sample images in product_images/ and PDFs in docs/."
  exit 1
fi

read -p $'Press Enter to create dataset…'
bq mk --dataset --location=$LOCATION "$PROJECT_ID:$DATASET_ID" 2>/dev/null || true

echo "\n[1/3] Create external Object Table over bucket"
read -p $'Press Enter to create object table…'

envsubst <<'SQL' | bq query --use_legacy_sql=false
CREATE OR REPLACE EXTERNAL TABLE `$PROJECT_ID.$DATASET_ID.multimodal_assets`
OPTIONS (object_metadata = 'SIMPLE',
         uris = ['$DEMO_BUCKET/product_images/*', '$DEMO_BUCKET/docs/*']);
SQL

echo "\n[2/3] Analyze mixed content using ObjectRef + AI.GENERATE (10 row sample)"
read -p $'Press Enter to run analysis…'

envsubst <<'SQL' | bq query --use_legacy_sql=false --format=prettyjson
SELECT
  uri, content_type, size_bytes,
  CASE
    WHEN content_type = 'application/pdf' THEN
      AI.GENERATE(ObjectRef(uri),
                  'Extract and summarize key points from this PDF',
                  CONNECTION_ID => '$CONNECTION_ID').result
    WHEN content_type LIKE 'image/%' THEN
      AI.GENERATE(ObjectRef(uri),
                  'Describe the image and note any potential issues',
                  CONNECTION_ID => '$CONNECTION_ID').result
    ELSE 'Unsupported file type'
  END AS analysis,
  AI.GENERATE(CONCAT('Based on this ', content_type, ' file, recommend an action'),
              CONNECTION_ID => '$CONNECTION_ID').result AS recommended_action
FROM `$PROJECT_ID.$DATASET_ID.multimodal_assets`
LIMIT 10;
SQL

echo "\n[3/3] Optional: create an embeddings model for image/text pairs"
read -p $'Press Enter to create embedding model (optional)…'

envsubst <<'SQL' | bq query --use_legacy_sql=false
CREATE OR REPLACE MODEL `$PROJECT_ID.$DATASET_ID.gemini_embedding_model`
REMOTE WITH CONNECTION `$CONNECTION_ID`
OPTIONS(endpoint = 'text-embedding-004');
SQL

echo "\nDone ✅"
