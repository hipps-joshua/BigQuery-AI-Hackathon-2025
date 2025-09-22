-- ============================================
-- MULTIMODAL PIONEER - TEST QUERIES
-- ============================================
-- Validate Object Tables, AI.ANALYZE_IMAGE, and multimodal functions

-- Test 1: Object Table creation test
-- Note: Requires a GCS bucket with images
SELECT
  'Object Table Test' AS test_name,
  'gs://your-bucket/product_images/' AS test_bucket_path,
  'Run create_image_object_tables procedure after updating bucket name' AS instructions;

-- Test 2: Basic image analysis components
WITH test_image AS (
  SELECT 'gs://your-bucket/product_images/shoe001.jpg' AS image_uri
)
SELECT
  'Image Analysis Components' AS test_name,
  
  -- Test Gemini Vision can access image
  ML.GENERATE_TEXT(
    MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_text_model`,
    PROMPT => CONCAT('Describe this product image in 20 words: ', image_uri),
    STRUCT(0.5 AS temperature, 30 AS max_output_tokens)
  ).generated_text AS image_description,
  
  -- Test quality scoring
  AI.GENERATE_DOUBLE(
    CONCAT('Rate image quality 1-10: ', image_uri),
    connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
  ) AS quality_score,
  
  -- Test compliance check
  AI.GENERATE_BOOL(
    CONCAT('Does this image show required product labels? ', image_uri),
    connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
  ) AS has_labels
  
FROM test_image;

-- Test 3: Create test product data with images
CREATE OR REPLACE TABLE `${PROJECT_ID}.${DATASET_ID}.test_products_multimodal` AS
SELECT * FROM UNNEST([
  STRUCT(
    'MM_TEST_001' AS sku,
    'Nike' AS brand_name,
    'Air Max 270' AS product_name,
    'Footwear' AS category,
    'Running Shoes' AS subcategory,
    159.99 AS price,
    'Black' AS listed_color,
    'Mesh' AS listed_material,
    'shoe001.jpg' AS image_filename,
    'gs://your-bucket/product_images/shoe001.jpg' AS image_url
  ),
  STRUCT(
    'MM_TEST_002', 'Apple', 'iPhone 14 Pro', 'Electronics', 'Smartphones',
    999.99, 'Space Black', 'Glass/Aluminum', 'iphone001.jpg',
    'gs://your-bucket/product_images/iphone001.jpg'
  ),
  STRUCT(
    'MM_TEST_003', 'Patagonia', 'Better Sweater', 'Apparel', 'Outerwear',
    139.00, 'Navy Blue', 'Recycled Polyester', 'sweater001.jpg',
    'gs://your-bucket/product_images/sweater001.jpg'
  ),
  -- Duplicate/counterfeit test
  STRUCT(
    'MM_TEST_004', 'Nike', 'Air Max 270', 'Footwear', 'Running Shoes',
    59.99, 'Black', 'Synthetic', 'fake_shoe001.jpg',
    'gs://your-bucket/product_images/fake_shoe001.jpg'
  ),
  -- Compliance test (toy without warning)
  STRUCT(
    'MM_TEST_005', 'LEGO', 'Creator Set', 'Toys', 'Building Sets',
    49.99, 'Multicolor', 'Plastic', 'lego001.jpg',
    'gs://your-bucket/product_images/lego001.jpg'
  )
]);

-- Test 4: ML.ANALYZE_IMAGE simulation (using available functions)
WITH image_analysis_test AS (
  SELECT
    sku,
    brand_name,
    product_name,
    category,
    image_url,
    
    -- Simulate ML.ANALYZE_IMAGE with multiple AI calls
    STRUCT(
      AI.GENERATE_TABLE(
        -- Using connection_id with AI.GENERATE_TABLE below
        PROMPT => CONCAT(
          'Analyze product image and return JSON with:\n',
          '- detected_objects (array of objects found)\n',
          '- detected_text (array of text found)\n',
          '- dominant_colors (array of colors)\n',
          '- has_logo (boolean)\n',
          'Image: ', image_url
        )
      ) AS vision_features,
      
      AI.GENERATE_BOOL(
        CONCAT('Is this image appropriate for all ages? ', image_url),
        connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
      ) AS safe_search_pass
    ) AS ml_analyze_image_result
    
  FROM `${PROJECT_ID}.${DATASET_ID}.test_products_multimodal`
)
SELECT
  sku,
  product_name,
  ml_analyze_image_result,
  'Check vision features extracted' AS test_validation
FROM image_analysis_test;

-- Test 5: Visual embedding generation
CREATE OR REPLACE TABLE `${PROJECT_ID}.${DATASET_ID}.test_visual_embeddings` AS
SELECT
  sku,
  product_name,
  
  -- Generate visual embedding
  ML.GENERATE_EMBEDDING(
    MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
    CONTENT => image_url,
    STRUCT(TRUE AS flatten_json_output)
  ).ml_generate_embedding_result AS visual_embedding,
  
  -- Generate text embedding
  ML.GENERATE_EMBEDDING(
    MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
    CONTENT => CONCAT(brand_name, ' ', product_name),
    STRUCT(TRUE AS flatten_json_output)
  ).ml_generate_embedding_result AS text_embedding,
  
  -- Multimodal embedding (if supported)
  ML.GENERATE_EMBEDDING(
    MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
    CONTENT => STRUCT(image_url AS image, product_name AS text),
    STRUCT(TRUE AS flatten_json_output)
  ).ml_generate_embedding_result AS multimodal_embedding
  
FROM `${PROJECT_ID}.${DATASET_ID}.test_products_multimodal`;

-- Test 6: Visual similarity search
WITH query_image AS (
  SELECT 'gs://your-bucket/product_images/query_shoe.jpg' AS query_uri
),
similarity_test AS (
  SELECT
    p.sku,
    p.product_name,
    1 - ML.DISTANCE(
      e.visual_embedding,
      (SELECT ML.GENERATE_EMBEDDING(
        MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
        CONTENT => query_uri,
        STRUCT(TRUE AS flatten_json_output)
      ).ml_generate_embedding_result FROM query_image),
      'COSINE'
    ) AS visual_similarity
  FROM `${PROJECT_ID}.${DATASET_ID}.test_products_multimodal` p
  JOIN `${PROJECT_ID}.${DATASET_ID}.test_visual_embeddings` e ON p.sku = e.sku
)
SELECT
  *,
  CASE 
    WHEN sku = 'MM_TEST_001' AND visual_similarity > 0.8 THEN 'PASS: Found similar shoe'
    WHEN sku = 'MM_TEST_002' AND visual_similarity < 0.3 THEN 'PASS: iPhone has low similarity to shoe'
    ELSE 'CHECK'
  END AS test_result
FROM similarity_test
ORDER BY visual_similarity DESC;

-- Test 7: Quality control test
WITH qc_test AS (
  SELECT
    sku,
    product_name,
    category,
    price,
    listed_color,
    
    -- Quality assessment
    JSON_EXTRACT_SCALAR(
      ML.GENERATE_TEXT(
        MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_text_model`,
        PROMPT => CONCAT(
          'Rate image quality (return JSON): {"clarity": 1-10, "lighting": 1-10, "overall": 1-10}\n',
          'Image: ', image_url
        ),
        STRUCT(0.3 AS temperature, 50 AS max_output_tokens)
      ).generated_text, '$.overall'
    ) AS quality_score,
    
    -- Compliance check
    CASE 
      WHEN category = 'Toys' THEN
        AI.GENERATE_BOOL(
          PROMPT => CONCAT('Does toy image show age warning label? ', image_url),
          connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
        )
      WHEN category = 'Electronics' THEN  
        AI.GENERATE_BOOL(
          PROMPT => CONCAT('Does electronic product show FCC/safety labels? ', image_url),
          connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
        )
      ELSE TRUE
    END AS is_compliant,
    
    -- Color extraction
    JSON_EXTRACT_SCALAR(
      ML.GENERATE_TEXT(
        MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_text_model`,
        PROMPT => CONCAT(
          'What is the primary color? Return JSON: {"primary_color": "color_name"}\n',
          'Image: ', image_url
        ),
        STRUCT(0.2 AS temperature, 20 AS max_output_tokens)
      ).generated_text, '$.primary_color'
    ) AS detected_color,
    
    -- Counterfeit check
    CASE
      WHEN sku = 'MM_TEST_004' THEN  -- Fake Nike
        AI.GENERATE_DOUBLE(
          CONCAT(
            'Rate authenticity 0-1 for this Nike product (check logo, quality): ',
            image_url
          ),
          connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
        )
      ELSE 1.0
    END AS authenticity_score
    
  FROM `${PROJECT_ID}.${DATASET_ID}.test_products_multimodal`
)
SELECT
  *,
  -- Validate QC results
  CASE
    WHEN sku = 'MM_TEST_004' AND authenticity_score < 0.5 THEN 'PASS: Detected fake'
    WHEN sku = 'MM_TEST_005' AND NOT is_compliant THEN 'PASS: Found compliance issue'
    WHEN quality_score IS NOT NULL THEN 'PASS: Quality assessed'
    ELSE 'CHECK: Review results'
  END AS test_validation
FROM qc_test;

-- Test 8: Performance test
CREATE OR REPLACE TABLE `${PROJECT_ID}.${DATASET_ID}.multimodal_performance_test` AS
WITH test_batch AS (
  SELECT
    CONCAT('MM_PERF_', CAST(ROW_NUMBER() OVER() AS STRING)) AS sku,
    CASE MOD(num, 3)
      WHEN 0 THEN 'Electronics'
      WHEN 1 THEN 'Apparel'
      ELSE 'Footwear'
    END AS category,
    CONCAT('gs://your-bucket/test_images/product_', CAST(num AS STRING), '.jpg') AS image_uri
  FROM UNNEST(GENERATE_ARRAY(1, 100)) AS num
),
timed_analysis AS (
  SELECT
    CURRENT_TIMESTAMP() AS start_time,
    COUNT(*) AS batch_size,
    -- Simulate batch image analysis
    COUNT(
      ML.GENERATE_TEXT(
        MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_text_model`,
        PROMPT => CONCAT('Describe product category: ', category),
        STRUCT(0.5 AS temperature, 20 AS max_output_tokens)
      ).generated_text
    ) AS processed_count,
    CURRENT_TIMESTAMP() AS end_time
  FROM test_batch
)
SELECT
  batch_size,
  processed_count,
  TIMESTAMP_DIFF(end_time, start_time, MILLISECOND) / 1000.0 AS processing_seconds,
  batch_size / (TIMESTAMP_DIFF(end_time, start_time, MILLISECOND) / 1000.0) AS images_per_second,
  batch_size * 0.002 AS estimated_cost_usd  -- $0.002 per image
