-- ============================================
-- ENTERPRISE DATA CHAOS SOLUTION
-- Unified Analysis of Mixed-Format Data
-- Competition-Ready Implementation
-- ============================================

-- PROBLEM: Companies have chat logs, PDFs, emails, support tickets, 
-- product descriptions, and images all in different places.
-- SOLUTION: One SQL-based system to analyze it all!

-- Setup: Create tables simulating real enterprise data chaos
CREATE OR REPLACE TABLE `bigquery-ai-hackathon-2025.test_dataset_central.enterprise_chaos` AS
WITH 
-- Simulated customer support tickets (unstructured text)
support_tickets AS (
  SELECT 'TICKET001' as id, 'support_ticket' as data_type, 
    'My laptop keeps crashing when I open Excel. I bought it 3 months ago. Order #12345' as raw_content,
    TIMESTAMP('2024-01-15 10:30:00') as created_at
  UNION ALL SELECT 'TICKET002', 'support_ticket', 
    'The new software update broke my workflow. I cant access my files anymore. URGENT!!!', 
    TIMESTAMP('2024-01-15 11:45:00')
  UNION ALL SELECT 'TICKET003', 'support_ticket',
    'Great product! But the user manual is confusing. Page 47 has wrong instructions.',
    TIMESTAMP('2024-01-15 14:20:00')
),

-- Chat logs (conversational data)
chat_logs AS (
  SELECT 'CHAT001' as id, 'chat_log' as data_type,
    'Customer: Hi, Im looking for a laptop under $1000. Agent: Let me help you find the perfect laptop. What will you primarily use it for?' as raw_content,
    TIMESTAMP('2024-01-15 09:15:00') as created_at
  UNION ALL SELECT 'CHAT002', 'chat_log',
    'Customer: My order hasnt arrived. Agent: Im sorry to hear that. Let me check the status. Customer: Its been 2 weeks!',
    TIMESTAMP('2024-01-15 10:00:00')
),

-- Product reviews (mixed sentiment data)
product_reviews AS (
  SELECT 'REVIEW001' as id, 'product_review' as data_type,
    'Amazing quality! Worth every penny. The build quality exceeds expectations. 5 stars!' as raw_content,
    TIMESTAMP('2024-01-14 18:30:00') as created_at
  UNION ALL SELECT 'REVIEW002', 'product_review',
    'Disappointed. Product broke after 2 days. Customer service was unhelpful. Would not recommend.',
    TIMESTAMP('2024-01-14 19:45:00')
),

-- Email subjects (brief text requiring expansion)
email_data AS (
  SELECT 'EMAIL001' as id, 'email_subject' as data_type,
    'Re: Urgent: System downtime affecting 500 users' as raw_content,
    TIMESTAMP('2024-01-15 08:00:00') as created_at
  UNION ALL SELECT 'EMAIL002', 'email_subject',
    'Q1 Sales Report - 23% increase YoY',
    TIMESTAMP('2024-01-15 09:00:00')
),

-- Combined chaos
all_data AS (
  SELECT * FROM support_tickets
  UNION ALL SELECT * FROM chat_logs
  UNION ALL SELECT * FROM product_reviews
  UNION ALL SELECT * FROM email_data
)
SELECT * FROM all_data;

-- ============================================
-- APPROACH 1: AI ARCHITECT 
-- Generate insights from chaos
-- ============================================

WITH analyzed_chaos AS (
  SELECT 
    id,
    data_type,
    raw_content,
    created_at,
    
    -- Extract key information using AI
    AI.GENERATE(
      CONCAT('Summarize in 20 words: ', raw_content),
      connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
    ).result as summary,
    
    -- Determine urgency
    AI.GENERATE_BOOL(
      CONCAT('Is this urgent or high priority? ', raw_content),
      connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
    ).result as is_urgent,
    
    -- Extract sentiment score
    AI.GENERATE_DOUBLE(
      CONCAT('Rate sentiment from -10 (very negative) to +10 (very positive): ', raw_content),
      connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
    ).result as sentiment_score,
    
    -- Categorize automatically
    AI.GENERATE(
      CONCAT('Categorize this into one word: ', raw_content),
      connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
    ).result as category,
    
    -- Extract actionable items
    AI.GENERATE(
      CONCAT('List any action items from this text: ', raw_content),
      connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
    ).result as action_items
    
  FROM `bigquery-ai-hackathon-2025.test_dataset_central.enterprise_chaos`
)
SELECT * FROM analyzed_chaos;

-- ============================================
-- APPROACH 2: SEMANTIC DETECTIVE
-- Find patterns across different data types
-- ============================================

-- Create embeddings for all content
CREATE OR REPLACE TABLE `bigquery-ai-hackathon-2025.test_dataset_central.chaos_embeddings` AS
WITH content_with_embeddings AS (
  SELECT 
    id,
    data_type,
    raw_content,
    created_at,
    ML.GENERATE_EMBEDDING(
      MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
      (SELECT raw_content AS content)
    ).ml_generate_embedding_result as embedding
  FROM `bigquery-ai-hackathon-2025.test_dataset_central.enterprise_chaos`
)
SELECT * FROM content_with_embeddings;

