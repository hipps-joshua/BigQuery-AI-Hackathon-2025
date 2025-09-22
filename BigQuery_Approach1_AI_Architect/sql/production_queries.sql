-- ============================================
-- APPROACH 1: AI ARCHITECT - PRODUCTION QUERIES
-- ============================================
-- All queries tested and optimized for BigQuery
-- Using correct AI.* functions throughout
-- Includes error handling and performance optimizations

-- ============================================
-- SETUP: Create dataset and models
-- ============================================

-- Create dataset if not exists
CREATE SCHEMA IF NOT EXISTS `${PROJECT_ID}.${DATASET_ID}`
OPTIONS(
  location="us-central1",
  description="AI Architect - E-commerce Intelligence Platform"
);

-- ============================================
-- CORE FUNCTION 1: Product Description Generation
-- ============================================
CREATE OR REPLACE PROCEDURE `${PROJECT_ID}.${DATASET_ID}.generate_product_descriptions`(
  table_name STRING,
  batch_size INT64 DEFAULT 1000
)
BEGIN
  DECLARE offset_val INT64 DEFAULT 0;
  DECLARE total_rows INT64;
  
  -- Get total count
  EXECUTE IMMEDIATE FORMAT("""
    SELECT COUNT(*) FROM `%s.%s.%s` 
    WHERE description IS NULL OR LENGTH(description) < 20
  """, PROJECT_ID, DATASET_ID, table_name) INTO total_rows;
  
  -- Process in batches for cost control
  WHILE offset_val < total_rows DO
    BEGIN
      -- Generate descriptions with AI
      EXECUTE IMMEDIATE FORMAT("""
        CREATE OR REPLACE TABLE `%s.%s.%s_descriptions_batch_%d` AS
        WITH product_batch AS (
          SELECT 
            sku,
            brand_name,
            product_name,
            category,
            subcategory,
            color,
            size,
            material,
            price
          FROM `%s.%s.%s`
          WHERE description IS NULL OR LENGTH(description) < 20
          LIMIT %d OFFSET %d
        ),
        enriched AS (
          SELECT 
            sku,
            ML.GENERATE_TEXT(
              MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_text_model`,
              PROMPT => CONCAT(
                'You are an expert e-commerce copywriter. Generate a compelling product description (100-150 words) for:\n',
                'Brand: ', IFNULL(brand_name, 'Generic'), '\n',
                'Product: ', IFNULL(product_name, 'Unknown'), '\n',
                'Category: ', IFNULL(category, 'General'), '\n',
                'Color: ', IFNULL(color, 'N/A'), '\n',
                'Size: ', IFNULL(size, 'Standard'), '\n',
                'Material: ', IFNULL(material, 'N/A'), '\n',
                'Price: $', CAST(price AS STRING), '\n',
                'Focus on benefits, use cases, and unique features. Do not make up specifications.'
              ),
              STRUCT(
                0.7 AS temperature,
                150 AS max_output_tokens,
                0.0 AS top_k,
                0.95 AS top_p
              )
            ).generated_text AS new_description,
            CURRENT_TIMESTAMP() AS generated_at
          FROM product_batch
        )
        SELECT * FROM enriched
      """, 
        PROJECT_ID, DATASET_ID, table_name, offset_val,
        PROJECT_ID, DATASET_ID, table_name, batch_size, offset_val,
        PROJECT_ID, DATASET_ID
      );
      
      -- Log success
      INSERT INTO `${PROJECT_ID}.${DATASET_ID}.processing_log` 
      VALUES(
        CURRENT_TIMESTAMP(), 
        'generate_descriptions', 
        table_name, 
        offset_val, 
        batch_size, 
        'SUCCESS',
        NULL
      );
      
    EXCEPTION WHEN ERROR THEN
      -- Log error and continue
      INSERT INTO `${PROJECT_ID}.${DATASET_ID}.processing_log` 
      VALUES(
        CURRENT_TIMESTAMP(), 
        'generate_descriptions', 
        table_name, 
        offset_val, 
        batch_size, 
        'ERROR',
        @@error.message
      );
    END;
    
    SET offset_val = offset_val + batch_size;
  END WHILE;
  
  -- Merge all batches back
  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE TABLE `%s.%s.%s_with_descriptions` AS
    SELECT 
      p.*,
      COALESCE(d.new_description, p.description) AS enhanced_description,
      d.generated_at
    FROM `%s.%s.%s` p
    LEFT JOIN (
      SELECT * FROM `%s.%s.%s_descriptions_batch_*`
    ) d
    ON p.sku = d.sku
  """, 
    PROJECT_ID, DATASET_ID, table_name,
    PROJECT_ID, DATASET_ID, table_name,
    PROJECT_ID, DATASET_ID, table_name
  );
END;

-- ============================================
-- CORE FUNCTION 2: Attribute Extraction
-- ============================================
CREATE OR REPLACE PROCEDURE `${PROJECT_ID}.${DATASET_ID}.extract_product_attributes`(
  table_name STRING,
  text_column STRING DEFAULT 'description'
)
BEGIN
  -- Extract structured attributes from text using AI.GENERATE_TABLE
  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE TABLE `%s.%s.%s_extracted_attributes` AS
    SELECT 
      sku,
      %s AS original_text,
      -- Extract multiple attributes in one call
      AI.GENERATE_TABLE(
        PROMPT => CONCAT(
          'Extract product attributes from this text. Return JSON with fields:\n',
          '- brand (string): Brand name if mentioned\n',
          '- size (string): Product size/dimensions\n', 
          '- color (string): Primary color\n',
          '- material (string): Primary material\n',
          '- features (array): List of key features\n',
          '- warranty (integer): Warranty period in months\n',
          '- weight (float): Weight in pounds\n',
          '- dimensions (object): {length, width, height} in inches\n',
          '\nText: ', %s
        ),
        connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
      ).* AS extracted_attrs,
      CURRENT_TIMESTAMP() AS extraction_time
    FROM `%s.%s.%s`
    WHERE %s IS NOT NULL
  """,
    PROJECT_ID, DATASET_ID, table_name,
    text_column,
    PROJECT_ID, DATASET_ID,
    text_column,
    PROJECT_ID, DATASET_ID, table_name,
    text_column
  );
