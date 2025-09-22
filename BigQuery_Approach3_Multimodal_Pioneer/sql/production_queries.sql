-- ============================================
-- APPROACH 3: MULTIMODAL PIONEER - PRODUCTION QUERIES
-- ============================================
-- Using Object Tables for unstructured data
-- AI.ANALYZE_IMAGE for native image analysis
-- Plus all AI.* and ML.* functions for complete multimodal intelligence

-- ============================================
-- SETUP: Create dataset and models
-- ============================================

CREATE SCHEMA IF NOT EXISTS `${PROJECT_ID}.${DATASET_ID}`
OPTIONS(
  location="us-central1",
  description="Multimodal Pioneer - Visual Intelligence for E-commerce"
);

-- ============================================
-- CORE FUNCTION 1: Create Object Tables for Images
-- ============================================
CREATE OR REPLACE PROCEDURE `${PROJECT_ID}.${DATASET_ID}.create_image_object_tables`(
  bucket_name STRING,
  image_folder STRING DEFAULT 'product_images'
)
BEGIN
  -- Create object table for product images
  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE EXTERNAL TABLE `%s.%s.product_images`
    OPTIONS (
      object_metadata = 'DIRECTORY',
      uris = ['gs://%s/%s/*']
    )
  """, PROJECT_ID, DATASET_ID, bucket_name, image_folder);
  
  -- Create enriched object table with metadata
  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE EXTERNAL TABLE `%s.%s.product_images_metadata`
    WITH CONNECTION `%s.%s.gemini_connection`
    OPTIONS (
      object_metadata = 'SIMPLE',
      uris = ['gs://%s/%s/*']
    )
  """, PROJECT_ID, DATASET_ID, PROJECT_ID, LOCATION, bucket_name, image_folder);
  
  -- Log creation
  INSERT INTO `${PROJECT_ID}.${DATASET_ID}.processing_log`
  VALUES(
    CURRENT_TIMESTAMP(),
    'create_object_tables',
    'product_images',
    0,
    0,
    'SUCCESS',
    CONCAT('Created object tables for bucket: ', bucket_name)
  );
END;

