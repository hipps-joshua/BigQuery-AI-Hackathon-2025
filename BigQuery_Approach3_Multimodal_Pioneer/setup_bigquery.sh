#!/bin/bash

# ============================================
# MULTIMODAL PIONEER - BIGQUERY SETUP SCRIPT
# ============================================
# This script sets up everything needed for Approach 3
# Usage: ./setup_bigquery.sh PROJECT_ID DATASET_ID BUCKET_NAME

set -e  # Exit on error

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Check arguments
if [ $# -ne 3 ]; then
    echo -e "${RED}Usage: $0 PROJECT_ID DATASET_ID BUCKET_NAME${NC}"
    echo "Example: $0 my-project multimodal-pioneer my-product-images"
    exit 1
fi

PROJECT_ID=$1
DATASET_ID=$2
BUCKET_NAME=$3
LOCATION="us-central1"

echo -e "${PURPLE}========================================${NC}"
echo -e "${PURPLE}🖼️ MULTIMODAL PIONEER - BIGQUERY SETUP${NC}"
echo -e "${PURPLE}========================================${NC}"
echo "Project ID: $PROJECT_ID"
echo "Dataset ID: $DATASET_ID"
echo "Bucket Name: $BUCKET_NAME"
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
        -e "s/\${BUCKET_NAME}/$BUCKET_NAME/g" \
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

# Step 1: Create GCS bucket for images
echo -e "${YELLOW}Step 1: Setting up Cloud Storage bucket...${NC}"
if gsutil ls -p "$PROJECT_ID" "gs://$BUCKET_NAME" &>/dev/null; then
    echo -e "${YELLOW}Bucket gs://$BUCKET_NAME already exists${NC}"
else
    echo "Creating bucket gs://$BUCKET_NAME..."
    gsutil mb -p "$PROJECT_ID" -l "$LOCATION" "gs://$BUCKET_NAME"
fi

# Create folder structure
gsutil -m rsync -d -r /dev/null "gs://$BUCKET_NAME/product_images/" 2>/dev/null || true
gsutil -m rsync -d -r /dev/null "gs://$BUCKET_NAME/compliance_reference/" 2>/dev/null || true
gsutil -m rsync -d -r /dev/null "gs://$BUCKET_NAME/quality_examples/" 2>/dev/null || true

echo -e "${GREEN}✓ Bucket structure created${NC}"

# Step 2: Create dataset
echo -e "${YELLOW}Step 2: Creating dataset...${NC}"
bq mk \
    --project_id="$PROJECT_ID" \
    --location="$LOCATION" \
    --dataset \
    --description="Multimodal Pioneer - Visual Intelligence for E-commerce" \
    "$PROJECT_ID:$DATASET_ID" 2>/dev/null || {
        echo -e "${YELLOW}Dataset already exists, continuing...${NC}"
    }

# Step 3: Create base tables
echo -e "${YELLOW}Step 3: Creating base tables...${NC}"
execute_sql "
-- Products table with image references
CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET_ID}.products\` (
  sku STRING NOT NULL,
  brand_name STRING,
  product_name STRING,
  description STRING,
  category STRING,
  subcategory STRING,
  price FLOAT64,
  cost FLOAT64,
  listed_color STRING,
  listed_size STRING,
  listed_material STRING,
  weight_kg FLOAT64,
  dimensions_cm STRUCT<length FLOAT64, width FLOAT64, height FLOAT64>,
  image_filename STRING,  -- Reference to object table
  image_url STRING,       -- Full GCS URI
  compliance_required BOOL DEFAULT FALSE,
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

-- QC run log
CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET_ID}.qc_run_log\` (
  qc_run_id STRING,
  run_timestamp TIMESTAMP,
  products_analyzed INT64,
  issues_found INT64,
  total_risk_value FLOAT64,
  avg_quality_score FLOAT64,
  compliance_violations INT64,
  counterfeit_suspects INT64
);

-- Visual search log
CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET_ID}.visual_search_log\` (
  search_id STRING DEFAULT GENERATE_UUID(),
  query_image_uri STRING,
  search_mode STRING,
  results_returned INT64,
  avg_similarity_score FLOAT64,
  search_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  user_action STRING,
  clicked_sku STRING
);

-- Test results
CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET_ID}.test_results\` (
  test_name STRING,
  result STRING,
  status STRING,
  timestamp TIMESTAMP
);

-- Compliance rules by category
CREATE TABLE IF NOT EXISTS \`${PROJECT_ID}.${DATASET_ID}.compliance_rules\` (
  category STRING,
  required_labels ARRAY<STRING>,
  min_image_quality FLOAT64,
  special_requirements STRING
);
" "Creating base tables"

# Step 4: Create AI models
echo -e "${YELLOW}Step 4: Creating AI models...${NC}"
echo -e "${YELLOW}Note: Ensure you have created a connection:${NC}"
echo "bq mk --connection --location=$LOCATION --project_id=$PROJECT_ID --connection_type=CLOUD_RESOURCE gemini_connection"
echo ""

execute_sql "
-- Vision model for image analysis
CREATE OR REPLACE MODEL \`${PROJECT_ID}.${DATASET_ID}.vision_model\`
REMOTE WITH CONNECTION \`${PROJECT_ID}.${LOCATION}.gemini_connection\`
OPTIONS (
  endpoint = 'gemini-1.5-pro-vision-001'
);

-- Gemini Pro Vision for detailed analysis
CREATE OR REPLACE MODEL \`${PROJECT_ID}.${DATASET_ID}.gemini_pro_vision_model\`
REMOTE WITH CONNECTION \`${PROJECT_ID}.${LOCATION}.gemini_connection\`
OPTIONS (
  endpoint = 'gemini-1.5-pro-vision-001'
);

-- Text embedding model
CREATE OR REPLACE MODEL \`${PROJECT_ID}.${DATASET_ID}.text_embedding_model\`
REMOTE WITH CONNECTION \`${PROJECT_ID}.${LOCATION}.gemini_connection\`
OPTIONS (
  endpoint = 'text-embedding-004'
);

-- Multimodal embedding model
CREATE OR REPLACE MODEL \`${PROJECT_ID}.${DATASET_ID}.multimodal_embedding_model\`
REMOTE WITH CONNECTION \`${PROJECT_ID}.${LOCATION}.gemini_connection\`
OPTIONS (
  endpoint = 'multimodalembedding@001'
);

-- Standard Gemini for text generation
CREATE OR REPLACE MODEL \`${PROJECT_ID}.${DATASET_ID}.gemini_pro_model\`
REMOTE WITH CONNECTION \`${PROJECT_ID}.${LOCATION}.gemini_connection\`
OPTIONS (
  endpoint = 'gemini-1.5-pro-001'
);
" "Creating AI models" || {
    echo -e "${YELLOW}Model creation failed - ensure connection exists${NC}"
}

# Step 5: Create Object Tables
echo -e "${YELLOW}Step 5: Creating Object Tables...${NC}"
execute_sql "
-- Create Object Table for product images
CREATE OR REPLACE EXTERNAL TABLE \`${PROJECT_ID}.${DATASET_ID}.product_images\`
OPTIONS (
  format = 'OBJECT_TABLE',
  uris = ['gs://${BUCKET_NAME}/product_images/*']
);

-- Create Object Table with metadata
CREATE OR REPLACE EXTERNAL TABLE \`${PROJECT_ID}.${DATASET_ID}.product_images_metadata\`
OPTIONS (
  object_metadata = 'SIMPLE',
  uris = ['gs://${BUCKET_NAME}/product_images/*']
);

-- Compliance reference images
CREATE OR REPLACE EXTERNAL TABLE \`${PROJECT_ID}.${DATASET_ID}.compliance_reference_images\`
OPTIONS (
  format = 'OBJECT_TABLE',
  uris = ['gs://${BUCKET_NAME}/compliance_reference/*']
);

-- Quality example images
CREATE OR REPLACE EXTERNAL TABLE \`${PROJECT_ID}.${DATASET_ID}.quality_example_images\`
OPTIONS (
  format = 'OBJECT_TABLE', 
  uris = ['gs://${BUCKET_NAME}/quality_examples/*']
);
" "Creating Object Tables"

# Step 6: Load sample data
echo -e "${YELLOW}Step 6: Loading sample data...${NC}"

# Upload sample images (create dummy files for demo)
echo -e "${YELLOW}Creating sample image references...${NC}"
for i in {1..10}; do
    echo "Sample product image $i" > /tmp/product_$i.txt
done
gsutil -m cp /tmp/product_*.txt "gs://$BUCKET_NAME/product_images/" 2>/dev/null || true
rm -f /tmp/product_*.txt

execute_sql "
-- Insert sample products with multimodal data
INSERT INTO \`${PROJECT_ID}.${DATASET_ID}.products\` 
(sku, brand_name, product_name, category, subcategory, price, listed_color, listed_size, listed_material, 
 image_filename, image_url, compliance_required, description)
VALUES
  -- Electronics (compliance required)
  ('ELEC001', 'Apple', 'iPhone 14 Pro', 'Electronics', 'Smartphones', 999.99, 'Space Black', '128GB', 'Glass/Aluminum',
   'product_1.txt', 'gs://${BUCKET_NAME}/product_images/product_1.txt', TRUE,
   'Latest iPhone with ProMotion display and advanced camera system.'),
   
  ('ELEC002', 'Samsung', 'Galaxy S23', 'Electronics', 'Smartphones', 899.99, 'Phantom Black', '256GB', 'Glass/Metal',
   'product_2.txt', 'gs://${BUCKET_NAME}/product_images/product_2.txt', TRUE,
   'Flagship Android phone with AI-powered features.'),
   
  -- Toys (age warning required)
  ('TOY001', 'LEGO', 'Creator Expert', 'Toys', 'Building Sets', 299.99, 'Multicolor', '3000 pieces', 'Plastic',
   'product_3.txt', 'gs://${BUCKET_NAME}/product_images/product_3.txt', TRUE,
   'Advanced building set for ages 16+. Small parts warning.'),
   
  -- Apparel (quality focus)
  ('APP001', 'Nike', 'Air Zoom Pegasus', 'Footwear', 'Running Shoes', 129.99, 'Black/White', '10', 'Mesh/Rubber',
   'product_4.txt', 'gs://${BUCKET_NAME}/product_images/product_4.txt', FALSE,
   'Responsive cushioning and secure fit for daily runs.'),
   
  ('APP002', 'Nike', 'Air Zoom Pegasus', 'Footwear', 'Running Shoes', 129.99, 'Blue/White', '10', 'Mesh/Rubber',
   'product_5.txt', 'gs://${BUCKET_NAME}/product_images/product_5.txt', FALSE,
   'Same shoe, different colorway - potential duplicate.'),
   
  -- Counterfeit test
  ('APP003', 'Nike', 'Air Max', 'Footwear', 'Running Shoes', 49.99, 'Black', '10', 'Synthetic',
   'product_6.txt', 'gs://${BUCKET_NAME}/product_images/product_6.txt', FALSE,
   'Suspiciously cheap Nike product.'),
   
  -- Food (compliance critical)
  ('FOOD001', 'Nestle', 'Protein Bar', 'Food', 'Nutrition', 2.99, 'Brown', '50g', 'Various',
   'product_7.txt', 'gs://${BUCKET_NAME}/product_images/product_7.txt', TRUE,
   'High protein snack bar. Contains nuts and dairy.'),
   
  -- Cosmetics (ingredient list required)
  ('COSM001', 'LOreal', 'Face Cream', 'Cosmetics', 'Skincare', 39.99, 'White', '50ml', 'Cream',
   'product_8.txt', 'gs://${BUCKET_NAME}/product_images/product_8.txt', TRUE,
   'Anti-aging cream with retinol. FDA approved.'),
   
  -- Home goods
  ('HOME001', 'Dyson', 'V15 Vacuum', 'Home', 'Appliances', 649.99, 'Purple', 'Standard', 'Plastic/Metal',
   'product_9.txt', 'gs://${BUCKET_NAME}/product_images/product_9.txt', FALSE,
   'Advanced cordless vacuum with laser detection.'),
   
  -- Sports equipment
  ('SPORT001', 'Wilson', 'Tennis Racket', 'Sports', 'Tennis', 199.99, 'Black/Red', 'L3', 'Carbon Fiber',
   'product_10.txt', 'gs://${BUCKET_NAME}/product_images/product_10.txt', FALSE,
   'Professional grade tennis racket for advanced players.');

-- Insert compliance rules
INSERT INTO \`${PROJECT_ID}.${DATASET_ID}.compliance_rules\`
(category, required_labels, min_image_quality, special_requirements)
VALUES
  ('Electronics', ['FCC label', 'Model number', 'Safety warnings'], 7.0, 'Must show all regulatory labels'),
  ('Toys', ['Age warning', 'Choking hazard', 'CE mark'], 7.0, 'Clear visibility of safety warnings'),
  ('Food', ['Nutrition facts', 'Ingredients', 'Expiration', 'Allergens'], 8.0, 'All text must be legible'),
  ('Cosmetics', ['Ingredients', 'FDA statement', 'Warning labels'], 8.0, 'Complete ingredient list visible');
" "Loading sample data"

# Step 7: Create stored procedures
echo -e "${YELLOW}Step 7: Creating stored procedures and functions...${NC}"
if [ -f "./sql/production_queries.sql" ]; then
    execute_sql "$(cat ./sql/production_queries.sql)" "Creating production queries"
else
    echo -e "${RED}Warning: production_queries.sql not found${NC}"
fi

# Step 8: Run initial setup procedures
echo -e "${YELLOW}Step 8: Running initial setup procedures...${NC}"
execute_sql "
-- Create object tables for the bucket
CALL \`${PROJECT_ID}.${DATASET_ID}.create_image_object_tables\`(
  '${BUCKET_NAME}',
  'product_images'
);
" "Setting up object tables" || {
    echo -e "${YELLOW}Object tables will be created when procedures are ready${NC}"
}

# Step 9: Generate initial embeddings
echo -e "${YELLOW}Step 9: Building visual search index...${NC}"
execute_sql "
-- Build visual embeddings for sample products
CALL \`${PROJECT_ID}.${DATASET_ID}.build_visual_search_index\`(
  'products',
  10
);
" "Building visual search index" || {
    echo -e "${YELLOW}Visual search index will be built when ready${NC}"
}

# Step 10: Create monitoring dashboards
echo -e "${YELLOW}Step 10: Creating monitoring dashboards...${NC}"
execute_sql "
-- QC effectiveness view
CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_ID}.qc_effectiveness\` AS
SELECT
  DATE(run_timestamp) AS date,
  COUNT(*) AS qc_runs,
  SUM(products_analyzed) AS products_checked,
  SUM(compliance_violations) AS compliance_issues_found,
  SUM(counterfeit_suspects) AS counterfeits_detected,
  ROUND(AVG(avg_quality_score), 1) AS avg_quality_score,
  SUM(total_risk_value) AS risk_prevented_usd
FROM \`${PROJECT_ID}.${DATASET_ID}.qc_run_log\`
WHERE run_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY date
ORDER BY date DESC;

-- Visual search performance
CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_ID}.visual_search_performance\` AS
SELECT
  DATE(search_timestamp) AS date,
  search_mode,
  COUNT(*) AS searches,
  AVG(results_returned) AS avg_results,
  ROUND(AVG(avg_similarity_score), 3) AS avg_similarity,
  COUNT(DISTINCT query_image_uri) AS unique_images,
  SUM(CASE WHEN clicked_sku IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS click_through_rate
FROM \`${PROJECT_ID}.${DATASET_ID}.visual_search_log\`
WHERE search_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY date, search_mode
ORDER BY date DESC, searches DESC;

-- ROI summary
CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_ID}.multimodal_roi_summary\` AS
WITH monthly_metrics AS (
  SELECT
    -- QC savings
    (SELECT SUM(total_risk_value) FROM \`${PROJECT_ID}.${DATASET_ID}.qc_run_log\`
     WHERE run_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)) AS risk_prevented,
    
    -- Time savings (5 min per product manual QC)
    (SELECT SUM(products_analyzed) * 5 / 60 * 50  -- $50/hour
     FROM \`${PROJECT_ID}.${DATASET_ID}.qc_run_log\`
     WHERE run_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)) AS labor_saved,
     
    -- Visual search value (20% conversion lift assumption)
    (SELECT COUNT(*) * 100 * 0.2  -- $100 avg order * 20% lift
     FROM \`${PROJECT_ID}.${DATASET_ID}.visual_search_log\`
     WHERE search_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)) AS search_revenue_lift
)
SELECT
  ROUND(risk_prevented, 2) AS compliance_risk_prevented,
  ROUND(labor_saved, 2) AS qc_labor_costs_saved,
  ROUND(search_revenue_lift, 2) AS visual_search_revenue,
  ROUND(risk_prevented + labor_saved + search_revenue_lift, 2) AS total_monthly_value,
  ROUND((risk_prevented + labor_saved + search_revenue_lift) * 12, 2) AS annual_value
FROM monthly_metrics;
" "Creating monitoring views"

# Step 11: Run validation tests
echo -e "${YELLOW}Step 11: Running validation tests...${NC}"
if [ -f "./sql/test_queries.sql" ]; then
    execute_sql "$(cat ./sql/test_queries.sql)" "Running tests" || {
        echo -e "${YELLOW}Some tests may fail until images are uploaded${NC}"
    }
else
    echo -e "${RED}Warning: test_queries.sql not found${NC}"
fi

# Step 12: Create monitoring and alerting
echo -e "${YELLOW}Step 12: Creating monitoring and alerting infrastructure...${NC}"
if [ -f "./sql/monitoring_queries.sql" ]; then
    execute_sql "$(cat ./sql/monitoring_queries.sql)" "Creating monitoring queries"
else
    echo -e "${RED}Warning: monitoring_queries.sql not found${NC}"
fi

# Cleanup and summary
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}🎉 MULTIMODAL PIONEER SETUP COMPLETE!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Next steps:"
echo ""
echo "1. Upload product images to your bucket:"
echo -e "${PURPLE}   gsutil -m cp /path/to/images/* gs://$BUCKET_NAME/product_images/${NC}"
echo ""
echo "2. Run quality control analysis:"
echo -e "${PURPLE}   bq query --use_legacy_sql=false --project_id=$PROJECT_ID \\
   \"CALL \\\`$PROJECT_ID.$DATASET_ID.run_visual_quality_control\\\`('products', 7.0)\"${NC}"
echo ""
echo "3. Test visual search:"
echo -e "${PURPLE}   bq query --use_legacy_sql=false --project_id=$PROJECT_ID \\
   \"SELECT * FROM \\\`$PROJECT_ID.$DATASET_ID.visual_search\\\`(
      'gs://$BUCKET_NAME/product_images/query_image.jpg',
      '$PROJECT_ID.$DATASET_ID.products_visual_embeddings',
      'visual',
      10,
      JSON '{\"category\": \"Footwear\"}'
   )\"${NC}"
echo ""
echo "4. Check QC results:"
echo -e "${PURPLE}   bq query --use_legacy_sql=false --project_id=$PROJECT_ID \\
   \"SELECT * FROM \\\`$PROJECT_ID.$DATASET_ID.quality_control_results\\\` 
    WHERE action_required != 'Pass' 
    ORDER BY potential_loss DESC\"${NC}"
echo ""
echo "5. View ROI dashboard:"
echo -e "${PURPLE}   bq query --use_legacy_sql=false --project_id=$PROJECT_ID \\
   \"SELECT * FROM \\\`$PROJECT_ID.$DATASET_ID.multimodal_roi_summary\\\`\"${NC}"
echo ""
echo -e "${GREEN}Ready to revolutionize e-commerce with visual intelligence! 🖼️🚀${NC}"