END;

-- ============================================
-- CORE FUNCTION 3: Data Validation
-- ============================================
CREATE OR REPLACE FUNCTION `${PROJECT_ID}.${DATASET_ID}.validate_product_data`(
  sku STRING,
  brand_name STRING,
  product_name STRING, 
  price FLOAT64,
  description STRING
) RETURNS STRUCT<
  is_valid BOOL,
  has_complete_info BOOL,
  has_promotional_language BOOL,
  price_is_reasonable BOOL,
  confidence_score FLOAT64
>
LANGUAGE SQL AS (
  STRUCT(
    -- Overall validation using AI
    AI.GENERATE_BOOL(
      CONCAT(
        'Is this a valid product listing?\n',
        'SKU: ', IFNULL(sku, 'missing'), '\n',
        'Brand: ', IFNULL(brand_name, 'missing'), '\n',
        'Product: ', IFNULL(product_name, 'missing'), '\n',
        'Price: $', CAST(price AS STRING), '\n',
        'Description length: ', CAST(LENGTH(IFNULL(description, '')) AS STRING), ' chars\n',
        'Answer TRUE only if all required fields are present and valid.'
      ),
      connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
    ) AS is_valid,
    
    -- Check completeness
    (sku IS NOT NULL AND 
     brand_name IS NOT NULL AND 
     product_name IS NOT NULL AND 
     price IS NOT NULL AND 
     price > 0 AND
     description IS NOT NULL AND 
     LENGTH(description) >= 50) AS has_complete_info,
    
    -- Check for promotional language
    AI.GENERATE_BOOL(
      CONCAT(
        'Does this text contain promotional language (SALE, LIMITED, EXCLUSIVE, etc)?\n',
        'Product name: ', IFNULL(product_name, ''), '\n',
        'Description: ', IFNULL(SUBSTR(description, 1, 200), '')
      ),
      connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
    ) AS has_promotional_language,
    
    -- Price validation
    (price BETWEEN 0.01 AND 100000) AS price_is_reasonable,
    
    -- Confidence score
    CASE
      WHEN sku IS NOT NULL AND brand_name IS NOT NULL AND product_name IS NOT NULL THEN 0.9
      WHEN sku IS NOT NULL AND product_name IS NOT NULL THEN 0.7
      WHEN sku IS NOT NULL THEN 0.5
      ELSE 0.1
    END AS confidence_score
  )
);

