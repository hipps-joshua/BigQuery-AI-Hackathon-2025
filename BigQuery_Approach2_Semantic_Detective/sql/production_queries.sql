-- ============================================
-- APPROACH 2: SEMANTIC DETECTIVE - PRODUCTION QUERIES
-- ============================================
-- Using ML.GENERATE_EMBEDDING for vector search
-- Plus ALL AI.* functions for enhanced intelligence
-- Includes CREATE VECTOR INDEX for scale

-- ============================================
-- SETUP: Create dataset and models
-- ============================================

CREATE SCHEMA IF NOT EXISTS `${PROJECT_ID}.${DATASET_ID}`
OPTIONS(
  location="us-central1",
  description="Semantic Detective - Intelligent Product Matching Platform"
);

-- ============================================
-- CORE FUNCTION 1: Multi-Aspect Embedding Generation
-- ============================================
CREATE OR REPLACE PROCEDURE `${PROJECT_ID}.${DATASET_ID}.generate_product_embeddings`(
  table_name STRING,
  batch_size INT64 DEFAULT 1000
)
BEGIN
  DECLARE offset_val INT64 DEFAULT 0;
  DECLARE total_rows INT64;
  
  -- Get total count
  EXECUTE IMMEDIATE FORMAT("""
    SELECT COUNT(*) FROM `%s.%s.%s` 
  """, PROJECT_ID, DATASET_ID, table_name) INTO total_rows;
  
  -- Create embedding table
  EXECUTE IMMEDIATE FORMAT("""
    CREATE TABLE IF NOT EXISTS `%s.%s.%s_embeddings` (
      sku STRING NOT NULL,
      full_text STRING,
      full_embedding ARRAY<FLOAT64>,
      title_embedding ARRAY<FLOAT64>,
      attributes_embedding ARRAY<FLOAT64>,
      category_context STRING,
      embedding_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
    )
  """, PROJECT_ID, DATASET_ID, table_name);
  
  -- Process in batches
  WHILE offset_val < total_rows DO
    BEGIN
      EXECUTE IMMEDIATE FORMAT("""
        INSERT INTO `%s.%s.%s_embeddings`
        WITH batch AS (
          SELECT *
          FROM `%s.%s.%s`
          LIMIT %d OFFSET %d
        ),
        prepared_text AS (
          SELECT
            sku,
            -- Full text for general matching
            CONCAT(
              IFNULL(brand_name, ''), ' ',
              IFNULL(product_name, ''), ' ',
              IFNULL(description, ''), ' ',
              IFNULL(category, ''), ' ',
              IFNULL(subcategory, ''), ' ',
              'Color: ', IFNULL(color, ''), ' ',
              'Size: ', IFNULL(size, ''), ' ',
              'Material: ', IFNULL(material, '')
            ) AS full_text,
            -- Title for exact matches
            CONCAT(IFNULL(brand_name, ''), ' ', IFNULL(product_name, '')) AS title_text,
            -- Attributes for technical matching
            CONCAT(
              'Category: ', IFNULL(category, ''), ' ',
              'Color: ', IFNULL(color, ''), ' ',
              'Size: ', IFNULL(size, ''), ' ',
              'Material: ', IFNULL(material, ''), ' ',
              'Price: $', CAST(price AS STRING)
            ) AS attributes_text,
            category AS category_context
          FROM batch
        )
        SELECT
          sku,
          full_text,
          ML.GENERATE_EMBEDDING(
            MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
            CONTENT => full_text,
            STRUCT(TRUE AS flatten_json_output)
          ).ml_generate_embedding_result AS full_embedding,
          ML.GENERATE_EMBEDDING(
            MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
            CONTENT => title_text,
            STRUCT(TRUE AS flatten_json_output)
          ).ml_generate_embedding_result AS title_embedding,
          ML.GENERATE_EMBEDDING(
            MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
            CONTENT => attributes_text,
            STRUCT(TRUE AS flatten_json_output)
          ).ml_generate_embedding_result AS attributes_embedding,
          category_context,
          CURRENT_TIMESTAMP()
        FROM prepared_text
      """,
        PROJECT_ID, DATASET_ID, table_name,
        PROJECT_ID, DATASET_ID, table_name, batch_size, offset_val,
        PROJECT_ID, DATASET_ID,
        PROJECT_ID, DATASET_ID,
        PROJECT_ID, DATASET_ID
      );
      
      -- Log success
      INSERT INTO `${PROJECT_ID}.${DATASET_ID}.processing_log`
      VALUES(
        CURRENT_TIMESTAMP(),
        'generate_embeddings',
        table_name,
        offset_val,
        batch_size,
        'SUCCESS',
        NULL
      );
      
    EXCEPTION WHEN ERROR THEN
      -- Log error
      INSERT INTO `${PROJECT_ID}.${DATASET_ID}.processing_log`
      VALUES(
        CURRENT_TIMESTAMP(),
        'generate_embeddings',
        table_name,
        offset_val,
        batch_size,
        'ERROR',
        @@error.message
      );
    END;
    
    SET offset_val = offset_val + batch_size;
  END WHILE;
