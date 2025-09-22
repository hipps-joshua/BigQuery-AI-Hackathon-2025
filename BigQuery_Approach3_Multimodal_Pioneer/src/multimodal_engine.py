"""
BigQuery Multimodal Engine for E-commerce Visual Intelligence
Combines structured data with images for quality control and compliance
"""

import asyncio
import concurrent.futures
from typing import Dict, List, Optional, Any, Tuple, Union
from dataclasses import dataclass
from datetime import datetime
import pandas as pd
from google.cloud import bigquery
from google.cloud import storage
from google.cloud.exceptions import GoogleCloudError
import logging
import json
import re

logger = logging.getLogger(__name__)


@dataclass
class ImageAnalysisResult:
    """Result of image analysis operation"""
    sku: str
    image_uri: str
    detected_attributes: Dict[str, Any]
    compliance_status: Dict[str, bool]
    confidence_scores: Dict[str, float]
    processing_time_ms: float
    error: Optional[str] = None


@dataclass
class QualityControlResult:
    """Result of quality control check"""
    total_products: int
    passed: int
    failed: int
    issues_found: List[Dict[str, Any]]
    compliance_rate: float
    processing_time_ms: float


@dataclass
class VisualSearchResult:
    """Result of visual search operation"""
    query_image: str
    similar_products: List[Dict[str, Any]]
    similarity_scores: List[float]
    search_time_ms: float


