"""
Advanced Duplicate Detection Algorithms
Using semantic similarity and business rules
"""

import pandas as pd
import numpy as np
from typing import List, Dict, Tuple, Optional, Set
from dataclasses import dataclass
from collections import defaultdict
import re
import logging

logger = logging.getLogger(__name__)


@dataclass
class DuplicateCandidate:
    """A pair of potentially duplicate products"""
    sku1: str
    sku2: str
    similarity_score: float
    matching_attributes: Dict[str, bool]
    confidence: float
    reason: str


class DuplicateDetector:
    """
    Advanced duplicate detection using multiple strategies:
    1. Semantic similarity (embeddings)
    2. Attribute matching (exact and fuzzy)
    3. Pattern recognition (SKU patterns, naming conventions)
    4. Business rules (price ranges, categories)
    """
    
    def __init__(self):
        # Similarity thresholds for different confidence levels
        self.thresholds = {
            'definite_duplicate': 0.95,
            'likely_duplicate': 0.90,
            'possible_duplicate': 0.85,
            'similar_product': 0.80
        }
        
        # Attribute weights for matching
        self.attribute_weights = {
            'brand': 0.25,
            'model_number': 0.20,
            'upc': 0.30,
            'ean': 0.30,
            'size': 0.15,
            'color': 0.10,
            'material': 0.05,
            'price': 0.05
        }
        
        # Common variations in brand names
        self.brand_variations = {
            'nike': ['nike', 'nike inc', 'nike incorporated'],
            'adidas': ['adidas', 'adidas ag', 'adidas originals'],
            'apple': ['apple', 'apple inc', 'apple incorporated'],
            'samsung': ['samsung', 'samsung electronics', 'samsung group'],
            'sony': ['sony', 'sony corporation', 'sony corp']
        }
        
    def detect_duplicates_multi_strategy(
        self,
        products_df: pd.DataFrame,
        embeddings_df: pd.DataFrame,
        similarity_threshold: float = 0.85
    ) -> List[DuplicateCandidate]:
        """
        Detect duplicates using multiple strategies
        """
        candidates = []
        
        # Strategy 1: High embedding similarity
        embedding_candidates = self._find_by_embedding_similarity(
            embeddings_df, similarity_threshold
        )
        candidates.extend(embedding_candidates)
        
        # Strategy 2: Exact identifier matching
        identifier_candidates = self._find_by_identifiers(products_df)
        candidates.extend(identifier_candidates)
        
        # Strategy 3: Fuzzy attribute matching
        attribute_candidates = self._find_by_fuzzy_attributes(products_df)
        candidates.extend(attribute_candidates)
        
        # Strategy 4: Pattern-based matching
        pattern_candidates = self._find_by_patterns(products_df)
        candidates.extend(pattern_candidates)
        
        # Deduplicate and merge candidates
        final_candidates = self._merge_candidates(candidates, products_df)
        
        return final_candidates
    
    def _find_by_embedding_similarity(
        self,
        embeddings_df: pd.DataFrame,
        threshold: float
    ) -> List[DuplicateCandidate]:
        """Find duplicates based on embedding similarity"""
        candidates = []
        
        # This would use the vector search results
        # For now, returning placeholder
        # In production, this would process VECTOR_SEARCH results
        
        return candidates
    
    def _find_by_identifiers(self, df: pd.DataFrame) -> List[DuplicateCandidate]:
        """Find duplicates by exact matching on identifiers"""
        candidates = []
        identifier_columns = ['upc', 'ean', 'isbn', 'asin', 'model_number']
        
        for col in identifier_columns:
            if col in df.columns:
                # Group by identifier
                grouped = df[df[col].notna()].groupby(col)
                
                for identifier, group in grouped:
                    if len(group) > 1:
                        # Found products with same identifier
                        skus = group['sku'].tolist()
                        
                        for i in range(len(skus)):
                            for j in range(i + 1, len(skus)):
                                candidates.append(DuplicateCandidate(
                                    sku1=skus[i],
                                    sku2=skus[j],
                                    similarity_score=1.0,
                                    matching_attributes={col: True},
                                    confidence=1.0,
                                    reason=f"Exact {col} match: {identifier}"
                                ))
        
        return candidates
    
    def _find_by_fuzzy_attributes(self, df: pd.DataFrame) -> List[DuplicateCandidate]:
        """Find duplicates using fuzzy matching on attributes"""
        candidates = []
        
        # Normalize text fields
        text_fields = ['brand_name', 'product_name', 'color', 'material']
        for field in text_fields:
            if field in df.columns:
                df[f'{field}_normalized'] = df[field].fillna('').str.lower().str.strip()
        
        # Check each pair of products
        for i in range(len(df)):
            for j in range(i + 1, len(df)):
                row1 = df.iloc[i]
                row2 = df.iloc[j]
                
                # Calculate attribute matches
                matches = {}
                match_score = 0
                
                # Brand matching with variations
                if 'brand_name_normalized' in df.columns:
                    brand_match = self._match_brand(
                        row1['brand_name_normalized'],
                        row2['brand_name_normalized']
                    )
                    matches['brand'] = brand_match
                    if brand_match:
                        match_score += self.attribute_weights.get('brand', 0)
                
                # Size matching with unit conversion
                if 'size' in df.columns:
                    size_match = self._match_size(row1.get('size'), row2.get('size'))
                    matches['size'] = size_match
                    if size_match:
                        match_score += self.attribute_weights.get('size', 0)
                
                # Price matching within range
                if 'price' in df.columns:
                    price_match = self._match_price(
                        row1.get('price', 0),
                        row2.get('price', 0),
                        tolerance=0.10  # 10% tolerance
                    )
                    matches['price'] = price_match
                    if price_match:
                        match_score += self.attribute_weights.get('price', 0)
                
                # Product name similarity
                if 'product_name_normalized' in df.columns:
                    name_sim = self._calculate_name_similarity(
                        row1['product_name_normalized'],
                        row2['product_name_normalized']
                    )
                    if name_sim > 0.8:
                        match_score += 0.2
                
                # If sufficient matches, add as candidate
                if match_score >= 0.5:
                    candidates.append(DuplicateCandidate(
                        sku1=row1['sku'],
                        sku2=row2['sku'],
                        similarity_score=match_score,
                        matching_attributes=matches,
                        confidence=match_score,
                        reason="Fuzzy attribute matching"
                    ))
        
        return candidates
    
    def _find_by_patterns(self, df: pd.DataFrame) -> List[DuplicateCandidate]:
        """Find duplicates using SKU and naming patterns"""
        candidates = []
        
        # Pattern 1: Sequential SKUs (e.g., PROD-001-BLK, PROD-001-RED)
        if 'sku' in df.columns:
            sku_patterns = defaultdict(list)
            
            for _, row in df.iterrows():
                sku = row['sku']
                # Extract base pattern (remove size/color suffixes)
                base_pattern = re.sub(r'[-_](S|M|L|XL|XXL|[0-9]+)$', '', sku, flags=re.IGNORECASE)
                base_pattern = re.sub(r'[-_](BLACK|WHITE|RED|BLUE|GREEN)$', '', base_pattern, flags=re.IGNORECASE)
                sku_patterns[base_pattern].append(row)
            
            # Find groups with same base pattern
            for pattern, products in sku_patterns.items():
                if len(products) > 1:
                    for i in range(len(products)):
                        for j in range(i + 1, len(products)):
                            candidates.append(DuplicateCandidate(
                                sku1=products[i]['sku'],
                                sku2=products[j]['sku'],
                                similarity_score=0.85,
                                matching_attributes={'sku_pattern': True},
                                confidence=0.85,
                                reason=f"Similar SKU pattern: {pattern}"
                            ))
        
        # Pattern 2: Product name variations
        if 'product_name' in df.columns:
            name_patterns = defaultdict(list)
            
            for _, row in df.iterrows():
                name = str(row['product_name']).lower()
                # Remove common variations
                clean_name = re.sub(r'\b(mens?|womens?|kids?|boys?|girls?)\b', '', name)
                clean_name = re.sub(r'\b(small|medium|large|[xs]?[xls])\b', '', clean_name)
                clean_name = re.sub(r'\b\d+(\.\d+)?\s*(oz|ml|lb|kg|g)\b', '', clean_name)
                clean_name = ' '.join(clean_name.split())  # Normalize whitespace
                
                if clean_name:
                    name_patterns[clean_name].append(row)
            
            # Find products with same cleaned name
            for pattern, products in name_patterns.items():
                if len(products) > 1:
                    for i in range(len(products)):
                        for j in range(i + 1, len(products)):
                            candidates.append(DuplicateCandidate(
                                sku1=products[i]['sku'],
                                sku2=products[j]['sku'],
                                similarity_score=0.80,
                                matching_attributes={'name_pattern': True},
                                confidence=0.80,
                                reason=f"Similar name pattern"
                            ))
        
        return candidates
    
    def _match_brand(self, brand1: str, brand2: str) -> bool:
        """Check if two brands are the same (accounting for variations)"""
        if brand1 == brand2:
            return True
        
        # Check known variations
        for canonical, variations in self.brand_variations.items():
            if brand1 in variations and brand2 in variations:
                return True
        
        # Check if one is substring of other
        if brand1 in brand2 or brand2 in brand1:
            return True
        
        return False
    
    def _match_size(self, size1: Optional[str], size2: Optional[str]) -> bool:
        """Match sizes with unit conversion"""
        if not size1 or not size2:
            return False
        
        # Simple exact match first
        if str(size1).lower() == str(size2).lower():
            return True
        
        # Try to extract numeric values and units
        pattern = r'(\d+(?:\.\d+)?)\s*([a-zA-Z]*)'
        
        match1 = re.match(pattern, str(size1))
        match2 = re.match(pattern, str(size2))
        
        if match1 and match2:
            val1, unit1 = float(match1.group(1)), match1.group(2).lower()
            val2, unit2 = float(match2.group(1)), match2.group(2).lower()
            
            # Unit conversion
            conversions = {
                ('oz', 'ml'): 29.5735,
                ('ml', 'oz'): 0.033814,
                ('lb', 'kg'): 0.453592,
                ('kg', 'lb'): 2.20462,
                ('in', 'cm'): 2.54,
                ('cm', 'in'): 0.393701
            }
            
            if unit1 == unit2:
                return abs(val1 - val2) < 0.1
            elif (unit1, unit2) in conversions:
                converted_val1 = val1 * conversions[(unit1, unit2)]
                return abs(converted_val1 - val2) < 0.1
        
        return False
    
    def _match_price(self, price1: float, price2: float, tolerance: float = 0.1) -> bool:
        """Check if prices are within tolerance"""
        if price1 == 0 or price2 == 0:
            return False
        
        price_diff = abs(price1 - price2) / max(price1, price2)
        return price_diff <= tolerance
    
    def _calculate_name_similarity(self, name1: str, name2: str) -> float:
        """Calculate similarity between product names"""
        # Simple word overlap similarity
        words1 = set(name1.lower().split())
        words2 = set(name2.lower().split())
        
        if not words1 or not words2:
            return 0.0
        
        intersection = words1 & words2
        union = words1 | words2
        
        return len(intersection) / len(union)
    
    def _merge_candidates(
        self,
        candidates: List[DuplicateCandidate],
        products_df: pd.DataFrame
    ) -> List[DuplicateCandidate]:
        """Merge and deduplicate candidates"""
        # Group by product pair
        pair_map = defaultdict(list)
        
        for candidate in candidates:
            # Ensure consistent ordering
            key = tuple(sorted([candidate.sku1, candidate.sku2]))
            pair_map[key].append(candidate)
        
        # Merge information for each pair
        final_candidates = []
        
        for (sku1, sku2), pair_candidates in pair_map.items():
            # Combine all matching attributes
            all_matches = {}
            reasons = []
            
            for candidate in pair_candidates:
                all_matches.update(candidate.matching_attributes)
                reasons.append(candidate.reason)
            
            # Calculate final confidence
            max_similarity = max(c.similarity_score for c in pair_candidates)
            confidence_boost = len(set(reasons)) * 0.1  # Boost for multiple strategies
            final_confidence = min(max_similarity + confidence_boost, 1.0)
            
            final_candidates.append(DuplicateCandidate(
                sku1=sku1,
                sku2=sku2,
                similarity_score=max_similarity,
                matching_attributes=all_matches,
                confidence=final_confidence,
                reason="; ".join(set(reasons))
            ))
        
        # Sort by confidence
        final_candidates.sort(key=lambda x: x.confidence, reverse=True)
        
        return final_candidates
    
    def group_duplicates(
        self,
        candidates: List[DuplicateCandidate],
        min_confidence: float = 0.85
    ) -> List[Set[str]]:
        """Group duplicates into clusters using graph connectivity"""
        # Filter by confidence
        high_confidence = [c for c in candidates if c.confidence >= min_confidence]
        
        # Build adjacency graph
        graph = defaultdict(set)
        for candidate in high_confidence:
            graph[candidate.sku1].add(candidate.sku2)
            graph[candidate.sku2].add(candidate.sku1)
        
        # Find connected components
        visited = set()
        groups = []
        
        def dfs(node: str, group: Set[str]):
            if node in visited:
                return
            visited.add(node)
            group.add(node)
            for neighbor in graph[node]:
                dfs(neighbor, group)
        
        for node in graph:
            if node not in visited:
                group = set()
                dfs(node, group)
                groups.append(group)
        
        return groups