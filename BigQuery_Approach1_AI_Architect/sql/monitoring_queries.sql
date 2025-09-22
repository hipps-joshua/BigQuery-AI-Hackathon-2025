-- ============================================
-- APPROACH 1: AI ARCHITECT - MONITORING & ALERTING
-- ============================================
-- Production monitoring queries for operational excellence

-- ============================================
-- 1. REAL-TIME PERFORMANCE MONITORING
-- ============================================

-- Performance metrics by operation
CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.operation_performance` AS
WITH hourly_metrics AS (
  SELECT
    TIMESTAMP_TRUNC(timestamp, HOUR) AS hour,
    operation,
    COUNT(*) AS executions,
    AVG(processing_time_seconds) AS avg_processing_seconds,
    MAX(processing_time_seconds) AS max_processing_seconds,
    SUM(records_processed) AS total_records,
    AVG(records_processed / processing_time_seconds) AS avg_throughput_per_sec,
    SUM(tokens_used) AS total_tokens,
    SUM(estimated_cost) AS total_cost
  FROM `${PROJECT_ID}.${DATASET_ID}.performance_metrics`
  WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
  GROUP BY hour, operation
)
SELECT
  *,
  -- Performance alerts
  CASE 
    WHEN avg_processing_seconds > 60 THEN 'CRITICAL: Slow processing'
    WHEN avg_throughput_per_sec < 10 THEN 'WARNING: Low throughput'
    ELSE 'OK'
  END AS performance_alert,
  
  -- Cost alerts
  CASE
    WHEN total_cost > 100 THEN 'CRITICAL: High cost per hour'
    WHEN total_cost > 50 THEN 'WARNING: Elevated cost'
    ELSE 'OK'
  END AS cost_alert
FROM hourly_metrics
ORDER BY hour DESC, total_cost DESC;

-- ============================================
-- 2. ERROR TRACKING & ALERTING
-- ============================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.error_monitoring` AS
WITH error_summary AS (
  SELECT
    DATE(timestamp) AS date,
    operation,
    COUNT(CASE WHEN status = 'ERROR' THEN 1 END) AS error_count,
    COUNT(*) AS total_operations,
    COUNT(CASE WHEN status = 'ERROR' THEN 1 END) / COUNT(*) AS error_rate,
    STRING_AGG(DISTINCT error_message LIMIT 5) AS sample_errors
  FROM `${PROJECT_ID}.${DATASET_ID}.processing_log`
  WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  GROUP BY date, operation
)
SELECT
  *,
  -- Alert levels
  CASE
    WHEN error_rate > 0.1 THEN 'CRITICAL: >10% error rate'
    WHEN error_rate > 0.05 THEN 'WARNING: >5% error rate'
    WHEN error_count > 100 THEN 'WARNING: High error volume'
    ELSE 'OK'
  END AS alert_level,
  
  -- Trend analysis
  error_rate - LAG(error_rate) OVER (PARTITION BY operation ORDER BY date) AS error_rate_change,
  
  -- Action required
  CASE
    WHEN error_rate > 0.1 THEN 'Immediate investigation required'
    WHEN error_count > 100 THEN 'Review error logs'
    ELSE 'Monitor'
  END AS action_required
FROM error_summary
WHERE error_count > 0
ORDER BY date DESC, error_rate DESC;

