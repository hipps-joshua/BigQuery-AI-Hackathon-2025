-- ============================================
-- REAL DATA ENTERPRISE CHAOS SOLUTION
-- Using BigQuery Public Datasets
-- Full Competition Implementation
-- ============================================

-- BUSINESS PROBLEM: 
-- Companies have customer feedback scattered across GitHub issues, 
-- Stack Overflow questions, news articles, and support data.
-- They can't connect insights across these silos.

-- SOLUTION: Unified AI-powered analysis across multiple data sources

-- ============================================
-- STEP 1: GATHER REAL MIXED-FORMAT DATA
-- ============================================

-- Create unified view of multiple public datasets
CREATE OR REPLACE TABLE `bigquery-ai-hackathon-2025.test_dataset_central.mixed_enterprise_data` AS
WITH 
-- GitHub Issues (Real developer feedback)
github_issues AS (
  SELECT 
    'github_issue' as source_type,
    CAST(number AS STRING) as record_id,
    title as title,
    body as content,
    state as status,
    created_at as timestamp,
    user.login as author,
    'technical' as category
  FROM `bigquery-public-data.github_repos.issues` 
  WHERE repo_name = 'tensorflow/tensorflow'
    AND created_at > '2024-01-01'
  LIMIT 100
),

-- Stack Overflow Questions (Real technical problems)
stackoverflow_questions AS (
  SELECT 
    'stackoverflow' as source_type,
    CAST(id AS STRING) as record_id,
    title as title,
    body as content,
    CASE WHEN accepted_answer_id IS NOT NULL THEN 'resolved' ELSE 'open' END as status,
    creation_date as timestamp,
    owner_display_name as author,
    'technical' as category
  FROM `bigquery-public-data.stackoverflow.posts_questions`
  WHERE tags LIKE '%python%'
    AND creation_date > '2024-01-01'
  LIMIT 100
),

-- Hacker News Stories (Real tech news and discussions)
hacker_news AS (
  SELECT 
    'hacker_news' as source_type,
    CAST(id AS STRING) as record_id,
    title as title,
    text as content,
    'published' as status,
    timestamp as timestamp,
    author as author,
    'news' as category
  FROM `bigquery-public-data.hacker_news.full`
  WHERE type = 'story'
    AND timestamp > '2024-01-01'
    AND text IS NOT NULL
  LIMIT 100
)

-- Combine all sources
SELECT * FROM github_issues
UNION ALL SELECT * FROM stackoverflow_questions  
UNION ALL SELECT * FROM hacker_news;

-- ============================================
-- STEP 2: AI ANALYSIS - APPROACH 1 (AI ARCHITECT)
-- Extract insights from each piece of content
-- ============================================

CREATE OR REPLACE TABLE `bigquery-ai-hackathon-2025.test_dataset_central.ai_analyzed_data` AS
SELECT 
  source_type,
  record_id,
  title,
  SUBSTR(content, 1, 500) as content_preview,
  status,
  timestamp,
  author,
  category,
  
  -- AI-powered analysis
  AI.GENERATE(
    CONCAT('Summarize the main issue or topic in 20 words: ', 
           SUBSTR(IFNULL(title, ''), 1, 100), ' ', 
           SUBSTR(IFNULL(content, ''), 1, 200)),
    connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
  ).result as ai_summary,
  
  -- Urgency detection
  AI.GENERATE_BOOL(
    CONCAT('Is this urgent or critical? ', 
           SUBSTR(IFNULL(title, ''), 1, 100)),
    connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
  ).result as is_urgent,
  
  -- Sentiment analysis
  AI.GENERATE_DOUBLE(
    CONCAT('Rate the sentiment from -10 (very negative) to 10 (very positive): ',
           SUBSTR(IFNULL(content, ''), 1, 300)),
    connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
  ).result as sentiment_score,
  
  -- Topic extraction
  AI.GENERATE(
    CONCAT('Extract the main technology or product mentioned: ',
           SUBSTR(IFNULL(content, ''), 1, 200)),
    connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
  ).result as main_topic,
  
  -- Business impact
  AI.GENERATE(
    CONCAT('What business impact could this have? Answer in 15 words: ',
           SUBSTR(IFNULL(title, ''), 1, 100)),
    connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
  ).result as business_impact

FROM `bigquery-ai-hackathon-2025.test_dataset_central.mixed_enterprise_data`
LIMIT 20;  -- Limit for demo to control costs

-- ============================================
-- STEP 3: SEMANTIC SEARCH - APPROACH 2 
-- Find patterns across different data sources
-- ============================================

-- Generate embeddings for semantic search
CREATE OR REPLACE TABLE `bigquery-ai-hackathon-2025.test_dataset_central.data_embeddings` AS
SELECT 
  source_type,
  record_id,
  title,
  SUBSTR(content, 1, 200) as content_preview,
  ML.GENERATE_EMBEDDING(
    MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
    (SELECT CONCAT(IFNULL(title, ''), ' ', SUBSTR(IFNULL(content, ''), 1, 500)) AS content)
  ).ml_generate_embedding_result as embedding
