-- ============================================================
-- BIGQUERY AI HACKATHON - ENTERPRISE DATA CHAOS SOLUTION
-- Public Notebook: Complete Implementation
-- ============================================================

-- HOW TO RUN THIS NOTEBOOK
-- This script uses EXECUTE IMMEDIATE + FORMAT() for any statement that needs fully-qualified identifiers.
-- Set the three variables below (PROJECT_ID, LOCATION=us-central1, DATASET_ID), then run cells top-to-bottom.

-- PREREQUISITES:
-- Before running this notebook, ensure you have:
-- 1. Created a Gemini connection:
--    (Deprecated inline example below — use the UPDATED CLI EXAMPLE further down)
--    bq mk --connection --location=us-central1 --connection_type=CLOUD_RESOURCE \
--    bigquery-ai-hackathon-2025.us-central1.gemini_connection
-- 2. Created the embedding model:
--    CREATE OR REPLACE MODEL `PROJECT_ID.DATASET_ID.gemini_embedding_model`
--    REMOTE WITH CONNECTION `PROJECT_ID.us-central1.gemini_connection`
--    OPTIONS (endpoint = 'text-embedding-004');
-- 3. Note: Endpoint names may vary by region. Common endpoints:
--    - Text generation: 'gemini-2.0-flash-exp' or 'gemini-1.5-pro'
--    - Embeddings: 'text-embedding-004' or 'textembedding-gecko'
-- 4. For full setup, see the automated setup scripts in the repository
--
-- UPDATED CLI EXAMPLE (matches README):
--    bq mk --connection \
--      --location=us-central1 \
--      --project_id=PROJECT_ID \
--      --connection_type=CLOUD_RESOURCE \
--      gemini_connection

-- SETUP: Set your project variables
DECLARE PROJECT_ID STRING DEFAULT 'bigquery-ai-hackathon-2025';
DECLARE LOCATION STRING DEFAULT 'us-central1';
DECLARE DATASET_ID STRING DEFAULT 'test_dataset_central';

-- Convenience: fully-qualified IDs
DECLARE CONNECTION_ID STRING DEFAULT CONCAT(PROJECT_ID, '.', LOCATION, '.gemini_connection');

-- ============================================================
-- APPROACH 1: AI ARCHITECT 🧠
-- Using generative AI functions for intelligent analysis
-- ============================================================

-- 1.1 Basic AI.GENERATE for text summarization
SELECT
  'GitHub Issue: App crashes when uploading large files over 10MB' AS content,
  AI.GENERATE(
    'Summarize this GitHub issue in 15 words',
    CONNECTION_ID => CONCAT(PROJECT_ID, '.', LOCATION, '.gemini_connection')
  ).result AS summary;

-- 1.2 AI.GENERATE_BOOL for urgency detection
SELECT
  'CRITICAL: Production database is down, all services affected' AS issue,
  AI.GENERATE_BOOL(
    'Is this issue urgent and requires immediate attention?',
    CONNECTION_ID => CONCAT(PROJECT_ID, '.', LOCATION, '.gemini_connection')
  ).result AS is_urgent;

-- 1.3 AI.GENERATE_DOUBLE for sentiment scoring
SELECT
  'The new feature is amazing! Best update ever!' AS feedback,
  AI.GENERATE_DOUBLE(
    'Rate the sentiment of this feedback from 1 (negative) to 10 (positive)',
    CONNECTION_ID => CONCAT(PROJECT_ID, '.', LOCATION, '.gemini_connection')
  ).result AS sentiment_score;

-- 1.4 AI.GENERATE_TABLE for structured extraction
WITH raw_feedback AS (
  SELECT '''
  Customer John Doe reported slow performance on Chrome browser.
  Issue started on 2025-01-15. Priority seems high.
  Contact: john@example.com
  ''' AS feedback
)
SELECT
  AI.GENERATE_TABLE(
    CONCAT('Extract structured information from: ', feedback),
    CONNECTION_ID => CONCAT(PROJECT_ID, '.', LOCATION, '.gemini_connection'),
    SCHEMA => [
      'customer_name STRING',
      'browser STRING',
      'issue_type STRING',
      'date STRING',
      'priority STRING',
      'email STRING'
    ]
  ).result AS structured_data
FROM raw_feedback;

