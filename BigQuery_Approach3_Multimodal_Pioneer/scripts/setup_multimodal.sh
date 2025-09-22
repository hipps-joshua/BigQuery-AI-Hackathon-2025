#!/bin/bash

# BigQuery Multimodal Setup Script
# Sets up BigQuery dataset, tables, and models for multimodal e-commerce

echo "🚀 BigQuery Multimodal Setup"
echo "=========================="

# Configuration
read -p "Enter your GCP Project ID: " PROJECT_ID
read -p "Enter dataset name (default: ecommerce_multimodal): " DATASET_ID
DATASET_ID=${DATASET_ID:-ecommerce_multimodal}
read -p "Enter Cloud Storage bucket name: " BUCKET_NAME

echo ""
echo "📋 Configuration:"
echo "  Project: $PROJECT_ID"
echo "  Dataset: $DATASET_ID"
echo "  Bucket: $BUCKET_NAME"
echo ""

# Set project
echo "Setting project..."
gcloud config set project $PROJECT_ID

# Create dataset
echo ""
echo "Creating BigQuery dataset..."
bq mk --dataset \
  --description "E-commerce multimodal analytics dataset" \
  --location us-central1 \
  $PROJECT_ID:$DATASET_ID

# Create Cloud Storage bucket
echo ""
echo "Creating Cloud Storage bucket..."
gsutil mb -p $PROJECT_ID -l us-central1 gs://$BUCKET_NAME/

# Create directories in bucket
echo ""
echo "Setting up bucket structure..."
gsutil -m mkdir -p \
  gs://$BUCKET_NAME/product_images \
  gs://$BUCKET_NAME/compliance_docs \
  gs://$BUCKET_NAME/exports

# Upload sample data (if exists)
if [ -f "../data/sample_products_multimodal.csv" ]; then
  echo ""
  echo "Uploading sample data..."
  bq load \
    --source_format=CSV \
    --autodetect \
    --skip_leading_rows=1 \
    $DATASET_ID.products \
    ../data/sample_products_multimodal.csv
fi

# Create tables using bq
echo ""
echo "Creating tables..."

# Products table (if not loaded from CSV)
bq mk --table \
  $PROJECT_ID:$DATASET_ID.products \
  sku:STRING,product_name:STRING,brand_name:STRING,category:STRING,subcategory:STRING,listed_color:STRING,listed_size:STRING,material:STRING,price:FLOAT,description:STRING,image_filename:STRING,seller_name:STRING,gender:STRING,is_active:BOOLEAN,rating:FLOAT,inventory_count:INTEGER

# Image analysis results table
bq mk --table \
  $PROJECT_ID:$DATASET_ID.image_analysis \
  sku:STRING,primary_color:STRING,detected_colors:STRING,detected_text:STRING,brand_visible:STRING,quality_score:STRING,compliance_labels:STRING,full_analysis:STRING,analyzed_at:TIMESTAMP

# QC results table
bq mk --table \
  $PROJECT_ID:$DATASET_ID.qc_results \
  batch_id:STRING,sku:STRING,rule_id:STRING,status:STRING,confidence:FLOAT,message:STRING,suggested_fix:STRING,timestamp:TIMESTAMP

# Brand mapping table
bq mk --table \
  $PROJECT_ID:$DATASET_ID.brand_mapping \
  original_brand:STRING,standardized_brand:STRING,brand_id:STRING

# Authorized sellers table
bq mk --table \
  $PROJECT_ID:$DATASET_ID.authorized_sellers \
  brand:STRING,authorized_seller:STRING,seller_id:STRING,authorized_date:DATE