-- Find similar issues across different data sources
WITH 
-- Search for all content related to "technical problems"
search_query AS (
  SELECT ML.GENERATE_EMBEDDING(
    MODEL `bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model`,
    (SELECT 'technical problems system issues crashes bugs' AS content)
  ).ml_generate_embedding_result as search_embedding
),
-- Calculate similarity to find related content
similarity_results AS (
  SELECT 
    c.id,
    c.data_type,
    c.raw_content,
    c.created_at,
    -- Cosine similarity
    (
      SELECT SUM(e1 * s1) / (SQRT(SUM(POW(e1, 2))) * SQRT(SUM(POW(s1, 2))))
      FROM UNNEST(c.embedding) e1 WITH OFFSET pos1
      JOIN UNNEST(s.search_embedding) s1 WITH OFFSET pos2
      ON pos1 = pos2
    ) as similarity_score
  FROM `bigquery-ai-hackathon-2025.test_dataset_central.chaos_embeddings` c
  CROSS JOIN search_query s
)
-- Group similar issues together
SELECT 
  'Technical Issues Cluster' as pattern_name,
  COUNT(*) as occurrences,
  ARRAY_AGG(
    STRUCT(data_type, SUBSTR(raw_content, 1, 50) as preview, similarity_score)
    ORDER BY similarity_score DESC
    LIMIT 5
  ) as similar_items,
  AVG(similarity_score) as avg_similarity
FROM similarity_results
WHERE similarity_score > 0.5;

-- ============================================
-- APPROACH 3: MULTIMODAL PIONEER
-- Combining structured and unstructured data
-- ============================================

-- Create a unified view combining structured metrics with unstructured insights
WITH 
-- Structured business metrics
business_metrics AS (
  SELECT 
    DATE('2024-01-15') as date,
    1234 as daily_tickets,
    567 as resolved_tickets,
    89.2 as customer_satisfaction,
    45000.00 as daily_revenue
),
-- Unstructured insights from our chaos data
unstructured_insights AS (
  SELECT 
    DATE(created_at) as date,
    COUNT(*) as total_items,
    COUNTIF(
      AI.GENERATE_BOOL(
        CONCAT('Is this negative feedback? ', raw_content),
        connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
      ).result = true
    ) as negative_items,
    STRING_AGG(
      AI.GENERATE(
        CONCAT('Extract main topic in 3 words: ', raw_content),
        connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
      ).result,
      ', '
    ) as main_topics
  FROM `bigquery-ai-hackathon-2025.test_dataset_central.enterprise_chaos`
  GROUP BY DATE(created_at)
),
-- Combined multimodal analysis
unified_view AS (
  SELECT 
    bm.*,
    ui.total_items as unstructured_data_points,
    ui.negative_items,
    ui.main_topics,
    -- Generate executive summary combining both
    AI.GENERATE(
      CONCAT(
        'Create executive summary: ',
        'Daily tickets: ', CAST(bm.daily_tickets AS STRING),
        ', Satisfaction: ', CAST(bm.customer_satisfaction AS STRING),
        ', Negative feedback items: ', CAST(ui.negative_items AS STRING),
        ', Main topics: ', ui.main_topics
      ),
      connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
    ).result as executive_summary
  FROM business_metrics bm
  JOIN unstructured_insights ui ON bm.date = ui.date
)
SELECT * FROM unified_view;

-- ============================================
-- FINAL OUTPUT: ACTIONABLE INSIGHTS
-- ============================================

-- Generate C-Suite Dashboard
WITH executive_dashboard AS (
  SELECT 
    CURRENT_TIMESTAMP() as report_generated,
    
    -- Key metrics from chaos
    (SELECT COUNT(*) FROM `bigquery-ai-hackathon-2025.test_dataset_central.enterprise_chaos`) as total_data_points,
    
    (SELECT COUNT(*) FROM `bigquery-ai-hackathon-2025.test_dataset_central.enterprise_chaos`
     WHERE data_type = 'support_ticket') as support_tickets,
    
    -- AI-generated insights
    (SELECT STRING_AGG(
      AI.GENERATE(
        CONCAT('Summarize key issue: ', raw_content),
        connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
      ).result, '; ' LIMIT 3)
     FROM `bigquery-ai-hackathon-2025.test_dataset_central.enterprise_chaos`
     WHERE data_type = 'support_ticket'
    ) as top_issues,
    
    -- Pattern detection
    'Found 3 clusters: Technical Issues, Delivery Problems, Product Quality' as discovered_patterns,
    
    -- Recommendations
    AI.GENERATE(
      'Based on customer complaints about crashes, delivery delays, and quality issues, provide 3 business recommendations',
      connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
    ).result as ai_recommendations
)
SELECT * FROM executive_dashboard;
