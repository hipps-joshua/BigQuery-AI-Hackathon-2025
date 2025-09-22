-- ============================================
-- APPROACH 2: SEMANTIC DETECTIVE - MONITORING & ALERTING
-- ============================================
-- Production monitoring queries for semantic search platform

-- ============================================
-- 1. VECTOR SEARCH PERFORMANCE MONITORING
-- ============================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.vector_search_performance` AS
WITH search_metrics AS (
  SELECT
    DATE(search_timestamp) AS date,
    EXTRACT(HOUR FROM search_timestamp) AS hour,
    search_type,
    COUNT(*) AS search_count,
    AVG(results_count) AS avg_results,
    AVG(avg_similarity) AS avg_match_score,
    PERCENTILE_CONT(avg_similarity, 0.5) OVER (PARTITION BY DATE(search_timestamp)) AS median_match_score,
    PERCENTILE_CONT(avg_similarity, 0.95) OVER (PARTITION BY DATE(search_timestamp)) AS p95_match_score,
    SUM(CASE WHEN conversion THEN 1 ELSE 0 END) / COUNT(*) AS conversion_rate,
    AVG(CASE WHEN clicked_sku IS NOT NULL THEN 1 ELSE 0 END) AS click_through_rate
  FROM `${PROJECT_ID}.${DATASET_ID}.search_log`
  WHERE search_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  GROUP BY date, hour, search_type
)
SELECT
  *,
  -- Performance alerts
  CASE
    WHEN avg_match_score < 0.7 THEN 'WARNING: Low relevance scores'
    WHEN conversion_rate < 0.1 AND search_count > 100 THEN 'WARNING: Low conversion'
    WHEN avg_results < 3 THEN 'WARNING: Few results returned'
    ELSE 'OK'
  END AS performance_alert,
  
  -- Search quality score (0-100)
  ROUND(
    (avg_match_score * 30) +  -- 30 points for relevance
    (CASE WHEN avg_results >= 5 AND avg_results <= 10 THEN 30 ELSE 15 END) + -- 30 points for result count
    (conversion_rate * 100 * 0.4)  -- 40 points for conversion
  , 1) AS search_quality_score
FROM search_metrics
ORDER BY date DESC, hour DESC;

-- ============================================
-- 2. EMBEDDING GENERATION MONITORING
-- ============================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.embedding_health` AS
WITH embedding_stats AS (
  SELECT
    DATE(timestamp) AS date,
    table_name,
    COUNT(*) AS batches_processed,
    SUM(batch_size) AS total_records,
    COUNT(CASE WHEN status = 'ERROR' THEN 1 END) AS failed_batches,
    AVG(CASE WHEN status = 'SUCCESS' THEN batch_size ELSE 0 END) AS avg_batch_success_size,
    STRING_AGG(DISTINCT error_message LIMIT 3) AS sample_errors
  FROM `${PROJECT_ID}.${DATASET_ID}.processing_log`
  WHERE operation IN ('generate_embeddings', 'update_embeddings')
    AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  GROUP BY date, table_name
),
embedding_coverage AS (
  SELECT
    COUNT(*) AS total_products,
    COUNT(e.sku) AS products_with_embeddings,
    COUNT(e.sku) / COUNT(*) AS embedding_coverage,
    MAX(e.embedding_timestamp) AS latest_embedding_update
  FROM `${PROJECT_ID}.${DATASET_ID}.products` p
  LEFT JOIN `${PROJECT_ID}.${DATASET_ID}.products_embeddings` e ON p.sku = e.sku
)
SELECT
  s.*,
  c.embedding_coverage,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), c.latest_embedding_update, HOUR) AS hours_since_update,
  
  -- Health indicators
  CASE
    WHEN failed_batches > 0 THEN 'CRITICAL: Embedding failures'
    WHEN c.embedding_coverage < 0.9 THEN 'WARNING: Low embedding coverage'
    WHEN TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), c.latest_embedding_update, HOUR) > 24 THEN 'WARNING: Stale embeddings'
    ELSE 'HEALTHY'
  END AS embedding_health_status,
  
  -- Recommendations
  CASE
    WHEN c.embedding_coverage < 0.9 THEN 
      CONCAT('Generate embeddings for ', 
        CAST(c.total_products - c.products_with_embeddings AS STRING), ' products')
    WHEN failed_batches > 0 THEN 'Investigate and retry failed batches'
    ELSE 'No action needed'
  END AS recommended_action
  