# Create Object Table for images
echo ""
echo "Creating Object Table for product images..."
cat << EOF > /tmp/create_object_table.sql
CREATE OR REPLACE EXTERNAL TABLE \`$PROJECT_ID.$DATASET_ID.product_images\`
OPTIONS (
    format = 'OBJECT_TABLE',
    uris = ['gs://$BUCKET_NAME/product_images/*']
);
EOF

bq query --use_legacy_sql=false < /tmp/create_object_table.sql

# Create models (placeholders - actual models need to be created separately)
echo ""
echo "Model setup instructions:"
echo "========================"
echo ""
echo "To complete the setup, create these models in BigQuery:"
echo ""
echo "1. Text Generation Model (Gemini):"
echo "   CREATE OR REPLACE MODEL \`$PROJECT_ID.$DATASET_ID.gemini_vision_model\`"
echo "   REMOTE WITH CONNECTION \`$PROJECT_ID.us-central1.gemini_connection\`"
echo "   OPTIONS (ENDPOINT = 'gemini-1.5-pro');"
echo ""
echo "2. Embedding Model:"
echo "   CREATE OR REPLACE MODEL \`$PROJECT_ID.$DATASET_ID.multimodal_embedding_model\`"
echo "   REMOTE WITH CONNECTION \`$PROJECT_ID.us-central1.gemini_connection\`"
echo "   OPTIONS (ENDPOINT = 'text-embedding-004');"
echo ""

# Create sample SQL queries
echo ""
echo "Creating sample queries..."
mkdir -p ../queries

cat << 'EOF' > ../queries/analyze_images.sql
-- Analyze product images using Gemini Vision
WITH image_analysis AS (
  SELECT 
    p.sku,
    p.product_name,
    p.listed_color,
    ML.GENERATE_TEXT(
      MODEL `PROJECT_ID.DATASET_ID.gemini_vision_model`,
      PROMPT => CONCAT(
        'Analyze this product image and extract in JSON format: ',
        '1. detected_colors (list), 2. detected_text, ',
        '3. brand_visibility (true/false), 4. image_quality_score (0-1), ',
        '5. compliance_labels (list)'
      ),
      STRUCT(i.content AS image, 0.3 AS temperature)
    ) AS analysis_result
  FROM `PROJECT_ID.DATASET_ID.products` p
  JOIN `PROJECT_ID.DATASET_ID.product_images` i
    ON p.image_filename = i.name
)
SELECT * FROM image_analysis;
EOF

cat << 'EOF' > ../queries/visual_search.sql
-- Find visually similar products
WITH query_embedding AS (
  SELECT ML.GENERATE_EMBEDDING(
    MODEL `PROJECT_ID.DATASET_ID.multimodal_embedding_model`,
    CONTENT => (
      SELECT content 
      FROM `PROJECT_ID.DATASET_ID.product_images` 
      WHERE name = 'query_image.jpg'
    ),
    STRUCT('IMAGE' as content_type)
  ) AS embedding
),
product_embeddings AS (
  SELECT 
    p.sku,
    p.product_name,
    p.price,
    ML.GENERATE_EMBEDDING(
      MODEL `PROJECT_ID.DATASET_ID.multimodal_embedding_model`,
      CONTENT => i.content,
      STRUCT('IMAGE' as content_type)
    ) AS embedding
  FROM `PROJECT_ID.DATASET_ID.products` p
  JOIN `PROJECT_ID.DATASET_ID.product_images` i
    ON p.image_filename = i.name
)
SELECT 
  pe.sku,
  pe.product_name,
  pe.price,
  ML.DISTANCE(qe.embedding, pe.embedding, 'COSINE') as similarity
FROM query_embedding qe
CROSS JOIN product_embeddings pe
ORDER BY similarity ASC
LIMIT 10;
EOF

cat << 'EOF' > ../queries/compliance_check.sql
-- Check compliance for regulated categories
WITH compliance_analysis AS (
  SELECT 
    p.sku,
    p.product_name,
    p.category,
    a.compliance_labels,
    CASE 
      WHEN p.category IN ('electronics', 'toys', 'cosmetics', 'food')
        AND ARRAY_LENGTH(a.compliance_labels) = 0
      THEN 'FAIL'
      ELSE 'PASS'
    END as compliance_status
  FROM `PROJECT_ID.DATASET_ID.products` p
  JOIN `PROJECT_ID.DATASET_ID.image_analysis` a
    ON p.sku = a.sku
  WHERE p.category IN ('electronics', 'toys', 'cosmetics', 'food')
)
SELECT 
  category,
  COUNT(*) as total_products,
  COUNTIF(compliance_status = 'PASS') as passed,
  ROUND(COUNTIF(compliance_status = 'PASS') / COUNT(*) * 100, 1) as pass_rate_pct
FROM compliance_analysis
GROUP BY category;
EOF

echo ""
echo "Sample queries created in ../queries/"

# Create monitoring views
echo ""
echo "Creating monitoring views..."

bq mk --view \
  "SELECT 
    DATE(timestamp) as date,
    COUNT(DISTINCT sku) as products_checked,
    COUNTIF(status = 'passed') as passed,
    COUNTIF(status = 'failed') as failed,
    ROUND(COUNTIF(status = 'passed') / COUNT(*) * 100, 1) as pass_rate_pct
  FROM \`$PROJECT_ID.$DATASET_ID.qc_results\`
  WHERE timestamp >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  GROUP BY date
  ORDER BY date DESC" \
  $PROJECT_ID:$DATASET_ID.qc_daily_summary

echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Upload product images to gs://$BUCKET_NAME/product_images/"
echo "2. Create the ML models as shown above"
echo "3. Run the demo notebook to see multimodal AI in action"
echo ""
echo "Sample queries available in ../queries/"
