"""
Semantic Similarity Search Implementation
Advanced search strategies for product discovery
"""

from typing import List, Dict, Optional, Tuple, Any
from dataclasses import dataclass
from enum import Enum
import logging

logger = logging.getLogger(__name__)


class SearchStrategy(Enum):
    """Different search strategies for various use cases"""
    EXACT_MATCH = "exact_match"
    SEMANTIC_SIMILAR = "semantic_similar"
    CATEGORY_CONSTRAINED = "category_constrained"
    PRICE_AWARE = "price_aware"
    BRAND_FOCUSED = "brand_focused"
    SUBSTITUTE_FINDER = "substitute_finder"


@dataclass
class SearchQuery:
    """Structured search query"""
    text: str
    strategy: SearchStrategy
    filters: Optional[Dict[str, Any]] = None
    boost_fields: Optional[List[str]] = None
    negative_keywords: Optional[List[str]] = None
    price_range: Optional[Tuple[float, float]] = None
    category_constraint: Optional[str] = None


@dataclass
class SearchResult:
    """Individual search result"""
    sku: str
    score: float
    product_data: Dict[str, Any]
    explanation: str
    matched_fields: List[str]


class SimilaritySearch:
    """
    Advanced similarity search for products using BigQuery vector search.
    Implements multiple search strategies optimized for e-commerce.
    """
    
    def __init__(self, project_id: str, dataset_id: str):
        self.project_id = project_id
        self.dataset_id = dataset_id
        self.dataset_ref = f"{project_id}.{dataset_id}"
        
        # Search configuration
        self.default_top_k = 20
        self.rerank_top_k = 100  # Fetch more, then rerank
        
        # Relevance thresholds
        self.relevance_thresholds = {
            SearchStrategy.EXACT_MATCH: 0.95,
            SearchStrategy.SEMANTIC_SIMILAR: 0.80,
            SearchStrategy.CATEGORY_CONSTRAINED: 0.75,
            SearchStrategy.PRICE_AWARE: 0.70,
            SearchStrategy.BRAND_FOCUSED: 0.85,
            SearchStrategy.SUBSTITUTE_FINDER: 0.75
        }
    
    def build_search_query(
        self,
        user_input: str,
        strategy: SearchStrategy = SearchStrategy.SEMANTIC_SIMILAR,
        **kwargs
    ) -> SearchQuery:
        """
        Build a structured search query from user input
        """
        # Extract filters from natural language
        filters = self._extract_filters_from_text(user_input)
        
        # Merge with provided filters
        if 'filters' in kwargs:
            filters.update(kwargs['filters'])
        
        # Extract price range if mentioned
        price_range = self._extract_price_range(user_input)
        if 'price_range' in kwargs:
            price_range = kwargs['price_range']
        
        # Build query object
        query = SearchQuery(
            text=self._clean_search_text(user_input),
            strategy=strategy,
            filters=filters,
            boost_fields=kwargs.get('boost_fields', []),
            negative_keywords=kwargs.get('negative_keywords', []),
            price_range=price_range,
            category_constraint=kwargs.get('category', filters.get('category'))
        )
        
        return query
    
    def execute_search(
        self,
        query: SearchQuery,
        embedding_table: str,
        top_k: Optional[int] = None
    ) -> List[SearchResult]:
        """
        Execute search based on strategy
        """
        if top_k is None:
            top_k = self.default_top_k
        
        # Choose search implementation based on strategy
        if query.strategy == SearchStrategy.EXACT_MATCH:
            results = self._search_exact_match(query, embedding_table, top_k)
        elif query.strategy == SearchStrategy.SEMANTIC_SIMILAR:
            results = self._search_semantic(query, embedding_table, top_k)
        elif query.strategy == SearchStrategy.CATEGORY_CONSTRAINED:
            results = self._search_within_category(query, embedding_table, top_k)
        elif query.strategy == SearchStrategy.PRICE_AWARE:
            results = self._search_price_aware(query, embedding_table, top_k)
        elif query.strategy == SearchStrategy.BRAND_FOCUSED:
            results = self._search_brand_focused(query, embedding_table, top_k)
        elif query.strategy == SearchStrategy.SUBSTITUTE_FINDER:
            results = self._search_substitutes(query, embedding_table, top_k)
        else:
            results = self._search_semantic(query, embedding_table, top_k)
        
        # Post-process results
        results = self._postprocess_results(results, query)
        
        return results
    
    def _search_exact_match(
        self,
        query: SearchQuery,
        embedding_table: str,
        top_k: int
    ) -> List[SearchResult]:
        """
        Search for exact or near-exact matches
        High precision, low recall
        """
        sql = f"""
        WITH query_embedding AS (
            SELECT ML.GENERATE_EMBEDDING(
                MODEL `{self.dataset_ref}.text-embedding-004`,
                CONTENT => '{query.text}',
                STRUCT(TRUE AS flatten_json_output)
            ) AS embedding
        ),
        search_results AS (
            SELECT
                e.sku,
                e.brand_name,
                e.product_name,
                e.category,
                e.price,
                ML.DISTANCE(e.full_embedding, q.embedding, 'COSINE') AS distance,
                1 - ML.DISTANCE(e.full_embedding, q.embedding, 'COSINE') AS similarity_score
            FROM `{self.dataset_ref}.{embedding_table}` e
            CROSS JOIN query_embedding q
            WHERE 1=1
                {self._build_filter_clause(query.filters)}
                AND ML.DISTANCE(e.full_embedding, q.embedding, 'COSINE') < {1 - self.relevance_thresholds[SearchStrategy.EXACT_MATCH]}
        )
        SELECT *
        FROM search_results
        ORDER BY similarity_score DESC
        LIMIT {top_k}
        """
        
        # Execute and convert to SearchResult objects
        results = self._execute_sql_search(sql, SearchStrategy.EXACT_MATCH)
        return results
    
    def _search_semantic(
        self,
        query: SearchQuery,
        embedding_table: str,
        top_k: int
    ) -> List[SearchResult]:
        """
        Standard semantic similarity search
        Balanced precision and recall
        """
        # First, get more results for reranking
        fetch_k = min(top_k * 5, self.rerank_top_k)
        
        sql = f"""
        WITH query_embedding AS (
            SELECT ML.GENERATE_EMBEDDING(
                MODEL `{self.dataset_ref}.text-embedding-004`,
                CONTENT => '{query.text}',
                STRUCT(TRUE AS flatten_json_output)
            ) AS embedding
        ),
        initial_results AS (
            SELECT
                e.*,
                p.price,
                p.category,
                p.subcategory,
                p.in_stock,
                ML.DISTANCE(e.full_embedding, q.embedding, 'COSINE') AS distance
            FROM `{self.dataset_ref}.{embedding_table}` e
            JOIN `{self.dataset_ref}.{embedding_table.replace('_embeddings', '')}` p
                ON e.sku = p.sku
            CROSS JOIN query_embedding q
            WHERE 1=1
                {self._build_filter_clause(query.filters)}
        ),
        ranked_results AS (
            SELECT 
                *,
                1 - distance AS base_score,
                -- Boost score based on additional factors
                (1 - distance) * 
                CASE 
                    WHEN in_stock = true THEN 1.1 
                    ELSE 0.9 
                END AS adjusted_score
            FROM initial_results
            WHERE distance < {1 - self.relevance_thresholds[SearchStrategy.SEMANTIC_SIMILAR]}
        )
        SELECT *
        FROM ranked_results
        ORDER BY adjusted_score DESC
        LIMIT {fetch_k}
        """
        
        # Get initial results
        results = self._execute_sql_search(sql, SearchStrategy.SEMANTIC_SIMILAR)
        
        # Rerank if we have boost fields
        if query.boost_fields:
            results = self._rerank_results(results, query, top_k)
        else:
            results = results[:top_k]
        
        return results
    
    def _search_within_category(
        self,
        query: SearchQuery,
        embedding_table: str,
        top_k: int
    ) -> List[SearchResult]:
        """
        Search within a specific category
        Useful for "more like this" in same category
        """
        category_filter = ""
        if query.category_constraint:
            category_filter = f"AND p.category = '{query.category_constraint}'"
        
        sql = f"""
        WITH query_embedding AS (
            SELECT ML.GENERATE_EMBEDDING(
                MODEL `{self.dataset_ref}.text-embedding-004`,
                CONTENT => '{query.text}',
                STRUCT(TRUE AS flatten_json_output)
            ) AS embedding
        ),
        category_results AS (
            SELECT
                e.sku,
                e.brand_name,
                e.product_name,
                p.category,
                p.subcategory,
                p.price,
                ML.DISTANCE(e.full_embedding, q.embedding, 'COSINE') AS distance,
                -- Also calculate title similarity for category searches
                ML.DISTANCE(e.title_embedding, q.embedding, 'COSINE') AS title_distance
            FROM `{self.dataset_ref}.{embedding_table}` e
            JOIN `{self.dataset_ref}.{embedding_table.replace('_embeddings', '')}` p
                ON e.sku = p.sku
            CROSS JOIN query_embedding q
            WHERE 1=1
                {category_filter}
                {self._build_filter_clause(query.filters)}
        )
        SELECT 
            *,
            -- Combine full and title similarity for category searches
            1 - (0.7 * distance + 0.3 * title_distance) AS combined_score
        FROM category_results
        WHERE distance < {1 - self.relevance_thresholds[SearchStrategy.CATEGORY_CONSTRAINED]}
        ORDER BY combined_score DESC
        LIMIT {top_k}
        """
        
        results = self._execute_sql_search(sql, SearchStrategy.CATEGORY_CONSTRAINED)
        return results
    
    def _search_price_aware(
        self,
        query: SearchQuery,
        embedding_table: str,
        top_k: int
    ) -> List[SearchResult]:
        """
        Search with price sensitivity
        Balances similarity with price preferences
        """
        price_clause = ""
        if query.price_range:
            min_price, max_price = query.price_range
            price_clause = f"AND p.price BETWEEN {min_price} AND {max_price}"
        
        sql = f"""
        WITH query_embedding AS (
            SELECT ML.GENERATE_EMBEDDING(
                MODEL `{self.dataset_ref}.text-embedding-004`,
                CONTENT => '{query.text}',
                STRUCT(TRUE AS flatten_json_output)
            ) AS embedding
        ),
        price_stats AS (
            SELECT 
                AVG(price) AS avg_price,
                STDDEV(price) AS stddev_price
            FROM `{self.dataset_ref}.{embedding_table.replace('_embeddings', '')}`
            WHERE price > 0
        ),
        price_results AS (
            SELECT
                e.sku,
                e.brand_name,
                e.product_name,
                p.price,
                p.original_price,
                ML.DISTANCE(e.full_embedding, q.embedding, 'COSINE') AS distance,
                -- Calculate price score (lower is better if looking for deals)
                (p.price - ps.avg_price) / NULLIF(ps.stddev_price, 0) AS price_zscore,
                -- Discount percentage
                SAFE_DIVIDE(p.original_price - p.price, p.original_price) AS discount_pct
            FROM `{self.dataset_ref}.{embedding_table}` e
            JOIN `{self.dataset_ref}.{embedding_table.replace('_embeddings', '')}` p
                ON e.sku = p.sku
            CROSS JOIN query_embedding q
            CROSS JOIN price_stats ps
            WHERE 1=1
                {price_clause}
                {self._build_filter_clause(query.filters)}
        )
        SELECT 
            *,
            -- Combine similarity with price attractiveness
            (1 - distance) * 0.7 + 
            (1 / (1 + EXP(price_zscore))) * 0.2 +  -- Sigmoid of price z-score
            IFNULL(discount_pct, 0) * 0.1 AS combined_score
        FROM price_results
        WHERE distance < {1 - self.relevance_thresholds[SearchStrategy.PRICE_AWARE]}
        ORDER BY combined_score DESC
        LIMIT {top_k}
        """
        
        results = self._execute_sql_search(sql, SearchStrategy.PRICE_AWARE)
        return results
    
    def _search_brand_focused(
        self,
        query: SearchQuery,
        embedding_table: str,
        top_k: int
    ) -> List[SearchResult]:
        """
        Search focusing on brand similarity
        Useful for brand-conscious shoppers
        """
        sql = f"""
        WITH query_embedding AS (
            SELECT ML.GENERATE_EMBEDDING(
                MODEL `{self.dataset_ref}.text-embedding-004`,
                CONTENT => '{query.text}',
                STRUCT(TRUE AS flatten_json_output)
            ) AS embedding
        ),
        -- Extract potential brand from query
        query_brand AS (
            SELECT 
                REGEXP_EXTRACT(LOWER('{query.text}'), r'\\b(nike|adidas|puma|reebok|new balance|under armour)\\b') AS brand
        ),
        brand_results AS (
            SELECT
                e.sku,
                e.brand_name,
                e.product_name,
                p.category,
                p.price,
                ML.DISTANCE(e.full_embedding, q.embedding, 'COSINE') AS full_distance,
                ML.DISTANCE(e.title_embedding, q.embedding, 'COSINE') AS title_distance,
                -- Brand match bonus
                CASE 
                    WHEN LOWER(e.brand_name) = qb.brand THEN 0.3
                    WHEN LOWER(e.brand_name) LIKE CONCAT('%', qb.brand, '%') THEN 0.2
                    ELSE 0
                END AS brand_bonus
            FROM `{self.dataset_ref}.{embedding_table}` e
            JOIN `{self.dataset_ref}.{embedding_table.replace('_embeddings', '')}` p
                ON e.sku = p.sku
            CROSS JOIN query_embedding q
            CROSS JOIN query_brand qb
            WHERE 1=1
                {self._build_filter_clause(query.filters)}
        )
        SELECT 
            *,
            -- Weight title similarity higher for brand searches
            (1 - (0.4 * full_distance + 0.6 * title_distance)) + brand_bonus AS combined_score
        FROM brand_results
        WHERE full_distance < {1 - self.relevance_thresholds[SearchStrategy.BRAND_FOCUSED]}
        ORDER BY combined_score DESC
        LIMIT {top_k}
        """
        
        results = self._execute_sql_search(sql, SearchStrategy.BRAND_FOCUSED)
        return results
    
    def _search_substitutes(
        self,
        query: SearchQuery,
        embedding_table: str,
        top_k: int
    ) -> List[SearchResult]:
        """
        Find substitute products
        Similar products that could replace the query item
        """
        sql = f"""
        WITH query_embedding AS (
            SELECT ML.GENERATE_EMBEDDING(
                MODEL `{self.dataset_ref}.text-embedding-004`,
                CONTENT => '{query.text}',
                STRUCT(TRUE AS flatten_json_output)
            ) AS embedding
        ),
        -- Use attribute embedding for substitute matching
        substitute_results AS (
            SELECT
                e.sku,
                e.brand_name,
                e.product_name,
                p.category,
                p.subcategory,
                p.price,
                p.rating,
                p.review_count,
                ML.DISTANCE(e.full_embedding, q.embedding, 'COSINE') AS full_distance,
                ML.DISTANCE(e.attribute_embedding, q.embedding, 'COSINE') AS attr_distance
            FROM `{self.dataset_ref}.{embedding_table}` e
            JOIN `{self.dataset_ref}.{embedding_table.replace('_embeddings', '')}` p
                ON e.sku = p.sku
            CROSS JOIN query_embedding q
            WHERE 1=1
                AND p.in_stock = true  -- Only in-stock items for substitutes
                {self._build_filter_clause(query.filters)}
        )
        SELECT 
            *,
            -- Combine distances with emphasis on attributes
            1 - (0.4 * full_distance + 0.6 * attr_distance) AS similarity_score,
            -- Quality score based on ratings
            CASE 
                WHEN rating >= 4.5 AND review_count >= 10 THEN 0.1
                WHEN rating >= 4.0 AND review_count >= 5 THEN 0.05
                ELSE 0
            END AS quality_bonus
        FROM substitute_results
        WHERE full_distance < {1 - self.relevance_thresholds[SearchStrategy.SUBSTITUTE_FINDER]}
        ORDER BY (similarity_score + quality_bonus) DESC
        LIMIT {top_k}
        """
        
        results = self._execute_sql_search(sql, SearchStrategy.SUBSTITUTE_FINDER)
        return results
    
    def _extract_filters_from_text(self, text: str) -> Dict[str, Any]:
        """Extract filter conditions from natural language"""
        filters = {}
        
        # Extract brand mentions
        brand_pattern = r'\b(nike|adidas|puma|reebok|new balance|under armour)\b'
        brand_match = re.search(brand_pattern, text.lower())
        if brand_match:
            filters['brand_name'] = brand_match.group(1)
        
        # Extract category mentions
        category_pattern = r'\b(shoes?|clothing|accessories|electronics|sports)\b'
        category_match = re.search(category_pattern, text.lower())
        if category_match:
            filters['category'] = category_match.group(1)
        
        # Extract color mentions
        color_pattern = r'\b(black|white|red|blue|green|yellow|purple|grey|gray)\b'
        color_match = re.search(color_pattern, text.lower())
        if color_match:
            filters['color'] = color_match.group(1)
        
        return filters
    
    def _extract_price_range(self, text: str) -> Optional[Tuple[float, float]]:
        """Extract price range from natural language"""
        # Pattern for "under $X"
        under_pattern = r'under\s*\$?(\d+)'
        under_match = re.search(under_pattern, text.lower())
        if under_match:
            return (0, float(under_match.group(1)))
        
        # Pattern for "over $X"
        over_pattern = r'over\s*\$?(\d+)'
        over_match = re.search(over_pattern, text.lower())
        if over_match:
            return (float(over_match.group(1)), 999999)
        
        # Pattern for "$X to $Y" or "$X-$Y"
        range_pattern = r'\$?(\d+)\s*(?:to|-)\s*\$?(\d+)'
        range_match = re.search(range_pattern, text)
        if range_match:
            return (float(range_match.group(1)), float(range_match.group(2)))
        
        return None
    
    def _clean_search_text(self, text: str) -> str:
        """Clean search text for embedding generation"""
        # Remove price mentions
        text = re.sub(r'\$\d+(?:\.\d+)?', '', text)
        text = re.sub(r'\b(?:under|over|between)\s+\d+', '', text)
        
        # Remove common filter words
        filter_words = ['in stock', 'available', 'on sale', 'discounted']
        for word in filter_words:
            text = text.replace(word, '')
        
        # Clean up whitespace
        text = ' '.join(text.split())
        
        return text.strip()
    
    def _build_filter_clause(self, filters: Optional[Dict[str, Any]]) -> str:
        """Build SQL WHERE clause from filters"""
        if not filters:
            return ""
        
        clauses = []
        for field, value in filters.items():
            if isinstance(value, list):
                values_str = ','.join([f"'{v}'" for v in value])
                clauses.append(f"AND p.{field} IN ({values_str})")
            elif isinstance(value, str):
                clauses.append(f"AND LOWER(p.{field}) = '{value.lower()}'")
            elif isinstance(value, bool):
                clauses.append(f"AND p.{field} = {str(value).lower()}")
            else:
                clauses.append(f"AND p.{field} = {value}")
        
        return ' '.join(clauses)
    
    def _execute_sql_search(self, sql: str, strategy: SearchStrategy) -> List[SearchResult]:
        """Execute SQL and convert to SearchResult objects"""
        # This is a placeholder - in production, would execute via BigQuery client
        # For now, return empty results
        return []
    
    def _rerank_results(
        self,
        results: List[SearchResult],
        query: SearchQuery,
        top_k: int
    ) -> List[SearchResult]:
        """Rerank results based on boost fields and other factors"""
        # Apply boost scoring
        for result in results:
            boost_score = 0
            
            # Check boost fields
            for field in query.boost_fields:
                if field in result.matched_fields:
                    boost_score += 0.1
            
            # Apply negative keywords penalty
            if query.negative_keywords:
                for neg_keyword in query.negative_keywords:
                    if neg_keyword.lower() in result.product_data.get('product_name', '').lower():
                        boost_score -= 0.2
            
            # Update score
            result.score = result.score * (1 + boost_score)
        
        # Resort and return top k
        results.sort(key=lambda x: x.score, reverse=True)
        return results[:top_k]
    
    def _postprocess_results(
        self,
        results: List[SearchResult],
        query: SearchQuery
    ) -> List[SearchResult]:
        """Post-process search results"""
        # Add explanations
        for result in results:
            result.explanation = self._generate_explanation(result, query)
        
        # Filter by minimum score threshold
        min_score = self.relevance_thresholds.get(query.strategy, 0.7)
        results = [r for r in results if r.score >= min_score]
        
        return results
    
    def _generate_explanation(self, result: SearchResult, query: SearchQuery) -> str:
        """Generate human-readable explanation for why result matches"""
        explanations = []
        
        if result.score >= 0.95:
            explanations.append("Near exact match")
        elif result.score >= 0.85:
            explanations.append("High similarity")
        else:
            explanations.append("Related product")
        
        if query.strategy == SearchStrategy.PRICE_AWARE:
            price = result.product_data.get('price', 0)
            if query.price_range and query.price_range[0] <= price <= query.price_range[1]:
                explanations.append(f"Within price range")
        
        if result.matched_fields:
            explanations.append(f"Matches: {', '.join(result.matched_fields)}")
        
        return "; ".join(explanations)