-- ============================================
-- 3. TEMPLATE EFFECTIVENESS MONITORING
-- ============================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.template_effectiveness` AS
WITH template_metrics AS (
  SELECT
    t.template_id,
    t.template_name,
    t.category,
    t.confidence_threshold,
    COUNT(l.operation) AS usage_count,
    COUNT(CASE WHEN l.status = 'SUCCESS' THEN 1 END) AS success_count,
    COUNT(CASE WHEN l.status = 'ERROR' THEN 1 END) AS error_count,
    AVG(p.processing_time_seconds) AS avg_processing_time,
    SUM(p.estimated_cost) AS total_cost,
    
    -- Calculate effectiveness score
    COUNT(CASE WHEN l.status = 'SUCCESS' THEN 1 END) / NULLIF(COUNT(*), 0) AS success_rate
  FROM `${PROJECT_ID}.${DATASET_ID}.template_library` t
  LEFT JOIN `${PROJECT_ID}.${DATASET_ID}.processing_log` l
    ON t.template_id = l.operation
  LEFT JOIN `${PROJECT_ID}.${DATASET_ID}.performance_metrics` p
    ON l.operation = p.operation AND ABS(TIMESTAMP_DIFF(l.timestamp, p.timestamp, SECOND)) < 1
  WHERE l.timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  GROUP BY 1,2,3,4
)
SELECT
  *,
  -- Template health score (0-100)
  ROUND(
    (success_rate * 40) +  -- 40 points for success rate
    (CASE WHEN avg_processing_time < 10 THEN 30 ELSE 15 END) + -- 30 points for speed
    (CASE WHEN error_count = 0 THEN 30 ELSE 10 END)  -- 30 points for reliability
  ) AS health_score,
  
  -- Recommendations
  CASE
    WHEN success_rate < 0.8 THEN 'Review and update template logic'
    WHEN avg_processing_time > 30 THEN 'Optimize for performance'
    WHEN usage_count < 10 THEN 'Low usage - consider deprecation'
    ELSE 'Performing well'
  END AS recommendation
FROM template_metrics
ORDER BY category, health_score DESC;

-- ============================================
-- 4. DATA QUALITY MONITORING
-- ============================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.data_quality_alerts` AS
WITH quality_checks AS (
  SELECT
    CURRENT_TIMESTAMP() AS check_time,
    
    -- Completeness checks
    COUNT(*) AS total_products,
    COUNT(brand_name) / COUNT(*) AS brand_completeness,
    COUNT(description) / COUNT(*) AS description_completeness,
    COUNT(enhanced_description) / COUNT(*) AS enrichment_rate,
    
    -- Validity checks
    SUM(CASE WHEN price <= 0 OR price IS NULL THEN 1 ELSE 0 END) AS invalid_prices,
    SUM(CASE WHEN cost > price THEN 1 ELSE 0 END) AS negative_margin_products,
    
    -- Freshness checks
    MAX(TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), updated_at, HOUR)) AS hours_since_last_update,
    
    -- Anomaly detection
    AVG(price) AS avg_price,
    STDDEV(price) AS price_stddev,
    COUNT(CASE WHEN price > AVG(price) + 3*STDDEV(price) THEN 1 END) AS price_outliers
    
  FROM `${PROJECT_ID}.${DATASET_ID}.products`
)
SELECT
  *,
  -- Generate alerts
  ARRAY(
    SELECT AS STRUCT
      alert_type,
      severity,
      message
    FROM UNNEST([
      STRUCT(
        'Data Completeness' AS alert_type,
        CASE 
          WHEN brand_completeness < 0.8 THEN 'CRITICAL'
          WHEN brand_completeness < 0.9 THEN 'WARNING'
          ELSE 'OK'
        END AS severity,
        CONCAT('Brand name completion: ', ROUND(brand_completeness * 100, 1), '%') AS message
      ),
      STRUCT(
        'Data Enrichment' AS alert_type,
        CASE 
          WHEN enrichment_rate < 0.5 THEN 'WARNING'
          WHEN enrichment_rate < 0.8 THEN 'INFO'
          ELSE 'OK'
        END AS severity,
        CONCAT('Products enriched: ', ROUND(enrichment_rate * 100, 1), '%') AS message
      ),
      STRUCT(
        'Data Quality' AS alert_type,
        CASE 
          WHEN invalid_prices > 0 THEN 'CRITICAL'
          WHEN negative_margin_products > 10 THEN 'WARNING'
          ELSE 'OK'
        END AS severity,
        CONCAT('Invalid prices: ', invalid_prices, ', Negative margins: ', negative_margin_products) AS message
      ),
      STRUCT(
        'Data Freshness' AS alert_type,
        CASE 
          WHEN hours_since_last_update > 48 THEN 'WARNING'
          WHEN hours_since_last_update > 168 THEN 'CRITICAL'
          ELSE 'OK'
        END AS severity,
        CONCAT('Hours since last update: ', hours_since_last_update) AS message
      ),
      STRUCT(
        'Anomalies' AS alert_type,
        CASE 
          WHEN price_outliers > total_products * 0.05 THEN 'WARNING'
          ELSE 'OK'
        END AS severity,
        CONCAT('Price outliers detected: ', price_outliers) AS message
      )
    ])
    WHERE severity != 'OK'
  ) AS active_alerts
FROM quality_checks;