-- 1.5 Real-world implementation: Analyzing GitHub issues
WITH github_issues AS (
  SELECT
    'App crashes when uploading files' AS title,
    'Users report app crashes when uploading files larger than 10MB. Error: OutOfMemoryException' AS body,
    'bug' AS label,
    'open' AS status
  UNION ALL
  SELECT
    'Feature request: Dark mode',
    'Please add dark mode support for better viewing at night',
    'enhancement',
    'open'
  UNION ALL
  SELECT
    'Login timeout issues',
    'Login session expires too quickly, users need to re-login every 5 minutes',
    'bug',
    'closed'
)
SELECT
  title,
  -- Generate executive summary
  AI.GENERATE(
    CONCAT('Write a 20-word executive summary for: ', title, '. ', body),
    CONNECTION_ID => CONCAT(PROJECT_ID, '.', LOCATION, '.gemini_connection')
  ).result AS executive_summary,

  -- Determine urgency
  AI.GENERATE_BOOL(
    CONCAT('Is this issue urgent? Title: ', title, ' Body: ', body),
    CONNECTION_ID => CONCAT(PROJECT_ID, '.', LOCATION, '.gemini_connection')
  ).result AS is_urgent,

  -- Calculate business impact score
  AI.GENERATE_DOUBLE(
    CONCAT('Rate business impact 1-10 for: ', title),
    CONNECTION_ID => CONCAT(PROJECT_ID, '.', LOCATION, '.gemini_connection')
  ).result AS impact_score,

  -- Generate recommended action
  AI.GENERATE(
    CONCAT('What action should be taken for: ', title, '? Answer in 10 words.'),
    CONNECTION_ID => CONCAT(PROJECT_ID, '.', LOCATION, '.gemini_connection')
  ).result AS recommended_action

FROM github_issues;

-- ============================================================
-- APPROACH 2: SEMANTIC DETECTIVE 🕵️
-- Using embeddings and vector search for semantic analysis
-- ============================================================

-- 2.1 Create embeddings for content (dynamic identifiers)
EXECUTE IMMEDIATE FORMAT(
  'CREATE OR REPLACE TABLE `%s.%s.content_with_embeddings` AS\n'
  || 'WITH sample_content AS (\n'
  || '  SELECT \'\'Database connection timeout errors in production\'\' AS content, \'\'github\'\' AS source\n'
  || '  UNION ALL SELECT \'\'How to fix connection pool exhaustion?\'\', \'\'stackoverflow\'\'\n'
  || '  UNION ALL SELECT \'\'Customer complaint: app is very slow to load\'\', \'\'support\'\'\n'
  || '  UNION ALL SELECT \'\'Performance degradation after recent update\'\', \'\'github\'\'\n'
  || '  UNION ALL SELECT \'\'Best practices for database connection pooling\'\', \'\'documentation\'\'\n'
  || ')\n'
  || 'SELECT content, source,\n'
  || '  ML.GENERATE_EMBEDDING(\n'
  || '    MODEL `%s.%s.gemini_embedding_model`,\n'
  || '    content\n'
  || '  ) AS embedding\n'
  || 'FROM sample_content;',
  PROJECT_ID, DATASET_ID, PROJECT_ID, DATASET_ID
);

-- 2.2 Create vector index for fast search (optional)
EXECUTE IMMEDIATE FORMAT(
  'CREATE OR REPLACE VECTOR INDEX `%s.%s.content_index`\n'
  || 'ON `%s.%s.content_with_embeddings`(embedding)\n'
  || 'OPTIONS(index_type = \'\'IVF\'\', distance_type = \'\'COSINE\'\');',
  PROJECT_ID, DATASET_ID, PROJECT_ID, DATASET_ID
);

