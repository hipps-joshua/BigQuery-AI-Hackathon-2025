#!/bin/bash

# BigQuery AI Complete Test Script
# Run all tests with one command

# Configuration
PROJECT_ID="bigquery-ai-hackathon-2025"
LOCATION="us-central1"
DATASET_ID="test_dataset_central"
CONNECTION_ID="$PROJECT_ID.$LOCATION.gemini_connection"

echo "========================================="
echo "BigQuery AI Comprehensive Test"
echo "Project: $PROJECT_ID"
echo "Dataset: $DATASET_ID"
echo "========================================="

# Function to run query and show results
run_query() {
    local description=$1
    local query=$2
    echo ""
    echo "📊 $description"
    echo "-----------------------------------------"
    bq query --use_legacy_sql=false "$query"
}

# Test 1: Basic AI Generation
run_query "Test 1: AI.GENERATE - Simple Text Generation" "
SELECT AI.GENERATE(
  'Write a haiku about data analytics',
  connection_id => '$CONNECTION_ID'
).result as haiku;"

# Test 2: Boolean Generation
run_query "Test 2: AI.GENERATE_BOOL - Decision Making" "
SELECT 
  'iPhone at \$1199' as product,
  AI.GENERATE_BOOL(
    'Is an iPhone at \$1199 a good value for most consumers?',
    connection_id => '$CONNECTION_ID'
  ).result as good_value;"

# Test 3: Numeric Generation
run_query "Test 3: AI.GENERATE_DOUBLE - Scoring" "
SELECT 
  'MacBook Pro for video editing' as use_case,
  AI.GENERATE_DOUBLE(
    'Rate the suitability 1-10 of MacBook Pro for professional video editing',
    connection_id => '$CONNECTION_ID'
  ).result as suitability_score;"

# Test 4: Create Sample Data
echo ""
echo "📊 Test 4: Creating Sample Product Data"
echo "-----------------------------------------"
bq query --use_legacy_sql=false "
CREATE OR REPLACE TABLE \`$PROJECT_ID.$DATASET_ID.demo_products\` AS
SELECT * FROM (
  SELECT 'P001' as id, 'Nike Air Max' as name, 'Shoes' as category, 120.00 as price
  UNION ALL SELECT 'P002', 'Apple AirPods', 'Electronics', 199.00
  UNION ALL SELECT 'P003', 'Yoga Mat', 'Sports', 29.99
  UNION ALL SELECT 'P004', 'Smart Watch', 'Electronics', 299.00
  UNION ALL SELECT 'P005', 'Running Shorts', 'Apparel', 39.99
);"
echo "✅ Sample products created"

# Test 5: Multi-Product AI Analysis
run_query "Test 5: Batch AI Analysis on Multiple Products" "
SELECT 
  name,
  category,
  price,
  AI.GENERATE(
    CONCAT('In 15 words, describe why someone would buy: ', name),
    connection_id => '$CONNECTION_ID'
  ).result as purchase_reason,
  AI.GENERATE_BOOL(
    CONCAT('Is ', name, ' at \$', CAST(price AS STRING), ' competitively priced?'),
    connection_id => '$CONNECTION_ID'
  ).result as competitive_price
FROM \`$PROJECT_ID.$DATASET_ID.demo_products\`
LIMIT 3;"

# Test 6: Embeddings (if model exists)
echo ""
echo "📊 Test 6: Testing Embeddings"
echo "-----------------------------------------"
bq query --use_legacy_sql=false "
SELECT 
  'Running shoes for marathon training' as search_term,
  ARRAY_LENGTH(ml_generate_embedding_result) as embedding_dimensions
FROM ML.GENERATE_EMBEDDING(
  MODEL \`$PROJECT_ID.$DATASET_ID.gemini_embedding_model\`,
  (SELECT 'Running shoes for marathon training' AS content)
)
LIMIT 1;" 2>/dev/null || echo "⚠️  Embedding model not found - skipping"

# Test 7: Summary Statistics
run_query "Test 7: Final Summary" "
SELECT 
  COUNT(*) as total_products,
  ROUND(AVG(price), 2) as avg_price,
  MIN(price) as min_price,
  MAX(price) as max_price
FROM \`$PROJECT_ID.$DATASET_ID.demo_products\`;"

echo ""
echo "========================================="
echo "✅ All tests completed successfully!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Review the results above"
echo "2. Modify queries in this script for your use case"
echo "3. Scale up with more products and complex queries"
echo "4. Check costs in BigQuery console"
echo ""
