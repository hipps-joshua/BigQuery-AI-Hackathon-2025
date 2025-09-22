-- ============================================
-- SEMANTIC DETECTIVE - TEST QUERIES
-- ============================================
-- Validate all vector search and AI functions work correctly

-- Test 1: ML.GENERATE_EMBEDDING basic test
SELECT
  'test_embedding' AS test_name,
  ML.GENERATE_EMBEDDING(
    MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
    CONTENT => 'Nike running shoes black size 10',
    STRUCT(TRUE AS flatten_json_output)
  ).ml_generate_embedding_result AS embedding,
  ARRAY_LENGTH(
    ML.GENERATE_EMBEDDING(
      MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
      CONTENT => 'Nike running shoes black size 10',
      STRUCT(TRUE AS flatten_json_output)
    ).ml_generate_embedding_result
  ) AS embedding_dimension;

-- Test 2: Vector distance calculations
WITH test_embeddings AS (
  SELECT
    ML.GENERATE_EMBEDDING(
      MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
      CONTENT => 'Nike Air Max black running shoes',
      STRUCT(TRUE AS flatten_json_output)
    ).ml_generate_embedding_result AS embedding1,
    ML.GENERATE_EMBEDDING(
      MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
      CONTENT => 'Adidas Ultra Boost black running shoes',
      STRUCT(TRUE AS flatten_json_output)
    ).ml_generate_embedding_result AS embedding2,
    ML.GENERATE_EMBEDDING(
      MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
      CONTENT => 'Sony PlayStation 5 gaming console',
      STRUCT(TRUE AS flatten_json_output)
    ).ml_generate_embedding_result AS embedding3
)
SELECT
  ROUND(1 - ML.DISTANCE(embedding1, embedding2, 'COSINE'), 3) AS similar_shoes_score,
  ROUND(1 - ML.DISTANCE(embedding1, embedding3, 'COSINE'), 3) AS different_category_score,
  CASE 
    WHEN 1 - ML.DISTANCE(embedding1, embedding2, 'COSINE') > 
         1 - ML.DISTANCE(embedding1, embedding3, 'COSINE') 
    THEN 'PASS: Similar items have higher similarity'
    ELSE 'FAIL: Similarity scores incorrect'
  END AS test_result
FROM test_embeddings;

-- Test 3: Create test data with embeddings
CREATE OR REPLACE TABLE `${PROJECT_ID}.${DATASET_ID}.test_products_embedded` AS
WITH test_products AS (
  SELECT * FROM UNNEST([
    STRUCT('TEST_SHOE_001' AS sku, 'Nike' AS brand, 'Air Max 270' AS product, 'Black running shoes size 10' AS description, 159.99 AS price),
    STRUCT('TEST_SHOE_002', 'Nike', 'Air Max 270', 'Black running shoes size 11', 159.99),
    STRUCT('TEST_SHOE_003', 'Adidas', 'Ultra Boost', 'Black running shoes size 10', 189.99),
    STRUCT('TEST_ELEC_001', 'Apple', 'iPhone 14', 'Smartphone 128GB black', 799.99),
    STRUCT('TEST_ELEC_002', 'Samsung', 'Galaxy S23', 'Smartphone 128GB black', 749.99)
  ])
)
SELECT
  sku,
  brand,
  product,
  description,
  price,
  ML.GENERATE_EMBEDDING(
    MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
    CONTENT => CONCAT(brand, ' ', product, ' ', description),
    STRUCT(TRUE AS flatten_json_output)
  ).ml_generate_embedding_result AS embedding
FROM test_products;

-- Test 4: Semantic search test
WITH query_embedding AS (
  SELECT ML.GENERATE_EMBEDDING(
    MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
    CONTENT => 'black running shoes size 10',
    STRUCT(TRUE AS flatten_json_output)
  ).ml_generate_embedding_result AS embedding
),
search_results AS (
  SELECT
    p.sku,
    p.brand,
    p.product,
    p.description,
    ROUND(1 - ML.DISTANCE(p.embedding, q.embedding, 'COSINE'), 3) AS similarity
  FROM `${PROJECT_ID}.${DATASET_ID}.test_products_embedded` p
  CROSS JOIN query_embedding q
  ORDER BY similarity DESC
)
SELECT
  *,
  CASE 
    WHEN sku IN ('TEST_SHOE_001', 'TEST_SHOE_003') AND similarity > 0.8 
    THEN 'PASS: Found relevant shoes'
    WHEN sku IN ('TEST_ELEC_001', 'TEST_ELEC_002') AND similarity < 0.5
    THEN 'PASS: Electronics have low similarity'
    ELSE 'CHECK: Unexpected result'
  END AS test_result