-- ============================================
-- CORE FUNCTION 2: AI.ANALYZE_IMAGE Implementation
-- ============================================
CREATE OR REPLACE TABLE FUNCTION `${PROJECT_ID}.${DATASET_ID}.analyze_product_images`(
  products_table STRING,
  images_table STRING,
  analysis_type STRING DEFAULT 'comprehensive'  -- comprehensive, quality, compliance, counterfeit
)
AS (
  WITH product_images AS (
    SELECT
      p.sku,
      p.brand_name,
      p.product_name,
      p.category,
      p.subcategory,
      p.listed_color,
      p.listed_size,
      p.listed_material,
      p.price,
      i.uri AS image_uri,
      i.content_type,
      i.size AS file_size_bytes,
      i.updated
    FROM products_table p
    JOIN images_table i ON p.image_filename = i.name
  ),
  -- Comprehensive image analysis
  image_analysis AS (
    SELECT
      *,
      -- Native BigQuery AI image analysis
      ML.ANALYZE_IMAGE(
        MODEL `${PROJECT_ID}.${DATASET_ID}.vision_model`,
        TABLE product_images,
        STRUCT(
          ['label_detection', 'text_detection', 'object_detection', 
           'safe_search_detection', 'logo_detection', 'product_attributes'] AS feature_types,
          10 AS max_results,
          0.5 AS confidence_threshold
        )
      ) AS vision_analysis,
      
      -- Quality assessment
      ML.GENERATE_TEXT(
        MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_text_model`,
        PROMPT => CONCAT(
          'Analyze product image quality:\n',
          '1. Image clarity (1-10)\n',
          '2. Lighting quality (1-10)\n',
          '3. Background cleanliness (1-10)\n',
          '4. Product visibility (1-10)\n',
          '5. Professional appearance (1-10)\n',
          'Image: ', image_uri,
          '\nReturn JSON with scores and brief explanation.'
        ),
        STRUCT(0.3 AS temperature, 200 AS max_output_tokens)
      ).generated_text AS quality_assessment,
      
      -- Compliance check based on category
      AI.GENERATE_BOOL(
        CONCAT(
          'Check if this ', category, ' product image meets compliance:\n',
          CASE category
            WHEN 'Electronics' THEN 'Shows FCC label, safety warnings, model number'
            WHEN 'Toys' THEN 'Shows age warning, choking hazard label if needed'
            WHEN 'Food' THEN 'Shows nutrition facts, expiration date, allergen info'
            WHEN 'Cosmetics' THEN 'Shows ingredients list, FDA warnings'
            ELSE 'Shows required safety labels and warnings'
          END,
          '\nImage: ', image_uri
        ),
        connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
      ) AS is_compliant,
      
      -- Color/material verification
      AI.GENERATE_TABLE(
        PROMPT => CONCAT(
          'Extract visual attributes from product image.\n',
          'Return columns: primary_color, secondary_color, material_appearance, pattern, finish\n',
          'Image: ', image_uri
        ),
        connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
      ).* AS extracted_attributes,
      
      -- Counterfeit risk assessment
      AI.GENERATE_DOUBLE(
        CONCAT(
          'Assess counterfeit risk (0-1) for this ', brand_name, ' product:\n',
          'Check: logo quality, stitching/construction, packaging, labels\n',
          'Image: ', image_uri,
          '\nReturn confidence score where 1 = definitely authentic, 0 = likely counterfeit'
        ),
        connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
      ) AS authenticity_score
      
    FROM product_images
  )
  SELECT
    sku,
    brand_name,
    product_name,
    category,
    price,
    image_uri,
    
    -- Vision analysis results
    vision_analysis,
    JSON_EXTRACT_SCALAR(quality_assessment, '$.overall_score') AS quality_score,
    quality_assessment,
    is_compliant,
    
    -- Attribute comparison
    listed_color,
    extracted_attributes.primary_color AS detected_color,
    CASE 
      WHEN LOWER(listed_color) = LOWER(extracted_attributes.primary_color) THEN TRUE
      WHEN listed_color IS NULL THEN NULL
      ELSE FALSE
    END AS color_matches,
    
    listed_material,
    extracted_attributes.material_appearance AS detected_material,
    
    -- Risk scores
    authenticity_score,
    CASE
      WHEN authenticity_score < 0.5 THEN 'High Risk'
      WHEN authenticity_score < 0.7 THEN 'Medium Risk'
      WHEN authenticity_score < 0.9 THEN 'Low Risk'
      ELSE 'Verified'
    END AS counterfeit_risk_level,
    
    -- Business impact
    CASE 
      WHEN NOT is_compliant THEN price * 100  -- Potential fine
      WHEN authenticity_score < 0.5 THEN price * 50  -- Brand damage
      ELSE 0
    END AS potential_loss,
    
    CURRENT_TIMESTAMP() AS analysis_timestamp
    
  FROM image_analysis
  WHERE 
    CASE analysis_type
      WHEN 'quality' THEN JSON_EXTRACT_SCALAR(quality_assessment, '$.overall_score') < '7'
      WHEN 'compliance' THEN NOT is_compliant
      WHEN 'counterfeit' THEN authenticity_score < 0.7
      ELSE TRUE  -- comprehensive shows all
    END
);

-- ============================================
-- CORE FUNCTION 3: Visual Search with Embeddings
-- ============================================
CREATE OR REPLACE PROCEDURE `${PROJECT_ID}.${DATASET_ID}.build_visual_search_index`(
  products_table STRING,
  batch_size INT64 DEFAULT 100
)
BEGIN
  DECLARE offset_val INT64 DEFAULT 0;
  DECLARE total_rows INT64;
  
  -- Get total count
  EXECUTE IMMEDIATE FORMAT("""
    SELECT COUNT(*) FROM `%s.%s.%s` WHERE image_url IS NOT NULL
  """, PROJECT_ID, DATASET_ID, products_table) INTO total_rows;
  
  -- Create visual embeddings table
  EXECUTE IMMEDIATE FORMAT("""
    CREATE TABLE IF NOT EXISTS `%s.%s.%s_visual_embeddings` (
      sku STRING NOT NULL,
      image_uri STRING,
      visual_embedding ARRAY<FLOAT64>,
      text_embedding ARRAY<FLOAT64>,
      multimodal_embedding ARRAY<FLOAT64>,
      embedding_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
    )
  """, PROJECT_ID, DATASET_ID, products_table);
  
  -- Process in batches
  WHILE offset_val < total_rows DO
    BEGIN
      EXECUTE IMMEDIATE FORMAT("""
        INSERT INTO `%s.%s.%s_visual_embeddings`
        WITH batch AS (
          SELECT 
            p.sku,
            p.brand_name,
            p.product_name,
            p.description,
            i.uri AS image_uri
          FROM `%s.%s.%s` p
          JOIN `%s.%s.product_images` i ON p.image_filename = i.name
          WHERE p.image_url IS NOT NULL
          LIMIT %d OFFSET %d
        )
        SELECT
          sku,
          image_uri,
          -- Generate visual embedding
          ML.GENERATE_EMBEDDING(
            MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
            CONTENT => image_uri,
            STRUCT(TRUE AS flatten_json_output)
          ).ml_generate_embedding_result AS visual_embedding,
          
          -- Generate text embedding
          ML.GENERATE_EMBEDDING(
            MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
            CONTENT => CONCAT(brand_name, ' ', product_name, ' ', IFNULL(description, '')),
            STRUCT(TRUE AS flatten_json_output)
          ).ml_generate_embedding_result AS text_embedding,
          
          -- Generate combined multimodal embedding
          ML.GENERATE_EMBEDDING(
            MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
            CONTENT => STRUCT(
              image_uri AS image,
              CONCAT(brand_name, ' ', product_name) AS text
            ),
            STRUCT(TRUE AS flatten_json_output)
          ).ml_generate_embedding_result AS multimodal_embedding,
          
          CURRENT_TIMESTAMP()
        FROM batch
      """,
        PROJECT_ID, DATASET_ID, products_table,
        PROJECT_ID, DATASET_ID, products_table,
        PROJECT_ID, DATASET_ID,
        batch_size, offset_val,
        PROJECT_ID, DATASET_ID,
        PROJECT_ID, DATASET_ID,
        PROJECT_ID, DATASET_ID
      );
      
      -- Log progress
      INSERT INTO `${PROJECT_ID}.${DATASET_ID}.processing_log`
      VALUES(
        CURRENT_TIMESTAMP(),
        'generate_visual_embeddings',
        products_table,
        offset_val,
        batch_size,
        'SUCCESS',
        NULL
      );
      
    EXCEPTION WHEN ERROR THEN
      INSERT INTO `${PROJECT_ID}.${DATASET_ID}.processing_log`
      VALUES(
        CURRENT_TIMESTAMP(),
        'generate_visual_embeddings',
        products_table,
        offset_val,
        batch_size,
        'ERROR',
        @@error.message
      );
    END;
    
    SET offset_val = offset_val + batch_size;
  END WHILE;
  
  -- Create vector indexes
  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE VECTOR INDEX `%s.%s.%s_visual_idx`
    ON `%s.%s.%s_visual_embeddings`(visual_embedding)
    OPTIONS(
      distance_type='COSINE',
      index_type='IVF',
      ivf_options='{"num_lists": 1000}'
    )
  """,
    PROJECT_ID, DATASET_ID, products_table,
    PROJECT_ID, DATASET_ID, products_table
  );
  
  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE VECTOR INDEX `%s.%s.%s_multimodal_idx`
    ON `%s.%s.%s_visual_embeddings`(multimodal_embedding)
    OPTIONS(
      distance_type='COSINE',
      index_type='IVF',
      ivf_options='{"num_lists": 1000}'
    )
  """,
    PROJECT_ID, DATASET_ID, products_table,
    PROJECT_ID, DATASET_ID, products_table
  );
END;

-- ============================================
-- CORE FUNCTION 4: Visual Similarity Search
-- ============================================
CREATE OR REPLACE TABLE FUNCTION `${PROJECT_ID}.${DATASET_ID}.visual_search`(
  query_image_uri STRING,
  search_table STRING,
  search_mode STRING DEFAULT 'visual',  -- visual, text, multimodal
  top_k INT64 DEFAULT 10,
  filters JSON DEFAULT NULL
)
AS (
  WITH query_embedding AS (
    SELECT
      CASE search_mode
        WHEN 'visual' THEN ML.GENERATE_EMBEDDING(
          MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
          CONTENT => query_image_uri,
          STRUCT(TRUE AS flatten_json_output)
        ).ml_generate_embedding_result
        WHEN 'multimodal' THEN ML.GENERATE_EMBEDDING(
          MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
          CONTENT => STRUCT(
            query_image_uri AS image,
            IFNULL(JSON_EXTRACT_SCALAR(filters, '$.text_query'), '') AS text
          ),
          STRUCT(TRUE AS flatten_json_output)
        ).ml_generate_embedding_result
      END AS embedding
  ),
  search_results AS (
    SELECT
      p.*,
      e.image_uri,
      1 - ML.DISTANCE(
        CASE search_mode
          WHEN 'visual' THEN e.visual_embedding
          WHEN 'multimodal' THEN e.multimodal_embedding
        END,
        q.embedding,
        'COSINE'
      ) AS similarity_score
    FROM query_embedding q
    CROSS JOIN search_table e
    JOIN `${PROJECT_ID}.${DATASET_ID}.products` p ON e.sku = p.sku
    WHERE 
      -- Apply filters
      (JSON_EXTRACT_SCALAR(filters, '$.category') IS NULL OR 
       p.category = JSON_EXTRACT_SCALAR(filters, '$.category'))
      AND (JSON_EXTRACT_SCALAR(filters, '$.max_price') IS NULL OR 
           p.price <= CAST(JSON_EXTRACT_SCALAR(filters, '$.max_price') AS FLOAT64))
      AND (JSON_EXTRACT_SCALAR(filters, '$.brand') IS NULL OR 
           p.brand_name = JSON_EXTRACT_SCALAR(filters, '$.brand'))
    ORDER BY similarity_score DESC
    LIMIT top_k
  ),
  enhanced_results AS (
    SELECT
      *,
      -- Explain visual similarity
      AI.GENERATE(
        PROMPT => CONCAT(
          'Compare these product images and explain key visual similarities (30 words):\n',
          'Query image: ', query_image_uri, '\n',
          'Result image: ', image_uri
        ),
        connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
      ) AS similarity_explanation,
      
      -- Style match score
      AI.GENERATE_DOUBLE(
        CONCAT(
          'Rate style match (0-10) between these images:\n',
          'Query: ', query_image_uri, '\n',
          'Result: ', image_uri
        ),
        connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
      ) AS style_match_score
      
    FROM search_results
  )
  SELECT 
    sku,
    brand_name,
    product_name,
    category,
    price,
    image_uri,
    ROUND(similarity_score * 100, 1) AS visual_similarity_percent,
    similarity_explanation,
    ROUND(style_match_score, 1) AS style_score,
    CASE 
      WHEN similarity_score > 0.9 THEN 'Nearly Identical'
      WHEN similarity_score > 0.8 THEN 'Very Similar'
      WHEN similarity_score > 0.7 THEN 'Similar Style'
      ELSE 'Related'
    END AS match_quality
  FROM enhanced_results
  ORDER BY similarity_score DESC
);

-- ============================================
-- CORE FUNCTION 5: Quality Control Automation
-- ============================================
CREATE OR REPLACE PROCEDURE `${PROJECT_ID}.${DATASET_ID}.run_visual_quality_control`(
  products_table STRING,
  qc_threshold FLOAT64 DEFAULT 7.0
)
BEGIN
  -- Create QC results table
  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE TABLE `%s.%s.quality_control_results` AS
    WITH qc_analysis AS (
      SELECT * FROM `%s.%s.analyze_product_images`(
        '%s.%s.%s',
        '%s.%s.product_images',
        'comprehensive'
      )
    )
    SELECT
      sku,
      brand_name,
      product_name,
      category,
      price,
      image_uri,
      
      -- Quality metrics
      CAST(quality_score AS FLOAT64) AS quality_score,
      quality_score < %f AS needs_reshoot,
      
      -- Compliance
      is_compliant,
      NOT is_compliant AS compliance_violation,
      
      -- Attribute validation
      color_matches,
      detected_color != listed_color AS color_mismatch,
      
      -- Risk assessment
      authenticity_score,
      counterfeit_risk_level,
      
      -- Automated fixes
      CASE
        WHEN NOT color_matches AND detected_color IS NOT NULL THEN
          AI.GENERATE(
            PROMPT => CONCAT(
              'Generate SQL UPDATE statement to fix color from "',
              listed_color, '" to "', detected_color, '" for SKU ', sku
            ),
            connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
          )
        ELSE NULL
      END AS color_fix_sql,
      
      -- Recommendations
      CASE
        WHEN CAST(quality_score AS FLOAT64) < 5 THEN 'Urgent: Reshoot required'
        WHEN CAST(quality_score AS FLOAT64) < 7 THEN 'Schedule reshoot'
        WHEN NOT is_compliant THEN 'Add compliance labels'
        WHEN authenticity_score < 0.5 THEN 'Investigate supplier'
        ELSE 'Pass'
      END AS action_required,
      
      -- Business impact
      CASE
        WHEN NOT is_compliant THEN 'High - Regulatory Risk'
        WHEN authenticity_score < 0.5 THEN 'High - Brand Risk'
        WHEN CAST(quality_score AS FLOAT64) < 5 THEN 'Medium - Customer Experience'
        ELSE 'Low'
      END AS priority,
      
      potential_loss,
      analysis_timestamp
      
    FROM qc_analysis
    WHERE 
      NOT is_compliant 
      OR CAST(quality_score AS FLOAT64) < %f
      OR authenticity_score < 0.7
      OR NOT color_matches
    ORDER BY potential_loss DESC
  """,
    PROJECT_ID, DATASET_ID,
    PROJECT_ID, DATASET_ID,
    PROJECT_ID, DATASET_ID, products_table,
    PROJECT_ID, DATASET_ID,
    qc_threshold,
    PROJECT_ID, DATASET_ID,
    qc_threshold
  );
  
  -- Create QC summary
  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE TABLE `%s.%s.qc_summary` AS
    SELECT
      category,
      COUNT(*) AS products_checked,
      SUM(CASE WHEN needs_reshoot THEN 1 ELSE 0 END) AS poor_quality_images,
      SUM(CASE WHEN compliance_violation THEN 1 ELSE 0 END) AS compliance_issues,
      SUM(CASE WHEN color_mismatch THEN 1 ELSE 0 END) AS color_mismatches,
      SUM(CASE WHEN counterfeit_risk_level IN ('High Risk', 'Medium Risk') THEN 1 ELSE 0 END) AS counterfeit_risks,
      SUM(potential_loss) AS total_potential_loss,
      COUNT(*) - SUM(CASE WHEN action_required = 'Pass' THEN 1 ELSE 0 END) AS total_issues
    FROM `%s.%s.quality_control_results`
    GROUP BY category
    ORDER BY total_potential_loss DESC
  """,
    PROJECT_ID, DATASET_ID,
    PROJECT_ID, DATASET_ID
  );
  
  -- Log QC run
  INSERT INTO `${PROJECT_ID}.${DATASET_ID}.qc_run_log`
  SELECT
    GENERATE_UUID() AS qc_run_id,
    CURRENT_TIMESTAMP() AS run_timestamp,
    COUNT(*) AS products_analyzed,
    SUM(CASE WHEN action_required != 'Pass' THEN 1 ELSE 0 END) AS issues_found,
    SUM(potential_loss) AS total_risk_value,
    AVG(CAST(quality_score AS FLOAT64)) AS avg_quality_score,
    SUM(CASE WHEN compliance_violation THEN 1 ELSE 0 END) AS compliance_violations,
    SUM(CASE WHEN counterfeit_risk_level IN ('High Risk', 'Medium Risk') THEN 1 ELSE 0 END) AS counterfeit_suspects
  FROM `${PROJECT_ID}.${DATASET_ID}.quality_control_results`;
  
END;

-- ============================================
-- CORE FUNCTION 6: Visual Merchandising
-- ============================================
CREATE OR REPLACE TABLE FUNCTION `${PROJECT_ID}.${DATASET_ID}.optimize_visual_merchandising`(
  category STRING,
  style_profile JSON DEFAULT NULL
)
AS (
  WITH category_products AS (
    SELECT 
      p.*,
      e.visual_embedding,
      a.quality_score,
      a.extracted_attributes
    FROM `${PROJECT_ID}.${DATASET_ID}.products` p
    JOIN `${PROJECT_ID}.${DATASET_ID}.products_visual_embeddings` e ON p.sku = e.sku
    JOIN `${PROJECT_ID}.${DATASET_ID}.quality_control_results` a ON p.sku = a.sku
    WHERE p.category = category
      AND a.quality_score >= 7  -- Only high-quality images
  ),
  -- Find visual clusters
  visual_groups AS (
    SELECT
      *,
      -- Group visually similar products
      DENSE_RANK() OVER (
        ORDER BY 
          ROUND(visual_embedding[OFFSET(0)], 2),  -- Simplified clustering
          ROUND(visual_embedding[OFFSET(1)], 2)
      ) AS visual_group
    FROM category_products
  ),
  -- Analyze each group
  group_analysis AS (
    SELECT
      visual_group,
      COUNT(*) AS group_size,
      AVG(price) AS avg_price,
      STRING_AGG(DISTINCT extracted_attributes.primary_color, ', ') AS color_palette,
      STRING_AGG(DISTINCT brand_name, ', ') AS brands,
      
      -- AI merchandising recommendations
      ML.GENERATE_TEXT(
        MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_text_model`,
        PROMPT => CONCAT(
          'Create visual merchandising strategy for these products:\n',
          'Category: ', category, '\n',
          'Colors: ', STRING_AGG(DISTINCT extracted_attributes.primary_color, ', '), '\n',
          'Price range: $', CAST(MIN(price) AS STRING), '-$', CAST(MAX(price) AS STRING), '\n',
          'Suggest: hero product, supporting products, display layout (50 words)'
        ),
        STRUCT(0.7 AS temperature, 70 AS max_output_tokens)
      ).generated_text AS merchandising_strategy,
      
      -- Select hero product (best quality + median price)
      ARRAY_AGG(
        STRUCT(sku, product_name, price, quality_score)
        ORDER BY ABS(price - AVG(price) OVER()) + (10 - quality_score)
        LIMIT 1
      )[OFFSET(0)] AS hero_product
      
    FROM visual_groups
    GROUP BY visual_group
  )
  SELECT
    visual_group,
    hero_product.sku AS hero_sku,
    hero_product.product_name AS hero_product_name,
    hero_product.price AS hero_price,
    group_size,
    color_palette,
    brands,
    merchandising_strategy,
    
    -- ROI projection
    group_size * avg_price * 0.02 AS projected_lift_value,  -- 2% conversion lift
    
    -- Implementation priority
    CASE
      WHEN group_size >= 10 THEN 'High'
      WHEN group_size >= 5 THEN 'Medium'
      ELSE 'Low'
    END AS priority
    
  FROM group_analysis
  WHERE group_size >= 3  -- Minimum products for display
  ORDER BY projected_lift_value DESC
);