-- ============================================
-- 5. COST OPTIMIZATION MONITORING
-- ============================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.cost_optimization_dashboard` AS
WITH daily_costs AS (
  SELECT
    DATE(timestamp) AS date,
    operation,
    SUM(records_processed) AS records,
    SUM(tokens_used) AS tokens,
    SUM(estimated_cost) AS cost,
    AVG(estimated_cost / NULLIF(records_processed, 0)) AS cost_per_record
  FROM `${PROJECT_ID}.${DATASET_ID}.performance_metrics`
  WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  GROUP BY date, operation
),
cost_trends AS (
  SELECT
    date,
    SUM(cost) AS daily_cost,
    SUM(cost) - LAG(SUM(cost)) OVER (ORDER BY date) AS cost_change,
    AVG(SUM(cost)) OVER (ORDER BY date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS avg_7day_cost
  FROM daily_costs
  GROUP BY date
)
SELECT
  t.*,
  
  -- Cost projections
  avg_7day_cost * 30 AS projected_monthly_cost,
  
  -- Cost alerts
  CASE
    WHEN daily_cost > avg_7day_cost * 1.5 THEN 'ALERT: 50% above average'
    WHEN cost_change > avg_7day_cost * 0.3 THEN 'WARNING: 30% daily increase'
    ELSE 'Normal'
  END AS cost_alert,
  
  -- Top cost operations
  ARRAY(
    SELECT AS STRUCT operation, cost
    FROM daily_costs d
    WHERE d.date = t.date
    ORDER BY cost DESC
    LIMIT 5
  ) AS top_cost_operations,
  
  -- Optimization recommendations
  CASE
    WHEN daily_cost > 1000 THEN 'Consider batch size optimization'
    WHEN projected_monthly_cost > 20000 THEN 'Review high-cost operations'
    ELSE 'Costs within normal range'
  END AS optimization_recommendation
  
FROM cost_trends t
ORDER BY date DESC;

-- ============================================
-- 6. WORKFLOW MONITORING
-- ============================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.workflow_monitoring` AS
WITH workflow_executions AS (
  SELECT
    workflow_id,
    COUNT(DISTINCT timestamp) AS execution_count,
    COUNT(CASE WHEN status = 'SUCCESS' THEN 1 END) AS successful_steps,
    COUNT(CASE WHEN status = 'ERROR' THEN 1 END) AS failed_steps,
    MAX(timestamp) AS last_execution,
    MIN(timestamp) AS first_execution
  FROM `${PROJECT_ID}.${DATASET_ID}.template_workflows` w
  JOIN `${PROJECT_ID}.${DATASET_ID}.processing_log` l
    ON w.template_id = l.operation
  WHERE l.timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  GROUP BY workflow_id
)
SELECT
  *,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), last_execution, HOUR) AS hours_since_last_run,
  successful_steps / NULLIF(successful_steps + failed_steps, 0) AS success_rate,
  
  -- Workflow health
  CASE
    WHEN failed_steps > 0 THEN 'CRITICAL: Workflow failures'
    WHEN hours_since_last_run > 24 THEN 'WARNING: No recent execution'
    ELSE 'Healthy'
  END AS workflow_status,
  
  -- SLA compliance (assuming daily workflows)
  CASE
    WHEN hours_since_last_run > 24 THEN 'SLA BREACH'
    WHEN hours_since_last_run > 20 THEN 'AT RISK'
    ELSE 'COMPLIANT'
  END AS sla_status
FROM workflow_executions
ORDER BY workflow_status DESC, last_execution DESC;

-- ============================================
-- 7. ALERTING PROCEDURE
-- ============================================

