"""
Visual Search Engine for E-commerce
Find products using image similarity and style matching
"""

import numpy as np
import pandas as pd
from typing import Dict, List, Optional, Tuple, Any
from dataclasses import dataclass
from datetime import datetime
import json
import logging

logger = logging.getLogger(__name__)


@dataclass
class StyleVector:
    """Represents visual style characteristics"""
    color_palette: List[str]
    pattern_type: str  # 'solid', 'striped', 'floral', 'geometric', 'abstract'
    texture: str  # 'smooth', 'rough', 'glossy', 'matte'
    style_category: str  # 'modern', 'classic', 'vintage', 'minimalist'
    formality: float  # 0-1 scale from casual to formal


@dataclass
class VisualSearchQuery:
    """Visual search query parameters"""
    image_uri: Optional[str] = None
    style_preferences: Optional[StyleVector] = None
    color_filter: Optional[List[str]] = None
    category_filter: Optional[List[str]] = None
    price_range: Optional[Tuple[float, float]] = None
    brand_filter: Optional[List[str]] = None
    include_similar_styles: bool = True


class VisualSearchEngine:
    """
    Advanced visual search for e-commerce products
    """
    
    def __init__(self, project_id: str, dataset_id: str):
        self.project_id = project_id
        self.dataset_id = dataset_id
        self.dataset_ref = f"{project_id}.{dataset_id}"
        
        # Style similarity weights
        self.style_weights = {
            'color': 0.35,
            'pattern': 0.20,
            'texture': 0.15,
            'category': 0.20,
            'formality': 0.10
        }
        
        # Color similarity mappings
        self.color_families = {
            'warm': ['red', 'orange', 'yellow', 'pink', 'coral'],
            'cool': ['blue', 'green', 'purple', 'teal', 'turquoise'],
            'neutral': ['black', 'white', 'gray', 'beige', 'brown'],
            'earth': ['brown', 'tan', 'olive', 'rust', 'khaki']
        }
        
    def build_visual_search_query(self, query: VisualSearchQuery) -> str:
        """
        Build BigQuery query for visual search
        """
        # Base query with image embeddings
        base_query = f"""
        WITH query_embedding AS (
            SELECT AI.GENERATE_EMBEDDING(
                MODEL `{self.dataset_ref}.multimodal_embedding_model`,
                CONTENT => (
                    SELECT content 
                    FROM `{self.dataset_ref}.product_images` 
                    WHERE uri = '{query.image_uri}'
                ),
                STRUCT('IMAGE' as content_type)
            ) AS embedding
        ),
        product_catalog AS (
            SELECT 
                p.*,
                i.uri as image_uri,
                a.primary_color,
                a.detected_style,
                a.quality_score,
                AI.GENERATE_EMBEDDING(
                    MODEL `{self.dataset_ref}.multimodal_embedding_model`,
                    CONTENT => i.content,
                    STRUCT('IMAGE' as content_type)
                ) AS embedding
            FROM `{self.dataset_ref}.products` p
            JOIN `{self.dataset_ref}.product_images` i
                ON p.image_filename = i.name
            LEFT JOIN `{self.dataset_ref}.image_analysis` a
                ON p.sku = a.sku
            WHERE 1=1
        """
        
        # Add filters
        filters = []
        
        if query.category_filter:
            categories = "','".join(query.category_filter)
            filters.append(f"p.category IN ('{categories}')")
        
        if query.brand_filter:
            brands = "','".join(query.brand_filter)
            filters.append(f"p.brand_name IN ('{brands}')")
        
        if query.price_range:
            filters.append(f"p.price BETWEEN {query.price_range[0]} AND {query.price_range[1]}")
        
        if query.color_filter:
            colors = "','".join(query.color_filter)
            filters.append(f"a.primary_color IN ('{colors}')")
        
        if filters:
            base_query = base_query.replace("WHERE 1=1", f"WHERE {' AND '.join(filters)}")
        
        # Complete query with similarity calculation
        full_query = f"""
        {base_query}
        )
        SELECT 
            pc.sku,
            pc.product_name,
            pc.brand_name,
            pc.price,
            pc.category,
            pc.image_uri,
            pc.primary_color,
            ML.DISTANCE(qe.embedding, pc.embedding, 'COSINE') as visual_distance,
            1 - ML.DISTANCE(qe.embedding, pc.embedding, 'COSINE') as similarity_score,
            RANK() OVER (ORDER BY ML.DISTANCE(qe.embedding, pc.embedding, 'COSINE') ASC) as similarity_rank
        FROM query_embedding qe
        CROSS JOIN product_catalog pc
        WHERE pc.image_uri != '{query.image_uri}'
        ORDER BY visual_distance ASC
        LIMIT 50
        """
        
        return full_query
    
    def find_style_matches(self, reference_sku: str, style_attributes: Dict[str, Any]) -> str:
        """
        Find products matching a specific style profile
        """
        query = f"""
        WITH reference_product AS (
            SELECT 
                p.*,
                a.primary_color,
                a.detected_pattern,
                a.detected_texture,
                a.style_category,
                a.formality_score
            FROM `{self.dataset_ref}.products` p
            JOIN `{self.dataset_ref}.image_analysis` a
                ON p.sku = a.sku
            WHERE p.sku = '{reference_sku}'
        ),
        style_scoring AS (
            SELECT 
                p.sku,
                p.product_name,
                p.brand_name,
                p.price,
                p.category,
                p.image_uri,
                a.primary_color,
                a.style_category,
                -- Color similarity
                CASE 
                    WHEN a.primary_color = r.primary_color THEN 1.0
                    WHEN a.primary_color IN (
                        SELECT color 
                        FROM UNNEST({self._get_similar_colors('r.primary_color')}) as color
                    ) THEN 0.8
                    ELSE 0.3
                END * {self.style_weights['color']} as color_score,
                
                -- Pattern similarity
                CASE 
                    WHEN a.detected_pattern = r.detected_pattern THEN 1.0
                    WHEN a.detected_pattern IS NULL OR r.detected_pattern IS NULL THEN 0.5
                    ELSE 0.2
                END * {self.style_weights['pattern']} as pattern_score,
                
                -- Style category match
                CASE 
                    WHEN a.style_category = r.style_category THEN 1.0
                    ELSE 0.3
                END * {self.style_weights['category']} as category_score,
                
                -- Formality similarity
                (1 - ABS(IFNULL(a.formality_score, 0.5) - IFNULL(r.formality_score, 0.5))) 
                    * {self.style_weights['formality']} as formality_score
                
            FROM `{self.dataset_ref}.products` p
            JOIN `{self.dataset_ref}.image_analysis` a
                ON p.sku = a.sku
            CROSS JOIN reference_product r
            WHERE p.sku != r.sku
        )
        SELECT 
            sku,
            product_name,
            brand_name,
            price,
            category,
            image_uri,
            primary_color,
            style_category,
            (color_score + pattern_score + category_score + formality_score) as style_match_score,
            STRUCT(
                color_score,
                pattern_score,
                category_score,
                formality_score
            ) as score_breakdown
        FROM style_scoring
        WHERE (color_score + pattern_score + category_score + formality_score) > 0.5
        ORDER BY style_match_score DESC
        LIMIT 20
        """
        
        return query
    
    def find_outfit_combinations(self, base_product_sku: str, outfit_type: str = 'casual') -> str:
        """
        Find complementary products for outfit building
        """
        # Define outfit rules
        outfit_rules = {
            'casual': {
                'tops': ['t-shirt', 'shirt', 'blouse', 'sweater'],
                'bottoms': ['jeans', 'pants', 'shorts', 'skirt'],
                'footwear': ['sneakers', 'loafers', 'sandals'],
                'accessories': ['belt', 'watch', 'bag']
            },
            'formal': {
                'tops': ['dress shirt', 'blouse', 'blazer'],
                'bottoms': ['dress pants', 'skirt', 'suit'],
                'footwear': ['dress shoes', 'heels', 'oxfords'],
                'accessories': ['tie', 'watch', 'belt', 'jewelry']
            },
            'athletic': {
                'tops': ['sports bra', 'tank top', 'athletic shirt'],
                'bottoms': ['leggings', 'shorts', 'track pants'],
                'footwear': ['running shoes', 'trainers'],
                'accessories': ['headband', 'water bottle', 'gym bag']
            }
        }
        
        query = f"""
        WITH base_item AS (
            SELECT 
                p.*,
                a.primary_color,
                a.style_category,
                a.formality_score,
                CASE 
                    WHEN p.subcategory IN {outfit_rules[outfit_type]['tops']} THEN 'top'
                    WHEN p.subcategory IN {outfit_rules[outfit_type]['bottoms']} THEN 'bottom'
                    WHEN p.subcategory IN {outfit_rules[outfit_type]['footwear']} THEN 'footwear'
                    WHEN p.subcategory IN {outfit_rules[outfit_type]['accessories']} THEN 'accessory'
                    ELSE 'other'
                END as item_type
            FROM `{self.dataset_ref}.products` p
            JOIN `{self.dataset_ref}.image_analysis` a
                ON p.sku = a.sku
            WHERE p.sku = '{base_product_sku}'
        ),
        complementary_items AS (
            SELECT 
                p.sku,
                p.product_name,
                p.brand_name,
                p.price,
                p.category,
                p.subcategory,
                p.image_uri,
                a.primary_color,
                CASE 
                    WHEN p.subcategory IN {outfit_rules[outfit_type]['tops']} THEN 'top'
                    WHEN p.subcategory IN {outfit_rules[outfit_type]['bottoms']} THEN 'bottom'
                    WHEN p.subcategory IN {outfit_rules[outfit_type]['footwear']} THEN 'footwear'
                    WHEN p.subcategory IN {outfit_rules[outfit_type]['accessories']} THEN 'accessory'
                    ELSE 'other'
                END as item_type,
                -- Color harmony score
                CASE 
                    WHEN a.primary_color = b.primary_color THEN 0.8  -- Monochromatic
                    WHEN {self._check_complementary_colors('a.primary_color', 'b.primary_color')} THEN 1.0
                    WHEN {self._check_analogous_colors('a.primary_color', 'b.primary_color')} THEN 0.9
                    ELSE 0.5
                END as color_harmony_score
            FROM `{self.dataset_ref}.products` p
            JOIN `{self.dataset_ref}.image_analysis` a
                ON p.sku = a.sku
            CROSS JOIN base_item b
            WHERE p.sku != b.sku
                AND p.gender IN (b.gender, 'unisex')
        )
        SELECT 
            item_type,
            ARRAY_AGG(
                STRUCT(
                    sku,
                    product_name,
                    brand_name,
                    price,
                    image_uri,
                    primary_color,
                    color_harmony_score
                )
                ORDER BY color_harmony_score DESC
                LIMIT 3
            ) as recommendations
        FROM complementary_items
        WHERE item_type != (SELECT item_type FROM base_item)
            AND item_type != 'other'
        GROUP BY item_type
        """
        
        return query
    
    def trending_visual_styles(self, timeframe_days: int = 30) -> str:
        """
        Identify trending visual styles based on engagement
        """
        query = f"""
        WITH style_engagement AS (
            SELECT 
                a.style_category,
                a.primary_color,
                a.detected_pattern,
                COUNT(DISTINCT e.user_id) as unique_viewers,
                SUM(e.view_duration) as total_view_time,
                COUNT(DISTINCT c.order_id) as conversions,
                AVG(p.rating) as avg_rating
            FROM `{self.dataset_ref}.image_analysis` a
            JOIN `{self.dataset_ref}.products` p
                ON a.sku = p.sku
            LEFT JOIN `{self.dataset_ref}.product_engagement` e
                ON p.sku = e.sku
                AND e.event_date >= DATE_SUB(CURRENT_DATE(), INTERVAL {timeframe_days} DAY)
            LEFT JOIN `{self.dataset_ref}.conversions` c
                ON p.sku = c.sku
                AND c.order_date >= DATE_SUB(CURRENT_DATE(), INTERVAL {timeframe_days} DAY)
            GROUP BY a.style_category, a.primary_color, a.detected_pattern
        ),
        style_trends AS (
            SELECT 
                style_category,
                primary_color,
                detected_pattern,
                unique_viewers,
                conversions,
                conversions / NULLIF(unique_viewers, 0) as conversion_rate,
                avg_rating,
                -- Calculate trend score
                (
                    (unique_viewers / (SELECT MAX(unique_viewers) FROM style_engagement)) * 0.3 +
                    (conversions / NULLIF((SELECT MAX(conversions) FROM style_engagement), 0)) * 0.4 +
                    (conversions / NULLIF(unique_viewers, 0) / 0.1) * 0.2 +  -- Normalize conv rate
                    (avg_rating / 5.0) * 0.1
                ) as trend_score
            FROM style_engagement
            WHERE unique_viewers >= 10  -- Minimum threshold
        )
        SELECT 
            style_category,
            primary_color,
            detected_pattern,
            unique_viewers,
            conversions,
            ROUND(conversion_rate * 100, 2) as conversion_rate_pct,
            ROUND(avg_rating, 2) as avg_rating,
            ROUND(trend_score * 100, 2) as trend_score,
            RANK() OVER (ORDER BY trend_score DESC) as trend_rank
        FROM style_trends
        ORDER BY trend_score DESC
        LIMIT 20
        """
        
        return query
    
    def _get_similar_colors(self, color: str) -> List[str]:
        """Get colors from the same family"""
        for family, colors in self.color_families.items():
            if color.lower() in colors:
                return colors
        return [color]
    
    def _check_complementary_colors(self, color1: str, color2: str) -> bool:
        """Check if colors are complementary"""
        complementary_pairs = [
            ('red', 'green'),
            ('blue', 'orange'),
            ('yellow', 'purple'),
            ('black', 'white')
        ]
        
        for pair in complementary_pairs:
            if (color1 in pair and color2 in pair) and color1 != color2:
                return True
        return False
    
    def _check_analogous_colors(self, color1: str, color2: str) -> bool:
        """Check if colors are analogous (next to each other on color wheel)"""
        color_wheel = ['red', 'orange', 'yellow', 'green', 'blue', 'purple']
        
        try:
            idx1 = color_wheel.index(color1.lower())
            idx2 = color_wheel.index(color2.lower())
            
            # Check if adjacent on color wheel
            return abs(idx1 - idx2) == 1 or abs(idx1 - idx2) == len(color_wheel) - 1
        except ValueError:
            return False


