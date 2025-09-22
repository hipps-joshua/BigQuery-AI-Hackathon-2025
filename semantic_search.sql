-- Find similar products using embeddings
-- Replace paths with your PROJECT_ID.DATASET_ID

WITH search_query AS (
  SELECT ml_generate_embedding_result as query_embedding
  FROM ML.GENERATE_EMBEDDING(
    MODEL `PROJECT_ID.DATASET_ID.gemini_embedding_model`,
    (SELECT 'comfortable running shoes for daily training' AS content)
  )
),
similarity_scores AS (
  SELECT 
    p.name,
    p.category,
    p.price,
    -- Calculate cosine similarity
    (
      SUM(p_emb * q_emb) / 
      (SQRT(SUM(POW(p_emb, 2))) * SQRT(SUM(POW(q_emb, 2))))
    ) AS similarity
  FROM 
    `PROJECT_ID.DATASET_ID.product_embeddings` p,
    UNNEST(p.embedding) AS p_emb WITH OFFSET AS p_idx,
    search_query sq,
    UNNEST(sq.query_embedding) AS q_emb WITH OFFSET AS q_idx
  WHERE p_idx = q_idx
  GROUP BY p.name, p.category, p.price
)
SELECT 
  name,
  category,
  price,
  ROUND(similarity, 3) as similarity_score,
  CASE 
    WHEN similarity > 0.7 THEN 'Highly Relevant'
    WHEN similarity > 0.5 THEN 'Relevant'
    ELSE 'Somewhat Relevant'
  END as relevance
FROM similarity_scores
ORDER BY similarity DESC
LIMIT 5;