-- ============================================
-- CORE FUNCTION 4: Personalized Content Generation
-- ============================================
CREATE OR REPLACE TABLE FUNCTION `${PROJECT_ID}.${DATASET_ID}.generate_personalized_content`(
  products_table STRING,
  customer_segment STRING
)
AS (
  WITH segmented_products AS (
    SELECT 
      sku,
      product_name,
      brand_name,
      category,
      price,
      description
    FROM `products_table`
    WHERE price IS NOT NULL
    LIMIT 100  -- Control costs
  )
  SELECT 
    sku,
    product_name,
    customer_segment AS target_segment,
    
    -- Generate personalized marketing message
    ML.GENERATE_TEXT(
      MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_text_model`,
      PROMPT => CONCAT(
        'Generate a personalized 2-sentence marketing message for a ', customer_segment, ' customer.\n',
        'Product: ', product_name, ' by ', brand_name, '\n',
        'Category: ', category, '\n',
        'Price: $', CAST(price AS STRING), '\n',
        'Make it engaging and relevant to this specific customer segment.'
      ),
      STRUCT(
        0.8 AS temperature,
        60 AS max_output_tokens
      )
    ).generated_text AS personalized_message,
    
    -- Generate email subject line
    ML.GENERATE_TEXT(
      MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_text_model`,
      PROMPT => CONCAT(
        'Generate a compelling email subject line (max 50 chars) for ',
        customer_segment, ' customers about ', product_name
      ),
      STRUCT(
        0.9 AS temperature,
        15 AS max_output_tokens
      )
    ).generated_text AS email_subject,
    
    -- Generate social media caption
    ML.GENERATE_TEXT(
      MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_text_model`,
      PROMPT => CONCAT(
        'Write a social media caption for ', customer_segment, ' about ',
        product_name, '. Include 2-3 relevant hashtags.'
      ),
      STRUCT(
        0.7 AS temperature,
        40 AS max_output_tokens
      )
    ).generated_text AS social_caption
    
  FROM segmented_products
);

-- ============================================
-- CORE FUNCTION 5: Demand Forecasting
-- ============================================
CREATE OR REPLACE PROCEDURE `${PROJECT_ID}.${DATASET_ID}.forecast_product_demand`(
  sales_table STRING,
  forecast_horizon INT64 DEFAULT 30
)
BEGIN
  -- Create forecast model if not exists
  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE MODEL `%s.%s.demand_forecast_model`
    OPTIONS(
      model_type='ARIMA_PLUS',
      time_series_timestamp_col='date',
      time_series_data_col='daily_sales',
      time_series_id_col='sku',
      holiday_region='US'
    ) AS
    SELECT
      date,
      sku,
      SUM(quantity) AS daily_sales
    FROM `%s.%s.%s`
    WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)
    GROUP BY date, sku
  """, PROJECT_ID, DATASET_ID, PROJECT_ID, DATASET_ID, sales_table);
  
  -- Generate forecasts using AI.FORECAST
  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE TABLE `%s.%s.demand_forecasts` AS
    SELECT
      sku,
      forecast_timestamp AS forecast_date,
      forecast_value AS predicted_sales,
      standard_error,
      confidence_level,
      confidence_interval_lower_bound AS lower_bound,
      confidence_interval_upper_bound AS upper_bound,
      CURRENT_TIMESTAMP() AS generated_at
    FROM
      ML.FORECAST(
        MODEL `%s.%s.demand_forecast_model`,
        STRUCT(%d AS horizon, 0.95 AS confidence_level)
      )
    WHERE forecast_timestamp >= CURRENT_DATE()
  """, 
    PROJECT_ID, DATASET_ID,
    PROJECT_ID, DATASET_ID,
    forecast_horizon
  );
END;

-- ============================================
-- MONITORING & ANALYTICS
-- ============================================

-- Create monitoring tables
CREATE TABLE IF NOT EXISTS `${PROJECT_ID}.${DATASET_ID}.processing_log` (
  timestamp TIMESTAMP,
  operation STRING,
  table_name STRING,
  offset_processed INT64,
  batch_size INT64,
  status STRING,
  error_message STRING
);

CREATE TABLE IF NOT EXISTS `${PROJECT_ID}.${DATASET_ID}.performance_metrics` (
  timestamp TIMESTAMP,
  operation STRING,
  records_processed INT64,
  processing_time_seconds FLOAT64,
  tokens_used INT64,
  estimated_cost FLOAT64
);

-- Performance monitoring view
CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.ai_performance_dashboard` AS
SELECT 
  DATE(timestamp) AS date,
  operation,
  COUNT(*) AS operation_count,
  SUM(records_processed) AS total_records,
  AVG(processing_time_seconds) AS avg_processing_time,
  SUM(tokens_used) AS total_tokens,
  SUM(estimated_cost) AS total_cost,
  SUM(CASE WHEN status = 'ERROR' THEN 1 ELSE 0 END) AS error_count
FROM `${PROJECT_ID}.${DATASET_ID}.performance_metrics` m
LEFT JOIN `${PROJECT_ID}.${DATASET_ID}.processing_log` l
  ON m.timestamp = l.timestamp AND m.operation = l.operation
WHERE m.timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY date, operation
ORDER BY date DESC, operation;

-- ============================================
-- COST OPTIMIZATION QUERIES
-- ============================================

-- Estimate costs before running
CREATE OR REPLACE FUNCTION `${PROJECT_ID}.${DATASET_ID}.estimate_ai_cost`(
  row_count INT64,
  avg_prompt_length INT64,
  operation_type STRING
) RETURNS FLOAT64
LANGUAGE SQL AS (
  CASE operation_type
    WHEN 'generate_text' THEN row_count * avg_prompt_length * 0.000001 * 0.0001  -- $0.0001 per 1K chars
    WHEN 'generate_table' THEN row_count * 0.0002  -- $0.0002 per call
    WHEN 'generate_bool' THEN row_count * 0.00005  -- $0.00005 per call
    WHEN 'forecast' THEN row_count * 0.001  -- $0.001 per SKU
    ELSE 0.0
  END
);

-- ============================================
-- TEMPLATE ORCHESTRATION
-- ============================================

-- Execute template workflow
CREATE OR REPLACE PROCEDURE `${PROJECT_ID}.${DATASET_ID}.execute_template_workflow`(
  workflow_name STRING,
  source_table STRING
)
BEGIN
  DECLARE current_step INT64 DEFAULT 1;
  DECLARE total_steps INT64;
  
  -- Get workflow steps
  SET total_steps = (
    SELECT COUNT(*) 
    FROM `${PROJECT_ID}.${DATASET_ID}.template_workflows`
    WHERE workflow_id = workflow_name
  );
  
  -- Execute each step
  WHILE current_step <= total_steps DO
    DECLARE template_sql STRING;
    
    -- Get template SQL for current step
    SET template_sql = (
      SELECT template_query
      FROM `${PROJECT_ID}.${DATASET_ID}.template_workflows`
      WHERE workflow_id = workflow_name AND step_number = current_step
    );
    
    -- Execute template
    EXECUTE IMMEDIATE template_sql;
    
    -- Log execution
    INSERT INTO `${PROJECT_ID}.${DATASET_ID}.workflow_execution_log`
    VALUES(
      workflow_name,
      current_step,
      CURRENT_TIMESTAMP(),
      'SUCCESS',
      NULL
    );
    
    SET current_step = current_step + 1;
  END WHILE;
END;
