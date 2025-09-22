#!/bin/bash

# ============================================
# SEMANTIC DETECTIVE - BIGQUERY SETUP SCRIPT
# ============================================
# This script sets up everything needed for Approach 2
# Usage: ./setup_bigquery.sh PROJECT_ID DATASET_ID

set -e  # Exit on error

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check arguments
if [ $# -ne 2 ]; then
    echo -e "${RED}Usage: $0 PROJECT_ID DATASET_ID${NC}"
    echo "Example: $0 my-project semantic-detective"
    exit 1
fi

PROJECT_ID=$1
DATASET_ID=$2
LOCATION="us-central1"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}🕵️ SEMANTIC DETECTIVE - BIGQUERY SETUP${NC}"
echo -e "${BLUE}========================================${NC}"
echo "Project ID: $PROJECT_ID"
echo "Dataset ID: $DATASET_ID"
echo "Location: $LOCATION"
echo ""

# Function to execute SQL
execute_sql() {
    local sql_content=$1
    local description=$2
    
    echo -e "${YELLOW}Executing: $description${NC}"
    
    echo "$sql_content" | \
    sed -e "s/\${PROJECT_ID}/$PROJECT_ID/g" \
        -e "s/\${DATASET_ID}/$DATASET_ID/g" \
        -e "s/\${LOCATION}/$LOCATION/g" | \
    bq query \
        --use_legacy_sql=false \
        --project_id="$PROJECT_ID" \
        --location="$LOCATION" 2>&1 | \
    grep -v "WARNING" || true
        
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo -e "${GREEN}✓ $description completed${NC}"
    else
        echo -e "${RED}✗ $description failed${NC}"
        return 1
    fi
}

# Step 1: Create dataset
echo -e "${YELLOW}Step 1: Creating dataset...${NC}"
bq mk \
    --project_id="$PROJECT_ID" \
    --location="$LOCATION" \
    --dataset \
    --description="Semantic Detective - Intelligent Product Matching Platform" \
    "$PROJECT_ID:$DATASET_ID" 2>/dev/null || {
        echo -e "${YELLOW}Dataset already exists, continuing...${NC}"
    }

