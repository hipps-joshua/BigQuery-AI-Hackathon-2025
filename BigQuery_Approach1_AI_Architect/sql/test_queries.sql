-- ============================================
-- AI ARCHITECT - TEST QUERIES
-- ============================================
-- Run these to validate all functions work correctly

-- Test 1: Basic ML.GENERATE_TEXT via remote model
SELECT 
  'TEST_SKU_001' AS sku,
  ML.GENERATE_TEXT(
    MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_text_model`,
    PROMPT => 'Generate a 50-word product description for: Nike Air Max Running Shoes, Black, Size 10',
    STRUCT(
      0.7 AS temperature,
      60 AS max_output_tokens
    )
  ).generated_text AS test_description;

-- Test 2: AI.GENERATE_TABLE for attribute extraction
WITH test_product AS (
  SELECT 'The Nike Air Zoom Pegasus 40 mens running shoes feature a breathable mesh upper, Zoom Air cushioning, and a durable rubber outsole. Available in size 10.5, black/white colorway. Weight: 10.2 oz. Includes 1-year warranty.' AS description
)
SELECT 
  AI.GENERATE_TABLE(
    PROMPT => CONCAT(
      'Extract attributes and return columns: brand, model, size, color, weight_oz, warranty_months\n',
      'Text: ', description
    ),
    connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
  ).*
FROM test_product;

-- Test 3: AI.GENERATE_BOOL for validation
SELECT
  AI.GENERATE_BOOL(
    'Is $999 a reasonable price for basic running shoes? Answer TRUE or FALSE only.',
    connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
  ) AS price_validation,
  
  AI.GENERATE_BOOL(
    'Does "SALE! LIMITED TIME OFFER!" contain promotional language?',
    connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
  ) AS promo_check;

-- Test 4: AI.GENERATE_INT and AI.GENERATE_DOUBLE
SELECT
  AI.GENERATE_INT(
    'Extract the warranty period in months from: "Includes 24-month manufacturer warranty"',
    connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
  ) AS warranty_months,
  
  AI.GENERATE_DOUBLE(
    'Extract the weight in pounds from: "Product weight: 2.5 lbs"',
    connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
  ) AS weight_lbs;

-- Test 5: AI.FORECAST with sample data
-- First create sample time series data
CREATE OR REPLACE TABLE `${PROJECT_ID}.${DATASET_ID}.test_sales_data` AS
SELECT 
  DATE_SUB(CURRENT_DATE(), INTERVAL days DAY) AS date,
  'TEST_SKU_001' AS sku,
  CAST(100 + RAND() * 50 + (days * 0.5) AS INT64) AS quantity
FROM UNNEST(GENERATE_ARRAY(1, 180)) AS days;

-- Create and test forecast model
CREATE OR REPLACE MODEL `${PROJECT_ID}.${DATASET_ID}.test_forecast_model`
OPTIONS(
  model_type='ARIMA_PLUS',
  time_series_timestamp_col='date',
  time_series_data_col='quantity',
  time_series_id_col='sku'
) AS
SELECT * FROM `${PROJECT_ID}.${DATASET_ID}.test_sales_data`;

-- Generate forecast
SELECT * FROM ML.FORECAST(
  MODEL `${PROJECT_ID}.${DATASET_ID}.test_forecast_model`,
  STRUCT(30 AS horizon, 0.95 AS confidence_level)
)
LIMIT 10;

-- Test 6: Batch processing with error handling
BEGIN
  DECLARE test_result STRING;
  
  -- Test with valid data
  BEGIN
    SET test_result = (
      SELECT ML.GENERATE_TEXT(
        MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_text_model`,
        PROMPT => 'Say "Hello BigQuery"',
        STRUCT(0.1 AS temperature, 10 AS max_output_tokens)
      ).generated_text
    );
    
    INSERT INTO `${PROJECT_ID}.${DATASET_ID}.test_results` 
    VALUES('generate_text_valid', test_result, 'SUCCESS', CURRENT_TIMESTAMP());
    
  EXCEPTION WHEN ERROR THEN
    INSERT INTO `${PROJECT_ID}.${DATASET_ID}.test_results` 
    VALUES('generate_text_valid', NULL, CONCAT('ERROR: ', @@error.message), CURRENT_TIMESTAMP());
  END;
  
  -- Test with invalid model (should fail gracefully)
  BEGIN
    SET test_result = (
      SELECT ML.GENERATE_TEXT(
        MODEL `${PROJECT_ID}.${DATASET_ID}.nonexistent_model`,
        PROMPT => 'This should fail',
        STRUCT(0.1 AS temperature)
      ).generated_text
    );
    
  EXCEPTION WHEN ERROR THEN
    INSERT INTO `${PROJECT_ID}.${DATASET_ID}.test_results` 
    VALUES('generate_text_invalid', NULL, 'ERROR_HANDLED', CURRENT_TIMESTAMP());
  END;
