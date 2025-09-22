-- Create a test product catalog
-- Replace PROJECT_ID and DATASET_ID with your values

CREATE OR REPLACE TABLE `PROJECT_ID.DATASET_ID.test_products` AS
SELECT * FROM (
  -- Electronics
  SELECT 'E001' as sku, 'iPhone 15 Pro' as name, 'Electronics' as category, 1199.00 as price, 'Latest iPhone with A17 Pro chip' as description, 4.8 as rating
  UNION ALL SELECT 'E002', 'MacBook Air M3', 'Electronics', 999.00, '15-inch laptop with M3 chip', 4.9
  UNION ALL SELECT 'E003', 'AirPods Pro 2', 'Electronics', 249.00, 'Noise cancelling earbuds', 4.7
  UNION ALL SELECT 'E004', 'iPad Pro 11', 'Electronics', 799.00, 'M2 powered tablet', 4.8
  UNION ALL SELECT 'E005', 'Apple Watch 9', 'Electronics', 399.00, 'Latest smartwatch', 4.6
  
  -- Sports
  UNION ALL SELECT 'S001', 'Nike Pegasus 40', 'Sports', 130.00, 'Daily running shoes', 4.5
  UNION ALL SELECT 'S002', 'Yoga Mat Pro', 'Sports', 79.99, 'Non-slip exercise mat', 4.6
  UNION ALL SELECT 'S003', 'Dumbbells 20lb', 'Sports', 89.99, 'Adjustable weights', 4.7
  UNION ALL SELECT 'S004', 'Running Belt', 'Sports', 29.99, 'Waterproof storage belt', 4.4
  UNION ALL SELECT 'S005', 'Garmin Watch', 'Sports', 299.99, 'GPS fitness tracker', 4.8
);