CREATE OR REPLACE PROCEDURE `${PROJECT_ID}.${DATASET_ID}.check_alerts`()
BEGIN
  DECLARE alert_count INT64;
  DECLARE critical_alerts ARRAY<STRING>;
  
  -- Check for critical alerts
  SET critical_alerts = (
    SELECT ARRAY_AGG(CONCAT(alert_level, ': ', operation))
    FROM `${PROJECT_ID}.${DATASET_ID}.error_monitoring`
    WHERE alert_level LIKE 'CRITICAL%'
      AND date = CURRENT_DATE()
  );
  
  SET alert_count = ARRAY_LENGTH(critical_alerts);
  
  IF alert_count > 0 THEN
    -- Log critical alerts
    INSERT INTO `${PROJECT_ID}.${DATASET_ID}.processing_log`
    VALUES(
      CURRENT_TIMESTAMP(),
      'ALERT_CHECK',
      'system',
      0,
      0,
      'CRITICAL_ALERT',
      CONCAT('Found ', CAST(alert_count AS STRING), ' critical alerts: ', 
             ARRAY_TO_STRING(critical_alerts, ', '))
    );
  END IF;
  
  -- Check data quality
  INSERT INTO `${PROJECT_ID}.${DATASET_ID}.processing_log`
  SELECT
    check_time,
    'DATA_QUALITY_CHECK',
    'products',
    total_products,
    0,
    CASE WHEN ARRAY_LENGTH(active_alerts) > 0 THEN 'ALERT' ELSE 'OK' END,
    ARRAY_TO_STRING(
      ARRAY(SELECT CONCAT(severity, ': ', message) FROM UNNEST(active_alerts)),
      '; '
    )
  FROM `${PROJECT_ID}.${DATASET_ID}.data_quality_alerts`;
  
END;

-- ============================================
-- 8. EXECUTIVE DASHBOARD
-- ============================================

CREATE OR REPLACE VIEW `${PROJECT_ID}.${DATASET_ID}.executive_dashboard` AS
WITH summary_metrics AS (
  SELECT
    -- Volume metrics
    (SELECT COUNT(*) FROM `${PROJECT_ID}.${DATASET_ID}.products`) AS total_products,
    (SELECT COUNT(*) FROM `${PROJECT_ID}.${DATASET_ID}.products` WHERE enhanced_description IS NOT NULL) AS enriched_products,
    
    -- Performance metrics  
    (SELECT AVG(processing_time_seconds) FROM `${PROJECT_ID}.${DATASET_ID}.performance_metrics` 
     WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)) AS avg_processing_time,
    
    -- Quality metrics
    (SELECT COUNT(*) FROM `${PROJECT_ID}.${DATASET_ID}.products` WHERE is_valid = TRUE) AS validated_products,
    
    -- Cost metrics
    (SELECT SUM(estimated_cost) FROM `${PROJECT_ID}.${DATASET_ID}.performance_metrics`
     WHERE DATE(timestamp) = CURRENT_DATE()) AS todays_cost,
    
    -- Error metrics
    (SELECT COUNT(*) FROM `${PROJECT_ID}.${DATASET_ID}.processing_log`
     WHERE status = 'ERROR' AND DATE(timestamp) = CURRENT_DATE()) AS todays_errors
)
SELECT
  *,
  -- Calculate KPIs
  ROUND(enriched_products / total_products * 100, 1) AS enrichment_coverage_pct,
  ROUND(validated_products / total_products * 100, 1) AS validation_coverage_pct,
  
  -- Health score
  CASE
    WHEN todays_errors > 100 THEN 'CRITICAL'
    WHEN todays_cost > 1000 THEN 'WARNING'
    WHEN enrichment_coverage_pct < 50 THEN 'NEEDS ATTENTION'
    ELSE 'HEALTHY'
  END AS system_health,
  
  -- ROI metrics
  enriched_products * 3 / 60 * 50 AS labor_hours_saved_value, -- 3 min per product at $50/hr
  validated_products * 0.001 * 50 AS quality_issues_prevented_value -- 0.1% error rate * $50 per issue
  
FROM summary_metrics;

-- ============================================
-- 9. SCHEDULED MONITORING JOB
-- ============================================

CREATE OR REPLACE PROCEDURE `${PROJECT_ID}.${DATASET_ID}.run_monitoring_checks`()
BEGIN
  -- Run all monitoring checks
  CALL `${PROJECT_ID}.${DATASET_ID}.check_alerts`();
  
  -- Log monitoring run
  INSERT INTO `${PROJECT_ID}.${DATASET_ID}.processing_log`
  VALUES(
    CURRENT_TIMESTAMP(),
    'MONITORING_RUN',
    'system',
    0,
    0,
    'SUCCESS',
    'Daily monitoring checks completed'
  );
  
  -- Clean up old logs (keep 90 days)
  DELETE FROM `${PROJECT_ID}.${DATASET_ID}.processing_log`
  WHERE timestamp < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY);
  
  DELETE FROM `${PROJECT_ID}.${DATASET_ID}.performance_metrics`
  WHERE timestamp < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY);
END;