-- 2.3 Semantic search to find similar issues (dynamic + temp results)
EXECUTE IMMEDIATE FORMAT(
  'CREATE TEMP TABLE tmp_semantic_search AS\n'
  || 'WITH search_query AS (\n'
  || '  SELECT ML.GENERATE_EMBEDDING(\n'
  || '    MODEL `%s.%s.gemini_embedding_model`,\n'
  || '    \'\'database performance problems\'\'\n'
  || '  ) AS query_embedding\n'
  || ')\n'
  || 'SELECT base.content, base.source, search.distance, 1 - search.distance AS similarity_score\n'
  || 'FROM VECTOR_SEARCH(\n'
  || '  TABLE `%s.%s.content_with_embeddings`,\n'
  || '  \'\'embedding\'\',\n'
  || '  (SELECT query_embedding FROM search_query),\n'
  || '  top_k => 5\n'
  || ') AS search\n'
  || 'JOIN `%s.%s.content_with_embeddings` AS base\n'
  || '  ON search.row_id = base.row_id\n'
  || 'ORDER BY search.distance ASC;',
  PROJECT_ID, DATASET_ID, PROJECT_ID, DATASET_ID, PROJECT_ID, DATASET_ID
);

SELECT * FROM tmp_semantic_search;

-- 2.4 Cross-platform duplicate detection (dynamic + temp results)
EXECUTE IMMEDIATE FORMAT(
  'CREATE TEMP TABLE tmp_duplicates AS\n'
  || 'WITH all_issues AS (\n'
  || '  SELECT issue_id, platform, description,\n'
  || '         ML.GENERATE_EMBEDDING(\n'
  || '           MODEL `%s.%s.gemini_embedding_model`, description) AS embedding\n'
  || '  FROM (\n'
  || '    SELECT \'\'1\'\' AS issue_id, \'\'GitHub\'\' AS platform, \'\'Memory leak in file upload module\'\' AS description\n'
  || '    UNION ALL SELECT \'\'2\'\', \'\'StackOverflow\'\', \'\'How to debug memory leaks during file uploads?\'\'\n'
  || '    UNION ALL SELECT \'\'3\'\', \'\'Support\'\', \'\'App crashes when I upload large photos\'\'\n'
  || '    UNION ALL SELECT \'\'4\'\', \'\'GitHub\'\', \'\'OutOfMemoryError in FileUploadService.java\'\'\n'
  || '  )\n'
  || ')\n'
  || 'SELECT a.issue_id AS issue_1, b.issue_id AS issue_2, a.platform AS platform_1, b.platform AS platform_2,\n'
  || '       a.description AS description_1, b.description AS description_2,\n'
  || '       1 - ML.DISTANCE(a.embedding, b.embedding, \'\'COSINE\'\') AS similarity,\n'
  || '       CASE\n'
  || '         WHEN 1 - ML.DISTANCE(a.embedding, b.embedding, \'\'COSINE\'\') > 0.8 THEN \'\'LIKELY DUPLICATE\'\'\n'
  || '         WHEN 1 - ML.DISTANCE(a.embedding, b.embedding, \'\'COSINE\'\') > 0.6 THEN \'\'POSSIBLY RELATED\'\'\n'
  || '         ELSE \'\'DIFFERENT ISSUES\'\'\n'
  || '       END AS duplicate_status\n'
  || 'FROM all_issues a\n'
  || 'CROSS JOIN all_issues b\n'
  || 'WHERE a.issue_id < b.issue_id\n'
  || '  AND 1 - ML.DISTANCE(a.embedding, b.embedding, \'\'COSINE\'\') > 0.6\n'
  || 'ORDER BY similarity DESC;',
  PROJECT_ID, DATASET_ID
);

SELECT * FROM tmp_duplicates;

-- ============================================================
-- APPROACH 3: MULTIMODAL PIONEER 🖼️
-- Processing mixed data types together
-- ============================================================

EXECUTE IMMEDIATE FORMAT(
  'CREATE OR REPLACE EXTERNAL TABLE `%s.%s.multimodal_assets`\n'
  || 'OPTIONS (object_metadata = \'\'SIMPLE\'\',\n'
  || '         uris = [\'\'gs://your-bucket/screenshots/*.png\'\', \'\'gs://your-bucket/docs/*.pdf\'\']);',
  PROJECT_ID, DATASET_ID
);

