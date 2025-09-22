-- ============================================
-- APPROACH 3: MULTIMODAL PIONEER - MONITORING & ALERTING
-- ============================================
-- Production monitoring for visual intelligence platform

-- ============================================
-- 1. VISUAL QUALITY CONTROL MONITORING
-- ============================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.visual_qc_monitoring` AS
WITH qc_metrics AS (
  SELECT
    DATE(run_timestamp) AS date,
    COUNT(*) AS qc_runs,
    SUM(products_analyzed) AS total_products_checked,
    SUM(issues_found) AS total_issues,
    SUM(compliance_violations) AS compliance_issues,
    SUM(counterfeit_suspects) AS counterfeit_detections,
    AVG(avg_quality_score) AS avg_quality_score,
    SUM(total_risk_value) AS risk_prevented_usd,
    AVG(products_analyzed / NULLIF(issues_found, 0)) AS products_per_issue
  FROM `${PROJECT_ID}.${DATASET_ID}.qc_run_log`
  WHERE run_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  GROUP BY date
),
issue_trends AS (
  SELECT
    category,
    action_required,
    COUNT(*) AS issue_count,
    SUM(potential_loss) AS total_potential_loss,
    AVG(quality_score) AS avg_quality_in_category
  FROM `${PROJECT_ID}.${DATASET_ID}.quality_control_results`
  WHERE action_required != 'Pass'
    AND analysis_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  GROUP BY category, action_required
)
SELECT
  m.*,
  
  -- Calculate detection rates
  m.compliance_issues / NULLIF(m.total_products_checked, 0) AS compliance_violation_rate,
  m.counterfeit_detections / NULLIF(m.total_products_checked, 0) AS counterfeit_detection_rate,
  
  -- Effectiveness metrics
  CASE
    WHEN m.compliance_issues > m.total_products_checked * 0.05 THEN 'CRITICAL: >5% compliance issues'
    WHEN m.counterfeit_detections > 10 THEN 'WARNING: High counterfeit detection'
    WHEN m.avg_quality_score < 7.0 THEN 'WARNING: Low average quality'
    ELSE 'HEALTHY'
  END AS qc_status,
  
  -- Top issues by category
  ARRAY(
    SELECT AS STRUCT category, action_required, issue_count, total_potential_loss
    FROM issue_trends
    ORDER BY total_potential_loss DESC
    LIMIT 5
  ) AS top_issues,
  
  -- ROI metrics
  m.risk_prevented_usd AS compliance_savings,
  m.total_products_checked * 5 / 60 * 50 AS manual_qc_cost_avoided -- 5 min per product at $50/hr
  
FROM qc_metrics m
ORDER BY date DESC;

-- ============================================
-- 2. VISUAL SEARCH PERFORMANCE MONITORING
-- ============================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.visual_search_monitoring` AS
WITH search_metrics AS (
  SELECT
    DATE(search_timestamp) AS date,
    search_mode,
    COUNT(*) AS search_count,
    AVG(results_returned) AS avg_results_returned,
    AVG(avg_similarity_score) AS avg_similarity,
    STDDEV(avg_similarity_score) AS similarity_stddev,
    COUNT(DISTINCT query_image_uri) AS unique_query_images,
    SUM(CASE WHEN user_action = 'click' THEN 1 ELSE 0 END) / COUNT(*) AS click_through_rate,
    SUM(CASE WHEN clicked_sku IS NOT NULL THEN 1 ELSE 0 END) AS conversions
  FROM `${PROJECT_ID}.${DATASET_ID}.visual_search_log`
  WHERE search_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  GROUP BY date, search_mode
),
search_quality AS (
  SELECT
    query_image_uri,
    COUNT(*) AS search_frequency,
    AVG(avg_similarity_score) AS avg_score,
    MAX(avg_similarity_score) AS best_match_score
  FROM `${PROJECT_ID}.${DATASET_ID}.visual_search_log`
  WHERE search_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
  GROUP BY query_image_uri
  HAVING COUNT(*) > 3 -- Repeated searches might indicate issues
)
SELECT
  m.*,
  
  -- Performance indicators
  CASE
    WHEN m.avg_similarity < 0.7 THEN 'WARNING: Low match quality'
    WHEN m.avg_results_returned < 3 THEN 'WARNING: Few results found'
    WHEN m.click_through_rate < 0.2 THEN 'WARNING: Low engagement'
    ELSE 'HEALTHY'
  END AS search_health,
  
  -- Search quality score (0-100)
  ROUND(
    (m.avg_similarity * 40) +  -- 40 points for similarity
    (CASE WHEN m.avg_results_returned BETWEEN 5 AND 15 THEN 30 ELSE 15 END) + -- 30 points for result count
    (m.click_through_rate * 30)  -- 30 points for engagement
  ) AS visual_search_score,
  
  -- Problem searches (low quality repeated searches)
  ARRAY(
    SELECT AS STRUCT query_image_uri, search_frequency, ROUND(avg_score, 3) AS avg_score
    FROM search_quality
    WHERE avg_score < 0.6
    ORDER BY search_frequency DESC
    LIMIT 5
  ) AS problematic_searches,
  
  -- Business impact
  m.conversions * 100 AS estimated_revenue_impact -- $100 avg order value