# Step 2: Create base tables
echo -e "${YELLOW}Step 2: Creating base tables...${NC}"
execute_sql "
-- Products table
CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET_ID}.products\` (
  sku STRING NOT NULL,
  brand_name STRING,
  product_name STRING,
  description STRING,
  category STRING,
  subcategory STRING,
  price FLOAT64,
  cost FLOAT64,
  color STRING,
  size STRING,
  material STRING,
  weight_kg FLOAT64,
  image_url STRING,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- Processing log
CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET_ID}.processing_log\` (
  timestamp TIMESTAMP,
  operation STRING,
  table_name STRING,
  offset_processed INT64,
  batch_size INT64,
  status STRING,
  error_message STRING
);

-- Search log for analytics
CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET_ID}.search_log\` (
  search_id STRING DEFAULT GENERATE_UUID(),
  query_text STRING,
  search_type STRING,
  results_count INT64,
  avg_similarity FLOAT64,
  search_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  user_segment STRING,
  clicked_sku STRING,
  conversion BOOL DEFAULT FALSE
);

-- Duplicate detection log
CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET_ID}.duplicate_detection_log\` (
  detection_id STRING DEFAULT GENERATE_UUID(),
  run_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  total_products INT64,
  duplicate_pairs_found INT64,
  duplicate_groups_found INT64,
  estimated_savings FLOAT64,
  processing_time_seconds FLOAT64
);

-- Test results
CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET_ID}.test_results\` (
  test_name STRING,
  result STRING,
  status STRING,
  timestamp TIMESTAMP
);
" "Creating base tables"

# Step 3: Create models
echo -e "${YELLOW}Step 3: Creating AI models...${NC}"
echo -e "${YELLOW}Note: Make sure you have created a connection first:${NC}"
echo "bq mk --connection --location=$LOCATION --project_id=$PROJECT_ID --connection_type=CLOUD_RESOURCE gemini_connection"
echo ""

execute_sql "
-- Text embedding model for semantic search
CREATE OR REPLACE MODEL \`${PROJECT_ID}.${DATASET_ID}.text_embedding_model\`
REMOTE WITH CONNECTION \`${PROJECT_ID}.${LOCATION}.gemini_connection\`
OPTIONS (
  endpoint = 'text-embedding-004'
);

-- Gemini Pro for AI enhancements
CREATE OR REPLACE MODEL \`${PROJECT_ID}.${DATASET_ID}.gemini_pro_model\`
REMOTE WITH CONNECTION \`${PROJECT_ID}.${LOCATION}.gemini_connection\`
OPTIONS (
  endpoint = 'gemini-1.5-pro-001'
);
" "Creating AI models" || {
    echo -e "${YELLOW}Model creation failed - create connection first${NC}"
}

# Step 4: Load sample data
echo -e "${YELLOW}Step 4: Loading sample data...${NC}"
execute_sql "
-- Insert diverse products including duplicates
INSERT INTO \`${PROJECT_ID}.${DATASET_ID}.products\` 
(sku, brand_name, product_name, category, subcategory, price, color, size, material, description)
VALUES
  -- Original products
  ('SHOE001', 'Nike', 'Air Max 270', 'Footwear', 'Running Shoes', 159.99, 'Black', '10', 'Mesh', 
   'Experience ultimate comfort with Nike Air Max 270. Features large Max Air unit for exceptional cushioning.'),
  -- Duplicate with different SKU
  ('SHOE001B', 'Nike', 'Air Max 270', 'Footwear', 'Running Shoes', 159.99, 'Black', '10', 'Mesh',
   'Nike Air Max 270 delivers visible Max Air cushioning under every step. Ultimate comfort guaranteed.'),
  -- Size variant (potential duplicate)
  ('SHOE001_11', 'Nike', 'Air Max 270', 'Footwear', 'Running Shoes', 159.99, 'Black', '11', 'Mesh',
   'Experience ultimate comfort with Nike Air Max 270. Features large Max Air unit for exceptional cushioning.'),
  -- Similar competitor product
  ('SHOE002', 'Adidas', 'Ultraboost 22', 'Footwear', 'Running Shoes', 189.99, 'Black', '10', 'Primeknit',
   'Endless energy return with Ultraboost 22. Features responsive BOOST midsole and adaptive Primeknit upper.'),
  -- Different category
  ('SHIRT001', 'Nike', 'Dri-FIT Running Shirt', 'Apparel', 'Athletic Wear', 45.99, 'Black', 'L', 'Polyester',
   'Stay dry and comfortable with Nike Dri-FIT technology. Perfect for running and training.'),
  -- Potential cross-sell
  ('SOCK001', 'Nike', 'Elite Running Socks', 'Apparel', 'Socks', 24.99, 'Black', 'L', 'Synthetic',
   'Cushioned support for runners. Arch compression and moisture-wicking fabric.'),
  -- Another duplicate with typo
  ('SHOE001X', 'Nike', 'Air Max 270s', 'Footwear', 'Running', 155.99, 'Black', '10', 'Mesh',
   'Nike AirMax 270 - ultimate comfort with Max Air cushioning unit.'),
  -- Premium alternative
  ('SHOE003', 'Nike', 'Air Zoom Alphafly', 'Footwear', 'Running Shoes', 275.99, 'Black', '10', 'Flyknit',
   'Race-day shoe with ZoomX foam and carbon fiber plate. Built for speed.'),
  -- Budget alternative  
  ('SHOE004', 'Nike', 'Revolution 6', 'Footwear', 'Running Shoes', 69.99, 'Black', '10', 'Mesh',
   'Soft cushioning for everyday runs. Lightweight and breathable design.'),
  -- Different brand similar product
  ('SHOE005', 'New Balance', 'Fresh Foam 1080', 'Footwear', 'Running Shoes', 164.99, 'Black', '10', 'Mesh',
   'Plush Fresh Foam midsole for luxurious comfort. Premium running experience.');

-- Insert sample search history
INSERT INTO \`${PROJECT_ID}.${DATASET_ID}.search_log\`
(query_text, search_type, results_count, avg_similarity, user_segment)
VALUES
  ('black running shoes', 'full', 8, 0.85, 'general'),
  ('nike air max', 'title', 4, 0.92, 'brand_loyal'),
  ('comfortable running shoes under 200', 'attributes', 6, 0.78, 'budget_conscious'),
  ('marathon training shoes', 'full', 5, 0.81, 'serious_runner');
" "Loading sample products and search data"

# Step 5: Create stored procedures
echo -e "${YELLOW}Step 5: Creating stored procedures and functions...${NC}"
if [ -f "./sql/production_queries.sql" ]; then
    execute_sql "$(cat ./sql/production_queries.sql)" "Creating production queries"
else
    echo -e "${RED}Warning: production_queries.sql not found${NC}"
fi

# Step 6: Generate initial embeddings for sample data
echo -e "${YELLOW}Step 6: Generating embeddings for sample data...${NC}"
execute_sql "
-- Generate embeddings for sample products
CALL \`${PROJECT_ID}.${DATASET_ID}.generate_product_embeddings\`('products', 10);
" "Generating embeddings" || {
    echo -e "${YELLOW}Embedding generation will run when procedures are created${NC}"
}

# Step 7: Create vector indexes
echo -e "${YELLOW}Step 7: Creating vector indexes...${NC}"
execute_sql "
-- Create vector index for fast similarity search
CALL \`${PROJECT_ID}.${DATASET_ID}.create_vector_search_index\`('products', 'full_embedding');
" "Creating vector indexes" || {
    echo -e "${YELLOW}Vector indexes will be created after embeddings are generated${NC}"
}

# Step 8: Run initial duplicate detection
echo -e "${YELLOW}Step 8: Running duplicate detection on sample data...${NC}"
execute_sql "
-- Find duplicates in sample data
CALL \`${PROJECT_ID}.${DATASET_ID}.find_duplicate_products\`('products', 0.85);

-- Show duplicate summary
SELECT 
  COUNT(*) AS duplicate_pairs_found,
  COUNT(DISTINCT group_id) AS duplicate_groups,
  SUM(potential_revenue_loss) AS total_revenue_impact
FROM \`${PROJECT_ID}.${DATASET_ID}.duplicate_candidates\`
LEFT JOIN \`${PROJECT_ID}.${DATASET_ID}.duplicate_groups\` USING(sku);
" "Finding duplicates" || {
    echo -e "${YELLOW}Duplicate detection will run after setup completes${NC}"
}

# Step 9: Create monitoring views
echo -e "${YELLOW}Step 9: Creating monitoring dashboards...${NC}"
execute_sql "
-- Semantic search effectiveness view
CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_ID}.search_effectiveness\` AS
WITH search_stats AS (
  SELECT
    DATE(search_timestamp) AS date,
    search_type,
    COUNT(*) AS searches,
    AVG(results_count) AS avg_results,
    AVG(avg_similarity) AS avg_similarity,
    SUM(CASE WHEN conversion THEN 1 ELSE 0 END) / COUNT(*) AS conversion_rate
  FROM \`${PROJECT_ID}.${DATASET_ID}.search_log\`
  GROUP BY date, search_type
)
SELECT
  date,
  SUM(searches) AS total_searches,
  AVG(avg_results) AS avg_results_returned,
  AVG(avg_similarity) AS avg_match_quality,
  AVG(conversion_rate) AS overall_conversion_rate,
  SUM(searches) * 0.002 AS estimated_cost_usd
FROM search_stats
GROUP BY date
ORDER BY date DESC;

-- Duplicate detection ROI view
CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_ID}.duplicate_roi_dashboard\` AS
SELECT
  DATE(run_timestamp) AS date,
  SUM(duplicate_pairs_found) AS total_duplicates,
  SUM(duplicate_groups_found) AS unique_products_affected,
  SUM(estimated_savings) AS inventory_savings_usd,
  AVG(processing_time_seconds) AS avg_processing_seconds,
  SUM(duplicate_pairs_found) * 50 AS operational_savings_usd,
  SUM(estimated_savings) + (SUM(duplicate_pairs_found) * 50) AS total_monthly_savings
FROM \`${PROJECT_ID}.${DATASET_ID}.duplicate_detection_log\`
WHERE run_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY date
ORDER BY date DESC;
" "Creating monitoring views"

# Step 10: Run validation tests
echo -e "${YELLOW}Step 10: Running validation tests...${NC}"
if [ -f "./sql/test_queries.sql" ]; then
    execute_sql "$(cat ./sql/test_queries.sql)" "Running tests" || {
        echo -e "${YELLOW}Some tests may fail until all components are ready${NC}"
    }
else
    echo -e "${RED}Warning: test_queries.sql not found${NC}"
fi

# Step 11: Create monitoring and alerting
echo -e "${YELLOW}Step 11: Creating monitoring and alerting infrastructure...${NC}"
if [ -f "./sql/monitoring_queries.sql" ]; then
    execute_sql "$(cat ./sql/monitoring_queries.sql)" "Creating monitoring queries"
else
    echo -e "${RED}Warning: monitoring_queries.sql not found${NC}"
fi

# Cleanup
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}🎉 SEMANTIC DETECTIVE SETUP COMPLETE!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Next steps:"
echo ""
echo "1. Test semantic search:"
echo -e "${BLUE}   bq query --use_legacy_sql=false --project_id=$PROJECT_ID \\
   \"SELECT * FROM \\\`$PROJECT_ID.$DATASET_ID.semantic_search\\\`(
      'comfortable black running shoes',
      '$PROJECT_ID.$DATASET_ID.products_embeddings',
      'full',
      5,
      0.7
   )\"${NC}"
echo ""
echo "2. Check for duplicates:"
echo -e "${BLUE}   bq query --use_legacy_sql=false --project_id=$PROJECT_ID \\
   \"SELECT * FROM \\\`$PROJECT_ID.$DATASET_ID.duplicate_candidates\\\`
    ORDER BY combined_score DESC LIMIT 10\"${NC}"
echo ""
echo "3. Find substitutes:"
echo -e "${BLUE}   bq query --use_legacy_sql=false --project_id=$PROJECT_ID \\
   \"SELECT * FROM \\\`$PROJECT_ID.$DATASET_ID.find_substitutes\\\`(
      'SHOE001',
      0.3,
      5
   )\"${NC}"
echo ""
echo "4. View ROI dashboard:"
echo -e "${BLUE}   bq query --use_legacy_sql=false --project_id=$PROJECT_ID \\
   \"SELECT * FROM \\\`$PROJECT_ID.$DATASET_ID.duplicate_roi_dashboard\\\`\"${NC}"
echo ""
echo -e "${GREEN}Ready to find hidden value in your catalog! 🕵️💰${NC}"
