-- PASTE THIS IN BIGQUERY CONSOLE
-- Shows IMMEDIATE PROOF that AI is working

SELECT 
  '🎯 BIGQUERY AI - LIVE PROOF' as title,
  CURRENT_TIMESTAMP() as proof_generated_at,
  
  -- PROOF 1: AI responds uniquely
  AI.GENERATE(
    CONCAT('Generate a unique response at ', CAST(CURRENT_TIMESTAMP() AS STRING)),
    connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
  ).result as unique_ai_response,
  
  -- PROOF 2: AI makes decisions
  AI.GENERATE_BOOL(
    'Is BigQuery AI working right now?',
    connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
  ).result as ai_status_check,
  
  -- PROOF 3: AI analyzes numbers
  AI.GENERATE_DOUBLE(
    'Rate your confidence level 1-10 that this is working',
    connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
  ).result as confidence_score,
  
  '✅ If you see results above, IT WORKS!' as conclusion;
