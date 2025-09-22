-- Run comprehensive AI analysis
-- Replace connection_id with: PROJECT_ID.LOCATION.gemini_connection

SELECT 
  name,
  category,
  price,
  
  -- Generate marketing description
  AI.GENERATE(
    CONCAT('Write a 20-word marketing description for: ', name),
    connection_id => 'CONNECTION_ID_HERE'
  ).result as marketing_copy,
  
  -- Check if premium
  AI.GENERATE_BOOL(
    CONCAT('Is this a premium product? ', name, ' at $', CAST(price AS STRING)),
    connection_id => 'CONNECTION_ID_HERE'
  ).result as is_premium,
  
  -- Generate quality score
  AI.GENERATE_DOUBLE(
    CONCAT('Rate product appeal 1-10: ', name),
    connection_id => 'CONNECTION_ID_HERE'
  ).result as appeal_score
  
FROM `PROJECT_ID.DATASET_ID.test_products`
LIMIT 5;