class BigQueryMultimodalEngine:
    """
    Multimodal engine that combines structured and unstructured data
    for advanced e-commerce analytics and quality control
    """
    
    def __init__(self, project_id: str, dataset_id: str, bucket_name: str):
        """Initialize the multimodal engine"""
        self.project_id = project_id
        self.dataset_id = dataset_id
        self.bucket_name = bucket_name
        self.client = bigquery.Client(project=project_id)
        self.storage_client = storage.Client(project=project_id)
        self.dataset_ref = f"{project_id}.{dataset_id}"
        
        # Compliance rules configuration
        self.compliance_rules = {
            'has_required_labels': {
                'categories': ['food', 'cosmetics', 'electronics'],
                'required_elements': ['ingredients', 'warnings', 'certifications']
            },
            'brand_guidelines': {
                'logo_position': ['top-left', 'top-right'],
                'color_consistency': 0.85  # 85% similarity required
            },
            'image_quality': {
                'min_resolution': (800, 800),
                'max_blur_score': 0.3,
                'lighting_range': (0.3, 0.8)
            }
        }
        
    def create_object_table(self, table_name: str, image_uris: List[str]) -> str:
        """
        Create an Object Table for unstructured data
        """
        object_table_name = f"{table_name}_images"
        
        # Create external table pointing to images
        query = f"""
        CREATE OR REPLACE EXTERNAL TABLE `{self.dataset_ref}.{object_table_name}`
        OPTIONS (
            format = 'OBJECT_TABLE',
            uris = {image_uris}
        )
        """
        
        try:
            query_job = self.client.query(query)
            query_job.result()
            logger.info(f"Created object table: {object_table_name}")
            return object_table_name
        except GoogleCloudError as e:
            logger.error(f"Failed to create object table: {str(e)}")
            raise
    
    def analyze_product_images(self, product_table: str, image_table: str, limit: Optional[int] = None) -> pd.DataFrame:
        """
        Analyze product images using multimodal AI
        """
        start_time = datetime.now()
        limit_clause = f"LIMIT {limit}" if limit else ""
        
        query = f"""
        WITH product_image_pairs AS (
            SELECT 
                p.sku,
                p.product_name,
                p.listed_color,
                p.listed_size,
                p.category,
                p.brand_name,
                i.uri as image_uri,
                i.content as image_content
            FROM `{self.dataset_ref}.{product_table}` p
            JOIN `{self.dataset_ref}.{image_table}` i
                ON p.image_filename = i.name
            WHERE p.image_filename IS NOT NULL
            {limit_clause}
        ),
        image_analysis AS (
            SELECT 
                sku,
                product_name,
                listed_color,
                category,
                brand_name,
                image_uri,
                AI.GENERATE_TEXT(
                    MODEL `{self.dataset_ref}.gemini_vision_model`,
                    PROMPT => CONCAT(
                        'Analyze this product image and extract the following in JSON format: ',
                        '1. detected_colors (list of dominant colors), ',
                        '2. detected_text (any visible text/labels), ',
                        '3. product_condition (new/used/damaged), ',
                        '4. brand_visibility (is brand logo/name visible?), ',
                        '5. image_quality_score (0-1), ',
                        '6. detected_size_category (small/medium/large/xl if applicable), ',
                        '7. compliance_labels (list any certification marks, warnings, etc.)'
                    ),
                    STRUCT(
                        image_content AS image,
                        0.3 AS temperature,
                        'application/json' AS mime_type
                    )
                ) AS analysis_result
            FROM product_image_pairs
        )
        SELECT 
            sku,
            product_name,
            listed_color,
            category,
            brand_name,
            image_uri,
            JSON_EXTRACT_SCALAR(analysis_result.text, '$.detected_colors[0]') as primary_color,
            JSON_EXTRACT_SCALAR(analysis_result.text, '$.brand_visibility') as brand_visible,
            JSON_EXTRACT_SCALAR(analysis_result.text, '$.image_quality_score') as quality_score,
            JSON_EXTRACT_SCALAR(analysis_result.text, '$.product_condition') as condition,
            JSON_EXTRACT_ARRAY(analysis_result.text, '$.compliance_labels') as compliance_labels,
            analysis_result.text as full_analysis
        FROM image_analysis
        """
        
        try:
            results_df = self.client.query(query).to_dataframe()
            execution_time = (datetime.now() - start_time).total_seconds() * 1000
            
            logger.info(f"Analyzed {len(results_df)} images in {execution_time:.2f}ms")
            return results_df
            
        except GoogleCloudError as e:
            logger.error(f"Image analysis failed: {str(e)}")
            raise
    
    def validate_product_specifications(self, product_table: str, image_analysis_table: str) -> QualityControlResult:
        """
        Validate that product images match listed specifications
        """
        start_time = datetime.now()
        
        query = f"""
        WITH validation_results AS (
            SELECT 
                p.sku,
                p.product_name,
                p.listed_color,
                p.listed_size,
                p.category,
                a.primary_color as detected_color,
                a.brand_visible,
                a.quality_score,
                a.compliance_labels,
                
                -- Color validation
                CASE 
                    WHEN LOWER(p.listed_color) = LOWER(a.primary_color) THEN TRUE
                    WHEN p.listed_color IS NULL THEN NULL
                    ELSE FALSE
                END as color_matches,
                
                -- Brand validation
                CASE 
                    WHEN p.brand_name IS NOT NULL AND a.brand_visible = 'true' THEN TRUE
                    WHEN p.brand_name IS NULL THEN NULL
                    ELSE FALSE
                END as brand_validated,
                
                -- Quality validation
                CASE 
                    WHEN CAST(a.quality_score AS FLOAT64) >= 0.7 THEN TRUE
                    ELSE FALSE
                END as quality_passed,
                
                -- Compliance validation for category
                CASE 
                    WHEN p.category IN ('food', 'cosmetics', 'electronics') 
                        AND ARRAY_LENGTH(a.compliance_labels) > 0 THEN TRUE
                    WHEN p.category NOT IN ('food', 'cosmetics', 'electronics') THEN TRUE
                    ELSE FALSE
                END as compliance_passed
                
            FROM `{self.dataset_ref}.{product_table}` p
            LEFT JOIN `{self.dataset_ref}.{image_analysis_table}` a
                ON p.sku = a.sku
        ),
        summary AS (
            SELECT 
                COUNT(*) as total_products,
                COUNTIF(color_matches = TRUE OR color_matches IS NULL) as color_pass,
                COUNTIF(brand_validated = TRUE OR brand_validated IS NULL) as brand_pass,
                COUNTIF(quality_passed = TRUE) as quality_pass,
                COUNTIF(compliance_passed = TRUE) as compliance_pass,
                COUNTIF(
                    (color_matches = TRUE OR color_matches IS NULL) 
                    AND (brand_validated = TRUE OR brand_validated IS NULL)
                    AND quality_passed = TRUE 
                    AND compliance_passed = TRUE
                ) as all_pass
            FROM validation_results
        ),
        issues AS (
            SELECT 
                sku,
                product_name,
                ARRAY_AGG(
                    CASE 
                        WHEN color_matches = FALSE THEN 
                            STRUCT('color_mismatch' as issue_type, 
                                   CONCAT('Listed: ', listed_color, ', Detected: ', detected_color) as details)
                        WHEN brand_validated = FALSE THEN 
                            STRUCT('brand_not_visible' as issue_type, 
                                   'Brand logo/name not detected in image' as details)
                        WHEN quality_passed = FALSE THEN 
                            STRUCT('low_quality_image' as issue_type, 
                                   CONCAT('Quality score: ', quality_score) as details)
                        WHEN compliance_passed = FALSE THEN 
                            STRUCT('missing_compliance_labels' as issue_type, 
                                   CONCAT('Required for category: ', category) as details)
                    END IGNORE NULLS
                ) as issues
            FROM validation_results
            WHERE color_matches = FALSE 
                OR brand_validated = FALSE 
                OR quality_passed = FALSE 
                OR compliance_passed = FALSE
            GROUP BY sku, product_name
        )
        SELECT 
            s.*,
            ARRAY_AGG(
                STRUCT(i.sku, i.product_name, i.issues)
            ) as failed_products
        FROM summary s
        CROSS JOIN issues i
        GROUP BY s.total_products, s.color_pass, s.brand_pass, 
                 s.quality_pass, s.compliance_pass, s.all_pass
        """
        
        try:
            results = self.client.query(query).to_dataframe()
            execution_time = (datetime.now() - start_time).total_seconds() * 1000
            
            if len(results) > 0:
                row = results.iloc[0]
                
                # Parse issues
                issues_list = []
                if 'failed_products' in row and row['failed_products']:
                    for product in row['failed_products']:
                        for issue in product.get('issues', []):
                            issues_list.append({
                                'sku': product['sku'],
                                'product_name': product['product_name'],
                                'issue_type': issue['issue_type'],
                                'details': issue['details']
                            })
                
                return QualityControlResult(
                    total_products=int(row['total_products']),
                    passed=int(row['all_pass']),
                    failed=int(row['total_products'] - row['all_pass']),
                    issues_found=issues_list,
                    compliance_rate=float(row['all_pass'] / row['total_products']) if row['total_products'] > 0 else 0.0,
                    processing_time_ms=execution_time
                )
            else:
                return QualityControlResult(
                    total_products=0,
                    passed=0,
                    failed=0,
                    issues_found=[],
                    compliance_rate=0.0,
                    processing_time_ms=execution_time
                )
                
        except GoogleCloudError as e:
            logger.error(f"Validation failed: {str(e)}")
            raise
    
    def visual_similarity_search(self, query_image_uri: str, product_image_table: str, top_k: int = 10) -> VisualSearchResult:
        """
        Find visually similar products using image embeddings
        """
        start_time = datetime.now()
        
        query = f"""
        WITH query_embedding AS (
            SELECT AI.GENERATE_EMBEDDING(
                MODEL `{self.dataset_ref}.multimodal_embedding_model`,
                CONTENT => (SELECT content FROM `{self.dataset_ref}.{product_image_table}` WHERE uri = '{query_image_uri}'),
                STRUCT('IMAGE' as content_type)
            ) AS embedding
        ),
        product_embeddings AS (
            SELECT 
                p.sku,
                p.product_name,
                p.brand_name,
                p.price,
                p.category,
                i.uri as image_uri,
                AI.GENERATE_EMBEDDING(
                    MODEL `{self.dataset_ref}.multimodal_embedding_model`,
                    CONTENT => i.content,
                    STRUCT('IMAGE' as content_type)
                ) AS embedding
            FROM `{self.dataset_ref}.products` p
            JOIN `{self.dataset_ref}.{product_image_table}` i
                ON p.image_filename = i.name
            WHERE i.uri != '{query_image_uri}'
        )
        SELECT 
            pe.sku,
            pe.product_name,
            pe.brand_name,
            pe.price,
            pe.category,
            pe.image_uri,
            ML.DISTANCE(qe.embedding, pe.embedding, 'COSINE') as distance,
            1 - ML.DISTANCE(qe.embedding, pe.embedding, 'COSINE') as similarity_score
        FROM query_embedding qe
        CROSS JOIN product_embeddings pe
        ORDER BY distance ASC
        LIMIT {top_k}
        """
        
        try:
            results = self.client.query(query).to_dataframe()
            execution_time = (datetime.now() - start_time).total_seconds() * 1000
            
            similar_products = []
            similarity_scores = []
            
            for _, row in results.iterrows():
                similar_products.append({
                    'sku': row['sku'],
                    'product_name': row['product_name'],
                    'brand_name': row['brand_name'],
                    'price': float(row['price']),
                    'category': row['category'],
                    'image_uri': row['image_uri']
                })
                similarity_scores.append(float(row['similarity_score']))
            
            return VisualSearchResult(
                query_image=query_image_uri,
                similar_products=similar_products,
                similarity_scores=similarity_scores,
                search_time_ms=execution_time
            )
            
        except GoogleCloudError as e:
            logger.error(f"Visual search failed: {str(e)}")
            raise
    
    def detect_counterfeit_products(self, product_table: str, image_analysis_table: str) -> pd.DataFrame:
        """
        Detect potential counterfeit products using visual and text analysis
        """
        query = f"""
        WITH authenticity_checks AS (
            SELECT 
                p.sku,
                p.product_name,
                p.brand_name,
                p.price,
                p.seller_name,
                a.brand_visible,
                a.quality_score,
                a.full_analysis,
                
                -- Price anomaly detection
                p.price < (
                    SELECT APPROX_QUANTILES(price, 100)[OFFSET(10)]  -- 10th percentile
                    FROM `{self.dataset_ref}.{product_table}` p2
                    WHERE p2.brand_name = p.brand_name
                        AND p2.category = p.category
                ) as suspiciously_cheap,
                
                -- Brand verification
                JSON_EXTRACT_SCALAR(a.full_analysis, '$.detected_text') as detected_text,
                
                -- Quality indicators
                CAST(a.quality_score AS FLOAT64) < 0.5 as low_quality_image,
                
                -- Seller reputation (simplified)
                p.seller_name NOT IN (
                    SELECT DISTINCT authorized_seller
                    FROM `{self.dataset_ref}.authorized_sellers`
                    WHERE brand = p.brand_name
                ) as unauthorized_seller
                
            FROM `{self.dataset_ref}.{product_table}` p
            LEFT JOIN `{self.dataset_ref}.{image_analysis_table}` a
                ON p.sku = a.sku
            WHERE p.brand_name IS NOT NULL
        )
        SELECT 
            sku,
            product_name,
            brand_name,
            price,
            seller_name,
            CASE 
                WHEN suspiciously_cheap AND low_quality_image AND unauthorized_seller THEN 'HIGH'
                WHEN (suspiciously_cheap AND low_quality_image) 
                    OR (suspiciously_cheap AND unauthorized_seller)
                    OR (low_quality_image AND unauthorized_seller) THEN 'MEDIUM'
                WHEN suspiciously_cheap OR low_quality_image OR unauthorized_seller THEN 'LOW'
                ELSE 'NONE'
            END as counterfeit_risk,
            ARRAY_AGG(
                CASE 
                    WHEN suspiciously_cheap THEN 'Price significantly below market'
                    WHEN low_quality_image THEN 'Poor image quality'
                    WHEN unauthorized_seller THEN 'Unauthorized seller'
                    WHEN brand_visible = 'false' THEN 'Brand not visible in image'
                END IGNORE NULLS
            ) as risk_factors
        FROM authenticity_checks
        GROUP BY sku, product_name, brand_name, price, seller_name,
                 suspiciously_cheap, low_quality_image, unauthorized_seller, brand_visible
        HAVING counterfeit_risk != 'NONE'
        ORDER BY 
            CASE counterfeit_risk 
                WHEN 'HIGH' THEN 1 
                WHEN 'MEDIUM' THEN 2 
                WHEN 'LOW' THEN 3 
            END
        """
        
        return self.client.query(query).to_dataframe()
    
    def generate_visual_insights_report(self, product_table: str, image_analysis_table: str) -> Dict[str, Any]:
        """
        Generate comprehensive visual insights report
        """
        insights = {}
        
        # Overall image quality metrics
        quality_query = f"""
        SELECT 
            AVG(CAST(quality_score AS FLOAT64)) as avg_quality_score,
            COUNTIF(CAST(quality_score AS FLOAT64) >= 0.8) / COUNT(*) * 100 as high_quality_pct,
            COUNTIF(CAST(quality_score AS FLOAT64) < 0.5) / COUNT(*) * 100 as low_quality_pct
        FROM `{self.dataset_ref}.{image_analysis_table}`
        """
        insights['image_quality'] = self.client.query(quality_query).to_dataframe().to_dict('records')[0]
        
        # Color accuracy
        color_query = f"""
        SELECT 
            COUNTIF(LOWER(p.listed_color) = LOWER(a.primary_color)) / COUNT(*) * 100 as color_accuracy_pct,
            COUNT(DISTINCT a.primary_color) as unique_colors_detected
        FROM `{self.dataset_ref}.{product_table}` p
        JOIN `{self.dataset_ref}.{image_analysis_table}` a
            ON p.sku = a.sku
        WHERE p.listed_color IS NOT NULL
        """
        insights['color_accuracy'] = self.client.query(color_query).to_dataframe().to_dict('records')[0]
        
        # Brand visibility
        brand_query = f"""
        SELECT 
            p.brand_name,
            COUNT(*) as total_products,
            COUNTIF(a.brand_visible = 'true') as brand_visible_count,
            COUNTIF(a.brand_visible = 'true') / COUNT(*) * 100 as visibility_rate
        FROM `{self.dataset_ref}.{product_table}` p
        JOIN `{self.dataset_ref}.{image_analysis_table}` a
            ON p.sku = a.sku
        WHERE p.brand_name IS NOT NULL
        GROUP BY p.brand_name
        ORDER BY total_products DESC
        LIMIT 10
        """
        insights['brand_visibility'] = self.client.query(brand_query).to_dataframe().to_dict('records')
        
        # Compliance by category
        compliance_query = f"""
        SELECT 
            p.category,
            COUNT(*) as total_products,
            COUNTIF(ARRAY_LENGTH(a.compliance_labels) > 0) as has_labels,
            COUNTIF(ARRAY_LENGTH(a.compliance_labels) > 0) / COUNT(*) * 100 as compliance_rate
        FROM `{self.dataset_ref}.{product_table}` p
        JOIN `{self.dataset_ref}.{image_analysis_table}` a
            ON p.sku = a.sku
        WHERE p.category IN ('food', 'cosmetics', 'electronics')
        GROUP BY p.category
        """
        insights['compliance_by_category'] = self.client.query(compliance_query).to_dataframe().to_dict('records')
        
        return insights
    
    def create_training_dataset_for_visual_model(self, product_table: str, image_table: str) -> str:
        """
        Create a training dataset for custom visual models
        """
        training_table = f"{product_table}_visual_training"
        
        query = f"""
        CREATE OR REPLACE TABLE `{self.dataset_ref}.{training_table}` AS
        SELECT 
            p.sku,
            p.category,
            p.brand_name,
            p.listed_color,
            p.price_range,
            i.uri as image_uri,
            -- Create labels for supervised learning
            STRUCT(
                p.category as product_category,
                p.brand_name as brand,
                p.listed_color as color,
                CASE 
                    WHEN p.price < 50 THEN 'budget'
                    WHEN p.price < 200 THEN 'mid-range'
                    ELSE 'premium'
                END as price_tier,
                p.is_on_sale,
                p.rating
            ) as labels,
            -- Include metadata for stratification
            CURRENT_TIMESTAMP() as created_at,
            FARM_FINGERPRINT(CONCAT(p.sku, CAST(CURRENT_TIMESTAMP() AS STRING))) as split_hash
        FROM `{self.dataset_ref}.{product_table}` p
        JOIN `{self.dataset_ref}.{image_table}` i
            ON p.image_filename = i.name
        WHERE i.content IS NOT NULL
            AND p.category IS NOT NULL
            AND p.brand_name IS NOT NULL
        """
        
        self.client.query(query).result()
        
        # Add train/validation/test splits
        split_query = f"""
        ALTER TABLE `{self.dataset_ref}.{training_table}`
        ADD COLUMN IF NOT EXISTS dataset_split STRING;
        
        UPDATE `{self.dataset_ref}.{training_table}`
        SET dataset_split = CASE 
            WHEN MOD(ABS(split_hash), 10) < 7 THEN 'TRAIN'
            WHEN MOD(ABS(split_hash), 10) < 9 THEN 'VALIDATION'
            ELSE 'TEST'
        END
        WHERE dataset_split IS NULL
        """
        
        self.client.query(split_query).result()
        
        logger.info(f"Created training dataset: {training_table}")
        return training_table


# Helper functions
def create_image_uri_list(bucket_name: str, prefix: str = "product_images/") -> List[str]:
    """Helper to create list of image URIs from GCS bucket"""
    return [f"gs://{bucket_name}/{prefix}*.jpg", f"gs://{bucket_name}/{prefix}*.png"]


def validate_image_format(image_path: str) -> bool:
    """Validate image format is supported"""
    supported_formats = ['.jpg', '.jpeg', '.png', '.webp', '.bmp']
    return any(image_path.lower().endswith(fmt) for fmt in supported_formats)


# Singleton instance getter
_engine_instance = None

def get_multimodal_engine(project_id: str, dataset_id: str, bucket_name: str) -> BigQueryMultimodalEngine:
    """Get or create the multimodal engine instance"""
    global _engine_instance
    if _engine_instance is None:
        _engine_instance = BigQueryMultimodalEngine(project_id, dataset_id, bucket_name)
    return _engine_instance