END;

-- ============================================
-- CORE FUNCTION 2: Create Vector Index for Scale
-- ============================================
CREATE OR REPLACE PROCEDURE `${PROJECT_ID}.${DATASET_ID}.create_vector_search_index`(
  table_name STRING,
  embedding_column STRING DEFAULT 'full_embedding'
)
BEGIN
  DECLARE index_name STRING;
  SET index_name = CONCAT(table_name, '_', embedding_column, '_idx');
  
  -- Create vector index for fast similarity search
  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE VECTOR INDEX `%s.%s.%s`
    ON `%s.%s.%s_embeddings`(%s)
    OPTIONS(
      distance_type='COSINE',
      index_type='IVF',
      ivf_options='{"num_lists": 1000}'
    )
  """,
    PROJECT_ID, DATASET_ID, index_name,
    PROJECT_ID, DATASET_ID, table_name, embedding_column
  );
  
  -- Also create indexes for other embedding types
  IF embedding_column = 'full_embedding' THEN
    -- Title embedding index
    EXECUTE IMMEDIATE FORMAT("""
      CREATE OR REPLACE VECTOR INDEX `%s.%s.%s_title_idx`
      ON `%s.%s.%s_embeddings`(title_embedding)
      OPTIONS(
        distance_type='COSINE',
        index_type='IVF',
        ivf_options='{"num_lists": 500}'
      )
    """,
      PROJECT_ID, DATASET_ID, table_name,
      PROJECT_ID, DATASET_ID, table_name
    );
    
    -- Attributes embedding index
    EXECUTE IMMEDIATE FORMAT("""
      CREATE OR REPLACE VECTOR INDEX `%s.%s.%s_attributes_idx`
      ON `%s.%s.%s_embeddings`(attributes_embedding)
      OPTIONS(
        distance_type='COSINE',
        index_type='IVF',
        ivf_options='{"num_lists": 500}'
      )
    """,
      PROJECT_ID, DATASET_ID, table_name,
      PROJECT_ID, DATASET_ID, table_name
    );
  END IF;
END;

-- ============================================
-- CORE FUNCTION 3: Semantic Search with AI Enhancement
-- ============================================
CREATE OR REPLACE TABLE FUNCTION `${PROJECT_ID}.${DATASET_ID}.semantic_search`(
  query_text STRING,
  search_table STRING,
  search_type STRING DEFAULT 'full',  -- full, title, attributes
  top_k INT64 DEFAULT 10,
  min_similarity FLOAT64 DEFAULT 0.7
)
AS (
  WITH query_embedding AS (
    SELECT ML.GENERATE_EMBEDDING(
      MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
      CONTENT => query_text,
      STRUCT(TRUE AS flatten_json_output)
    ).ml_generate_embedding_result AS embedding
  ),
  search_results AS (
    SELECT
      p.*,
      e.full_text,
      1 - ML.DISTANCE(
        CASE search_type
          WHEN 'title' THEN e.title_embedding
          WHEN 'attributes' THEN e.attributes_embedding
          ELSE e.full_embedding
        END,
        q.embedding,
        'COSINE'
      ) AS similarity_score
    FROM query_embedding q
    CROSS JOIN `search_table` e
    JOIN `${PROJECT_ID}.${DATASET_ID}.products` p ON e.sku = p.sku
    WHERE 1 - ML.DISTANCE(
      CASE search_type
        WHEN 'title' THEN e.title_embedding
        WHEN 'attributes' THEN e.attributes_embedding
        ELSE e.full_embedding
      END,
      q.embedding,
      'COSINE'
    ) >= min_similarity
    ORDER BY similarity_score DESC
    LIMIT top_k
  ),
  enhanced_results AS (
    SELECT
      *,
      -- Add AI explanation of why this result matches
      ML.GENERATE_TEXT(
        MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_text_model`,
        PROMPT => CONCAT(
          'Explain in 2 sentences why "', product_name, 
          '" matches the search query "', query_text, 
          '". Focus on key similarities.'
        ),
        STRUCT(0.3 AS temperature, 50 AS max_output_tokens)
      ).generated_text AS match_explanation,
      
      -- Generate purchase recommendation
      AI.GENERATE_BOOL(
        CONCAT(
          'Would "', product_name, '" be a good match for someone searching for "',
          query_text, '"? Consider features, use case, and price point.'
        ),
        connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
      ) AS is_recommended
    FROM search_results
  )
  SELECT * FROM enhanced_results
  WHERE is_recommended = TRUE OR similarity_score >= 0.85
);

-- ============================================
-- CORE FUNCTION 4: Intelligent Duplicate Detection
-- ============================================
CREATE OR REPLACE PROCEDURE `${PROJECT_ID}.${DATASET_ID}.find_duplicate_products`(
  table_name STRING,
  similarity_threshold FLOAT64 DEFAULT 0.9
)
BEGIN
  -- Create duplicate candidates table
  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE TABLE `%s.%s.duplicate_candidates` AS
    WITH embeddings AS (
      SELECT * FROM `%s.%s.%s_embeddings`
    ),
    -- Find similar products using different strategies
    similarity_pairs AS (
      SELECT
        e1.sku AS sku1,
        e2.sku AS sku2,
        p1.brand_name AS brand1,
        p2.brand_name AS brand2,
        p1.product_name AS product1,
        p2.product_name AS product2,
        p1.price AS price1,
        p2.price AS price2,
        -- Multiple similarity scores
        1 - ML.DISTANCE(e1.full_embedding, e2.full_embedding, 'COSINE') AS full_similarity,
        1 - ML.DISTANCE(e1.title_embedding, e2.title_embedding, 'COSINE') AS title_similarity,
        1 - ML.DISTANCE(e1.attributes_embedding, e2.attributes_embedding, 'COSINE') AS attribute_similarity
      FROM embeddings e1
      JOIN embeddings e2 ON e1.sku < e2.sku
      JOIN `%s.%s.products` p1 ON e1.sku = p1.sku
      JOIN `%s.%s.products` p2 ON e2.sku = p2.sku
      WHERE
        -- Same category constraint for efficiency
        e1.category_context = e2.category_context
        -- At least one similarity is high
        AND (
          1 - ML.DISTANCE(e1.full_embedding, e2.full_embedding, 'COSINE') >= %f
          OR 1 - ML.DISTANCE(e1.title_embedding, e2.title_embedding, 'COSINE') >= 0.95
          OR 1 - ML.DISTANCE(e1.attributes_embedding, e2.attributes_embedding, 'COSINE') >= 0.85
        )
    ),
    -- Use AI to validate duplicates
    validated_duplicates AS (
      SELECT
        *,
        -- Weighted similarity score
        (full_similarity * 0.5 + title_similarity * 0.3 + attribute_similarity * 0.2) AS combined_score,
        
        -- AI validation
        AI.GENERATE_BOOL(
          PROMPT => CONCAT(
            'Are these the same product? (Answer TRUE/FALSE only)\n',
            'Product 1: ', brand1, ' ', product1, ' ($', CAST(price1 AS STRING), ')\n',
            'Product 2: ', brand2, ' ', product2, ' ($', CAST(price2 AS STRING), ')\n',
            'Title similarity: ', CAST(ROUND(title_similarity * 100, 1) AS STRING), '%%\n',
            'Attribute similarity: ', CAST(ROUND(attribute_similarity * 100, 1) AS STRING), '%%'
          ),
          connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
        ) AS is_duplicate,
        
        -- Merge recommendation
        ML.GENERATE_TEXT(
          MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_text_model`,
          PROMPT => CONCAT(
            'If these are duplicates, which SKU should be kept? ',
            'SKU1: ', sku1, ' (', brand1, ' ', product1, ', $', CAST(price1 AS STRING), ')\n',
            'SKU2: ', sku2, ' (', brand2, ' ', product2, ', $', CAST(price2 AS STRING), ')\n',
            'Respond with just the SKU to keep and brief reason (20 words max).'
          ),
          STRUCT(0.2 AS temperature, 30 AS max_output_tokens)
        ).generated_text AS merge_recommendation,
        
        -- Business impact
        ABS(price1 - price2) * 100 AS potential_revenue_loss,
        CURRENT_TIMESTAMP() AS detected_at
      FROM similarity_pairs
    )
    SELECT * FROM validated_duplicates
    WHERE is_duplicate = TRUE
    ORDER BY combined_score DESC, potential_revenue_loss DESC
  """,
    PROJECT_ID, DATASET_ID,
    PROJECT_ID, DATASET_ID, table_name,
    PROJECT_ID, DATASET_ID,
    PROJECT_ID, DATASET_ID,
    similarity_threshold,
    PROJECT_ID, DATASET_ID,
    PROJECT_ID, DATASET_ID
  );
  
  -- Create duplicate groups using clustering
  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE TABLE `%s.%s.duplicate_groups` AS
    WITH duplicate_graph AS (
      -- Build graph of all duplicate relationships
      SELECT DISTINCT
        CASE WHEN sku1 < sku2 THEN sku1 ELSE sku2 END AS sku_a,
        CASE WHEN sku1 < sku2 THEN sku2 ELSE sku1 END AS sku_b
      FROM `%s.%s.duplicate_candidates`
    ),
    -- Find connected components (duplicate groups)
    groups AS (
      SELECT 
        sku_a AS sku,
        DENSE_RANK() OVER (ORDER BY MIN(sku_a) OVER (PARTITION BY sku_b)) AS group_id
      FROM duplicate_graph
      UNION DISTINCT
      SELECT 
        sku_b AS sku,
        DENSE_RANK() OVER (ORDER BY MIN(sku_a) OVER (PARTITION BY sku_b)) AS group_id
      FROM duplicate_graph
    )
    SELECT 
      g.group_id,
      g.sku,
      p.brand_name,
      p.product_name,
      p.price,
      COUNT(*) OVER (PARTITION BY g.group_id) AS group_size,
      SUM(p.price) OVER (PARTITION BY g.group_id) - MIN(p.price) OVER (PARTITION BY g.group_id) AS inventory_savings
    FROM groups g
    JOIN `%s.%s.products` p ON g.sku = p.sku
    ORDER BY group_id, price DESC
  """,
    PROJECT_ID, DATASET_ID,
    PROJECT_ID, DATASET_ID,
    PROJECT_ID, DATASET_ID
  );
END;

-- ============================================
-- CORE FUNCTION 5: Smart Product Substitutes
-- ============================================
CREATE OR REPLACE TABLE FUNCTION `${PROJECT_ID}.${DATASET_ID}.find_substitutes`(
  product_sku STRING,
  max_price_variance FLOAT64 DEFAULT 0.3,
  top_k INT64 DEFAULT 10
)
AS (
  WITH target_product AS (
    SELECT 
      p.*,
      e.full_embedding,
      e.attributes_embedding
    FROM `${PROJECT_ID}.${DATASET_ID}.products` p
    JOIN `${PROJECT_ID}.${DATASET_ID}.products_embeddings` e ON p.sku = e.sku
    WHERE p.sku = product_sku
  ),
  candidates AS (
    SELECT
      p.*,
      e.full_embedding,
      e.attributes_embedding,
      t.price AS target_price,
      t.category AS target_category,
      t.brand_name AS target_brand,
      t.product_name AS target_product_name,
      -- Similarity scores
      1 - ML.DISTANCE(e.full_embedding, t.full_embedding, 'COSINE') AS overall_similarity,
      1 - ML.DISTANCE(e.attributes_embedding, t.attributes_embedding, 'COSINE') AS attribute_similarity
    FROM `${PROJECT_ID}.${DATASET_ID}.products` p
    JOIN `${PROJECT_ID}.${DATASET_ID}.products_embeddings` e ON p.sku = e.sku
    CROSS JOIN target_product t
    WHERE 
      p.sku != product_sku
      -- Same category
      AND p.category = t.category
      -- Price within variance
      AND p.price BETWEEN t.price * (1 - max_price_variance) AND t.price * (1 + max_price_variance)
      -- Reasonable similarity
      AND 1 - ML.DISTANCE(e.attributes_embedding, t.attributes_embedding, 'COSINE') >= 0.5
  ),
  ranked_substitutes AS (
    SELECT
      *,
      -- AI-powered substitute scoring
      AI.GENERATE_DOUBLE(
        PROMPT => CONCAT(
          'Rate how good a substitute this is (0-10 scale):\n',
          'Original: ', target_brand, ' ', target_product_name, ' ($', CAST(target_price AS STRING), ')\n',
          'Substitute: ', brand_name, ' ', product_name, ' ($', CAST(price AS STRING), ')\n',
          'Category: ', category, '\n',
          'Similarity: ', CAST(ROUND(overall_similarity * 100, 1) AS STRING), '%\n',
          'Consider features, quality, and value. Return only a number 0-10.'
        ),
        connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
      ) AS substitute_score,
      
      -- Explanation
      ML.GENERATE_TEXT(
        MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_text_model`,
        PROMPT => CONCAT(
          'In 30 words, explain why ', brand_name, ' ', product_name,
          ' is a good substitute for ', target_brand, ' ', target_product_name
        ),
        STRUCT(0.5 AS temperature, 40 AS max_output_tokens)
      ).generated_text AS substitute_reason,
      
      -- Value comparison
      CASE 
        WHEN price < target_price THEN 'Better Value'
        WHEN price = target_price THEN 'Same Price'
        ELSE 'Premium Option'
      END AS price_comparison,
      
      ROUND((target_price - price) / target_price * 100, 1) AS savings_percent
    FROM candidates
  )
  SELECT 
    sku,
    brand_name,
    product_name,
    price,
    ROUND(substitute_score, 1) AS substitute_score,
    substitute_reason,
    price_comparison,
    savings_percent,
    ROUND(overall_similarity * 100, 1) AS similarity_percent
  FROM ranked_substitutes
  WHERE substitute_score >= 6.0
  ORDER BY substitute_score DESC, overall_similarity DESC
  LIMIT top_k
);

-- ============================================
-- CORE FUNCTION 6: Cross-Sell Recommendations
-- ============================================
CREATE OR REPLACE TABLE FUNCTION `${PROJECT_ID}.${DATASET_ID}.generate_cross_sell`(
  product_sku STRING,
  customer_segment STRING DEFAULT 'general'
)
AS (
  WITH target_product AS (
    SELECT * FROM `${PROJECT_ID}.${DATASET_ID}.products`
    WHERE sku = product_sku
  ),
  -- Find frequently bought together using embeddings
  related_products AS (
    SELECT DISTINCT
      p2.sku,
      p2.brand_name,
      p2.product_name,
      p2.category,
      p2.price,
      -- Different category bonus
      CASE WHEN p2.category != t.category THEN 0.2 ELSE 0.0 END AS category_bonus
    FROM target_product t
    CROSS JOIN `${PROJECT_ID}.${DATASET_ID}.products` p2
    JOIN `${PROJECT_ID}.${DATASET_ID}.products_embeddings` e1 ON t.sku = e1.sku
    JOIN `${PROJECT_ID}.${DATASET_ID}.products_embeddings` e2 ON p2.sku = e2.sku
    WHERE 
      p2.sku != product_sku
      -- Moderate similarity (complementary, not duplicate)
      AND 1 - ML.DISTANCE(e1.full_embedding, e2.full_embedding, 'COSINE') BETWEEN 0.4 AND 0.8
  ),
  scored_recommendations AS (
    SELECT
      *,
      -- AI cross-sell scoring
      AI.GENERATE_BOOL(
        CONCAT(
          'Would a ', customer_segment, ' customer who bought "', 
          (SELECT product_name FROM target_product), 
          '" also want "', product_name, '"? ',
          'Consider complementary usage and customer needs.'
        ),
        connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
      ) AS is_good_cross_sell,
      
      AI.GENERATE(
        PROMPT => CONCAT(
          'In 20 words, explain why someone who bought ',
          (SELECT product_name FROM target_product),
          ' would also want ', product_name
        ),
        connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
      ) AS cross_sell_reason,
      
      -- Bundle pricing
      (SELECT price FROM target_product) + price AS bundle_price,
      ROUND(((SELECT price FROM target_product) + price) * 0.9, 2) AS bundle_discount_price
    FROM related_products
  )
  SELECT
    sku,
    brand_name,
    product_name,
    category,
    price,
    cross_sell_reason,
    bundle_price,
    bundle_discount_price,
    ROUND((bundle_price - bundle_discount_price) / bundle_price * 100, 1) AS bundle_savings_percent
  FROM scored_recommendations
  WHERE is_good_cross_sell = TRUE
  ORDER BY category_bonus DESC, price ASC
  LIMIT 5
);

-- ============================================
-- MONITORING & ANALYTICS
-- ============================================

CREATE TABLE IF NOT EXISTS `${PROJECT_ID}.${DATASET_ID}.search_log` (
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

CREATE TABLE IF NOT EXISTS `${PROJECT_ID}.${DATASET_ID}.duplicate_detection_log` (
  detection_id STRING DEFAULT GENERATE_UUID(),
  run_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  total_products INT64,
  duplicate_pairs_found INT64,
  duplicate_groups_found INT64,
  estimated_savings FLOAT64,
  processing_time_seconds FLOAT64
);

-- Performance dashboard
CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.semantic_performance_dashboard` AS
WITH search_metrics AS (
  SELECT
    DATE(search_timestamp) AS date,
    COUNT(*) AS total_searches,
    AVG(results_count) AS avg_results_per_search,
    AVG(avg_similarity) AS avg_similarity_score,
    COUNT(DISTINCT query_text) AS unique_queries,
    SUM(CASE WHEN conversion THEN 1 ELSE 0 END) / COUNT(*) AS conversion_rate
  FROM `${PROJECT_ID}.${DATASET_ID}.search_log`
  WHERE search_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  GROUP BY date
),
duplicate_metrics AS (
  SELECT
    DATE(run_timestamp) AS date,
    SUM(duplicate_pairs_found) AS total_duplicates_found,
    SUM(estimated_savings) AS total_savings_identified,
    AVG(processing_time_seconds) AS avg_processing_time
  FROM `${PROJECT_ID}.${DATASET_ID}.duplicate_detection_log`
  WHERE run_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  GROUP BY date
)
SELECT
  COALESCE(s.date, d.date) AS date,
  s.total_searches,
  s.avg_results_per_search,
  s.avg_similarity_score,
  s.conversion_rate,
  d.total_duplicates_found,
  d.total_savings_identified,
  s.total_searches * 0.001 AS search_cost_usd,  -- Estimated cost
  d.total_duplicates_found * 50 AS duplicate_value_usd  -- $50 per duplicate found
FROM search_metrics s
FULL OUTER JOIN duplicate_metrics d ON s.date = d.date
ORDER BY date DESC;

-- ============================================
-- VECTOR SEARCH FUNCTION
-- ============================================
CREATE OR REPLACE FUNCTION `${PROJECT_ID}.${DATASET_ID}.vector_search`(
  base_table STRING,
  query_embedding ARRAY<FLOAT64>,
  top_k INT64,
  options JSON
) RETURNS TABLE<sku STRING, score FLOAT64>
LANGUAGE SQL AS (
  SELECT
    sku,
    1 - ML.DISTANCE(full_embedding, query_embedding, 'COSINE') AS score
  FROM `base_table`
  WHERE 1 - ML.DISTANCE(full_embedding, query_embedding, 'COSINE') >= 
    CAST(JSON_EXTRACT_SCALAR(options, '$.min_similarity') AS FLOAT64)
  ORDER BY score DESC
  LIMIT top_k
);

-- ============================================
-- NATIVE VECTOR_SEARCH (INDEX + DEMO VIEW)
-- ============================================

-- Create or replace vector index for full embeddings (recommended for large tables)
CREATE OR REPLACE VECTOR INDEX `${PROJECT_ID}.${DATASET_ID}.products_embeddings_full_idx`
ON `${PROJECT_ID}.${DATASET_ID}.products_embeddings`(full_embedding)
OPTIONS(
  distance_type='COSINE',
  index_type='IVF',
  ivf_options='{"num_lists": 1000}'
);

-- Demonstration view using native VECTOR_SEARCH
CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.native_vector_search_demo` AS
WITH q AS (
  SELECT ML.GENERATE_EMBEDDING(
    MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
    CONTENT => 'comfortable black running shoes',
    STRUCT(TRUE AS flatten_json_output)
  ).ml_generate_embedding_result AS emb
)
SELECT vs.*
FROM q, VECTOR_SEARCH(
  TABLE `${PROJECT_ID}.${DATASET_ID}.products_embeddings`,
  'full_embedding',
  q.emb,
  top_k => 10
) AS vs;
