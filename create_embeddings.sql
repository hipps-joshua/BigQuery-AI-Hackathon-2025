-- Generate embeddings for semantic search
-- Replace MODEL path with: PROJECT_ID.DATASET_ID.gemini_embedding_model

CREATE OR REPLACE TABLE `PROJECT_ID.DATASET_ID.product_embeddings` AS
WITH product_content AS (
  SELECT 
    sku,
    name,
    category,
    price,
    CONCAT(name, ' ', category, ' ', description) AS content
  FROM `PROJECT_ID.DATASET_ID.test_products`
)
SELECT 
  sku,
  name,
  category,
  price,
  content,
  ml_generate_embedding_result as embedding
FROM ML.GENERATE_EMBEDDING(
  MODEL `PROJECT_ID.DATASET_ID.gemini_embedding_model`,
  (SELECT * FROM product_content)
);