FROM embedding_stats s
CROSS JOIN embedding_coverage c
ORDER BY s.date DESC;

-- ============================================
-- 3. VECTOR INDEX PERFORMANCE
-- ============================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.vector_index_monitoring` AS
WITH index_stats AS (
  -- Get index metadata (simulated - in production would query system tables)
  SELECT
    'products_full_embedding_idx' AS index_name,
    'full_embedding' AS embedding_column,
    1000 AS num_lists, -- IVF configuration
    768 AS vector_dimension,
    (SELECT COUNT(*) FROM `${PROJECT_ID}.${DATASET_ID}.products_embeddings`) AS indexed_vectors
),
search_performance AS (
  SELECT
    COUNT(*) AS searches_last_hour,
    AVG(avg_similarity) AS avg_search_quality,
    PERCENTILE_CONT(results_count, 0.95) OVER() AS p95_result_count
  FROM `${PROJECT_ID}.${DATASET_ID}.search_log`
  WHERE search_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
    AND search_type = 'full'
)
SELECT
  i.*,
  s.searches_last_hour,
  s.avg_search_quality,
  
  -- Index efficiency metrics
  i.indexed_vectors / i.num_lists AS avg_vectors_per_list,
  CASE
    WHEN i.indexed_vectors / i.num_lists > 1000 THEN 'WARNING: Lists too large, consider increasing num_lists'
    WHEN i.indexed_vectors / i.num_lists < 100 THEN 'INFO: Lists sparse, could decrease num_lists'
    ELSE 'OPTIMAL'
  END AS index_efficiency,
  
  -- Performance recommendations
  CASE
    WHEN s.searches_last_hour > 1000 AND i.num_lists < 2000 THEN 'Consider scaling index for high traffic'
    WHEN s.avg_search_quality < 0.8 THEN 'Review embedding quality and similarity thresholds'
    ELSE 'Index performing well'
  END AS optimization_suggestion
  
FROM index_stats i
CROSS JOIN search_performance s;

-- ============================================
-- 4. DUPLICATE DETECTION MONITORING
-- ============================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.duplicate_monitoring` AS
WITH duplicate_trends AS (
  SELECT
    DATE(run_timestamp) AS date,
    COUNT(*) AS detection_runs,
    SUM(duplicate_pairs_found) AS total_duplicates_found,
    SUM(duplicate_groups_found) AS unique_duplicate_groups,
    AVG(duplicate_pairs_found) AS avg_duplicates_per_run,
    SUM(estimated_savings) AS total_savings,
    AVG(processing_time_seconds) AS avg_processing_time
  FROM `${PROJECT_ID}.${DATASET_ID}.duplicate_detection_log`
  WHERE run_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  GROUP BY date
),
duplicate_impact AS (
  SELECT
    COUNT(DISTINCT sku) AS products_affected,
    COUNT(DISTINCT group_id) AS duplicate_groups,
    SUM(potential_revenue_loss) AS total_revenue_impact,
    AVG(similarity_score) AS avg_duplicate_similarity
  FROM `${PROJECT_ID}.${DATASET_ID}.duplicate_candidates`
  LEFT JOIN `${PROJECT_ID}.${DATASET_ID}.duplicate_groups` USING(sku)
  WHERE detection_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
)
SELECT
  t.*,
  i.products_affected,
  i.total_revenue_impact,
  
  -- Detection effectiveness
  CASE
    WHEN t.total_duplicates_found = 0 THEN 'INFO: No duplicates found'
    WHEN t.avg_duplicates_per_run > 100 THEN 'CRITICAL: High duplicate rate'
    WHEN t.avg_duplicates_per_run > 50 THEN 'WARNING: Elevated duplicates'
    ELSE 'NORMAL'
  END AS duplicate_severity,
  
  -- ROI metrics
  t.total_savings AS inventory_cost_savings,
  i.products_affected * 50 AS operational_cost_savings, -- $50 per duplicate handling
  
  -- Actions needed
  CASE
    WHEN i.duplicate_groups > 20 THEN 'Urgent: Review and merge duplicate groups'
    WHEN t.avg_processing_time > 300 THEN 'Optimize detection query performance'
    ELSE 'Continue monitoring'
  END AS recommended_action
  
