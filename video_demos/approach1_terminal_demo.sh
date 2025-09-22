#!/bin/bash

set -euo pipefail

# Approach 1: AI Architect (Generative + validation + optional forecast)
# Region normalized to us-central1

PROJECT_ID=${PROJECT_ID:-"bigquery-ai-hackathon-2025"}
LOCATION=${LOCATION:-"us-central1"}
DATASET_ID=${DATASET_ID:-"ai_architect_demo"}
CONNECTION_ID="$PROJECT_ID.$LOCATION.gemini_connection"
# Ensure envsubst can see these
export PROJECT_ID LOCATION DATASET_ID CONNECTION_ID

echo "\n=== Approach 1: AI Architect (us-central1) ==="
echo "Project:   $PROJECT_ID"
echo "Dataset:   $DATASET_ID"
echo "Location:  $LOCATION"
echo "Connection: $CONNECTION_ID"

read -p $'Press Enter to create dataset…'
bq mk --dataset --location=$LOCATION "$PROJECT_ID:$DATASET_ID" 2>/dev/null || true

echo "\n[1/4] Smoke tests for AI.GENERATE* functions"
read -p $'Press Enter to run summarization, bool, double, table…'

envsubst <<'SQL' | bq query --use_legacy_sql=false --format=prettyjson
-- Summarize
SELECT AI.GENERATE(
  'Summarize: Customer reports crashes when uploading >10MB',
  CONNECTION_ID => '$CONNECTION_ID'
).result AS summary;
SQL

envsubst <<'SQL' | bq query --use_legacy_sql=false --format=prettyjson
-- Urgency classification
SELECT AI.GENERATE_BOOL(
  'Is this urgent? CRITICAL: Production DB down for 30 minutes',
  CONNECTION_ID => '$CONNECTION_ID'
).result AS is_urgent;
SQL

envsubst <<'SQL' | bq query --use_legacy_sql=false --format=prettyjson
-- Sentiment score 1–10
SELECT AI.GENERATE_DOUBLE(
  'Rate sentiment 1 (neg) to 10 (pos): The update is fantastic!',
  CONNECTION_ID => '$CONNECTION_ID'
).result AS sentiment_score;
SQL

envsubst <<'SQL' | bq query --use_legacy_sql=false --format=prettyjson
-- Structured extraction
WITH raw(feedback) AS (
  SELECT 'Customer Jane Doe on Chrome since 2025-01-15, priority high. Email jane@example.com'
)
SELECT AI.GENERATE_TABLE(
  CONCAT('Extract name, browser, date, priority, email from: ', feedback),
  CONNECTION_ID => '$CONNECTION_ID',
  SCHEMA => ['customer_name STRING', 'browser STRING', 'date STRING', 'priority STRING', 'email STRING']
).result AS structured_data
FROM raw;
SQL

echo "\n[2/4] Small demo table + end-to-end enrichment"
read -p $'Press Enter to create table and enrich…'

envsubst <<'SQL' | bq query --use_legacy_sql=false
CREATE OR REPLACE TABLE `$PROJECT_ID.$DATASET_ID.issues` AS
SELECT 'Upload crash over 10MB' AS title, 'bug' AS label UNION ALL
SELECT 'Add dark mode' AS title, 'feature' AS label UNION ALL
SELECT 'Login timeout after 5 minutes' AS title, 'bug' AS label;
SQL

envsubst <<'SQL' | bq query --use_legacy_sql=false --format=prettyjson
SELECT
  title, label,
  AI.GENERATE(CONCAT('Summarize: ', title), CONNECTION_ID => '$CONNECTION_ID').result AS summary,
  AI.GENERATE_BOOL(CONCAT('Is this urgent: ', title), CONNECTION_ID => '$CONNECTION_ID').result AS is_urgent,
  AI.GENERATE_DOUBLE(CONCAT('Rate business impact 1-10: ', title), CONNECTION_ID => '$CONNECTION_ID').result AS impact
FROM `$PROJECT_ID.$DATASET_ID.issues`;
SQL

echo "\n[3/4] Optional: quick AI.FORECAST demo (synthetic series)"
echo "Creates a tiny time-series and runs ARIMA+ forecast; skip with Ctrl+C if not needed."
read -p $'Press Enter to run (optional)…'

envsubst <<'SQL' | bq query --use_legacy_sql=false
CREATE OR REPLACE TABLE `$PROJECT_ID.$DATASET_ID.sales_history` AS
SELECT DATE_SUB(CURRENT_DATE(), INTERVAL 29 - i DAY) AS date,
       'SKU001' AS sku,
       CAST(ROUND(50 + 10*SIN(i/3.0) + RAND()*5) AS INT64) AS quantity
FROM UNNEST(GENERATE_ARRAY(0,29)) AS i;
SQL

# Use classic ARIMA_PLUS + ML.FORECAST for reliability in terminal
envsubst <<'SQL' | bq query --use_legacy_sql=false --format=prettyjson
CREATE OR REPLACE MODEL `$PROJECT_ID.$DATASET_ID.demand_forecast_model`
OPTIONS(model_type='ARIMA_PLUS', time_series_timestamp_col='date', time_series_data_col='quantity', time_series_id_col='sku') AS
SELECT date, sku, quantity FROM `$PROJECT_ID.$DATASET_ID.sales_history`;
SQL

envsubst <<'SQL' | bq query --use_legacy_sql=false --format=prettyjson
SELECT * FROM ML.FORECAST(MODEL `$PROJECT_ID.$DATASET_ID.demand_forecast_model`, STRUCT(14 AS horizon));
SQL

echo "\n[4/4] Done ✅"