EXECUTE IMMEDIATE FORMAT(
  'CREATE TEMP TABLE tmp_multimodal AS\n'
  || 'SELECT uri, content_type, size_bytes,\n'
  || '  CASE\n'
  || '    WHEN content_type = \'\'application/pdf\'\' THEN\n'
  || '      AI.GENERATE(ObjectRef(uri),\n'
  || '                   \'\'Extract and summarize the main points from this PDF document\'\',\n'
  || '                   CONNECTION_ID => \'\'%s\'\') .result\n'
  || '    WHEN content_type LIKE \'\'image/%\'\' THEN\n'
  || '      AI.GENERATE(ObjectRef(uri),\n'
  || '                   \'\'Describe what you see in this image, focusing on any errors or issues\'\',\n'
  || '                   CONNECTION_ID => \'\'%s\'\') .result\n'
  || '    ELSE \'\'Unsupported file type\'\'\n'
  || '  END AS analysis,\n'
  || '  AI.GENERATE(CONCAT(\'\'Based on this \'\', content_type, \'\' file, what action should be taken?\'\'),\n'
  || '              CONNECTION_ID => \'\'%s\'\') .result AS recommended_action\n'
  || 'FROM `%s.%s.multimodal_assets`\n'
  || 'LIMIT 10;',
  CONCAT(PROJECT_ID, '.', LOCATION, '.gemini_connection'),
  CONCAT(PROJECT_ID, '.', LOCATION, '.gemini_connection'),
  CONCAT(PROJECT_ID, '.', LOCATION, '.gemini_connection'),
  PROJECT_ID, DATASET_ID
);

SELECT * FROM tmp_multimodal;

-- ============================================================
-- INTEGRATED SOLUTION: COMBINING ALL APPROACHES
-- ============================================================

-- Create comprehensive analysis combining all three approaches

-- Step A: Collect data from multiple sources
CREATE TEMP TABLE unified_data AS
SELECT 'github' AS source, 'issue' AS type, 'Memory leak in upload service' AS content, CURRENT_TIMESTAMP() AS created_at
UNION ALL SELECT 'stackoverflow', 'question', 'How to fix memory leaks?', CURRENT_TIMESTAMP()
UNION ALL SELECT 'support', 'ticket', 'App crashes during file upload', CURRENT_TIMESTAMP();

-- Step B: Add AI insights (Approach 1)
CREATE TEMP TABLE ai_enhanced AS
SELECT
  *,
  AI.GENERATE(
    CONCAT('Summarize in 15 words: ', content),
    CONNECTION_ID => CONCAT(PROJECT_ID, '.', LOCATION, '.gemini_connection')
  ).result AS summary,
  AI.GENERATE_BOOL(
    CONCAT('Is this urgent: ', content),
    CONNECTION_ID => CONCAT(PROJECT_ID, '.', LOCATION, '.gemini_connection')
  ).result AS is_urgent,
  AI.GENERATE_DOUBLE(
    CONCAT('Rate priority 1-10: ', content),
    CONNECTION_ID => CONCAT(PROJECT_ID, '.', LOCATION, '.gemini_connection')
  ).result AS priority_score
FROM unified_data;

-- Step C: Add embeddings (Approach 2) using dynamic model identifier
EXECUTE IMMEDIATE FORMAT(
  'CREATE TEMP TABLE with_embeddings AS\n'
  || 'SELECT *, ML.GENERATE_EMBEDDING(MODEL `%s.%s.gemini_embedding_model`, content) AS embedding\n'
  || 'FROM ai_enhanced;',
  PROJECT_ID, DATASET_ID
);

-- Step D: Find patterns and produce the final dashboard
WITH pattern_analysis AS (
  SELECT
    source,
    type,
    COUNT(*) AS issue_count,
    AVG(priority_score) AS avg_priority,
    SUM(CASE WHEN is_urgent THEN 1 ELSE 0 END) AS urgent_count,
    AI.GENERATE(
      CONCAT(
        'Generate executive insight for: ', COUNT(*), ' issues from ', source,
        ' with average priority ', CAST(AVG(priority_score) AS STRING)
      ),
      CONNECTION_ID => CONCAT(PROJECT_ID, '.', LOCATION, '.gemini_connection')
    ).result AS executive_insight
  FROM with_embeddings
  GROUP BY source, type
)
SELECT
  source,
  issue_count,
  urgent_count,
  ROUND(avg_priority, 1) AS avg_priority,
  executive_insight,
  AI.GENERATE(
    CONCAT(
      'Based on ', issue_count, ' issues with ', urgent_count,
      ' urgent items from ', source,
      ', what strategic action should leadership take? Answer in 25 words.'
    ),
    CONNECTION_ID => CONCAT(PROJECT_ID, '.', LOCATION, '.gemini_connection')
  ).result AS strategic_recommendation