-- ============================================
-- MONITORING & ANALYTICS
-- ============================================

CREATE TABLE IF NOT EXISTS `${PROJECT_ID}.${DATASET_ID}.processing_log` (
  timestamp TIMESTAMP,
  operation STRING,
  table_name STRING,
  offset_processed INT64,
  batch_size INT64,
  status STRING,
  error_message STRING
);

CREATE TABLE IF NOT EXISTS `${PROJECT_ID}.${DATASET_ID}.qc_run_log` (
  qc_run_id STRING,
  run_timestamp TIMESTAMP,
  products_analyzed INT64,
  issues_found INT64,
  total_risk_value FLOAT64,
  avg_quality_score FLOAT64,
  compliance_violations INT64,
  counterfeit_suspects INT64
);

CREATE TABLE IF NOT EXISTS `${PROJECT_ID}.${DATASET_ID}.visual_search_log` (
  search_id STRING DEFAULT GENERATE_UUID(),
  query_image_uri STRING,
  search_mode STRING,
  results_returned INT64,
  avg_similarity_score FLOAT64,
  search_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  user_action STRING,
  clicked_sku STRING
);

-- Performance monitoring view
CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.multimodal_performance_dashboard` AS
WITH qc_metrics AS (
  SELECT
    DATE(run_timestamp) AS date,
    COUNT(*) AS qc_runs,
    SUM(products_analyzed) AS total_products_checked,
    SUM(issues_found) AS total_issues_found,
    SUM(compliance_violations) AS compliance_violations,
    SUM(counterfeit_suspects) AS counterfeit_detections,
    SUM(total_risk_value) AS risk_prevented,
    AVG(avg_quality_score) AS avg_quality
  FROM `${PROJECT_ID}.${DATASET_ID}.qc_run_log`
  WHERE run_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  GROUP BY date
),
search_metrics AS (
  SELECT
    DATE(search_timestamp) AS date,
    COUNT(*) AS visual_searches,
    AVG(results_returned) AS avg_results,
    AVG(avg_similarity_score) AS avg_match_quality,
    COUNT(DISTINCT query_image_uri) AS unique_images_searched
  FROM `${PROJECT_ID}.${DATASET_ID}.visual_search_log`
  WHERE search_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  GROUP BY date
),
roi_summary AS (
  SELECT
    CURRENT_DATE() AS date,
    -- QC savings
    (SELECT SUM(risk_prevented) FROM qc_metrics) AS total_risk_prevented,
    -- Time savings (5 min manual QC per product)
    (SELECT SUM(total_products_checked) * 5 / 60 FROM qc_metrics) AS hours_saved,
    -- Visual search value (assume 20% conversion lift)
    (SELECT COUNT(*) * 50 * 0.2 FROM search_metrics) AS search_revenue_impact
)
SELECT
  COALESCE(q.date, s.date, r.date) AS date,
  -- QC metrics
  q.qc_runs,
  q.total_products_checked,
  q.total_issues_found,
  q.compliance_violations,
  q.counterfeit_detections,
  q.risk_prevented,
  q.avg_quality,
  -- Search metrics  
  s.visual_searches,
  s.avg_match_quality,
  -- ROI metrics
  r.total_risk_prevented AS monthly_risk_prevented,
  r.hours_saved * 50 AS labor_cost_saved,  -- $50/hour
  r.search_revenue_impact,
  r.total_risk_prevented + (r.hours_saved * 50) + r.search_revenue_impact AS total_monthly_value
FROM qc_metrics q
FULL OUTER JOIN search_metrics s ON q.date = s.date
FULL OUTER JOIN roi_summary r ON q.date = r.date
ORDER BY date DESC;

-- ============================================
-- UTILITY FUNCTIONS
-- ============================================

-- Estimate processing costs
CREATE OR REPLACE FUNCTION `${PROJECT_ID}.${DATASET_ID}.estimate_multimodal_cost`(
  image_count INT64,
  analysis_type STRING
) RETURNS FLOAT64
LANGUAGE SQL AS (
  CASE analysis_type
    WHEN 'analyze_image' THEN image_count * 0.002  -- $0.002 per image
    WHEN 'visual_embedding' THEN image_count * 0.0001  -- $0.0001 per embedding
    WHEN 'quality_assessment' THEN image_count * 0.003  -- $0.003 per assessment
    WHEN 'visual_search' THEN image_count * 0.00001  -- $0.00001 per search
    ELSE image_count * 0.001
  END
);