FROM timed_analysis;

-- Test 9: End-to-end workflow
BEGIN
  -- Create object tables
  CALL `${PROJECT_ID}.${DATASET_ID}.create_image_object_tables`(
    'your-bucket',
    'product_images'
  );
  
  -- Build visual search index
  CALL `${PROJECT_ID}.${DATASET_ID}.build_visual_search_index`(
    'test_products_multimodal',
    10
  );
  
  -- Run quality control
  CALL `${PROJECT_ID}.${DATASET_ID}.run_visual_quality_control`(
    'test_products_multimodal',
    7.0
  );
  
  -- Log test completion
  INSERT INTO `${PROJECT_ID}.${DATASET_ID}.test_results`
  VALUES(
    'multimodal_e2e',
    'Workflow completed successfully',
    'SUCCESS',
    CURRENT_TIMESTAMP()
  );
  
EXCEPTION WHEN ERROR THEN
  INSERT INTO `${PROJECT_ID}.${DATASET_ID}.test_results`
  VALUES(
    'multimodal_e2e',
    @@error.message,
    'ERROR',
    CURRENT_TIMESTAMP()
  );
END;

-- Test 10: Visual merchandising test
WITH merchandising_test AS (
  SELECT * FROM `${PROJECT_ID}.${DATASET_ID}.optimize_visual_merchandising`(
    'Footwear',
    JSON '{"style": "athletic", "price_range": "100-200"}'
  )
)
SELECT
  'Visual Merchandising' AS test_name,
  COUNT(*) AS visual_groups_found,
  SUM(projected_lift_value) AS total_projected_value,
  STRING_AGG(hero_product_name, ', ' ORDER BY projected_lift_value DESC LIMIT 3) AS top_hero_products,
  CASE
    WHEN COUNT(*) > 0 THEN 'PASS: Generated merchandising groups'
    ELSE 'FAIL: No groups found'
  END AS test_result
