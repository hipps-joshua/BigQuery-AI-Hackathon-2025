# BigQuery AI Comprehensive Testing Guide

## 1. Initial Setup (One-Time)

### Set Environment Variables
```bash
export PROJECT_ID=bigquery-ai-hackathon-2025
export LOCATION=us-central1
export DATASET_ID=test_dataset_central
```

### Verify Setup
```bash
# Check authentication
gcloud auth list

# Set project
gcloud config set project $PROJECT_ID

# Enable required APIs
gcloud services enable aiplatform.googleapis.com
gcloud services enable bigquery.googleapis.com
```

## 2. Quick Test Scripts

### Create a simple test script
```bash
cat > run_basic_test.sh << 'SCRIPT'
#!/bin/bash

PROJECT_ID=bigquery-ai-hackathon-2025
LOCATION=us-central1
DATASET_ID=test_dataset_central

echo "Testing AI.GENERATE..."
bq query --use_legacy_sql=false "
SELECT AI.GENERATE(
  'Write a haiku about cloud computing',
  connection_id => '$PROJECT_ID.$LOCATION.gemini_connection'
).result as haiku;"

echo "Testing Embeddings..."
bq query --use_legacy_sql=false "
SELECT ARRAY_LENGTH(ml_generate_embedding_result) as embedding_dimension
FROM ML.GENERATE_EMBEDDING(
  MODEL \`$PROJECT_ID.$DATASET_ID.gemini_embedding_model\`,
  (SELECT 'test text' AS content)
);"
SCRIPT

chmod +x run_basic_test.sh
```

## 3. Run Comprehensive E-Commerce Test

### Step-by-Step Commands

#### A. Create Product Catalog (50 products)
```bash
bq query --use_legacy_sql=false < create_catalog.sql
```

#### B. Generate Embeddings
```bash
bq query --use_legacy_sql=false "
CREATE OR REPLACE TABLE \`$PROJECT_ID.$DATASET_ID.product_embeddings\` AS
WITH products_sample AS (
  SELECT 
    sku, name, category, price,
    CONCAT(name, ' ', category, ' ', description) AS content
  FROM \`$PROJECT_ID.$DATASET_ID.product_catalog\`
  LIMIT 10  -- Start small
)
SELECT *, ml_generate_embedding_result as embedding
FROM ML.GENERATE_EMBEDDING(
  MODEL \`$PROJECT_ID.$DATASET_ID.gemini_embedding_model\`,
  (SELECT * FROM products_sample)
);"
```

#### C. Run AI Analysis
```bash
bq query --use_legacy_sql=false "
SELECT 
  name,
  category,
  price,
  -- Market positioning
  AI.GENERATE(
    CONCAT('In 15 words, describe market position for: ', name),
    connection_id => '$PROJECT_ID.$LOCATION.gemini_connection'
  ).result as positioning,
  -- Pricing analysis  
  AI.GENERATE_BOOL(
    CONCAT('Is this well-priced? ', name, ' at \$', CAST(price AS STRING)),
    connection_id => '$PROJECT_ID.$LOCATION.gemini_connection'
  ).result as good_value,
  -- Quality score
  AI.GENERATE_DOUBLE(
    CONCAT('Rate appeal 1-10: ', name),
    connection_id => '$PROJECT_ID.$LOCATION.gemini_connection'
  ).result as appeal_score
FROM \`$PROJECT_ID.$DATASET_ID.product_catalog\`
LIMIT 5;"
```

## 4. Python/Colab Alternative

Create a new Colab notebook and run:

```python
from google.cloud import bigquery
from google.colab import auth

# Authenticate
auth.authenticate_user()

# Initialize client
project_id = 'bigquery-ai-hackathon-2025'
client = bigquery.Client(project=project_id)

# Test AI functions
query = """
SELECT 
  'iPhone 15' as product,
  AI.GENERATE(
    'Write a 20-word marketing tagline for iPhone 15',
    connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
  ).result as tagline
"""

results = client.query(query).to_dataframe()
print(results)
```

## 5. Cost-Optimized Testing