FROM duplicate_trends t
CROSS JOIN duplicate_impact i
ORDER BY t.date DESC;

-- ============================================
-- 5. SEMANTIC SEARCH QUALITY MONITORING
-- ============================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.search_quality_analysis` AS
WITH search_patterns AS (
  SELECT
    DATE(search_timestamp) AS date,
    query_text,
    search_type,
    COUNT(*) AS search_frequency,
    AVG(results_count) AS avg_results,
    AVG(avg_similarity) AS avg_relevance,
    SUM(CASE WHEN clicked_sku IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS click_rate,
    SUM(CASE WHEN conversion THEN 1 ELSE 0 END) / COUNT(*) AS conversion_rate
  FROM `${PROJECT_ID}.${DATASET_ID}.search_log`
  WHERE search_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  GROUP bologicallyY date, query_text, search_type
),
poor_performers AS (
  SELECT * FROM search_patterns
  WHERE (avg_relevance < 0.6 OR click_rate < 0.1) AND search_frequency > 5
)
SELECT
  date,
  COUNT(DISTINCT query_text) AS unique_queries,
  AVG(avg_relevance) AS overall_relevance,
  AVG(click_rate) AS overall_click_rate,
  AVG(conversion_rate) AS overall_conversion_rate,
  
  -- Poor performing queries
  ARRAY(
    SELECT AS STRUCT 
      query_text,
      search_frequency,
      ROUND(avg_relevance, 3) AS relevance,
      ROUND(click_rate, 3) AS click_rate
    FROM poor_performers p
    WHERE p.date = search_patterns.date
    ORDER BY search_frequency DESC
    LIMIT 10
  ) AS poor_performing_queries,
  
  -- Quality assessment
  CASE
    WHEN AVG(avg_relevance) < 0.7 THEN 'CRITICAL: Low overall relevance'
    WHEN AVG(click_rate) < 0.15 THEN 'WARNING: Low engagement'
    WHEN COUNT(DISTINCT query_text) < 10 THEN 'INFO: Low query diversity'
    ELSE 'HEALTHY'
  END AS search_quality_status
  
FROM search_patterns
GROUP BY date
ORDER BY date DESC;

-- ============================================
-- 6. COST AND PERFORMANCE OPTIMIZATION
-- ============================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.cost_performance_dashboard` AS
WITH operation_costs AS (
  SELECT
    DATE(timestamp) AS date,
    operation,
    COUNT(*) AS execution_count,
    SUM(batch_size) AS total_records,
    
    -- Estimate costs
    CASE operation
      WHEN 'generate_embeddings' THEN SUM(batch_size) * 0.0001  -- $0.0001 per embedding
      WHEN 'semantic_search' THEN COUNT(*) * 0.00001  -- $0.00001 per search
      WHEN 'find_duplicates' THEN SUM(batch_size) * 0.00002  -- $0.00002 per comparison
      ELSE 0
    END AS estimated_cost,
    
    -- Performance metrics
    AVG(TIMESTAMP_DIFF(
      (SELECT MIN(timestamp) FROM `${PROJECT_ID}.${DATASET_ID}.processing_log` p2 
       WHERE p2.operation = p1.operation 
         AND p2.timestamp > p1.timestamp),
      timestamp, SECOND
    )) AS avg_execution_time_seconds
    
  FROM `${PROJECT_ID}.${DATASET_ID}.processing_log` p1
  WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND status = 'SUCCESS'
  GROUP BY date, operation
),
daily_summary AS (
  SELECT
    date,
    SUM(estimated_cost) AS daily_cost,
    SUM(total_records) AS daily_records_processed,
    MAX(estimated_cost) AS highest_cost_operation_value,
    ARRAY_AGG(STRUCT(operation, estimated_cost) ORDER BY estimated_cost DESC LIMIT 1)[OFFSET(0)].operation AS highest_cost_operation
  FROM operation_costs
  GROUP BY date
)
SELECT
  *,
  -- Cost trends
  daily_cost - LAG(daily_cost) OVER (ORDER BY date) AS daily_cost_change,
  AVG(daily_cost) OVER (ORDER BY date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS avg_7day_cost,
  
  -- Projections
  AVG(daily_cost) OVER (ORDER BY date ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) * 365 AS projected_annual_cost,
  
  -- Optimization alerts
  CASE
    WHEN daily_cost > AVG(daily_cost) OVER (ORDER BY date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) * 1.5 
      THEN 'ALERT: 50% above weekly average'
    WHEN highest_cost_operation = 'generate_embeddings' AND daily_cost > 100
      THEN 'Consider batching embedding generation'
    WHEN daily_records_processed < 1000 AND daily_cost > 10
      THEN 'Low efficiency - review processing strategy'
    ELSE 'Costs normal'
  END AS cost_optimization_alert
  
FROM daily_summary
ORDER BY date DESC;

-- ============================================
-- 7. DATA FRESHNESS AND CONSISTENCY
-- ============================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.data_consistency_monitoring` AS
WITH freshness_check AS (
  SELECT
    'products' AS table_name,
    COUNT(*) AS total_records,
    MAX(updated_at) AS last_update,
    TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(updated_at), HOUR) AS hours_since_update,
    COUNT(CASE WHEN updated_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR) THEN 1 END) AS updates_last_24h
  FROM `${PROJECT_ID}.${DATASET_ID}.products`
),
embedding_sync AS (
  SELECT
    COUNT(p.sku) AS products_without_embeddings,
    COUNT(CASE WHEN p.updated_at > e.embedding_timestamp THEN 1 END) AS stale_embeddings
  FROM `${PROJECT_ID}.${DATASET_ID}.products` p
  LEFT JOIN `${PROJECT_ID}.${DATASET_ID}.products_embeddings` e ON p.sku = e.sku
),
consistency_metrics AS (
  SELECT
    -- Check for orphaned records
    (SELECT COUNT(*) FROM `${PROJECT_ID}.${DATASET_ID}.duplicate_candidates` d
     WHERE NOT EXISTS (SELECT 1 FROM `${PROJECT_ID}.${DATASET_ID}.products` p WHERE p.sku = d.sku)) 
     AS orphaned_duplicates,
    
    -- Check index coverage
    (SELECT COUNT(DISTINCT sku) FROM `${PROJECT_ID}.${DATASET_ID}.products`) -
    (SELECT COUNT(DISTINCT sku) FROM `${PROJECT_ID}.${DATASET_ID}.products_embeddings`) 
    AS products_missing_embeddings
)
SELECT
  f.*,
  e.products_without_embeddings,
  e.stale_embeddings,
  c.orphaned_duplicates,
  
  -- Health status
  CASE
    WHEN f.hours_since_update > 48 THEN 'CRITICAL: Data not updated in 48 hours'
    WHEN e.stale_embeddings > 100 THEN 'WARNING: Many stale embeddings'
    WHEN c.orphaned_duplicates > 0 THEN 'WARNING: Data inconsistency detected'
    ELSE 'HEALTHY'
  END AS data_health_status,
  
  -- Recommended actions
  ARRAY(
    SELECT action FROM UNNEST([
      IF(e.products_without_embeddings > 0, 
         CONCAT('Generate embeddings for ', CAST(e.products_without_embeddings AS STRING), ' products'), NULL),
      IF(e.stale_embeddings > 0,
         CONCAT('Update embeddings for ', CAST(e.stale_embeddings AS STRING), ' products'), NULL),
      IF(c.orphaned_duplicates > 0,
         'Clean up orphaned duplicate records', NULL)
    ]) AS action
    WHERE action IS NOT NULL
  ) AS required_actions
  
FROM freshness_check f
CROSS JOIN embedding_sync e
CROSS JOIN consistency_metrics c;

-- ============================================
-- 8. AUTOMATED ALERTING PROCEDURE
-- ============================================

CREATE OR REPLACE PROCEDURE `${PROJECT_ID}.${DATASET_ID}.semantic_monitoring_alerts`()
BEGIN
  DECLARE critical_alerts ARRAY<STRUCT<component STRING, issue STRING>>;
  
  -- Collect all critical issues
  SET critical_alerts = ARRAY(
    SELECT AS STRUCT 
      'Vector Search' AS component,
      performance_alert AS issue
    FROM `${PROJECT_ID}.${DATASET_ID}.vector_search_performance`
    WHERE performance_alert LIKE 'WARNING%' 
      AND date = CURRENT_DATE()
    
    UNION ALL
    
    SELECT AS STRUCT
      'Embeddings' AS component,
      embedding_health_status AS issue  
    FROM `${PROJECT_ID}.${DATASET_ID}.embedding_health`
    WHERE embedding_health_status != 'HEALTHY'
      AND date = CURRENT_DATE()
    
    UNION ALL
    
    SELECT AS STRUCT
      'Data Consistency' AS component,
      data_health_status AS issue
    FROM `${PROJECT_ID}.${DATASET_ID}.data_consistency_monitoring`
    WHERE data_health_status != 'HEALTHY'
  );
  
  -- Log alerts
  IF ARRAY_LENGTH(critical_alerts) > 0 THEN
    INSERT INTO `${PROJECT_ID}.${DATASET_ID}.processing_log`
    VALUES(
      CURRENT_TIMESTAMP(),
      'MONITORING_ALERT',
      'system',
      0,
      ARRAY_LENGTH(critical_alerts),
      'ALERT',
      CONCAT('Critical issues detected: ', 
        ARRAY_TO_STRING(
          ARRAY(SELECT CONCAT(component, ' - ', issue) FROM UNNEST(critical_alerts)),
          '; '
        )
      )
    );
  END IF;
  
  -- Auto-remediation for common issues
  IF EXISTS (
    SELECT 1 FROM `${PROJECT_ID}.${DATASET_ID}.data_consistency_monitoring`
    WHERE products_missing_embeddings > 10
  ) THEN
    -- Trigger embedding generation
    CALL `${PROJECT_ID}.${DATASET_ID}.generate_product_embeddings`('products', 100);
  END IF;
END;

-- ============================================
-- 9. EXECUTIVE DASHBOARD
-- ============================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.semantic_executive_dashboard` AS
WITH kpi_metrics AS (
  SELECT
    -- Search metrics
    (SELECT COUNT(*) FROM `${PROJECT_ID}.${DATASET_ID}.search_log` 
     WHERE DATE(search_timestamp) = CURRENT_DATE()) AS todays_searches,
    
    (SELECT AVG(avg_similarity) FROM `${PROJECT_ID}.${DATASET_ID}.search_log`
     WHERE DATE(search_timestamp) = CURRENT_DATE()) AS todays_avg_relevance,
    
    -- Duplicate metrics
    (SELECT SUM(duplicate_pairs_found) FROM `${PROJECT_ID}.${DATASET_ID}.duplicate_detection_log`
     WHERE DATE(run_timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)) AS weekly_duplicates_found,
    
    -- Coverage metrics
    (SELECT embedding_coverage FROM `${PROJECT_ID}.${DATASET_ID}.embedding_health`
     ORDER BY date DESC LIMIT 1) AS embedding_coverage,
    
    -- Cost metrics
    (SELECT SUM(estimated_cost) FROM `${PROJECT_ID}.${DATASET_ID}.cost_performance_dashboard`
     WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)) AS monthly_cost
),
value_metrics AS (
  SELECT
    -- Search value
    todays_searches * 0.50 AS search_revenue_impact, -- $0.50 value per search
    
    -- Duplicate detection value
    weekly_duplicates_found * 100 AS weekly_duplicate_savings, -- $100 per duplicate found
    
    -- Operational efficiency
    todays_searches * 0.001 AS hours_saved -- 0.001 hours saved per automated search
  FROM kpi_metrics
)
SELECT
  k.*,
  v.*,
  
  -- ROI calculation
  (v.search_revenue_impact + (v.weekly_duplicate_savings / 7)) - (k.monthly_cost / 30) AS daily_roi,
  
  -- Health score (0-100)
  ROUND(
    (k.embedding_coverage * 25) +  -- 25 points for coverage
    (CASE WHEN k.todays_avg_relevance > 0.8 THEN 25 ELSE 15 END) + -- 25 points for quality
    (CASE WHEN k.weekly_duplicates_found > 0 THEN 25 ELSE 10 END) + -- 25 points for detection
    (CASE WHEN k.monthly_cost < 5000 THEN 25 ELSE 15 END)  -- 25 points for cost efficiency
  ) AS platform_health_score,
  
  -- Executive summary
  CASE
    WHEN k.todays_searches = 0 THEN 'CRITICAL: No search activity'
    WHEN k.embedding_coverage < 0.8 THEN 'ACTION NEEDED: Low embedding coverage'
    WHEN k.monthly_cost > 10000 THEN 'REVIEW: High operational costs'
    ELSE 'PLATFORM HEALTHY'
  END AS executive_status
  
FROM kpi_metrics k
CROSS JOIN value_metrics v;