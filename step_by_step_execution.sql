-- ============================================
-- STEP-BY-STEP EXECUTION OF REAL DATA QUERIES
-- Run each section individually in BigQuery
-- ============================================

-- ============================================
-- STEP 1: GATHER REAL DATA (Run this first)
-- ============================================
-- This creates a table with 300 real records from public datasets

CREATE OR REPLACE TABLE `bigquery-ai-hackathon-2025.test_dataset_central.mixed_enterprise_data` AS
WITH
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
SELECT * FROM github_issues
UNION ALL SELECT * FROM stackoverflow_questions
UNION ALL SELECT * FROM hacker_news;

-- Verify data collection
SELECT
    source_type,
    COUNT(*) as record_count,
    MIN(timestamp) as earliest,
    MAX(timestamp) as latest
FROM `bigquery-ai-hackathon-2025.test_dataset_central.mixed_enterprise_data`
GROUP BY source_type;

-- ============================================
-- STEP 2: AI ANALYSIS (Run after Step 1)
-- ============================================
-- This applies AI functions to analyze the data

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

-- View urgent items
SELECT
    source_type,
    title,
    ai_summary,
    ROUND(sentiment_score, 2) as sentiment,
    main_topic,
    business_impact
FROM `bigquery-ai-hackathon-2025.test_dataset_central.ai_analyzed_data`
WHERE is_urgent = true;

-- ============================================
-- STEP 3: PATTERN DISCOVERY (Run after Step 2)
-- ============================================
-- Find patterns across all data sources

WITH topic_patterns AS (
    SELECT
        main_topic,
        COUNT(*) as occurrences,
        AVG(sentiment_score) as avg_sentiment,
        COUNTIF(is_urgent = true) as urgent_count,
        STRING_AGG(DISTINCT source_type) as found_in_sources
    FROM `bigquery-ai-hackathon-2025.test_dataset_central.ai_analyzed_data`
    WHERE main_topic IS NOT NULL
    GROUP BY main_topic
    HAVING COUNT(*) > 1
)
SELECT
    main_topic,
    occurrences,
    ROUND(avg_sentiment, 2) as avg_sentiment,
    urgent_count,
    found_in_sources
FROM topic_patterns
ORDER BY occurrences DESC
LIMIT 10;

-- ============================================
-- STEP 4: EXECUTIVE DASHBOARD (Run after Step 2)
-- ============================================
-- Create executive-level insights

CREATE OR REPLACE VIEW `bigquery-ai-hackathon-2025.test_dataset_central.executive_insights` AS
WITH
metrics AS (
  SELECT
    COUNT(*) as total_data_points,
    COUNT(DISTINCT source_type) as data_sources,
    COUNTIF(is_urgent = true) as urgent_items,
    AVG(sentiment_score) as avg_sentiment,
    COUNT(DISTINCT main_topic) as unique_topics
  FROM `bigquery-ai-hackathon-2025.test_dataset_central.ai_analyzed_data`
),
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

-- View the executive dashboard
SELECT * FROM `bigquery-ai-hackathon-2025.test_dataset_central.executive_insights`;

-- ============================================
-- STEP 5: BUSINESS RECOMMENDATIONS (Run last)
-- ============================================
-- Generate actionable business recommendations

WITH insights AS (
    SELECT
        COUNT(*) as total_issues,
        AVG(sentiment_score) as avg_sentiment,
        COUNTIF(is_urgent = true) as urgent_count,
        STRING_AGG(DISTINCT main_topic LIMIT 5) as top_topics
    FROM `bigquery-ai-hackathon-2025.test_dataset_central.ai_analyzed_data`
)
SELECT AI.GENERATE(
    CONCAT(
        'Based on this analysis of developer feedback and tech discussions: ',
        'Total issues: ', CAST(total_issues AS STRING),
        ', Average sentiment: ', CAST(avg_sentiment AS STRING),
        ', Urgent items: ', CAST(urgent_count AS STRING),
        ', Main topics: ', top_topics,
        '. Provide 5 specific business recommendations with expected impact and implementation priority.'
    ),
    connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
).result as recommendations
FROM insights;

-- ============================================
-- SAMPLE OUTPUT SHOWCASE
-- What each step accomplishes:
-- ============================================

/*
STEP 1 OUTPUT:
- Collects 300 real records from GitHub, Stack Overflow, and Hacker News
- Creates unified table with consistent schema
- Shows data distribution across sources

STEP 2 OUTPUT (AI Analysis):
- AI-generated summaries for each item
- Urgency flags (true/false) for prioritization
- Sentiment scores (-10 to +10) for mood analysis
- Main topics extracted (e.g., "TensorFlow", "Python", "Machine Learning")
- Business impact assessment for each item

STEP 3 OUTPUT (Pattern Discovery):
- Topics that appear across multiple platforms
- Average sentiment per topic
- Urgent item count per topic
- Cross-platform presence (e.g., "Found in: github_issue,stackoverflow")

STEP 4 OUTPUT (Executive Dashboard):
- Total data points analyzed: 20
- Urgent items identified: X
- Average sentiment across all sources: Y
- AI-generated executive summary with recommendations

STEP 5 OUTPUT (Business Recommendations):
Example:
"1. PRIORITY HIGH: Address TensorFlow performance issues reported across GitHub and Stack Overflow.
   Expected Impact: 30% reduction in user complaints, improved developer satisfaction.
   
2. PRIORITY MEDIUM: Create comprehensive Python integration documentation.
   Expected Impact: Reduce support tickets by 25%, faster onboarding.
   
3. PRIORITY HIGH: Fix critical bugs in model training pipeline.
   Expected Impact: Prevent data loss, maintain enterprise trust.
   
4. PRIORITY LOW: Update community examples and tutorials.
   Expected Impact: Better developer engagement, reduced confusion.
   
5. PRIORITY MEDIUM: Implement automated issue triage system.
   Expected Impact: 50% faster response time, better resource allocation."
*/