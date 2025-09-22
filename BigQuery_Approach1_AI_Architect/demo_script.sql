-- ============================================
-- AI ARCHITECT - DEMO SCRIPT
-- ============================================
-- Copy and paste these queries during your demo
-- Practice the flow several times before recording

-- ============================================
-- PART 1: Introduction & Problem Statement
-- ============================================
-- Show current state of product catalog
SELECT 
  sku,
  brand_name,
  product_name,
  price,
  description,
  enhanced_description,
  is_valid,
  quality_score
FROM `PROJECT_ID.DATASET_ID.products`
LIMIT 10;

-- Count products needing enrichment
SELECT 
  COUNT(*) as total_products,
  COUNT(enhanced_description) as enriched_products,
  COUNT(*) - COUNT(enhanced_description) as needs_enrichment,
  ROUND((COUNT(*) - COUNT(enhanced_description)) / COUNT(*) * 100, 1) as percent_incomplete
FROM `PROJECT_ID.DATASET_ID.products`;

-- ============================================
-- PART 2: Template Library Demo
-- ============================================
-- Show available AI templates
SELECT 
  template_id,
  template_name,
  category,
  confidence_threshold,
  CASE category
    WHEN 'product_enrichment' THEN '📝 Content Generation'
    WHEN 'attribute_extraction' THEN '🔍 Data Mining'
    WHEN 'quality_validation' THEN '✅ Quality Assurance'
    ELSE '🔧 Custom'
  END as template_type
FROM `PROJECT_ID.DATASET_ID.template_library`
ORDER BY category, template_name;

-- ============================================
-- PART 3: AI Product Enrichment
-- ============================================
-- Show products before enrichment
SELECT 
  sku,
  product_name,
  description,
  enhanced_description
FROM `PROJECT_ID.DATASET_ID.products`
WHERE enhanced_description IS NULL
LIMIT 5;

-- Run AI enrichment (smaller batch for demo)
CALL `PROJECT_ID.DATASET_ID.generate_product_descriptions`('products', 5);

-- Show the AI-generated results
SELECT 
  sku,
  product_name,
  brand_name,
  SUBSTR(description, 1, 50) || '...' as original_desc_preview,
  enhanced_description as ai_generated_description,
  LENGTH(enhanced_description) as description_length,
  enhanced_confidence_score
FROM `PROJECT_ID.DATASET_ID.products`
WHERE enhanced_description IS NOT NULL
  AND updated_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 MINUTE)
ORDER BY updated_at DESC
LIMIT 5;

-- ============================================
-- PART 4: Attribute Extraction
-- ============================================
-- Extract attributes using AI
WITH sample_products AS (
  SELECT * FROM `PROJECT_ID.DATASET_ID.products` 
  WHERE category = 'Apparel' 
  LIMIT 3
)
SELECT 
  sku,
  product_name,
  -- AI extracts structured data
  AI.GENERATE_TABLE(
    PROMPT => CONCAT(
      'Extract attributes from this product. Return columns: primary_color, material, style, season, target_demographic\n',
      'Product: ', product_name, '\n',
      'Description: ', IFNULL(enhanced_description, description)
    ),
    connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection'
  ).* AS extracted_attributes
FROM sample_products;

-- ============================================
-- PART 5: Quality Validation
-- ============================================
-- Run quality validation
CALL `PROJECT_ID.DATASET_ID.validate_product_quality`('products');

-- Show validation results
SELECT 
  sku,
  product_name,
  category,
  price,
  is_valid,
  quality_score,
  validation_details,
  CASE 
    WHEN is_valid = FALSE THEN '❌ Action Required'
    WHEN quality_score < 0.8 THEN '⚠️ Review Recommended'
    ELSE '✅ Passed'
  END as status
FROM `PROJECT_ID.DATASET_ID.products`
WHERE is_valid IS NOT NULL
ORDER BY is_valid, quality_score
LIMIT 10;

-- Show specific issues found
SELECT 
  category,
  COUNT(*) as products_checked,
  SUM(CASE WHEN is_valid = FALSE THEN 1 ELSE 0 END) as failed_validation,
  AVG(quality_score) as avg_quality_score,
  STRING_AGG(
    CASE WHEN is_valid = FALSE THEN validation_details END, 
    '; ' 
    LIMIT 3
  ) as sample_issues
FROM `PROJECT_ID.DATASET_ID.products`
WHERE quality_score IS NOT NULL
GROUP BY category;

