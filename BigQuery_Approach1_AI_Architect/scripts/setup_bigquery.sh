#!/bin/bash

# BigQuery Setup Script for CatalogAI
# This script sets up the necessary BigQuery resources for the E-commerce Intelligence Platform

echo "🚀 Setting up BigQuery for CatalogAI..."

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo "❌ gcloud CLI is not installed. Please install it first:"
    echo "   https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
    echo "🔐 Please authenticate with Google Cloud:"
    gcloud auth login
fi

# Get or set project ID
if [ -z "$PROJECT_ID" ]; then
    echo "📋 Enter your Google Cloud Project ID:"
    read PROJECT_ID
fi

# Set the project
gcloud config set project $PROJECT_ID

# Create dataset
DATASET_ID="ecommerce_demo"
LOCATION="us-central1"

echo "📊 Creating BigQuery dataset..."
bq mk --dataset --location=$LOCATION --description="E-commerce Intelligence Platform Demo Dataset" $PROJECT_ID:$DATASET_ID || echo "Dataset may already exist"

# Enable required APIs
echo "🔧 Enabling required APIs..."
gcloud services enable bigquery.googleapis.com
gcloud services enable aiplatform.googleapis.com
gcloud services enable bigqueryconnection.googleapis.com

# Create BigQuery connection for Vertex AI
echo "🔗 Creating BigQuery-Vertex AI connection..."
bq mk --connection --location=$LOCATION --project_id=$PROJECT_ID \
    --connection_type=CLOUD_RESOURCE \
    --display_name="gemini-connection" \
    gemini_connection

# Get the service account for the connection
CONNECTION_SA=$(bq show --format=json --connection $PROJECT_ID.$LOCATION.gemini_connection | jq -r '.cloudResource.serviceAccountId')

echo "🔑 Service account for connection: $CONNECTION_SA"

# Grant necessary permissions
echo "🛡️ Granting permissions..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$CONNECTION_SA" \
    --role="roles/aiplatform.user"

# Create the Gemini model reference
echo "🤖 Creating Gemini model reference in BigQuery..."
cat << EOF > /tmp/create_model.sql
-- Standard text model used across Approach 1
CREATE OR REPLACE MODEL \`$PROJECT_ID.$DATASET_ID.gemini_pro_model\`
REMOTE WITH CONNECTION \`$PROJECT_ID.$LOCATION.gemini_connection\`
OPTIONS(endpoint = 'gemini-1.5-pro-001');

-- Optional extraction model (alias to same endpoint for demo)
CREATE OR REPLACE MODEL \`$PROJECT_ID.$DATASET_ID.text_extraction_model\`
REMOTE WITH CONNECTION \`$PROJECT_ID.$LOCATION.gemini_connection\`
OPTIONS(endpoint = 'gemini-1.5-pro-001');

-- Multimodal embedding model
CREATE OR REPLACE MODEL \`$PROJECT_ID.$DATASET_ID.multimodal_embedding_model\`
REMOTE WITH CONNECTION \`$PROJECT_ID.$LOCATION.gemini_connection\`
OPTIONS(endpoint = 'multimodalembedding@001');
EOF

bq query --use_legacy_sql=false < /tmp/create_model.sql

# Load sample data
echo "📁 Loading sample catalog data..."
if [ -f "../data/sample_catalog.csv" ]; then
    bq load --autodetect --source_format=CSV \
        $PROJECT_ID:$DATASET_ID.messy_catalog \
        ../data/sample_catalog.csv
    echo "✅ Sample data loaded successfully"
else
    echo "⚠️  Sample data file not found at ../data/sample_catalog.csv"
fi

# Create a sample query to test
echo "🧪 Testing setup with a sample query..."
cat << EOF > /tmp/test_query.sql
-- Test basic setup
SELECT 
    'Setup Complete!' as status,
    CURRENT_TIMESTAMP() as timestamp,
    '$PROJECT_ID' as project_id,
    '$DATASET_ID' as dataset_id,
    '$LOCATION' as location;

-- Test ML.GENERATE_TEXT function
WITH test_ai AS (
    SELECT ML.GENERATE_TEXT(
        MODEL \`$PROJECT_ID.$DATASET_ID.gemini_pro_model\`,
        PROMPT => 'Generate a product description for: Blue Running Shoes',
        STRUCT(0.7 AS temperature, 50 AS max_output_tokens)
    ) AS generated_text
)
SELECT 'ML.GENERATE_TEXT' as function_tested, 
       CASE WHEN generated_text IS NOT NULL THEN 'SUCCESS' ELSE 'FAILED' END as status
FROM test_ai;

-- Test AI.GENERATE_BOOL function
SELECT 'AI.GENERATE_BOOL' as function_tested,
    AI.GENERATE_BOOL(
        MODEL \`$PROJECT_ID.$DATASET_ID.gemini_pro_model\`,
        PROMPT => 'Is $99.99 a reasonable price for running shoes? Answer TRUE or FALSE.',
        STRUCT(0.1 AS temperature)
    ) AS result;

-- Test AI.GENERATE_INT function  
SELECT 'AI.GENERATE_INT' as function_tested,
    AI.GENERATE_INT(
        MODEL \`$PROJECT_ID.$DATASET_ID.gemini_pro_model\`,
        PROMPT => 'Extract the size from: Size 10 running shoes',
        STRUCT(0.1 AS temperature)
    ) AS extracted_size;
EOF

bq query --use_legacy_sql=false < /tmp/test_query.sql

echo ""
echo "✅ BigQuery setup complete!"
echo ""
echo "📝 Next steps:"
echo "1. Update PROJECT_ID in the notebook to: $PROJECT_ID"
echo "2. Update DATASET_ID in the notebook to: $DATASET_ID"
echo "3. Run the demo notebook to see CatalogAI in action"
echo ""
echo "🔗 Useful links:"
echo "- BigQuery Console: https://console.cloud.google.com/bigquery?project=$PROJECT_ID"
echo "- Vertex AI Console: https://console.cloud.google.com/vertex-ai?project=$PROJECT_ID"

# Clean up temp files
rm -f /tmp/create_model.sql /tmp/test_query.sql
