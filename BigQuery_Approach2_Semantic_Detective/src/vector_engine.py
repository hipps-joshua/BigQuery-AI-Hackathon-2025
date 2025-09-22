"""
BigQuery Vector Search Engine for Semantic Product Matching
Enhanced with Template-Driven Processing from Neutron Star
"""

import asyncio
import concurrent.futures
from typing import Dict, List, Optional, Tuple, Any
from dataclasses import dataclass
from datetime import datetime
import numpy as np
import pandas as pd
from google.cloud import bigquery
from google.cloud.exceptions import GoogleCloudError
import logging
import json

logger = logging.getLogger(__name__)


@dataclass
class SimilarityResult:
    """Result of a similarity search"""
    query_item: Dict[str, Any]
    similar_items: List[Dict[str, Any]]
    similarity_scores: List[float]
    search_time_ms: float
    index_used: bool
    error: Optional[str] = None


@dataclass
class DuplicateGroup:
    """Group of duplicate products"""
    group_id: str
    products: List[Dict[str, Any]]
    confidence_score: float
    merge_recommendation: Dict[str, Any]


class BigQueryVectorEngine:
    """
    Vector search engine for semantic product matching.
    Combines embeddings with template-driven processing for accuracy.
    """
    
    def __init__(self, project_id: str, dataset_id: str):
        """Initialize the vector search engine"""
        self.project_id = project_id
        self.dataset_id = dataset_id
        self.client = bigquery.Client(project=project_id)
        self.dataset_ref = f"{project_id}.{dataset_id}"
        
        # Embedding configuration
        self.embedding_model = "text-embedding-004"  # Latest Google embedding model
        self.embedding_dimension = 768
        
        # Template categories for different product aspects
        self.embedding_templates = {
            'full_product': 'brand + name + category + description',
            'title_only': 'brand + name',
            'attributes': 'color + size + material + features',
            'technical': 'specifications + dimensions + weight',
            'categorical': 'category + subcategory + product_type'
        }
        
    def generate_product_embeddings(self, table_name: str, batch_size: int = 100) -> str:
        """
        Generate embeddings for all products in a table
        Returns the name of the table with embeddings
        """
        start_time = datetime.now()
        embedding_table = f"{table_name}_embeddings"
        
        # Create comprehensive product text for embedding
        query = f"""
        CREATE OR REPLACE TABLE `{self.dataset_ref}.{embedding_table}` AS
        WITH product_text AS (
            SELECT 
                sku,
                brand_name,
                product_name,
                category,
                description,
                -- Combine all text fields for comprehensive embedding
                CONCAT(
                    IFNULL(brand_name, ''), ' ',
                    IFNULL(product_name, ''), ' ',
                    IFNULL(category, ''), ' ',
                    IFNULL(subcategory, ''), ' ',
                    IFNULL(description, ''), ' ',
                    IFNULL(color, ''), ' ',
                    IFNULL(size, ''), ' ',
                    IFNULL(material, ''), ' ',
                    'Price: ', CAST(price AS STRING)
                ) AS full_text,
                -- Also create specialized embeddings
                CONCAT(IFNULL(brand_name, ''), ' ', IFNULL(product_name, '')) AS title_text,
                CONCAT(
                    IFNULL(color, ''), ' ',
                    IFNULL(size, ''), ' ', 
                    IFNULL(material, '')
                ) AS attribute_text
            FROM `{self.dataset_ref}.{table_name}`
        )
        SELECT 
            sku,
            brand_name,
            product_name,
            full_text,
            ML.GENERATE_EMBEDDING(
                MODEL `{self.dataset_ref}.{self.embedding_model}`,
                CONTENT => full_text,
                STRUCT(TRUE AS flatten_json_output)
            ) AS full_embedding,
            ML.GENERATE_EMBEDDING(
                MODEL `{self.dataset_ref}.{self.embedding_model}`,
                CONTENT => title_text,
                STRUCT(TRUE AS flatten_json_output)
            ) AS title_embedding,
            ML.GENERATE_EMBEDDING(
                MODEL `{self.dataset_ref}.{self.embedding_model}`,
                CONTENT => attribute_text,
                STRUCT(TRUE AS flatten_json_output)
            ) AS attribute_embedding
        FROM product_text
        """
        
        try:
            query_job = self.client.query(query)
            query_job.result()  # Wait for completion
            
            execution_time = (datetime.now() - start_time).total_seconds()
            logger.info(f"Generated embeddings in {execution_time:.2f} seconds")
            
            return embedding_table
            
        except GoogleCloudError as e:
            logger.error(f"Failed to generate embeddings: {str(e)}")
            raise
    
    def create_vector_index(self, embedding_table: str, embedding_column: str = 'full_embedding') -> None:
        """
        Create a vector index for fast similarity search
        Recommended for tables with 1M+ rows
        """
        index_name = f"{embedding_table}_{embedding_column}_index"
        
        query = f"""
        CREATE VECTOR INDEX IF NOT EXISTS `{index_name}`
        ON `{self.dataset_ref}.{embedding_table}`({embedding_column})
        OPTIONS(
            distance_type='COSINE',
            index_type='IVF',
            ivf_options='{{"num_lists": 1000}}'
        )
        """
        
        try:
            query_job = self.client.query(query)
            query_job.result()
            logger.info(f"Created vector index: {index_name}")
        except GoogleCloudError as e:
            logger.error(f"Failed to create vector index: {str(e)}")
            raise
    
    def find_similar_products(
        self,
        embedding_table: str,
        query_sku: str,
        top_k: int = 10,
        similarity_threshold: float = 0.8,
        use_index: bool = True
    ) -> SimilarityResult:
        """
        Find products similar to a given SKU
        """
        start_time = datetime.now()
        
        # Get the query product's embedding
        query_embedding_sql = f"""
        SELECT 
            sku,
            brand_name,
            product_name,
            full_embedding
        FROM `{self.dataset_ref}.{embedding_table}`
        WHERE sku = '{query_sku}'
        """
        
        query_result = self.client.query(query_embedding_sql).result()
        query_rows = list(query_result)
        
        if not query_rows:
            return SimilarityResult(
                query_item={},
                similar_items=[],
                similarity_scores=[],
                search_time_ms=0,
                index_used=False,
                error=f"SKU {query_sku} not found"
            )
        
        query_item = dict(query_rows[0])
        
        # Perform vector search
        if use_index:
            search_query = f"""
            SELECT
                base.sku,
                base.brand_name,
                base.product_name,
                distance AS similarity_score
            FROM VECTOR_SEARCH(
                TABLE `{self.dataset_ref}.{embedding_table}`,
                'full_embedding',
                (
                    SELECT full_embedding 
                    FROM `{self.dataset_ref}.{embedding_table}` 
                    WHERE sku = '{query_sku}'
                ),
                top_k => {top_k + 1}  -- +1 because query item will be included
            )
            WHERE base.sku != '{query_sku}'
                AND distance < {1 - similarity_threshold}  -- Convert threshold to distance
            ORDER BY distance ASC
            """
        else:
            # Fallback to brute force search without index
            search_query = f"""
            WITH query_embedding AS (
                SELECT full_embedding
                FROM `{self.dataset_ref}.{embedding_table}`
                WHERE sku = '{query_sku}'
            )
            SELECT
                e.sku,
                e.brand_name,
                e.product_name,
                ML.DISTANCE(e.full_embedding, q.full_embedding, 'COSINE') AS distance,
                1 - ML.DISTANCE(e.full_embedding, q.full_embedding, 'COSINE') AS similarity_score
            FROM `{self.dataset_ref}.{embedding_table}` e
            CROSS JOIN query_embedding q
            WHERE e.sku != '{query_sku}'
                AND ML.DISTANCE(e.full_embedding, q.full_embedding, 'COSINE') < {1 - similarity_threshold}
            ORDER BY distance ASC
            LIMIT {top_k}
            """
        
        try:
            search_results = self.client.query(search_query).result()
            
            similar_items = []
            similarity_scores = []
            
            for row in search_results:
                similar_items.append({
                    'sku': row.sku,
                    'brand_name': row.brand_name,
                    'product_name': row.product_name,
                    'similarity_score': 1 - row.distance if hasattr(row, 'distance') else row.similarity_score
                })
                similarity_scores.append(1 - row.distance if hasattr(row, 'distance') else row.similarity_score)
            
            execution_time = (datetime.now() - start_time).total_seconds() * 1000
            
            return SimilarityResult(
                query_item=query_item,
                similar_items=similar_items,
                similarity_scores=similarity_scores,
                search_time_ms=execution_time,
                index_used=use_index
            )
            
        except GoogleCloudError as e:
            logger.error(f"Vector search failed: {str(e)}")
            return SimilarityResult(
                query_item=query_item,
                similar_items=[],
                similarity_scores=[],
                search_time_ms=0,
                index_used=use_index,
                error=str(e)
            )
    
    def detect_duplicate_products(
        self,
        embedding_table: str,
        similarity_threshold: float = 0.95,
        batch_size: int = 1000
    ) -> List[DuplicateGroup]:
        """
        Detect duplicate products using high similarity threshold
        """
        # Find all pairs of products with very high similarity
        duplicate_query = f"""
        WITH product_pairs AS (
            SELECT
                p1.sku AS sku1,
                p1.brand_name AS brand1,
                p1.product_name AS name1,
                p2.sku AS sku2,
                p2.brand_name AS brand2,
                p2.product_name AS name2,
                ML.DISTANCE(p1.full_embedding, p2.full_embedding, 'COSINE') AS distance,
                1 - ML.DISTANCE(p1.full_embedding, p2.full_embedding, 'COSINE') AS similarity
            FROM `{self.dataset_ref}.{embedding_table}` p1
            JOIN `{self.dataset_ref}.{embedding_table}` p2
                ON p1.sku < p2.sku  -- Avoid duplicates and self-joins
            WHERE ML.DISTANCE(p1.full_embedding, p2.full_embedding, 'COSINE') < {1 - similarity_threshold}
        ),
        -- Group duplicates using graph connectivity
        duplicate_groups AS (
            SELECT 
                sku1,
                sku2,
                similarity,
                DENSE_RANK() OVER (ORDER BY LEAST(sku1, sku2)) AS group_id
            FROM product_pairs
        )
        SELECT *
        FROM duplicate_groups
        ORDER BY group_id, similarity DESC
        """
        
        try:
            results = self.client.query(duplicate_query).result()
            
            # Group duplicates
            groups = {}
            for row in results:
                group_id = str(row.group_id)
                if group_id not in groups:
                    groups[group_id] = {
                        'products': set(),
                        'similarities': []
                    }
                groups[group_id]['products'].add(row.sku1)
                groups[group_id]['products'].add(row.sku2)
                groups[group_id]['similarities'].append(row.similarity)
            
            # Create DuplicateGroup objects
            duplicate_groups = []
            for group_id, group_data in groups.items():
                # Get full product details for the group
                skus = list(group_data['products'])
                products = self._get_product_details(embedding_table.replace('_embeddings', ''), skus)
                
                # Create merge recommendation
                merge_rec = self._create_merge_recommendation(products)
                
                duplicate_groups.append(DuplicateGroup(
                    group_id=group_id,
                    products=products,
                    confidence_score=np.mean(group_data['similarities']),
                    merge_recommendation=merge_rec
                ))
            
            return duplicate_groups
            
        except GoogleCloudError as e:
            logger.error(f"Duplicate detection failed: {str(e)}")
            return []
    
    def semantic_product_search(
        self,
        embedding_table: str,
        search_query: str,
        top_k: int = 20,
        filters: Optional[Dict[str, Any]] = None
    ) -> List[Dict[str, Any]]:
        """
        Search products using natural language query
        """
        # Generate embedding for the search query
        query_embedding_sql = f"""
        SELECT ML.GENERATE_EMBEDDING(
            MODEL `{self.dataset_ref}.{self.embedding_model}`,
            CONTENT => '{search_query}',
            STRUCT(TRUE AS flatten_json_output)
        ) AS query_embedding
        """
        
        query_result = self.client.query(query_embedding_sql).result()
        query_embedding = list(query_result)[0].query_embedding
        
        # Build filter conditions
        filter_conditions = ""
        if filters:
            conditions = []
            for field, value in filters.items():
                if isinstance(value, list):
                    conditions.append(f"base.{field} IN ({','.join([f\"'{v}'\" for v in value])})")
                else:
                    conditions.append(f"base.{field} = '{value}'")
            filter_conditions = f"WHERE {' AND '.join(conditions)}"
        
        # Search using the query embedding
        search_sql = f"""
        SELECT
            base.*,
            distance AS relevance_score
        FROM VECTOR_SEARCH(
            TABLE `{self.dataset_ref}.{embedding_table}`,
            'full_embedding',
            (SELECT [{','.join(map(str, query_embedding))}] AS embedding),
            top_k => {top_k}
        )
        {filter_conditions}
        ORDER BY distance ASC
        """
        
        results = self.client.query(search_sql).result()
        
        products = []
        for row in results:
            product = dict(row)
            product['relevance_score'] = 1 - product.pop('distance', 0)
            products.append(product)
        
        return products
    
    def find_substitute_products(
        self,
        embedding_table: str,
        sku: str,
        price_range_pct: float = 0.2,
        same_category: bool = True
    ) -> List[Dict[str, Any]]:
        """
        Find substitute products within price range
        """
        # Get original product details
        original_query = f"""
        SELECT 
            e.*,
            p.price,
            p.category
        FROM `{self.dataset_ref}.{embedding_table}` e
        JOIN `{self.dataset_ref}.{embedding_table.replace('_embeddings', '')}` p
            ON e.sku = p.sku
        WHERE e.sku = '{sku}'
        """
        
        original_result = list(self.client.query(original_query).result())
        if not original_result:
            return []
        
        original = dict(original_result[0])
        price_min = original['price'] * (1 - price_range_pct)
        price_max = original['price'] * (1 + price_range_pct)
        
        # Find similar products within price range
        substitute_query = f"""
        WITH candidates AS (
            SELECT
                e.sku,
                e.brand_name,
                e.product_name,
                p.price,
                p.category,
                ML.DISTANCE(e.full_embedding, 
                    (SELECT full_embedding FROM `{self.dataset_ref}.{embedding_table}` WHERE sku = '{sku}'),
                    'COSINE'
                ) AS distance
            FROM `{self.dataset_ref}.{embedding_table}` e
            JOIN `{self.dataset_ref}.{embedding_table.replace('_embeddings', '')}` p
                ON e.sku = p.sku
            WHERE e.sku != '{sku}'
                AND p.price BETWEEN {price_min} AND {price_max}
                {f"AND p.category = '{original['category']}'" if same_category else ""}
        )
        SELECT 
            *,
            1 - distance AS similarity_score,
            ABS(price - {original['price']}) / {original['price']} AS price_difference_pct
        FROM candidates
        WHERE distance < 0.3  -- High similarity threshold
        ORDER BY distance ASC
        LIMIT 10
        """
        
        results = self.client.query(substitute_query).result()
        
        substitutes = []
        for row in results:
            substitute = dict(row)
            substitute['price_difference'] = substitute['price'] - original['price']
            substitute['is_cheaper'] = substitute['price'] < original['price']
            substitutes.append(substitute)
        
        return substitutes
    
    def _get_product_details(self, table_name: str, skus: List[str]) -> List[Dict[str, Any]]:
        """Get full product details for a list of SKUs"""
        sku_list = ','.join([f"'{sku}'" for sku in skus])
        query = f"""
        SELECT *
        FROM `{self.dataset_ref}.{table_name}`
        WHERE sku IN ({sku_list})
        """
        
        results = self.client.query(query).result()
        return [dict(row) for row in results]
    
    def _create_merge_recommendation(self, products: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Create a recommendation for merging duplicate products"""
        # Select the most complete product as the primary
        completeness_scores = []
        for product in products:
            score = sum(1 for v in product.values() if v is not None and str(v).strip())
            completeness_scores.append(score)
        
        primary_idx = np.argmax(completeness_scores)
        primary_product = products[primary_idx]
        
        # Aggregate inventory
        total_inventory = sum(p.get('inventory_count', 0) for p in products)
        
        # Merge attributes from all products
        merged_attributes = {}
        for key in primary_product.keys():
            if key not in ['sku', 'inventory_count']:
                # Take the most common non-null value
                values = [p.get(key) for p in products if p.get(key) is not None]
                if values:
                    # For numeric fields, take average
                    if key == 'price' and all(isinstance(v, (int, float)) for v in values):
                        merged_attributes[key] = np.mean(values)
                    else:
                        # For other fields, take most common
                        merged_attributes[key] = max(set(values), key=values.count)
        
        return {
            'primary_sku': primary_product['sku'],
            'merged_skus': [p['sku'] for p in products],
            'total_inventory': total_inventory,
            'merged_attributes': merged_attributes,
            'savings': f"${(len(products) - 1) * 50:.2f}"  # Estimated savings per duplicate
        }


# Singleton instance getter
_vector_engine_instance = None

def get_vector_engine(project_id: str, dataset_id: str) -> BigQueryVectorEngine:
    """Get or create the vector engine instance"""
    global _vector_engine_instance
    if _vector_engine_instance is None:
        _vector_engine_instance = BigQueryVectorEngine(project_id, dataset_id)
    return _vector_engine_instance