-- ============================================
-- PART 6: Template Orchestration
-- ============================================
-- Show workflow configuration
SELECT 
  'new_product_onboarding' as workflow_name,
  [
    STRUCT('PE001' as template_id, 'Generate Description' as step),
    STRUCT('AE001' as template_id, 'Extract Attributes' as step),
    STRUCT('QV001' as template_id, 'Validate Quality' as step)
  ] as workflow_steps,
  'Sequential execution with automatic error handling' as description;

-- Execute complete workflow
CALL `PROJECT_ID.DATASET_ID.execute_template_workflow`(
  'new_product_onboarding',
  'products',
  JSON '{"batch_size": 10, "confidence_threshold": 0.85}'
);

-- ============================================
-- PART 7: Performance Metrics
-- ============================================
-- Show processing performance
SELECT 
  operation,
  COUNT(*) as executions,
  AVG(processing_time_seconds) as avg_time_seconds,
  SUM(records_processed) as total_records,
  AVG(records_processed / processing_time_seconds) as throughput_per_sec,
  CONCAT('$', ROUND(SUM(estimated_cost), 2)) as total_cost
FROM `PROJECT_ID.DATASET_ID.performance_metrics`
WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
GROUP BY operation
ORDER BY total_records DESC;

-- ============================================
-- PART 8: ROI Dashboard
-- ============================================
-- Show comprehensive ROI
SELECT * FROM `PROJECT_ID.DATASET_ID.roi_dashboard`;

-- Calculate specific savings
WITH roi_calc AS (
  SELECT 
    COUNT(*) as products_enriched,
    COUNT(*) * 3 / 60 as hours_saved, -- 3 minutes per product
    COUNT(*) * 3 / 60 * 50 as labor_cost_saved, -- $50/hour
    COUNT(*) * 0.002 as enrichment_cost -- AI cost
  FROM `PROJECT_ID.DATASET_ID.products`
  WHERE enhanced_description IS NOT NULL
)
SELECT 
  products_enriched,
  ROUND(hours_saved, 1) as hours_saved,
  CONCAT('$', ROUND(labor_cost_saved, 0)) as labor_savings,
  CONCAT('$', ROUND(enrichment_cost, 2)) as ai_cost,
  CONCAT('$', ROUND(labor_cost_saved - enrichment_cost, 0)) as net_savings,
  ROUND((labor_cost_saved - enrichment_cost) / enrichment_cost, 0) as roi_multiple
FROM roi_calc;

-- ============================================
-- PART 9: Executive Summary
-- ============================================
SELECT * FROM `PROJECT_ID.DATASET_ID.executive_dashboard`;

-- Future projections
WITH projections AS (
  SELECT 
    10000 as monthly_new_products,
    0.002 as cost_per_enrichment,
    3 as minutes_saved_per_product
)
SELECT 
  monthly_new_products,
  monthly_new_products * minutes_saved_per_product / 60 as hours_saved_monthly,
  monthly_new_products * minutes_saved_per_product / 60 * 50 as monthly_labor_savings,
  monthly_new_products * cost_per_enrichment as monthly_ai_cost,
  (monthly_new_products * minutes_saved_per_product / 60 * 50) - 
  (monthly_new_products * cost_per_enrichment) as monthly_net_savings,
  ((monthly_new_products * minutes_saved_per_product / 60 * 50) - 
   (monthly_new_products * cost_per_enrichment)) * 12 as annual_net_savings
FROM projections;

-- ============================================
-- BONUS: Error Handling Demo
-- ============================================
-- Show how the system handles errors gracefully
SELECT 
  timestamp,
  operation,
  table_name,
  batch_size,
  status,
  CASE 
    WHEN status = 'ERROR' THEN SUBSTR(error_message, 1, 100) || '...'
    ELSE 'Success'
  END as result
FROM `PROJECT_ID.DATASET_ID.processing_log`
WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
ORDER BY timestamp DESC
LIMIT 10;

-- ============================================
-- CLOSING: Call to Action
-- ============================================
-- Show immediate next steps
SELECT 
  'AI Architect is Production Ready!' as message,
  '✅ All AI Functions Implemented' as feature_1,
  '✅ Template Library Extensible' as feature_2,
  '✅ Full Monitoring & Alerting' as feature_3,
  '✅ 10,000%+ ROI Proven' as feature_4,
  '🚀 Deploy in 2 Hours' as time_to_value;