FROM search_results;

-- Test 5: Duplicate detection test
WITH duplicate_check AS (
  SELECT
    p1.sku AS sku1,
    p2.sku AS sku2,
    p1.brand AS brand1,
    p2.brand AS brand2,
    p1.product AS product1,
    p2.product AS product2,
    ROUND(1 - ML.DISTANCE(p1.embedding, p2.embedding, 'COSINE'), 3) AS similarity
  FROM `${PROJECT_ID}.${DATASET_ID}.test_products_embedded` p1
  JOIN `${PROJECT_ID}.${DATASET_ID}.test_products_embedded` p2
  ON p1.sku < p2.sku
  WHERE 1 - ML.DISTANCE(p1.embedding, p2.embedding, 'COSINE') > 0.9
)
SELECT
  *,
  -- Should find TEST_SHOE_001 and TEST_SHOE_002 as duplicates
  CASE 
    WHEN sku1 = 'TEST_SHOE_001' AND sku2 = 'TEST_SHOE_002' AND similarity > 0.95
    THEN 'PASS: Detected size variants as duplicates'
    ELSE 'CHECK: Review duplicate detection'
  END AS test_result
FROM duplicate_check
ORDER BY similarity DESC;

-- Test 6: AI-enhanced validation
SELECT
  'AI Enhancement Test' AS test_name,
  AI.GENERATE_BOOL(
    'Are "Nike Air Max 270 Black Size 10" and "Nike Air Max 270 Black Size 11" the same product in different sizes?',
    connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
  ) AS same_product_check,
  
  ML.GENERATE_TEXT(
    MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_text_model`,
    PROMPT => 'Why would someone searching for "running shoes" be interested in "Nike Air Max 270"? (20 words max)',
    STRUCT(0.5 AS temperature, 30 AS max_output_tokens)
  ).generated_text AS search_relevance,
  
  AI.GENERATE_DOUBLE(
    'On a scale of 0-10, how good a substitute is "Adidas Ultra Boost" for "Nike Air Max 270"?',
    connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
  ) AS substitute_score;

-- Test 7: Vector index creation (DDL only, won't execute in test)
/*
CREATE OR REPLACE VECTOR INDEX `${PROJECT_ID}.${DATASET_ID}.test_embedding_idx`
ON `${PROJECT_ID}.${DATASET_ID}.test_products_embedded`(embedding)
OPTIONS(
  distance_type='COSINE',
  index_type='IVF',
  ivf_options='{"num_lists": 10}'
);
*/
SELECT 'Vector index DDL ready' AS test_status;

-- Test 8: Performance test with larger dataset
CREATE OR REPLACE TABLE `${PROJECT_ID}.${DATASET_ID}.performance_test_embeddings` AS
SELECT
  CONCAT('SKU_', CAST(ROW_NUMBER() OVER() AS STRING)) AS sku,
  CASE MOD(CAST(RAND() * 5 AS INT64), 5)
    WHEN 0 THEN 'Nike'
    WHEN 1 THEN 'Adidas'
    WHEN 2 THEN 'Puma'
    WHEN 3 THEN 'Reebok'
    ELSE 'New Balance'
  END AS brand,
  CONCAT(
    'Product description for item ',
    CAST(ROW_NUMBER() OVER() AS STRING),
    ' with random attributes ',
    CAST(RAND() AS STRING)
  ) AS description,
  ML.GENERATE_EMBEDDING(
    MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
    CONTENT => CONCAT(
      'Product ', CAST(ROW_NUMBER() OVER() AS STRING),
      ' Category: ', CAST(MOD(CAST(RAND() * 10 AS INT64), 10) AS STRING)
    ),
    STRUCT(TRUE AS flatten_json_output)
  ).ml_generate_embedding_result AS embedding
FROM UNNEST(GENERATE_ARRAY(1, 1000)) AS num;

-- Test 9: Batch processing performance
WITH timing AS (
  SELECT
    CURRENT_TIMESTAMP() AS start_time,
    COUNT(*) AS total_records
  FROM `${PROJECT_ID}.${DATASET_ID}.performance_test_embeddings`
),
search_test AS (
  SELECT
    p.sku,
    1 - ML.DISTANCE(
      p.embedding,
      (SELECT ML.GENERATE_EMBEDDING(
        MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
        CONTENT => 'Nike running shoes',
        STRUCT(TRUE AS flatten_json_output)
      ).ml_generate_embedding_result)
    , 'COSINE') AS similarity
  FROM `${PROJECT_ID}.${DATASET_ID}.performance_test_embeddings` p
  WHERE 1 - ML.DISTANCE(
    p.embedding,
    (SELECT ML.GENERATE_EMBEDDING(
      MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
      CONTENT => 'Nike running shoes',
      STRUCT(TRUE AS flatten_json_output)
    ).ml_generate_embedding_result),
    'COSINE'
  ) > 0.5
  LIMIT 100
)
SELECT
  (SELECT total_records FROM timing) AS records_searched,
  COUNT(*) AS results_found,
  CURRENT_TIMESTAMP() AS end_time,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), (SELECT start_time FROM timing), MILLISECOND) / 1000.0 AS search_time_seconds
FROM search_test;

-- Test 10: End-to-end workflow test
BEGIN
  -- Generate embeddings
  CALL `${PROJECT_ID}.${DATASET_ID}.generate_product_embeddings`('test_products', 10);
  
  -- Find duplicates
  CALL `${PROJECT_ID}.${DATASET_ID}.find_duplicate_products`('test_products', 0.9);
  
  -- Log results
  INSERT INTO `${PROJECT_ID}.${DATASET_ID}.test_results`
  SELECT
    'semantic_detective_e2e' AS test_name,
    CONCAT(
      'Embeddings: ', CAST(COUNT(*) AS STRING), 
      ', Duplicates: ', CAST((SELECT COUNT(*) FROM `${PROJECT_ID}.${DATASET_ID}.duplicate_candidates`) AS STRING)
    ) AS result,
    'SUCCESS' AS status,
    CURRENT_TIMESTAMP() AS timestamp
  FROM `${PROJECT_ID}.${DATASET_ID}.test_products_embeddings`;
  
EXCEPTION WHEN ERROR THEN
  INSERT INTO `${PROJECT_ID}.${DATASET_ID}.test_results`
  VALUES('semantic_detective_e2e', NULL, CONCAT('ERROR: ', @@error.message), CURRENT_TIMESTAMP());
END;

-- Test 11: Cross-sell recommendation test
WITH test_cross_sell AS (
  SELECT * FROM `${PROJECT_ID}.${DATASET_ID}.generate_cross_sell`(
    'TEST_SHOE_001',  -- Nike Air Max
    'fitness_enthusiast'
  )
)
SELECT
  'Cross-sell Test' AS test_name,
  COUNT(*) AS recommendations_count,
  STRING_AGG(CONCAT(brand_name, ' ', product_name), ', ' ORDER BY bundle_savings_percent DESC) AS recommended_products,
  CASE 
    WHEN COUNT(*) > 0 THEN 'PASS: Generated cross-sell recommendations'
    ELSE 'FAIL: No recommendations generated'
  END AS test_result
FROM test_cross_sell;

-- Test 12: Cost estimation
SELECT
  'Cost Estimate' AS scenario,
  1000000 AS products_to_embed,
  1000000 * 0.000005 AS embedding_generation_cost_usd,  -- ~$0.005 per 1K embeddings
  10000 AS searches_per_day,
  10000 * 0.000001 AS daily_search_cost_usd,  -- ~$0.001 per 1K searches
  1000000 * 0.000005 + (10000 * 30 * 0.000001) AS monthly_total_cost_usd,
  50000 AS duplicates_found_monthly_value,
  50000 - (1000000 * 0.000005 + (10000 * 30 * 0.000001)) AS monthly_roi_usd;

-- ============================================
-- TEST SUMMARY
-- ============================================
SELECT
  test_name,
  status,
  result,
  timestamp,
  CASE status
    WHEN 'SUCCESS' THEN '✅'
    WHEN 'ERROR' THEN '❌'
    ELSE '⚠️'
  END AS icon
FROM `${PROJECT_ID}.${DATASET_ID}.test_results`
WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
ORDER BY timestamp DESC;