FROM pattern_analysis
ORDER BY urgent_count DESC, avg_priority DESC;

-- ============================================================
-- BUSINESS VALUE DEMONSTRATION
-- ============================================================

-- ROI Calculation
WITH metrics AS (
  SELECT
    1000 AS daily_tickets,
    45 AS avg_resolution_minutes_before,
    18 AS avg_resolution_minutes_after,  -- 60% improvement
    50 AS hourly_rate_usd
)
SELECT
  daily_tickets,
  avg_resolution_minutes_before,
  avg_resolution_minutes_after,

  -- Time saved per day
  (daily_tickets * (avg_resolution_minutes_before - avg_resolution_minutes_after)) / 60 AS hours_saved_daily,

  -- Annual cost savings
  ((daily_tickets * (avg_resolution_minutes_before - avg_resolution_minutes_after)) / 60) * hourly_rate_usd * 365 AS annual_savings_usd,

  -- Efficiency improvement
  ROUND((1 - (avg_resolution_minutes_after / avg_resolution_minutes_before)) * 100, 1) AS efficiency_improvement_percent

FROM metrics;

-- ============================================================
-- PRODUCTION DEPLOYMENT VIEW
-- ============================================================

-- First, create the ai_analyzed_data table for the dashboard
-- (In production, this would be populated by your data pipeline)
EXECUTE IMMEDIATE FORMAT(
  'CREATE OR REPLACE TABLE `%s.%s.ai_analyzed_data` AS\n'
  || 'SELECT source_type AS platform, content, CURRENT_TIMESTAMP() AS timestamp, CURRENT_TIMESTAMP() AS created_at,\n'
  || '       RAND() > 0.3 AS is_urgent, RAND() * 10 AS sentiment_score\n'
  || 'FROM (\n'
  || '  SELECT \'\'github\'\' AS source_type, \'\'Sample issue 1\'\' AS content\n'
  || '  UNION ALL SELECT \'\'stackoverflow\'\', \'\'Sample question 1\'\'\n'
  || '  UNION ALL SELECT \'\'support\'\', \'\'Sample ticket 1\'\'\n'
  || ');',
  PROJECT_ID, DATASET_ID
);

EXECUTE IMMEDIATE FORMAT(
  'CREATE OR REPLACE VIEW `%s.%s.executive_realtime_dashboard` AS\n'
  || 'WITH current_state AS (\n'
  || '  SELECT COUNT(*) AS total_issues,\n'
  || '         SUM(CASE WHEN is_urgent THEN 1 ELSE 0 END) AS urgent_issues,\n'
  || '         AVG(sentiment_score) AS avg_sentiment,\n'
  || '         COUNT(DISTINCT platform) AS affected_platforms\n'
  || '  FROM `%s.%s.ai_analyzed_data`\n'
  || '  WHERE DATE(timestamp) = CURRENT_DATE()\n'
  || ')\n'
  || 'SELECT total_issues, urgent_issues, ROUND(avg_sentiment, 2) AS avg_sentiment, affected_platforms,\n'
  || '  AI.GENERATE(CONCAT(\'\'Write an executive summary for today: \'\', total_issues, \'\' total issues, \'\',\n'
  || '                        urgent_issues, \'\' urgent, sentiment score \'\', CAST(avg_sentiment AS STRING), \'\', \'\',\n'
  || '                        affected_platforms, \'\' platforms affected\'\'),\n'
  || '              CONNECTION_ID => \'\'%s\'\') .result AS daily_executive_summary,\n'
  || '  AI.GENERATE(CONCAT(\'\'Given \'\', urgent_issues, \'\' urgent issues today, what are the top 3 actions leadership should take?\'\' ),\n'
  || '              CONNECTION_ID => \'\'%s\'\') .result AS recommended_actions,\n'
  || '  CURRENT_TIMESTAMP() AS dashboard_updated_at\n'
  || 'FROM current_state;',
  PROJECT_ID, DATASET_ID,
  PROJECT_ID, DATASET_ID,
  CONCAT(PROJECT_ID, '.', LOCATION, '.gemini_connection'),
  CONCAT(PROJECT_ID, '.', LOCATION, '.gemini_connection')
);