class VisualMerchandisingOptimizer:
    """
    Optimize product presentation using visual analytics
    """
    
    def __init__(self, project_id: str, dataset_id: str):
        self.project_id = project_id
        self.dataset_id = dataset_id
        self.dataset_ref = f"{project_id}.{dataset_id}"
        
    def optimize_gallery_layout(self, category: str, layout_type: str = 'grid') -> str:
        """
        Optimize product gallery layout for visual appeal and conversion
        """
        query = f"""
        WITH product_visual_scores AS (
            SELECT 
                p.sku,
                p.product_name,
                p.price,
                p.image_uri,
                a.primary_color,
                a.quality_score,
                a.style_category,
                -- Visual diversity score
                COUNT(DISTINCT a.primary_color) OVER (
                    PARTITION BY p.category 
                    ORDER BY p.popularity_score DESC 
                    ROWS BETWEEN 3 PRECEDING AND 3 FOLLOWING
                ) as color_diversity,
                -- Price diversity
                STDDEV(p.price) OVER (
                    PARTITION BY p.category 
                    ORDER BY p.popularity_score DESC 
                    ROWS BETWEEN 3 PRECEDING AND 3 FOLLOWING
                ) as price_diversity,
                -- Combined score
                p.popularity_score * 0.4 +
                CAST(a.quality_score AS FLOAT64) * 0.3 +
                p.conversion_rate * 0.3 as display_score
            FROM `{self.dataset_ref}.products` p
            JOIN `{self.dataset_ref}.image_analysis` a
                ON p.sku = a.sku
            WHERE p.category = '{category}'
                AND p.is_active = TRUE
                AND a.quality_score >= 0.6
        ),
        layout_optimization AS (
            SELECT 
                sku,
                product_name,
                price,
                image_uri,
                primary_color,
                display_score,
                -- Assign to layout position
                CASE 
                    WHEN '{layout_type}' = 'grid' THEN 
                        ROW_NUMBER() OVER (ORDER BY display_score DESC)
                    WHEN '{layout_type}' = 'masonry' THEN 
                        ROW_NUMBER() OVER (ORDER BY display_score DESC, RAND())
                    ELSE 
                        ROW_NUMBER() OVER (ORDER BY display_score DESC)
                END as position,
                -- Determine prominence
                CASE 
                    WHEN ROW_NUMBER() OVER (ORDER BY display_score DESC) <= 4 THEN 'hero'
                    WHEN ROW_NUMBER() OVER (ORDER BY display_score DESC) <= 12 THEN 'featured'
                    ELSE 'standard'
                END as display_prominence
            FROM product_visual_scores
        )
        SELECT 
            position,
            sku,
            product_name,
            price,
            image_uri,
            primary_color,
            display_prominence,
            ROUND(display_score * 100, 2) as score
        FROM layout_optimization
        ORDER BY position
        LIMIT 48  -- Typical page size
        """
        
        return query
    
    def analyze_visual_performance(self) -> str:
        """
        Analyze which visual attributes drive engagement
        """
        query = f"""
        WITH visual_engagement AS (
            SELECT 
                a.primary_color,
                a.detected_pattern,
                a.style_category,
                a.quality_score,
                AVG(e.view_duration) as avg_view_duration,
                AVG(e.click_through_rate) as avg_ctr,
                AVG(c.conversion_rate) as avg_conversion_rate,
                COUNT(DISTINCT p.sku) as product_count
            FROM `{self.dataset_ref}.image_analysis` a
            JOIN `{self.dataset_ref}.products` p
                ON a.sku = p.sku
            JOIN `{self.dataset_ref}.product_engagement` e
                ON p.sku = e.sku
            JOIN `{self.dataset_ref}.conversion_metrics` c
                ON p.sku = c.sku
            GROUP BY a.primary_color, a.detected_pattern, a.style_category, a.quality_score
            HAVING product_count >= 5  -- Statistical significance
        )
        SELECT 
            primary_color,
            detected_pattern,
            style_category,
            ROUND(AVG(CAST(quality_score AS FLOAT64)), 2) as avg_quality_score,
            ROUND(avg_view_duration, 2) as avg_view_duration_sec,
            ROUND(avg_ctr * 100, 2) as avg_ctr_pct,
            ROUND(avg_conversion_rate * 100, 2) as avg_conversion_pct,
            product_count,
            -- Performance index
            ROUND(
                (avg_ctr / (SELECT AVG(avg_ctr) FROM visual_engagement)) * 0.3 +
                (avg_conversion_rate / (SELECT AVG(avg_conversion_rate) FROM visual_engagement)) * 0.5 +
                (avg_view_duration / (SELECT AVG(avg_view_duration) FROM visual_engagement)) * 0.2,
                2
            ) as performance_index
        FROM visual_engagement
        ORDER BY performance_index DESC
        """
        
        return query