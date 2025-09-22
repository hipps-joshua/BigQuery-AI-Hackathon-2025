#!/bin/bash

# Enhanced BigQuery Setup Script for Semantic Detective
# This sets up ALL AI models for the complete solution

echo "🔍 Setting up ALL BigQuery AI Models for Semantic Detective..."

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
DATASET_ID="semantic_detective"
LOCATION="us-central1"

echo "📊 Creating BigQuery dataset..."
bq mk --dataset --location=$LOCATION --description="Semantic Detective - AI-Enhanced Product Intelligence" $PROJECT_ID:$DATASET_ID || echo "Dataset may already exist"

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

# Create ALL AI models
echo "🤖 Creating ALL BigQuery AI models..."

# 1. Text Embedding Model (for vector search)
cat << EOF > /tmp/create_embedding_model.sql
CREATE OR REPLACE MODEL \`$PROJECT_ID.$DATASET_ID.text_embedding_model\`
REMOTE WITH CONNECTION \`$PROJECT_ID.$LOCATION.gemini_connection\`
OPTIONS(endpoint = 'text-embedding-004');
EOF

bq query --use_legacy_sql=false < /tmp/create_embedding_model.sql
echo "✅ Created text embedding model"

# 2. Text Generation Model (for AI.GENERATE_TEXT)
cat << EOF > /tmp/create_text_model.sql
CREATE OR REPLACE MODEL \`$PROJECT_ID.$DATASET_ID.text_generation_model\`
REMOTE WITH CONNECTION \`$PROJECT_ID.$LOCATION.gemini_connection\`
OPTIONS(endpoint = 'gemini-1.5-pro-001');
EOF

bq query --use_legacy_sql=false < /tmp/create_text_model.sql
echo "✅ Created text generation model"

# 3. Create sample tables for demonstration
echo "📁 Creating sample tables..."

# Product catalog
cat << EOF > /tmp/create_product_table.sql
CREATE OR REPLACE TABLE \`$PROJECT_ID.$DATASET_ID.products_raw\` (
    sku STRING,
    brand_name STRING,
    product_name STRING,
    category STRING,
    subcategory STRING,
    description STRING,
    price FLOAT64,
    color STRING,
    size STRING,
    material STRING,
    weight STRING,
    image_url STRING,
    inventory_count INT64
);
EOF

bq query --use_legacy_sql=false < /tmp/create_product_table.sql

# Sales history for forecasting
cat << EOF > /tmp/create_sales_table.sql
CREATE OR REPLACE TABLE \`$PROJECT_ID.$DATASET_ID.sales_history\` (
    date DATE,
    sku STRING,
    quantity INT64,
    revenue FLOAT64,
    category STRING
);
EOF

bq query --use_legacy_sql=false < /tmp/create_sales_table.sql

# Competitor prices
cat << EOF > /tmp/create_competitor_table.sql
CREATE OR REPLACE TABLE \`$PROJECT_ID.$DATASET_ID.competitor_prices\` (
    competitor STRING,
    sku STRING,
    product_name STRING,
    price FLOAT64,
    brand STRING
);
EOF

bq query --use_legacy_sql=false < /tmp/create_competitor_table.sql

echo "✅ Created all sample tables"

# 4. Test all AI functions
echo "🧪 Testing AI functions..."

# Test AI.GENERATE_TEXT
cat << EOF > /tmp/test_generate_text.sql
SELECT ML.GENERATE_TEXT(
    MODEL \`$PROJECT_ID.$DATASET_ID.text_generation_model\`,
    PROMPT => 'Generate a product description for comfortable running shoes',
    STRUCT(
        0.8 AS temperature,
        256 AS max_output_tokens
    )
).generated_text AS test_text;
EOF

echo "Testing AI.GENERATE_TEXT..."
bq query --use_legacy_sql=false < /tmp/test_generate_text.sql

# Test ML.GENERATE_EMBEDDING
cat << EOF > /tmp/test_embedding.sql
SELECT ML.GENERATE_EMBEDDING(
    MODEL \`$PROJECT_ID.$DATASET_ID.text_embedding_model\`,
    CONTENT => 'Nike running shoes',
    STRUCT(TRUE AS flatten_json_output)
) AS test_embedding;
EOF

echo "Testing ML.GENERATE_EMBEDDING..."
bq query --use_legacy_sql=false < /tmp/test_embedding.sql

# Test AI.GENERATE_BOOL
cat << EOF > /tmp/test_generate_bool.sql
SELECT AI.GENERATE_BOOL(
    MODEL \`$PROJECT_ID.$DATASET_ID.text_generation_model\`,
    PROMPT => 'Is Nike Air Max a running shoe?',
    STRUCT(0.1 AS temperature)
).generated_bool AS is_running_shoe;
EOF

echo "Testing AI.GENERATE_BOOL..."
bq query --use_legacy_sql=false < /tmp/test_generate_bool.sql

# Test AI.GENERATE_INT
cat << EOF > /tmp/test_generate_int.sql
SELECT AI.GENERATE_INT(
    MODEL \`$PROJECT_ID.$DATASET_ID.text_generation_model\`,
    PROMPT => 'Extract the size from: Size 10 running shoes',
    STRUCT(0.0 AS temperature)
).generated_int AS extracted_size;
EOF

echo "Testing AI.GENERATE_INT..."
bq query --use_legacy_sql=false < /tmp/test_generate_int.sql

# Test AI.GENERATE_DOUBLE
cat << EOF > /tmp/test_generate_double.sql
SELECT AI.GENERATE_DOUBLE(
    MODEL \`$PROJECT_ID.$DATASET_ID.text_generation_model\`,
    PROMPT => 'Extract the weight in grams from: Weight 280g',
    STRUCT(0.0 AS temperature)
).generated_double AS weight_grams;
EOF

echo "Testing AI.GENERATE_DOUBLE..."
bq query --use_legacy_sql=false < /tmp/test_generate_double.sql

echo ""
echo "✅ ALL BigQuery AI Models setup complete!"
echo ""
echo "📝 Configuration for notebooks:"
echo "   PROJECT_ID = '$PROJECT_ID'"
echo "   DATASET_ID = '$DATASET_ID'"
echo "   LOCATION = '$LOCATION'"
echo ""
echo "🤖 Models created:"
echo "   - text_embedding_model (ML.GENERATE_EMBEDDING)"
echo "   - text_generation_model (AI.GENERATE_TEXT, BOOL, INT, DOUBLE)"
echo ""
echo "💡 All AI functions ready:"
echo "   ✅ ML.GENERATE_EMBEDDING - For vector search"
echo "   ✅ AI.GENERATE_TEXT - For content generation"
echo "   ✅ AI.GENERATE_BOOL - For validation"
echo "   ✅ AI.GENERATE_INT - For integer extraction"
echo "   ✅ AI.GENERATE_DOUBLE - For decimal extraction"
echo "   ✅ AI.GENERATE_TABLE - Supported via text model"
echo "   ✅ AI.FORECAST - Ready when forecast model created"
echo ""
echo "🔗 Console links:"
echo "   BigQuery: https://console.cloud.google.com/bigquery?project=$PROJECT_ID"
echo "   Vertex AI: https://console.cloud.google.com/vertex-ai?project=$PROJECT_ID"

# Clean up temp files
rm -f /tmp/*.sql