FROM `bigquery-ai-hackathon-2025.test_dataset_central.mixed_enterprise_data`
LIMIT 50;

-- Find similar issues across platforms
WITH 
-- Search for "performance problems"
search_embedding AS (
  SELECT ML.GENERATE_EMBEDDING(
    MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
    (SELECT 'performance issues slow latency optimization' AS content)
  ).ml_generate_embedding_result as query_embedding
),
-- Find similar content
similar_content AS (
  SELECT 
    d.source_type,
    d.record_id,
    d.title,
    d.content_preview,
    -- Calculate cosine similarity
    (
      SELECT SUM(e1 * q1) / (SQRT(SUM(POW(e1, 2))) * SQRT(SUM(POW(q1, 2))))
      FROM UNNEST(d.embedding) e1 WITH OFFSET pos1
      JOIN UNNEST(s.query_embedding) q1 WITH OFFSET pos2
      ON pos1 = pos2
    ) as similarity_score
  FROM `bigquery-ai-hackathon-2025.test_dataset_central.data_embeddings` d
  CROSS JOIN search_embedding s
)
-- Group by source to see patterns
SELECT 
  source_type,
  COUNT(*) as related_issues_count,
  AVG(similarity_score) as avg_relevance,
  ARRAY_AGG(
    STRUCT(title, similarity_score)
    ORDER BY similarity_score DESC
    LIMIT 3
  ) as top_related_items
FROM similar_content
WHERE similarity_score > 0.5
GROUP BY source_type;

-- ============================================
-- STEP 4: EXECUTIVE DASHBOARD
-- Actionable insights for business decisions
-- ============================================

CREATE OR REPLACE VIEW `bigquery-ai-hackathon-2025.test_dataset_central.executive_insights` AS
WITH 
-- Aggregate metrics
metrics AS (
  SELECT 
    COUNT(*) as total_data_points,
    COUNT(DISTINCT source_type) as data_sources,
    COUNTIF(is_urgent = true) as urgent_items,
    AVG(sentiment_score) as avg_sentiment,
    COUNT(DISTINCT main_topic) as unique_topics
  FROM `bigquery-ai-hackathon-2025.test_dataset_central.ai_analyzed_data`
),
-- Top issues by source
top_issues AS (
  SELECT 
    source_type,
    COUNT(*) as issue_count,
    AVG(sentiment_score) as avg_sentiment,
    STRING_AGG(
      DISTINCT main_topic 
      ORDER BY main_topic 
      LIMIT 5
    ) as main_topics
  FROM `bigquery-ai-hackathon-2025.test_dataset_central.ai_analyzed_data`
  GROUP BY source_type
),
-- Generate executive summary
executive_summary AS (
  SELECT 
    AI.GENERATE(
      CONCAT(
        'Create an executive summary based on these insights: ',
        'Total data points analyzed: ', CAST((SELECT total_data_points FROM metrics) AS STRING),
        ', Urgent items: ', CAST((SELECT urgent_items FROM metrics) AS STRING),
        ', Average sentiment: ', CAST((SELECT ROUND(avg_sentiment, 2) FROM metrics) AS STRING),
        '. Provide 3 actionable recommendations.'
      ),
      connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
    ).result as summary
)
SELECT 
  CURRENT_TIMESTAMP() as report_generated,
  m.*,
  ARRAY(SELECT AS STRUCT * FROM top_issues) as breakdown_by_source,
  es.summary as executive_summary
FROM metrics m
CROSS JOIN executive_summary es;

-- ============================================
-- STEP 5: REAL-TIME PATTERN DISCOVERY
-- Identify emerging trends across all sources
-- ============================================

WITH pattern_analysis AS (
  SELECT 
    DATE(timestamp) as date,
    source_type,
    COUNT(*) as volume,
    AVG(sentiment_score) as sentiment_trend,
    COUNTIF(is_urgent = true) as urgent_count,
    STRING_AGG(DISTINCT main_topic LIMIT 3) as trending_topics
  FROM `bigquery-ai-hackathon-2025.test_dataset_central.ai_analyzed_data`
  GROUP BY date, source_type
)
SELECT 
  date,
  -- Cross-platform insights
  STRUCT(
    SUM(volume) as total_volume,
    AVG(sentiment_trend) as overall_sentiment,
    SUM(urgent_count) as total_urgent,
    STRING_AGG(trending_topics, ', ') as all_trending_topics
  ) as cross_platform_metrics,
  -- AI interpretation
  AI.GENERATE(
    CONCAT(
      'Analyze this trend: Volume=', CAST(SUM(volume) AS STRING),
      ', Sentiment=', CAST(AVG(sentiment_trend) AS STRING),
      ', Topics=', STRING_AGG(trending_topics, ', '),
      '. What does this mean for the business?'
    ),
    connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
  ).result as trend_interpretation
FROM pattern_analysis
GROUP BY date
ORDER BY date DESC
LIMIT 7;
