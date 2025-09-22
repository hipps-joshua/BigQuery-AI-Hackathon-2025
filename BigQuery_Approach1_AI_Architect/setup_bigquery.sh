#!/bin/bash

# ============================================
# AI ARCHITECT - BIGQUERY SETUP SCRIPT
# ============================================
# This script sets up everything needed for Approach 1
# Usage: ./setup_bigquery.sh PROJECT_ID DATASET_ID

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check arguments
if [ $# -ne 2 ]; then
    echo -e "${RED}Usage: $0 PROJECT_ID DATASET_ID${NC}"
    echo "Example: $0 my-project ai-architect"
    exit 1
fi

PROJECT_ID=$1
DATASET_ID=$2
LOCATION="us-central1"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AI ARCHITECT - BIGQUERY SETUP${NC}"
echo -e "${GREEN}========================================${NC}"
echo "Project ID: $PROJECT_ID"
echo "Dataset ID: $DATASET_ID"
echo "Location: $LOCATION"
echo ""

# Function to execute SQL files with variable substitution
execute_sql() {
    local sql_file=$1
    local description=$2
    
    echo -e "${YELLOW}Executing: $description${NC}"
    
    # Replace variables in SQL file and execute
    sed -e "s/\${PROJECT_ID}/$PROJECT_ID/g" \
        -e "s/\${DATASET_ID}/$DATASET_ID/g" \
        -e "s/\${LOCATION}/$LOCATION/g" \
        "$sql_file" | bq query \
        --use_legacy_sql=false \
        --project_id="$PROJECT_ID" \
        --location="$LOCATION"
        
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $description completed${NC}"
    else
        echo -e "${RED}✗ $description failed${NC}"
        exit 1
    fi
}

# Step 1: Create dataset
echo -e "${YELLOW}Step 1: Creating dataset...${NC}"
bq mk \
    --project_id="$PROJECT_ID" \
    --location="$LOCATION" \
    --dataset \
    --description="AI Architect - E-commerce Intelligence Platform" \
    "$PROJECT_ID:$DATASET_ID" 2>/dev/null || {
        echo -e "${YELLOW}Dataset already exists or creation failed, continuing...${NC}"
    }

# Step 2: Create base tables
echo -e "${YELLOW}Step 2: Creating base tables...${NC}"
cat > /tmp/create_tables.sql << EOF
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
  dimensions_cm STRUCT<length FLOAT64, width FLOAT64, height FLOAT64>,
  image_url STRING,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- Sales history table
CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET_ID}.sales_history\` (
  transaction_id STRING NOT NULL,
  date DATE NOT NULL,
  sku STRING NOT NULL,
  quantity INT64,
  revenue FLOAT64,
  customer_segment STRING,
  channel STRING,
  region STRING
);

-- Processing log table
CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET_ID}.processing_log\` (
  timestamp TIMESTAMP,
  operation STRING,
  table_name STRING,
  offset_processed INT64,
  batch_size INT64,
  status STRING,
  error_message STRING
);

-- Performance metrics table
CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET_ID}.performance_metrics\` (
  timestamp TIMESTAMP,
  operation STRING,
  records_processed INT64,
  processing_time_seconds FLOAT64,
  tokens_used INT64,
  estimated_cost FLOAT64
);

-- Template library table
CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET_ID}.template_library\` (
  template_id STRING NOT NULL,
  template_name STRING,
  category STRING,
  description STRING,
  template_sql STRING,
  parameters ARRAY<STRING>,
  confidence_threshold FLOAT64,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- Workflow definitions table
CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET_ID}.template_workflows\` (
  workflow_id STRING,
  step_number INT64,
  template_id STRING,
  template_query STRING,
  depends_on_step INT64
);

-- Test results table
CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET_ID}.test_results\` (
  test_name STRING,
  result STRING,
  status STRING,
  timestamp TIMESTAMP
);
EOF

execute_sql /tmp/create_tables.sql "Creating base tables"

# Step 3: Create AI models
echo -e "${YELLOW}Step 3: Creating AI models...${NC}"
cat > /tmp/create_models.sql << EOF
-- Create remote model for Gemini Pro
CREATE OR REPLACE MODEL \`${PROJECT_ID}.${DATASET_ID}.gemini_pro_model\`
REMOTE WITH CONNECTION \`${PROJECT_ID}.${LOCATION}.gemini_connection\`
OPTIONS (
  endpoint = 'gemini-1.5-pro-001'
);

-- Create embedding model  
CREATE OR REPLACE MODEL \`${PROJECT_ID}.${DATASET_ID}.text_embedding_model\`
REMOTE WITH CONNECTION \`${PROJECT_ID}.${LOCATION}.gemini_connection\`
OPTIONS (
  endpoint = 'text-embedding-004'
);
EOF

# Note: Connection needs to be created first
echo -e "${YELLOW}Note: You may need to create a connection first:${NC}"
echo "bq mk --connection --location=$LOCATION --project_id=$PROJECT_ID --connection_type=CLOUD_RESOURCE gemini_connection"
echo ""

# Try to create models (may fail if connection doesn't exist)
execute_sql /tmp/create_models.sql "Creating AI models" || {
    echo -e "${YELLOW}Model creation failed - please create connection first${NC}"
}

# Step 4: Load sample data
echo -e "${YELLOW}Step 4: Loading sample data...${NC}"
cat > /tmp/sample_data.sql << EOF
-- Insert sample products
INSERT INTO \`${PROJECT_ID}.${DATASET_ID}.products\` 
(sku, brand_name, product_name, category, subcategory, price, color, size, material)
VALUES
  ('SHOE001', 'Nike', 'Air Max 270', 'Footwear', 'Running Shoes', 159.99, 'Black', '10', 'Mesh'),
  ('SHOE002', 'Adidas', 'Ultraboost 22', 'Footwear', 'Running Shoes', 189.99, 'White', '9.5', 'Primeknit'),
  ('SHIRT001', 'Ralph Lauren', 'Polo Shirt', 'Apparel', 'Shirts', 89.99, 'Navy', 'L', 'Cotton'),
  ('JEANS001', 'Levis', '501 Original', 'Apparel', 'Jeans', 79.99, 'Blue', '32x32', 'Denim'),
  ('WATCH001', 'Apple', 'Watch Series 8', 'Electronics', 'Smartwatches', 399.99, 'Silver', '45mm', 'Aluminum'),
  ('BAG001', 'Samsonite', 'Carry-On Spinner', 'Luggage', 'Suitcases', 249.99, 'Black', '21"', 'Polycarbonate'),
  ('YOGA001', 'Lululemon', 'Yoga Mat', 'Sports', 'Yoga', 128.00, 'Purple', '6mm', 'Natural Rubber'),
  ('TENT001', 'Coleman', '6-Person Dome Tent', 'Outdoor', 'Camping', 199.99, 'Green', '10x10', 'Polyester'),
  ('COFFEE001', 'Nespresso', 'Vertuo Next', 'Appliances', 'Coffee Makers', 159.99, 'Black', 'Standard', 'Plastic'),
  ('BOOK001', 'Penguin', 'BigQuery Guide', 'Media', 'Books', 39.99, NULL, NULL, 'Paper');

-- Insert sample sales history
INSERT INTO \`${PROJECT_ID}.${DATASET_ID}.sales_history\`
SELECT 
  GENERATE_UUID() AS transaction_id,
  DATE_SUB(CURRENT_DATE(), INTERVAL MOD(CAST(RAND() * 365 AS INT64), 365) DAY) AS date,
  sku,
  CAST(1 + RAND() * 5 AS INT64) AS quantity,
  price * (1 + RAND() * 2) AS revenue,
  CASE CAST(RAND() * 3 AS INT64)
    WHEN 0 THEN 'Budget Conscious'
    WHEN 1 THEN 'Premium Buyers'
    ELSE 'Regular Shoppers'
  END AS customer_segment,
  CASE CAST(RAND() * 3 AS INT64)
    WHEN 0 THEN 'Online'
    WHEN 1 THEN 'Store'
    ELSE 'Mobile App'
  END AS channel,
  CASE CAST(RAND() * 4 AS INT64)
    WHEN 0 THEN 'North America'
    WHEN 1 THEN 'Europe'
    WHEN 2 THEN 'Asia'
    ELSE 'Other'
  END AS region
FROM \`${PROJECT_ID}.${DATASET_ID}.products\`
CROSS JOIN UNNEST(GENERATE_ARRAY(1, 100)) AS batch;

-- Load template library
INSERT INTO \`${PROJECT_ID}.${DATASET_ID}.template_library\` 
(template_id, template_name, category, confidence_threshold)
VALUES
  ('PE001', 'Basic Product Description', 'product_enrichment', 0.8),
  ('PE002', 'SEO-Optimized Description', 'product_enrichment', 0.85),
  ('AE001', 'Extract Color Variants', 'attribute_extraction', 0.9),
  ('AE002', 'Extract Size Information', 'attribute_extraction', 0.9),
  ('QV001', 'Validate Pricing', 'quality_validation', 0.95),
  ('QV002', 'Check Completeness', 'quality_validation', 0.9);
EOF

execute_sql /tmp/sample_data.sql "Loading sample data"

# Step 5: Create stored procedures and functions
echo -e "${YELLOW}Step 5: Creating stored procedures...${NC}"
execute_sql ./sql/production_queries.sql "Creating production queries"

# Step 6: Run tests
echo -e "${YELLOW}Step 6: Running validation tests...${NC}"
execute_sql ./sql/test_queries.sql "Running test queries" || {
    echo -e "${YELLOW}Some tests may fail if models aren't created yet${NC}"
}

# Step 7: Create monitoring and alerting
echo -e "${YELLOW}Step 7: Creating monitoring and alerting queries...${NC}"
if [ -f "./sql/monitoring_queries.sql" ]; then
    execute_sql ./sql/monitoring_queries.sql "Creating monitoring queries"
else
    echo -e "${YELLOW}Monitoring queries not found, using basic views${NC}"
fi

# Step 8: Create additional views and dashboards
echo -e "${YELLOW}Step 8: Creating monitoring views...${NC}"
cat > /tmp/create_views.sql << EOF
-- ROI Dashboard View
CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_ID}.roi_dashboard\` AS
WITH enrichment_stats AS (
  SELECT 
    COUNT(*) AS products_enriched,
    AVG(LENGTH(enhanced_description)) AS avg_description_length,
    COUNT(*) * 0.05 AS hours_saved -- 3 min per product manual writing
  FROM \`${PROJECT_ID}.${DATASET_ID}.products\`
  WHERE enhanced_description IS NOT NULL
),
quality_stats AS (
  SELECT 
    COUNT(*) AS products_validated,
    SUM(CASE WHEN is_valid THEN 1 ELSE 0 END) AS valid_products,
    SUM(CASE WHEN NOT is_valid THEN 1 ELSE 0 END) * 50 AS potential_loss_prevented
  FROM \`${PROJECT_ID}.${DATASET_ID}.products\`
  WHERE is_valid IS NOT NULL
)
SELECT 
  enrichment_stats.*,
  quality_stats.*,
  hours_saved * 50 AS labor_cost_saved, -- $50/hour
  potential_loss_prevented AS quality_savings,
  (hours_saved * 50) + potential_loss_prevented AS total_monthly_savings,
  ((hours_saved * 50) + potential_loss_prevented) * 12 AS annual_savings
FROM enrichment_stats
CROSS JOIN quality_stats;

-- Template usage analytics
CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_ID}.template_analytics\` AS
SELECT 
  tl.category,
  tl.template_name,
  COUNT(pl.operation) AS usage_count,
  AVG(pm.processing_time_seconds) AS avg_processing_time,
  SUM(pm.records_processed) AS total_records_processed,
  AVG(tl.confidence_threshold) AS confidence_threshold
FROM \`${PROJECT_ID}.${DATASET_ID}.template_library\` tl
LEFT JOIN \`${PROJECT_ID}.${DATASET_ID}.processing_log\` pl
  ON tl.template_id = pl.operation
LEFT JOIN \`${PROJECT_ID}.${DATASET_ID}.performance_metrics\` pm
  ON pl.operation = pm.operation AND pl.timestamp = pm.timestamp
GROUP BY tl.category, tl.template_name
ORDER BY usage_count DESC;
EOF

execute_sql /tmp/create_views.sql "Creating monitoring views"

# Cleanup
rm -f /tmp/*.sql

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SETUP COMPLETE!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Next steps:"
echo "1. Create BigQuery connection (if not exists):"
echo "   bq mk --connection --location=$LOCATION --project_id=$PROJECT_ID --connection_type=CLOUD_RESOURCE gemini_connection"
echo ""
echo "2. Test the setup:"
echo "   bq query --use_legacy_sql=false --project_id=$PROJECT_ID 'SELECT * FROM \`$PROJECT_ID.$DATASET_ID.products\` LIMIT 5'"
echo ""
echo "3. Run enrichment:"
echo "   bq query --use_legacy_sql=false --project_id=$PROJECT_ID 'CALL \`$PROJECT_ID.$DATASET_ID.generate_product_descriptions\`(\"products\", 10)'"
echo ""
echo "4. Check ROI dashboard:"
echo "   bq query --use_legacy_sql=false --project_id=$PROJECT_ID 'SELECT * FROM \`$PROJECT_ID.$DATASET_ID.roi_dashboard\`'"
echo ""
echo -e "${GREEN}Ready to win $100K! 🚀${NC}"