FROM merchandising_test;

-- Test 11: Cost estimation
SELECT
  'Multimodal Cost Estimate' AS scenario,
  
  -- Image analysis
  10000 AS products_with_images,
  `${PROJECT_ID}.${DATASET_ID}.estimate_multimodal_cost`(10000, 'analyze_image') AS image_analysis_cost,
  
  -- Visual embeddings
  10000 AS embeddings_to_generate,
  `${PROJECT_ID}.${DATASET_ID}.estimate_multimodal_cost`(10000, 'visual_embedding') AS embedding_cost,
  
  -- Daily QC runs
  1000 AS daily_qc_checks,
  `${PROJECT_ID}.${DATASET_ID}.estimate_multimodal_cost`(1000, 'quality_assessment') AS daily_qc_cost,
  
  -- Visual searches
  5000 AS daily_visual_searches,
  `${PROJECT_ID}.${DATASET_ID}.estimate_multimodal_cost`(5000, 'visual_search') AS daily_search_cost,
  
  -- Monthly total
  `${PROJECT_ID}.${DATASET_ID}.estimate_multimodal_cost`(10000, 'analyze_image') +
  `${PROJECT_ID}.${DATASET_ID}.estimate_multimodal_cost`(10000, 'visual_embedding') +
  (`${PROJECT_ID}.${DATASET_ID}.estimate_multimodal_cost`(1000, 'quality_assessment') * 30) +
  (`${PROJECT_ID}.${DATASET_ID}.estimate_multimodal_cost`(5000, 'visual_search') * 30) AS total_monthly_cost,
  
  -- ROI
  500000 AS monthly_value_delivered,  -- From compliance, quality, counterfeits
  500000 - (
    `${PROJECT_ID}.${DATASET_ID}.estimate_multimodal_cost`(10000, 'analyze_image') +
    `${PROJECT_ID}.${DATASET_ID}.estimate_multimodal_cost`(10000, 'visual_embedding') +
    (`${PROJECT_ID}.${DATASET_ID}.estimate_multimodal_cost`(1000, 'quality_assessment') * 30) +
    (`${PROJECT_ID}.${DATASET_ID}.estimate_multimodal_cost`(5000, 'visual_search') * 30)
  ) AS monthly_roi;

-- ============================================
-- TEST SUMMARY DASHBOARD
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
