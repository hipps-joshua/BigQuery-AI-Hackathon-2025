#!/bin/bash

set -euo pipefail

# Approach 2: Semantic Detective (Embeddings + VECTOR_SEARCH)
# Region normalized to us-central1

PROJECT_ID=${PROJECT_ID:-"bigquery-ai-hackathon-2025"}
LOCATION=${LOCATION:-"us-central1"}
DATASET_ID=${DATASET_ID:-"semantic_demo"}
CONNECTION_ID="$PROJECT_ID.$LOCATION.gemini_connection"
# Ensure envsubst can see these
export PROJECT_ID LOCATION DATASET_ID CONNECTION_ID

echo "\n=== Approach 2: Semantic Detective (us-central1) ==="
echo "Project:   $PROJECT_ID"
echo "Dataset:   $DATASET_ID"
echo "Location:  $LOCATION"
echo "Connection: $CONNECTION_ID"

read -p $'Press Enter to create dataset…'
bq mk --dataset --location=$LOCATION "$PROJECT_ID:$DATASET_ID" 2>/dev/null || true

echo "\n[1/5] Create embedding model (REMOTE)"
read -p $'Press Enter to create remote embedding model…'

envsubst <<'SQL' | bq query --use_legacy_sql=false
CREATE OR REPLACE MODEL `$PROJECT_ID.$DATASET_ID.gemini_embedding_model`
REMOTE WITH CONNECTION `$CONNECTION_ID`
OPTIONS(endpoint = 'text-embedding-004');
SQL

echo "\n[2/5] Create small content table"
envsubst <<'SQL' | bq query --use_legacy_sql=false
CREATE OR REPLACE TABLE `$PROJECT_ID.$DATASET_ID.content` AS
SELECT 'Database connection timeout errors in production' AS content, 'github' AS source UNION ALL
SELECT 'How to fix connection pool exhaustion?' AS content, 'stackoverflow' AS source UNION ALL
SELECT 'Customer complaint: app is very slow to load' AS content, 'support' AS source UNION ALL
SELECT 'Performance degradation after recent update' AS content, 'github' AS source UNION ALL
SELECT 'Best practices for database connection pooling' AS content, 'documentation' AS source;
SQL

echo "\n[3/5] Generate embeddings"
read -p $'Press Enter to generate embeddings…'

envsubst <<'SQL' | bq query --use_legacy_sql=false
CREATE OR REPLACE TABLE `$PROJECT_ID.$DATASET_ID.content_with_embeddings` AS
SELECT content, source,
  ML.GENERATE_EMBEDDING(MODEL `$PROJECT_ID.$DATASET_ID.gemini_embedding_model`, content) AS embedding
FROM `$PROJECT_ID.$DATASET_ID.content`;
SQL

echo "\n[4/5] Create vector index (optional for performance)"
envsubst <<'SQL' | bq query --use_legacy_sql=false
CREATE OR REPLACE VECTOR INDEX `$PROJECT_ID.$DATASET_ID.content_index`
ON `$PROJECT_ID.$DATASET_ID.content_with_embeddings`(embedding)
OPTIONS(index_type = 'IVF', distance_type = 'COSINE');
SQL

echo "\n[5/5] Run semantic search with a query phrase"
QUERY_PHRASE=${QUERY_PHRASE:-"database performance problems"}
echo "Search phrase: $QUERY_PHRASE"

envsubst <<'SQL' | bq query --use_legacy_sql=false --format=prettyjson
WITH search_query AS (
  SELECT ML.GENERATE_EMBEDDING(
    MODEL `$PROJECT_ID.$DATASET_ID.gemini_embedding_model`,
    '$QUERY_PHRASE'
  ) AS query_embedding
)
SELECT base.content, base.source, vs.distance, 1 - vs.distance AS similarity
FROM VECTOR_SEARCH(
  TABLE `$PROJECT_ID.$DATASET_ID.content_with_embeddings`,
  'embedding',
  (SELECT query_embedding FROM search_query),
  top_k => 5
) AS vs
JOIN `$PROJECT_ID.$DATASET_ID.content_with_embeddings` AS base
ON vs.row_id = base.row_id
ORDER BY vs.distance ASC;
SQL

echo "\nDone ✅"