END;

-- Test 7: Performance benchmark
CREATE OR REPLACE TABLE `${PROJECT_ID}.${DATASET_ID}.performance_test` AS
WITH test_batch AS (
  SELECT 
    GENERATE_UUID() AS sku,
    CONCAT('Product ', CAST(ROW_NUMBER() OVER() AS STRING)) AS product_name
  FROM UNNEST(GENERATE_ARRAY(1, 100)) -- Test with 100 rows
),
timed_execution AS (
  SELECT 
    sku,
    product_name,
    CURRENT_TIMESTAMP() AS start_time,
    ML.GENERATE_TEXT(
      MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_text_model`,
      PROMPT => CONCAT('Generate a 30-word description for: ', product_name),
      STRUCT(0.5 AS temperature, 40 AS max_output_tokens)
    ).generated_text AS description,
    CURRENT_TIMESTAMP() AS end_time
  FROM test_batch
)
SELECT 
  COUNT(*) AS records_processed,
  MIN(start_time) AS batch_start,
  MAX(end_time) AS batch_end,
  TIMESTAMP_DIFF(MAX(end_time), MIN(start_time), MILLISECOND) / 1000.0 AS total_seconds,
  COUNT(*) / (TIMESTAMP_DIFF(MAX(end_time), MIN(start_time), MILLISECOND) / 1000.0) AS records_per_second
FROM timed_execution;

-- Test 8: Validate all template categories work
CREATE OR REPLACE TABLE `${PROJECT_ID}.${DATASET_ID}.template_validation` AS
SELECT 
  category,
  COUNT(*) AS template_count,
  COUNT(DISTINCT parameters) AS unique_param_sets,
  AVG(confidence_threshold) AS avg_confidence
FROM `${PROJECT_ID}.${DATASET_ID}.template_library`
GROUP BY category
ORDER BY template_count DESC;

-- Test 9: End-to-end workflow test
CALL `${PROJECT_ID}.${DATASET_ID}.execute_template_workflow`(
  'test_enrichment_workflow',
  'test_products'
);

-- Verify results
SELECT 
  'Enrichment Test' AS test_name,
  COUNT(*) AS records_processed,
  COUNT(enhanced_description) AS descriptions_generated,
  AVG(LENGTH(enhanced_description)) AS avg_description_length,
  COUNT(*) - COUNT(enhanced_description) AS failed_count
FROM `${PROJECT_ID}.${DATASET_ID}.test_products_with_descriptions`;

-- Test 10: Cost estimation
SELECT 
  'Test Run Cost Estimate' AS scenario,
  1000000 AS product_count,
  `${PROJECT_ID}.${DATASET_ID}.estimate_ai_cost`(1000000, 200, 'generate_text') AS text_generation_cost,
  `${PROJECT_ID}.${DATASET_ID}.estimate_ai_cost`(1000000, 0, 'generate_bool') AS validation_cost,
  `${PROJECT_ID}.${DATASET_ID}.estimate_ai_cost`(10000, 0, 'forecast') AS forecast_cost,
  `${PROJECT_ID}.${DATASET_ID}.estimate_ai_cost`(1000000, 200, 'generate_text') +
  `${PROJECT_ID}.${DATASET_ID}.estimate_ai_cost`(1000000, 0, 'generate_bool') +
  `${PROJECT_ID}.${DATASET_ID}.estimate_ai_cost`(10000, 0, 'forecast') AS total_estimated_cost;

-- ============================================
-- VALIDATION CHECKLIST
-- ============================================
-- Run this query to see overall test status
WITH test_summary AS (
  SELECT 
    test_name,
    status,
    timestamp,
    ROW_NUMBER() OVER (PARTITION BY test_name ORDER BY timestamp DESC) AS rn
  FROM `${PROJECT_ID}.${DATASET_ID}.test_results`
)
SELECT 
  test_name,
  status,
  timestamp,
  CASE status 
    WHEN 'SUCCESS' THEN '✅'
    WHEN 'ERROR_HANDLED' THEN '⚠️'
    ELSE '❌'
  END AS result
FROM test_summary
WHERE rn = 1
ORDER BY timestamp DESC;