FROM search_metrics m
ORDER BY date DESC, search_mode;

-- ============================================
-- 3. OBJECT TABLE & IMAGE PROCESSING MONITORING
-- ============================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.image_processing_monitoring` AS
WITH object_table_stats AS (
  -- Monitor object table health
  SELECT
    'product_images' AS object_table,
    COUNT(*) AS total_images,
    SUM(size) / POW(1024, 3) AS total_size_gb,
    AVG(size) / POW(1024, 2) AS avg_image_size_mb,
    COUNT(DISTINCT content_type) AS unique_formats,
    MAX(updated) AS latest_update
  FROM `${PROJECT_ID}.${DATASET_ID}.product_images_metadata`
),
processing_stats AS (
  SELECT
    DATE(timestamp) AS date,
    operation,
    SUM(CASE WHEN status = 'SUCCESS' THEN batch_size ELSE 0 END) AS images_processed,
    SUM(CASE WHEN status = 'ERROR' THEN batch_size ELSE 0 END) AS images_failed,
    AVG(CASE WHEN status = 'SUCCESS' THEN batch_size / NULLIF(offset_processed, 0) END) AS processing_rate
  FROM `${PROJECT_ID}.${DATASET_ID}.processing_log`
  WHERE operation IN ('analyze_image', 'generate_visual_embedding')
    AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  GROUP BY date, operation
),
image_analysis_quality AS (
  SELECT
    COUNT(*) AS total_analyzed,
    AVG(CAST(quality_score AS FLOAT64)) AS avg_quality_score,
    COUNT(CASE WHEN quality_score < '5' THEN 1 END) AS poor_quality_images,
    COUNT(CASE WHEN NOT is_compliant THEN 1 END) AS non_compliant_images,
    COUNT(CASE WHEN authenticity_score < 0.5 THEN 1 END) AS suspicious_images
  FROM `${PROJECT_ID}.${DATASET_ID}.quality_control_results`
  WHERE analysis_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
)
SELECT
  o.*,
  p.images_processed,
  p.images_failed,
  i.avg_quality_score,
  i.poor_quality_images,
  
  -- Storage monitoring
  CASE
    WHEN o.total_size_gb > 1000 THEN 'WARNING: High storage usage'
    WHEN o.avg_image_size_mb > 10 THEN 'WARNING: Large image sizes'
    ELSE 'OK'
  END AS storage_alert,
  
  -- Processing health
  CASE
    WHEN p.images_failed > p.images_processed * 0.1 THEN 'CRITICAL: High failure rate'
    WHEN i.poor_quality_images > i.total_analyzed * 0.2 THEN 'WARNING: Many poor quality images'
    WHEN i.suspicious_images > 0 THEN 'ALERT: Potential counterfeits detected'
    ELSE 'HEALTHY'
  END AS processing_status,
  
  -- Optimization recommendations
  CASE
    WHEN o.avg_image_size_mb > 5 THEN 'Consider image compression'
    WHEN p.processing_rate < 100 THEN 'Scale up processing capacity'
    WHEN i.poor_quality_images > 50 THEN 'Implement pre-upload quality checks'
    ELSE 'No optimization needed'
  END AS recommendation
  
FROM object_table_stats o
CROSS JOIN (SELECT * FROM processing_stats WHERE date = CURRENT_DATE() LIMIT 1) p
CROSS JOIN image_analysis_quality i;

-- ============================================
-- 4. VISUAL EMBEDDING INDEX MONITORING
-- ============================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.visual_index_monitoring` AS
WITH embedding_coverage AS (
  SELECT
    COUNT(DISTINCT p.sku) AS total_products,
    COUNT(DISTINCT e.sku) AS products_with_visual_embeddings,
    COUNT(DISTINCT CASE WHEN e.multimodal_embedding IS NOT NULL THEN e.sku END) AS products_with_multimodal,
    MAX(e.embedding_timestamp) AS latest_embedding_update
  FROM `${PROJECT_ID}.${DATASET_ID}.products` p
  LEFT JOIN `${PROJECT_ID}.${DATASET_ID}.products_visual_embeddings` e ON p.sku = e.sku
  WHERE p.image_url IS NOT NULL
),
index_performance AS (
  -- Simulate index stats (in production would query system tables)
  SELECT
    'visual_idx' AS index_name,
    (SELECT COUNT(*) FROM `${PROJECT_ID}.${DATASET_ID}.products_visual_embeddings`) AS indexed_vectors,
    1000 AS num_lists, -- IVF configuration
    512 AS vector_dimension -- Multimodal embedding size
),
search_latency AS (
  SELECT
    PERCENTILE_CONT(results_returned, 0.5) OVER() AS median_results,
    PERCENTILE_CONT(results_returned, 0.95) OVER() AS p95_results,
    AVG(avg_similarity_score) AS avg_match_quality
  FROM `${PROJECT_ID}.${DATASET_ID}.visual_search_log`
  WHERE search_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
    AND search_mode = 'visual'
)
SELECT
  c.products_with_visual_embeddings / c.total_products AS visual_coverage,
  c.products_with_multimodal / c.total_products AS multimodal_coverage,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), c.latest_embedding_update, HOUR) AS hours_since_update,
  i.indexed_vectors,
  i.indexed_vectors / i.num_lists AS avg_vectors_per_list,
  l.avg_match_quality,
  
  -- Index health status
  CASE
    WHEN c.products_with_visual_embeddings / c.total_products < 0.9 THEN 'WARNING: Low embedding coverage'
    WHEN TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), c.latest_embedding_update, HOUR) > 24 THEN 'WARNING: Stale embeddings'
    WHEN i.indexed_vectors / i.num_lists > 1000 THEN 'INFO: Consider increasing num_lists'
    ELSE 'OPTIMAL'
  END AS index_health,
  
  -- Coverage gaps
  c.total_products - c.products_with_visual_embeddings AS products_missing_embeddings,
  
  -- Performance metrics
  CASE
    WHEN l.avg_match_quality < 0.75 THEN 'Review embedding quality'
    WHEN i.indexed_vectors > 1000000 THEN 'Consider partitioned indexes'
    ELSE 'Performance optimal'
  END AS performance_recommendation
  