### Small-Scale Tests First
```bash
# Test with 5 products
bq query --use_legacy_sql=false "
WITH test_products AS (
  SELECT * FROM \`$PROJECT_ID.$DATASET_ID.product_catalog\` 
  LIMIT 5
)
SELECT name, category, price
FROM test_products;"
```

### Monitor Costs
```bash
# Check query costs
bq ls -j -a -n 10 | grep "Total bytes"

# Estimate costs before running
bq query --dry_run --use_legacy_sql=false "YOUR_QUERY_HERE"
```

## 6. Gradual Complexity Increase

### Level 1: Basic AI Generation (1 product)
```sql
SELECT AI.GENERATE('Describe running shoes in 10 words', 
  connection_id => 'PROJECT.LOCATION.gemini_connection').result;
```

### Level 2: Multiple AI Functions (5 products)
```sql
SELECT name, 
  AI.GENERATE(...).result as description,
  AI.GENERATE_BOOL(...).result as premium,
  AI.GENERATE_DOUBLE(...).result as score
FROM products LIMIT 5;
```

### Level 3: Embeddings + Search (20 products)
```sql
-- Create embeddings
CREATE TABLE embeddings AS 
SELECT *, ML.GENERATE_EMBEDDING(...) 
FROM products LIMIT 20;

-- Semantic search
WITH query AS (...)
SELECT * FROM embeddings 
WHERE similarity > 0.5;
```

### Level 4: Full Integration (50+ products)
```sql
-- Complete analysis with all approaches
WITH personas AS (...),
     recommendations AS (...),
     insights AS (...)
SELECT * FROM final_report;
```

## 7. Troubleshooting

### Common Issues & Solutions

**Error: "Model not found"**
```bash
# Recreate models
bq query --use_legacy_sql=false "
CREATE OR REPLACE MODEL \`$PROJECT_ID.$DATASET_ID.gemini_text_model\`
REMOTE WITH CONNECTION \`$PROJECT_ID.$LOCATION.gemini_connection\`
OPTIONS (endpoint = 'gemini-2.0-flash-exp');"
```

**Error: "Permission denied"**
```bash
# Grant permissions
CONNECTION_SA=$(bq show --connection --location=$LOCATION \
  --project_id=$PROJECT_ID gemini_connection | \
  grep serviceAccountId | cut -d'"' -f4)
  
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${CONNECTION_SA}" \
  --role="roles/aiplatform.user"
```

**Slow queries**
- Reduce LIMIT values
- Process in batches
- Use sampling: TABLESAMPLE SYSTEM (10 PERCENT)

## 8. Save Results

### Export to CSV
```bash
bq query --format=csv --use_legacy_sql=false "YOUR_QUERY" > results.csv
```

### Save to Table
```bash
bq query --use_legacy_sql=false "
CREATE OR REPLACE TABLE \`$PROJECT_ID.$DATASET_ID.analysis_results\` AS
YOUR_QUERY_HERE;"
```

### Export to GCS
```bash
bq extract --destination_format=CSV \
  $PROJECT_ID:$DATASET_ID.analysis_results \
  gs://your-bucket/results.csv
```

## 9. Production Tips

1. **Start Small**: Test with 5-10 rows before scaling
2. **Use LIMIT**: Always limit results during testing
3. **Monitor Costs**: Check BigQuery console for query costs
4. **Batch Operations**: Group multiple AI calls
5. **Cache Results**: Save expensive computations to tables
6. **Use Partitioning**: For large datasets, partition by date
7. **Schedule Queries**: Use scheduled queries for regular analysis

## 10. Complete Test Suite

Run all tests in sequence:
```bash
# 1. Setup
./setup_connection.sh

# 2. Create data
./create_test_data.sh

# 3. Run basic tests
./run_basic_test.sh

# 4. Run advanced analysis
./run_advanced_analysis.sh

# 5. Check results
bq query --use_legacy_sql=false "
SELECT COUNT(*) as products,
       AVG(price) as avg_price,
       COUNT(DISTINCT category) as categories
FROM \`$PROJECT_ID.$DATASET_ID.product_catalog\`;"
```
