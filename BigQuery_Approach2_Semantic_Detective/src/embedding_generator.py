"""
Embedding Generation with Template-Driven Text Preparation
Optimized for e-commerce product matching
"""

from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass
import logging
import re

logger = logging.getLogger(__name__)


@dataclass
class EmbeddingTemplate:
    """Template for generating consistent embeddings"""
    name: str
    pattern: str
    fields: List[str]
    weights: Dict[str, float]
    preprocessing: Dict[str, str]


class EmbeddingGenerator:
    """
    Generate optimized embeddings for product matching.
    Uses templates to ensure consistent text preparation.
    """
    
    def __init__(self):
        # Define embedding templates for different use cases
        self.templates = {
            'full_product': EmbeddingTemplate(
                name='full_product',
                pattern='{brand} {name} {category} {subcategory} {description} {attributes}',
                fields=['brand_name', 'product_name', 'category', 'subcategory', 
                       'description', 'color', 'size', 'material'],
                weights={
                    'brand_name': 0.20,
                    'product_name': 0.25,
                    'category': 0.15,
                    'description': 0.20,
                    'attributes': 0.20
                },
                preprocessing={
                    'normalize_case': 'lower',
                    'remove_special_chars': True,
                    'expand_abbreviations': True
                }
            ),
            
            'title_focused': EmbeddingTemplate(
                name='title_focused',
                pattern='{brand} {name} {key_features}',
                fields=['brand_name', 'product_name', 'color', 'size'],
                weights={
                    'brand_name': 0.35,
                    'product_name': 0.50,
                    'key_features': 0.15
                },
                preprocessing={
                    'normalize_case': 'lower',
                    'remove_model_numbers': False,
                    'preserve_identifiers': True
                }
            ),
            
            'attribute_focused': EmbeddingTemplate(
                name='attribute_focused',
                pattern='{size} {color} {material} {features} {specs}',
                fields=['size', 'color', 'material', 'weight', 'dimensions'],
                weights={
                    'size': 0.25,
                    'color': 0.25,
                    'material': 0.25,
                    'specs': 0.25
                },
                preprocessing={
                    'standardize_units': True,
                    'normalize_colors': True,
                    'normalize_sizes': True
                }
            ),
            
            'search_optimized': EmbeddingTemplate(
                name='search_optimized',
                pattern='{name} {brand} {category} {key_terms}',
                fields=['product_name', 'brand_name', 'category', 'search_keywords'],
                weights={
                    'product_name': 0.40,
                    'brand_name': 0.20,
                    'category': 0.20,
                    'key_terms': 0.20
                },
                preprocessing={
                    'extract_keywords': True,
                    'remove_stopwords': True,
                    'stem_words': False
                }
            )
        }
        
        # Common abbreviations in e-commerce
        self.abbreviations = {
            'sz': 'size',
            'lg': 'large',
            'sm': 'small',
            'med': 'medium',
            'xl': 'extra large',
            'xxl': 'extra extra large',
            'blk': 'black',
            'wht': 'white',
            'pcs': 'pieces',
            'qty': 'quantity',
            'desc': 'description',
            'mfr': 'manufacturer',
            'orig': 'original'
        }
        
        # Size normalization mappings
        self.size_mappings = {
            'small': ['s', 'sm', 'small'],
            'medium': ['m', 'med', 'medium'],
            'large': ['l', 'lg', 'large'],
            'x-large': ['xl', 'x-large', 'extra large'],
            'xx-large': ['xxl', 'xx-large', 'extra extra large']
        }
        
        # Color normalization
        self.color_mappings = {
            'black': ['blk', 'black', 'negro', 'noir'],
            'white': ['wht', 'white', 'blanco', 'blanc'],
            'red': ['red', 'rojo', 'rouge'],
            'blue': ['blu', 'blue', 'azul', 'bleu'],
            'green': ['grn', 'green', 'verde', 'vert']
        }
    
    def prepare_embedding_text(
        self,
        product_data: Dict[str, any],
        template_name: str = 'full_product'
    ) -> str:
        """
        Prepare product text for embedding generation using templates
        """
        template = self.templates.get(template_name)
        if not template:
            raise ValueError(f"Unknown template: {template_name}")
        
        # Extract and preprocess fields
        processed_fields = {}
        for field in template.fields:
            value = product_data.get(field, '')
            if value:
                processed_value = self._preprocess_field(
                    str(value),
                    field,
                    template.preprocessing
                )
                processed_fields[field] = processed_value
        
        # Build text according to template pattern
        embedding_text = self._build_from_template(
            template.pattern,
            processed_fields,
            product_data
        )
        
        # Clean up final text
        embedding_text = self._final_cleanup(embedding_text)
        
        return embedding_text
    
    def generate_multi_aspect_embeddings(
        self,
        product_data: Dict[str, any]
    ) -> Dict[str, str]:
        """
        Generate multiple embedding texts for different aspects
        """
        embeddings = {}
        
        # Generate embedding text for each template
        for template_name in self.templates:
            try:
                embedding_text = self.prepare_embedding_text(
                    product_data,
                    template_name
                )
                embeddings[template_name] = embedding_text
            except Exception as e:
                logger.warning(f"Failed to generate {template_name} embedding: {str(e)}")
                embeddings[template_name] = ""
        
        return embeddings
    
    def _preprocess_field(
        self,
        value: str,
        field_name: str,
        preprocessing_rules: Dict[str, any]
    ) -> str:
        """Apply preprocessing rules to a field value"""
        
        # Case normalization
        if preprocessing_rules.get('normalize_case') == 'lower':
            value = value.lower()
        elif preprocessing_rules.get('normalize_case') == 'upper':
            value = value.upper()
        
        # Expand abbreviations
        if preprocessing_rules.get('expand_abbreviations'):
            value = self._expand_abbreviations(value)
        
        # Remove special characters
        if preprocessing_rules.get('remove_special_chars'):
            value = re.sub(r'[^\w\s-]', ' ', value)
        
        # Field-specific preprocessing
        if field_name == 'size' and preprocessing_rules.get('normalize_sizes'):
            value = self._normalize_size(value)
        elif field_name == 'color' and preprocessing_rules.get('normalize_colors'):
            value = self._normalize_color(value)
        elif field_name == 'price':
            value = self._normalize_price(value)
        
        # Standardize units
        if preprocessing_rules.get('standardize_units'):
            value = self._standardize_units(value)
        
        # Extract keywords
        if preprocessing_rules.get('extract_keywords'):
            value = self._extract_keywords(value)
        
        return value.strip()
    
    def _expand_abbreviations(self, text: str) -> str:
        """Expand common abbreviations"""
        words = text.split()
        expanded_words = []
        
        for word in words:
            word_lower = word.lower()
            if word_lower in self.abbreviations:
                expanded_words.append(self.abbreviations[word_lower])
            else:
                expanded_words.append(word)
        
        return ' '.join(expanded_words)
    
    def _normalize_size(self, size: str) -> str:
        """Normalize size values"""
        size_lower = size.lower().strip()
        
        # Check size mappings
        for normalized, variations in self.size_mappings.items():
            if size_lower in variations:
                return normalized
        
        # Extract numeric sizes
        numeric_match = re.match(r'(\d+(?:\.\d+)?)\s*([a-zA-Z]*)', size)
        if numeric_match:
            value = numeric_match.group(1)
            unit = numeric_match.group(2)
            return f"{value} {unit}".strip()
        
        return size
    
    def _normalize_color(self, color: str) -> str:
        """Normalize color values"""
        color_lower = color.lower().strip()
        
        # Check color mappings
        for normalized, variations in self.color_mappings.items():
            if color_lower in variations:
                return normalized
        
        # Handle multi-word colors
        color_parts = color_lower.split()
        normalized_parts = []
        
        for part in color_parts:
            for normalized, variations in self.color_mappings.items():
                if part in variations:
                    normalized_parts.append(normalized)
                    break
            else:
                normalized_parts.append(part)
        
        return ' '.join(normalized_parts)
    
    def _normalize_price(self, price: any) -> str:
        """Normalize price representation"""
        try:
            price_float = float(price)
            # Round to reasonable precision
            if price_float < 10:
                return f"${price_float:.2f}"
            elif price_float < 100:
                return f"${price_float:.0f}"
            else:
                return f"${price_float:.0f} expensive"
        except:
            return str(price)
    
    def _standardize_units(self, text: str) -> str:
        """Standardize measurement units"""
        # Weight units
        text = re.sub(r'\b(\d+)\s*lbs?\b', r'\1 pounds', text, flags=re.IGNORECASE)
        text = re.sub(r'\b(\d+)\s*oz\b', r'\1 ounces', text, flags=re.IGNORECASE)
        text = re.sub(r'\b(\d+)\s*kgs?\b', r'\1 kilograms', text, flags=re.IGNORECASE)
        
        # Length units
        text = re.sub(r'\b(\d+)\s*in\b', r'\1 inches', text, flags=re.IGNORECASE)
        text = re.sub(r'\b(\d+)\s*ft\b', r'\1 feet', text, flags=re.IGNORECASE)
        text = re.sub(r'\b(\d+)\s*cm\b', r'\1 centimeters', text, flags=re.IGNORECASE)
        
        return text
    
    def _extract_keywords(self, text: str) -> str:
        """Extract important keywords from text"""
        # Remove common stopwords
        stopwords = {
            'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
            'of', 'with', 'by', 'from', 'as', 'is', 'was', 'are', 'were'
        }
        
        words = text.lower().split()
        keywords = [w for w in words if w not in stopwords and len(w) > 2]
        
        return ' '.join(keywords)
    
    def _build_from_template(
        self,
        pattern: str,
        processed_fields: Dict[str, str],
        raw_data: Dict[str, any]
    ) -> str:
        """Build text from template pattern"""
        text = pattern
        
        # Replace placeholders
        text = text.format(**{
            'brand': processed_fields.get('brand_name', ''),
            'name': processed_fields.get('product_name', ''),
            'category': processed_fields.get('category', ''),
            'subcategory': processed_fields.get('subcategory', ''),
            'description': processed_fields.get('description', ''),
            'size': processed_fields.get('size', ''),
            'color': processed_fields.get('color', ''),
            'material': processed_fields.get('material', ''),
            'attributes': self._combine_attributes(processed_fields),
            'key_features': self._extract_key_features(processed_fields),
            'specs': self._combine_specs(processed_fields),
            'key_terms': self._extract_key_terms(raw_data)
        })
        
        return text
    
    def _combine_attributes(self, fields: Dict[str, str]) -> str:
        """Combine attribute fields"""
        attributes = []
        for attr in ['color', 'size', 'material', 'weight']:
            if attr in fields and fields[attr]:
                attributes.append(fields[attr])
        return ' '.join(attributes)
    
    def _extract_key_features(self, fields: Dict[str, str]) -> str:
        """Extract key features from fields"""
        features = []
        
        # Extract features from description
        if 'description' in fields:
            desc = fields['description']
            # Look for feature indicators
            feature_patterns = [
                r'features?\s+([^.]+)',
                r'includes?\s+([^.]+)',
                r'with\s+([^.]+)'
            ]
            
            for pattern in feature_patterns:
                matches = re.findall(pattern, desc, re.IGNORECASE)
                features.extend(matches)
        
        return ' '.join(features[:3])  # Limit to top 3 features
    
    def _combine_specs(self, fields: Dict[str, str]) -> str:
        """Combine specification fields"""
        specs = []
        for spec in ['weight', 'dimensions', 'capacity', 'power']:
            if spec in fields and fields[spec]:
                specs.append(f"{spec}: {fields[spec]}")
        return ' '.join(specs)
    
    def _extract_key_terms(self, data: Dict[str, any]) -> str:
        """Extract key search terms from product data"""
        key_terms = []
        
        # Extract from search_keywords if available
        if 'search_keywords' in data:
            key_terms.extend(str(data['search_keywords']).split(','))
        
        # Extract from tags
        if 'tags' in data:
            key_terms.extend(str(data['tags']).split(','))
        
        # Clean and deduplicate
        key_terms = [t.strip().lower() for t in key_terms]
        key_terms = list(dict.fromkeys(key_terms))  # Remove duplicates while preserving order
        
        return ' '.join(key_terms[:5])  # Limit to top 5 terms
    
    def _final_cleanup(self, text: str) -> str:
        """Final cleanup of embedding text"""
        # Remove multiple spaces
        text = re.sub(r'\s+', ' ', text)
        
        # Remove leading/trailing whitespace
        text = text.strip()
        
        # Remove empty placeholders
        text = re.sub(r'\{\w+\}', '', text)
        
        # Limit length (embeddings work better with reasonable length)
        max_length = 500
        if len(text) > max_length:
            # Try to cut at word boundary
            text = text[:max_length].rsplit(' ', 1)[0] + '...'
        
        return text