FROM embedding_coverage c
CROSS JOIN index_performance i
CROSS JOIN search_latency l;

-- ============================================
-- 5. COMPLIANCE & RISK MONITORING
-- ============================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.compliance_risk_dashboard` AS
WITH compliance_violations AS (
  SELECT
    category,
    COUNT(*) AS products_checked,
    SUM(CASE WHEN NOT is_compliant THEN 1 ELSE 0 END) AS violations,
    SUM(potential_loss) AS total_risk_value,
    STRING_AGG(DISTINCT 
      CASE WHEN NOT is_compliant THEN priority END 
      IGNORE NULLS 
      LIMIT 3
    ) AS violation_types
  FROM `${PROJECT_ID}.${DATASET_ID}.quality_control_results`
  WHERE analysis_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  GROUP BY category
),
counterfeit_risks AS (
  SELECT
    brand_name,
    COUNT(*) AS products_analyzed,
    COUNT(CASE WHEN authenticity_score < 0.5 THEN 1 END) AS high_risk_products,
    COUNT(CASE WHEN authenticity_score < 0.7 THEN 1 END) AS medium_risk_products,
    MIN(authenticity_score) AS lowest_authenticity_score,
    SUM(CASE WHEN authenticity_score < 0.5 THEN price END) AS revenue_at_risk
  FROM `${PROJECT_ID}.${DATASET_ID}.quality_control_results`
  WHERE analysis_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  GROUP BY brand_name
  HAVING COUNT(CASE WHEN authenticity_score < 0.7 THEN 1 END) > 0
),
risk_summary AS (
  SELECT
    SUM(violations) AS total_violations,
    SUM(total_risk_value) AS total_compliance_risk,
    COUNT(DISTINCT category) AS categories_with_issues
  FROM compliance_violations
  WHERE violations > 0
)
SELECT
  r.*,
  
  -- Top compliance risks
  ARRAY(
    SELECT AS STRUCT category, violations, total_risk_value, violation_types
    FROM compliance_violations
    WHERE violations > 0
    ORDER BY total_risk_value DESC
    LIMIT 5
  ) AS top_compliance_risks,
  
  -- Top counterfeit risks
  ARRAY(
    SELECT AS STRUCT 
      brand_name, 
      high_risk_products, 
      medium_risk_products, 
      ROUND(revenue_at_risk, 2) AS revenue_at_risk
    FROM counterfeit_risks
    ORDER BY revenue_at_risk DESC
    LIMIT 5
  ) AS top_counterfeit_risks,
  
  -- Risk level
  CASE
    WHEN r.total_violations > 50 THEN 'CRITICAL: Immediate action required'
    WHEN r.total_compliance_risk > 100000 THEN 'HIGH: Significant financial exposure'
    WHEN r.categories_with_issues > 3 THEN 'MEDIUM: Multiple categories affected'
    ELSE 'LOW: Manageable risk level'
  END AS overall_risk_level,
  
  -- Recommended actions
  CASE
    WHEN r.total_violations > 50 THEN 'Halt affected products and review compliance process'
    WHEN r.total_compliance_risk > 50000 THEN 'Prioritize high-value compliance issues'
    ELSE 'Continue monitoring and preventive measures'
  END AS recommended_action
  
FROM risk_summary r;

-- ============================================
-- 6. MERCHANDISING EFFECTIVENESS MONITORING
-- ============================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.merchandising_performance` AS
WITH merchandising_groups AS (
  SELECT
    category,
    COUNT(DISTINCT visual_group) AS total_groups,
    SUM(group_size) AS total_products,
    AVG(group_size) AS avg_group_size,
    SUM(projected_lift_value) AS total_projected_value,
    COUNT(CASE WHEN priority = 'High' THEN 1 END) AS high_priority_groups
  FROM `${PROJECT_ID}.${DATASET_ID}.optimize_visual_merchandising`(
    (SELECT DISTINCT category FROM `${PROJECT_ID}.${DATASET_ID}.products`),
    NULL
  )
  GROUP BY category
),
implementation_tracking AS (
  -- Track which recommendations were implemented
  SELECT
    category,
    COUNT(*) AS implemented_groups,
    SUM(CASE WHEN search_mode = 'visual' THEN 1 ELSE 0 END) AS visual_searches_to_groups
  FROM `${PROJECT_ID}.${DATASET_ID}.visual_search_log` s
  JOIN `${PROJECT_ID}.${DATASET_ID}.products` p ON s.clicked_sku = p.sku
  WHERE s.search_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  GROUP BY category
)
SELECT
  m.*,
  i.implemented_groups,
  i.visual_searches_to_groups,
  
  -- Implementation rate
  i.implemented_groups / NULLIF(m.total_groups, 0) AS implementation_rate,
  
  -- Effectiveness metrics
  m.total_projected_value AS monthly_revenue_opportunity,
  i.visual_searches_to_groups * 100 * 0.02 AS realized_revenue_lift, -- 2% conversion lift
  
  -- Performance status
  CASE
    WHEN i.implemented_groups / NULLIF(m.total_groups, 0) < 0.3 THEN 'Low implementation rate'
    WHEN m.avg_group_size < 5 THEN 'Small groups - consider broader clustering'
    WHEN m.high_priority_groups = 0 THEN 'No high-value opportunities found'
    ELSE 'Performing well'
  END AS merchandising_status,
  
  -- ROI calculation
  (i.visual_searches_to_groups * 100 * 0.02) / NULLIF(m.total_products * 0.01, 0) AS merchandising_roi
  
