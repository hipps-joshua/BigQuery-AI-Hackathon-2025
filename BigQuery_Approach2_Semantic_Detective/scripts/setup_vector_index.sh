#!/bin/bash

# BigQuery Setup Script for SemanticMatch
# This script sets up vector search capabilities for semantic product matching

echo "🔍 Setting up BigQuery Vector Search for SemanticMatch..."

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
DATASET_ID="semantic_demo"
LOCATION="us-central1"

echo "📊 Creating BigQuery dataset for semantic search..."
bq mk --dataset --location=$LOCATION --description="Semantic Product Search Demo Dataset" $PROJECT_ID:$DATASET_ID || echo "Dataset may already exist"

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

# Create the text embedding model reference
echo "🤖 Creating text embedding model reference in BigQuery..."
cat << EOF > /tmp/create_embedding_model.sql
CREATE OR REPLACE MODEL \`$PROJECT_ID.$DATASET_ID.text-embedding-004\`
REMOTE WITH CONNECTION \`$PROJECT_ID.$LOCATION.gemini_connection\`
OPTIONS(endpoint = 'text-embedding-004');
EOF

bq query --use_legacy_sql=false < /tmp/create_embedding_model.sql

# Load sample product catalog
echo "📁 Loading sample product catalog..."
if [ -f "../data/product_catalog.csv" ]; then
    bq load --autodetect --source_format=CSV \
        $PROJECT_ID:$DATASET_ID.product_catalog \
        ../data/product_catalog.csv
    echo "✅ Sample catalog loaded successfully"
else
    echo "⚠️  Sample data file not found at ../data/product_catalog.csv"
fi

# Create embeddings table
echo "🧮 Creating embeddings table structure..."
cat << EOF > /tmp/create_embeddings_table.sql
CREATE OR REPLACE TABLE \`$PROJECT_ID.$DATASET_ID.product_catalog_embeddings\` AS
WITH product_text AS (
    SELECT 
        sku,
        brand_name,
        product_name,
        category,
        description,
        CONCAT(
            IFNULL(brand_name, ''), ' ',
            IFNULL(product_name, ''), ' ',
            IFNULL(category, ''), ' ',
            IFNULL(description, '')
        ) AS full_text
    FROM \`$PROJECT_ID.$DATASET_ID.product_catalog\`
)
SELECT 
    sku,
    brand_name,
    product_name,
    full_text,
    ML.GENERATE_EMBEDDING(
        MODEL \`$PROJECT_ID.$DATASET_ID.text-embedding-004\`,
        CONTENT => full_text
    ) AS full_embedding
FROM product_text
LIMIT 5;  -- Start with 5 products for testing
EOF

echo "⏳ Generating embeddings for sample products..."
bq query --use_legacy_sql=false < /tmp/create_embeddings_table.sql

# Create vector index (for large datasets)
echo "📐 Creating vector index structure..."
cat << EOF > /tmp/vector_index_info.sql
-- Vector index would be created like this for large datasets:
-- CREATE VECTOR INDEX product_embedding_index
-- ON \`$PROJECT_ID.$DATASET_ID.product_catalog_embeddings\`(full_embedding)
-- OPTIONS(
--     distance_type='COSINE',
--     index_type='IVF',
--     ivf_options='{"num_lists": 100}'
-- );

SELECT 
    "Vector index is recommended for tables with 1M+ rows" as info,
    "For this demo with 20 products, brute force search is sufficient" as note;
EOF

bq query --use_legacy_sql=false < /tmp/vector_index_info.sql

# Test vector search
echo "🧪 Testing vector search capability..."
cat << EOF > /tmp/test_vector_search.sql
-- Find products similar to the first product
WITH query_product AS (
    SELECT full_embedding
    FROM \`$PROJECT_ID.$DATASET_ID.product_catalog_embeddings\`
    LIMIT 1
)
SELECT 
    p.sku,
    p.brand_name,
    p.product_name,
    1 - COSINE_DISTANCE(p.full_embedding, q.full_embedding) AS similarity_score
FROM \`$PROJECT_ID.$DATASET_ID.product_catalog_embeddings\` p
CROSS JOIN query_product q
ORDER BY similarity_score DESC
LIMIT 5;
EOF

bq query --use_legacy_sql=false < /tmp/test_vector_search.sql

echo ""
echo "✅ BigQuery Vector Search setup complete!"
echo ""
echo "📝 Next steps:"
echo "1. Update PROJECT_ID in the notebook to: $PROJECT_ID"
echo "2. Update DATASET_ID in the notebook to: $DATASET_ID" 
echo "3. Run the demo notebook to see semantic search in action"
echo ""
echo "🔗 Useful links:"
echo "- BigQuery Console: https://console.cloud.google.com/bigquery?project=$PROJECT_ID"
echo "- Vertex AI Console: https://console.cloud.google.com/vertex-ai?project=$PROJECT_ID"
echo ""
echo "💡 Key features enabled:"
echo "- ML.GENERATE_EMBEDDING for text embeddings"
echo "- VECTOR_SEARCH for similarity queries"
echo "- COSINE_DISTANCE for similarity calculations"

# Clean up temp files
rm -f /tmp/create_embedding_model.sql /tmp/create_embeddings_table.sql /tmp/vector_index_info.sql /tmp/test_vector_search.sql