FROM merchandising_groups m
LEFT JOIN implementation_tracking i ON m.category = i.category
ORDER BY m.total_projected_value DESC;

-- ============================================
-- 7. COST OPTIMIZATION & RESOURCE MONITORING
-- ============================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.multimodal_cost_monitoring` AS
WITH operation_costs AS (
  SELECT
    DATE(timestamp) AS date,
    operation,
    SUM(batch_size) AS items_processed,
    COUNT(*) AS operation_count,
    
    -- Estimate costs by operation type
    CASE operation
      WHEN 'analyze_product_images' THEN SUM(batch_size) * 0.002  -- $0.002 per image
      WHEN 'build_visual_search_index' THEN SUM(batch_size) * 0.0001  -- $0.0001 per embedding
      WHEN 'run_visual_quality_control' THEN SUM(batch_size) * 0.003  -- $0.003 per QC
      WHEN 'visual_search' THEN COUNT(*) * 0.00001  -- $0.00001 per search
      ELSE 0
    END AS estimated_cost
    
  FROM `${PROJECT_ID}.${DATASET_ID}.processing_log`
  WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND status = 'SUCCESS'
  GROUP BY date, operation
),
daily_summary AS (
  SELECT
    date,
    SUM(estimated_cost) AS daily_cost,
    SUM(items_processed) AS daily_items,
    ARRAY_AGG(STRUCT(operation, estimated_cost) ORDER BY estimated_cost DESC LIMIT 3) AS top_cost_operations
  FROM operation_costs
  GROUP BY date
),
resource_usage AS (
  SELECT
    -- Storage costs
    (SELECT SUM(size) / POW(1024, 4) FROM `${PROJECT_ID}.${DATASET_ID}.product_images_metadata`) * 0.02 AS monthly_storage_cost,
    
    -- Compute projections
    (SELECT AVG(daily_cost) * 30 FROM daily_summary) AS projected_monthly_compute_cost
)
SELECT
  s.*,
  r.monthly_storage_cost,
  r.projected_monthly_compute_cost,
  
  -- Cost trends
  s.daily_cost - LAG(s.daily_cost) OVER (ORDER BY s.date) AS daily_cost_change,
  AVG(s.daily_cost) OVER (ORDER BY s.date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS avg_7day_cost,
  
  -- Total projected costs
  r.monthly_storage_cost + r.projected_monthly_compute_cost AS total_monthly_cost,
  
  -- Cost alerts
  CASE
    WHEN s.daily_cost > 500 THEN 'ALERT: High daily spend'
    WHEN s.daily_cost > AVG(s.daily_cost) OVER (ORDER BY s.date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) * 2 
      THEN 'WARNING: Cost spike detected'
    WHEN r.projected_monthly_compute_cost > 10000 THEN 'Review: High projected monthly cost'
    ELSE 'Costs normal'
  END AS cost_alert,
  
  -- Optimization recommendations
  CASE
    WHEN s.daily_items < 1000 AND s.daily_cost > 100 THEN 'Low efficiency - batch operations'
    WHEN r.monthly_storage_cost > 100 THEN 'Consider archiving old images'
    WHEN EXISTS (SELECT 1 FROM UNNEST(s.top_cost_operations) WHERE operation = 'analyze_product_images' AND estimated_cost > 200)
      THEN 'Optimize image analysis frequency'
    ELSE 'No optimization needed'
  END AS cost_optimization_tip
  
FROM daily_summary s
CROSS JOIN resource_usage r
ORDER BY s.date DESC;

-- ============================================
-- 8. AUTOMATED MULTIMODAL ALERTING
-- ============================================

CREATE OR REPLACE PROCEDURE `${PROJECT_ID}.${DATASET_ID}.multimodal_system_alerts`()
BEGIN
  DECLARE system_alerts ARRAY<STRUCT<severity STRING, component STRING, issue STRING, impact STRING>>;
  
  -- Collect all system issues
  SET system_alerts = ARRAY(
    -- QC alerts
    SELECT AS STRUCT
      'CRITICAL' AS severity,
      'Quality Control' AS component,
      qc_status AS issue,
      CONCAT('$', CAST(risk_prevented_usd AS STRING), ' at risk') AS impact
    FROM `${PROJECT_ID}.${DATASET_ID}.visual_qc_monitoring`
    WHERE qc_status != 'HEALTHY'
      AND date = CURRENT_DATE()
    
    UNION ALL
    
    -- Compliance alerts
    SELECT AS STRUCT
      CASE WHEN overall_risk_level LIKE 'CRITICAL%' THEN 'CRITICAL' ELSE 'WARNING' END AS severity,
      'Compliance' AS component,
      overall_risk_level AS issue,
      CONCAT(CAST(total_violations AS STRING), ' violations, $', 
             CAST(total_compliance_risk AS STRING), ' exposure') AS impact
    FROM `${PROJECT_ID}.${DATASET_ID}.compliance_risk_dashboard`
    WHERE overall_risk_level NOT LIKE 'LOW%'
    
    UNION ALL
    
    -- Performance alerts
    SELECT AS STRUCT
      'WARNING' AS severity,
      'Visual Search' AS component,
      search_health AS issue,
      CONCAT('Search quality: ', CAST(visual_search_score AS STRING)) AS impact
    FROM `${PROJECT_ID}.${DATASET_ID}.visual_search_monitoring`
    WHERE search_health != 'HEALTHY'
      AND date = CURRENT_DATE()
      
    UNION ALL
    
    -- Cost alerts
    SELECT AS STRUCT
      CASE WHEN cost_alert LIKE 'ALERT%' THEN 'CRITICAL' ELSE 'WARNING' END AS severity,
      'Cost Management' AS component,
      cost_alert AS issue,
      CONCAT('Daily cost: $', CAST(daily_cost AS STRING)) AS impact
    FROM `${PROJECT_ID}.${DATASET_ID}.multimodal_cost_monitoring`
    WHERE cost_alert != 'Costs normal'
      AND date = CURRENT_DATE()
  );
  
  -- Log critical alerts
  IF EXISTS (SELECT 1 FROM UNNEST(system_alerts) WHERE severity = 'CRITICAL') THEN
    INSERT INTO `${PROJECT_ID}.${DATASET_ID}.processing_log`
    VALUES(
      CURRENT_TIMESTAMP(),
      'SYSTEM_ALERT',
      'monitoring',
      0,
      ARRAY_LENGTH(ARRAY(SELECT 1 FROM UNNEST(system_alerts) WHERE severity = 'CRITICAL')),
      'CRITICAL',
      ARRAY_TO_STRING(
        ARRAY(
          SELECT CONCAT(component, ': ', issue, ' (', impact, ')')
          FROM UNNEST(system_alerts)
          WHERE severity = 'CRITICAL'
        ),
        '; '
      )
    );
  END IF;
  
  -- Auto-remediation actions
  IF EXISTS (
    SELECT 1 FROM `${PROJECT_ID}.${DATASET_ID}.visual_index_monitoring`
    WHERE products_missing_embeddings > 100
  ) THEN
    -- Trigger embedding generation for products missing embeddings
    CALL `${PROJECT_ID}.${DATASET_ID}.build_visual_search_index`('products', 100);
  END IF;
END;

-- ============================================
-- 9. EXECUTIVE DASHBOARD
-- ============================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.multimodal_executive_dashboard` AS
WITH platform_metrics AS (
  SELECT
    -- Volume metrics
    (SELECT SUM(products_analyzed) FROM `${PROJECT_ID}.${DATASET_ID}.qc_run_log`
     WHERE DATE(run_timestamp) = CURRENT_DATE()) AS todays_products_analyzed,
    
    -- Quality metrics
    (SELECT AVG(avg_quality_score) FROM `${PROJECT_ID}.${DATASET_ID}.qc_run_log`
     WHERE run_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)) AS avg_quality_score,
    
    -- Search metrics
    (SELECT COUNT(*) FROM `${PROJECT_ID}.${DATASET_ID}.visual_search_log`
     WHERE DATE(search_timestamp) = CURRENT_DATE()) AS todays_visual_searches,
    
    -- Risk metrics
    (SELECT SUM(total_risk_value) FROM `${PROJECT_ID}.${DATASET_ID}.qc_run_log`
     WHERE run_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)) AS monthly_risk_prevented,
    
    -- Cost metrics
    (SELECT total_monthly_cost FROM `${PROJECT_ID}.${DATASET_ID}.multimodal_cost_monitoring`
     ORDER BY date DESC LIMIT 1) AS projected_monthly_cost
),
value_generation AS (
  SELECT
    -- QC value
    monthly_risk_prevented AS compliance_risk_avoided,
    todays_products_analyzed * 5 / 60 * 50 * 22 AS monthly_labor_saved, -- 5 min per product, 22 working days
    
    -- Search value
    todays_visual_searches * 30 * 100 * 0.02 AS monthly_search_revenue, -- 30 days * $100 AOV * 2% lift
    
    -- Merchandising value
    (SELECT SUM(total_projected_value) FROM `${PROJECT_ID}.${DATASET_ID}.merchandising_performance`) AS merchandising_opportunity
  FROM platform_metrics
),
health_scoring AS (
  SELECT
    -- Calculate platform health (0-100)
    ROUND(
      (CASE WHEN avg_quality_score > 7 THEN 25 ELSE 15 END) + -- Image quality
      (CASE WHEN todays_products_analyzed > 100 THEN 25 ELSE 10 END) + -- QC volume
      (CASE WHEN todays_visual_searches > 50 THEN 25 ELSE 10 END) + -- Search usage
      (CASE WHEN projected_monthly_cost < 5000 THEN 25 ELSE 15 END) -- Cost efficiency
    ) AS platform_health_score
  FROM platform_metrics
)
SELECT
  p.*,
  v.*,
  h.platform_health_score,
  
  -- Total value calculation
  v.compliance_risk_avoided + v.monthly_labor_saved + v.monthly_search_revenue AS total_monthly_value,
  
  -- ROI calculation
  ROUND((v.compliance_risk_avoided + v.monthly_labor_saved + v.monthly_search_revenue) / 
        NULLIF(p.projected_monthly_cost, 0), 2) AS roi_multiple,
  
  -- Executive summary
  CASE
    WHEN h.platform_health_score < 50 THEN 'ATTENTION REQUIRED: Low platform health'
    WHEN p.monthly_risk_prevented > 500000 THEN 'EXCEPTIONAL: High risk prevention'
    WHEN v.total_monthly_value / NULLIF(p.projected_monthly_cost, 0) > 10 THEN 'EXCELLENT: 10x+ ROI'
    ELSE 'HEALTHY: Normal operations'
  END AS executive_status,
  
  -- Strategic insights
  ARRAY(
    SELECT insight FROM UNNEST([
      IF(p.avg_quality_score < 7, 'Image quality below target - implement stricter guidelines', NULL),
      IF(p.todays_visual_searches < 50, 'Low visual search adoption - promote feature to users', NULL),
      IF(v.merchandising_opportunity > 100000, 'High merchandising opportunity - prioritize implementation', NULL),
      IF(p.projected_monthly_cost > 10000, 'Review cost optimization strategies', NULL)
    ]) AS insight
    WHERE insight IS NOT NULL
  ) AS strategic_recommendations
  
FROM platform_metrics p
CROSS JOIN value_generation v
CROSS JOIN health_scoring h;