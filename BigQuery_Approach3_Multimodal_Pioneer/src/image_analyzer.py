"""
Advanced Image Analysis for E-commerce Products
Extracts attributes, validates quality, and detects compliance issues
"""

import pandas as pd
import numpy as np
from typing import Dict, List, Optional, Tuple, Any
from dataclasses import dataclass
from datetime import datetime
import re
import json
import logging

logger = logging.getLogger(__name__)


@dataclass
class ImageAttribute:
    """Detected attribute from image"""
    attribute_type: str
    value: str
    confidence: float
    bounding_box: Optional[Dict[str, float]] = None


@dataclass 
class ComplianceIssue:
    """Compliance issue detected in image"""
    issue_type: str
    severity: str  # 'critical', 'major', 'minor'
    description: str
    regulation: Optional[str] = None
    fix_suggestion: str = ""


class ImageAttributeExtractor:
    """
    Extract structured attributes from product images
    """
    
    def __init__(self):
        # Color mapping for standardization
        self.color_mappings = {
            'red': ['crimson', 'scarlet', 'ruby', 'cherry', 'burgundy', 'maroon'],
            'blue': ['navy', 'azure', 'cobalt', 'royal', 'sky', 'teal', 'turquoise'],
            'green': ['emerald', 'forest', 'lime', 'olive', 'sage', 'mint'],
            'black': ['charcoal', 'ebony', 'onyx', 'jet'],
            'white': ['ivory', 'cream', 'pearl', 'snow'],
            'brown': ['chocolate', 'coffee', 'tan', 'beige', 'khaki'],
            'gray': ['grey', 'silver', 'charcoal', 'slate'],
            'pink': ['rose', 'fuchsia', 'magenta', 'blush'],
            'yellow': ['gold', 'amber', 'mustard', 'lemon'],
            'orange': ['coral', 'peach', 'tangerine', 'rust'],
            'purple': ['violet', 'lavender', 'plum', 'mauve']
        }
        
        # Size indicators
        self.size_indicators = {
            'clothing': {
                'patterns': [r'\b(XS|S|M|L|XL|XXL|XXXL)\b', r'\b\d{1,2}[/-]\d{1,2}\b'],
                'keywords': ['small', 'medium', 'large', 'extra large', 'petite', 'plus']
            },
            'shoes': {
                'patterns': [r'\b\d{1,2}\.?\d?\b', r'\bEU\s*\d{2}\b', r'\bUK\s*\d{1,2}\b'],
                'keywords': ['narrow', 'wide', 'regular']
            },
            'electronics': {
                'patterns': [r'\d+["\']\s*(inch|in)', r'\d+\s*(gb|tb|mb)', r'\d+\s*mm'],
                'keywords': ['compact', 'mini', 'standard', 'pro', 'max']
            }
        }
        
    def extract_colors(self, image_analysis: Dict[str, Any]) -> List[ImageAttribute]:
        """Extract and standardize color attributes"""
        attributes = []
        
        detected_colors = image_analysis.get('detected_colors', [])
        
        for idx, color in enumerate(detected_colors[:3]):  # Top 3 colors
            standardized_color = self._standardize_color(color)
            
            # Primary color gets higher confidence
            confidence = 0.9 if idx == 0 else (0.8 - idx * 0.1)
            
            attributes.append(ImageAttribute(
                attribute_type='color',
                value=standardized_color,
                confidence=confidence
            ))
        
        return attributes
    
    def extract_text_attributes(self, image_analysis: Dict[str, Any], category: str) -> List[ImageAttribute]:
        """Extract attributes from visible text in image"""
        attributes = []
        
        detected_text = image_analysis.get('detected_text', '')
        if not detected_text:
            return attributes
        
        # Extract brand names
        brand_pattern = r'\b[A-Z][A-Za-z]+(?:\s+[A-Z][A-Za-z]+)*\b'
        potential_brands = re.findall(brand_pattern, detected_text)
        
        for brand in potential_brands[:2]:  # Top 2 potential brands
            if len(brand) > 3:  # Filter out small words
                attributes.append(ImageAttribute(
                    attribute_type='brand',
                    value=brand,
                    confidence=0.7
                ))
        
        # Extract sizes based on category
        if category in self.size_indicators:
            for pattern in self.size_indicators[category]['patterns']:
                sizes = re.findall(pattern, detected_text, re.IGNORECASE)
                for size in sizes:
                    attributes.append(ImageAttribute(
                        attribute_type='size',
                        value=size.upper(),
                        confidence=0.8
                    ))
        
        # Extract model numbers
        model_patterns = [
            r'\b[A-Z]{2,4}[-\s]?\d{3,6}\b',  # ABC-1234
            r'\b\d{2,4}[A-Z]{2,4}\b',         # 123ABC
            r'\bModel:?\s*([A-Za-z0-9-]+)\b'  # Model: XYZ
        ]
        
        for pattern in model_patterns:
            models = re.findall(pattern, detected_text)
            for model in models:
                attributes.append(ImageAttribute(
                    attribute_type='model_number',
                    value=model,
                    confidence=0.75
                ))
        
        return attributes
    
    def extract_material_textures(self, image_analysis: Dict[str, Any]) -> List[ImageAttribute]:
        """Extract material and texture information"""
        attributes = []
        
        # Materials that might be detected visually
        visual_materials = {
            'leather': ['smooth', 'textured', 'glossy'],
            'fabric': ['woven', 'knit', 'mesh'],
            'metal': ['shiny', 'matte', 'brushed'],
            'plastic': ['glossy', 'matte', 'transparent'],
            'wood': ['grain', 'polished', 'natural']
        }
        
        detected_textures = image_analysis.get('detected_textures', [])
        
        for texture in detected_textures:
            # Map texture to material
            for material, indicators in visual_materials.items():
                if any(indicator in texture.lower() for indicator in indicators):
                    attributes.append(ImageAttribute(
                        attribute_type='material',
                        value=material,
                        confidence=0.6
                    ))
                    break
        
        return attributes
    
    def _standardize_color(self, color: str) -> str:
        """Standardize color names to primary categories"""
        color_lower = color.lower()
        
        for primary_color, variations in self.color_mappings.items():
            if color_lower == primary_color or color_lower in variations:
                return primary_color
        
        # Check if color contains primary color name
        for primary_color in self.color_mappings.keys():
            if primary_color in color_lower:
                return primary_color
        
        return color  # Return original if no mapping found


class ComplianceChecker:
    """
    Check products for compliance with regulations
    """
    
    def __init__(self):
        self.compliance_rules = {
            'food': {
                'required_labels': ['ingredients', 'nutrition facts', 'allergens', 'expiry date'],
                'certifications': ['FDA', 'USDA', 'organic', 'non-GMO'],
                'warnings': ['contains', 'may contain', 'allergen']
            },
            'cosmetics': {
                'required_labels': ['ingredients', 'usage instructions', 'warnings'],
                'certifications': ['cruelty-free', 'vegan', 'dermatologist tested'],
                'warnings': ['external use only', 'patch test', 'discontinue if']
            },
            'electronics': {
                'required_labels': ['CE mark', 'FCC', 'voltage', 'model number'],
                'certifications': ['UL', 'Energy Star', 'RoHS'],
                'warnings': ['electrical hazard', 'choking hazard', 'battery warning']
            },
            'toys': {
                'required_labels': ['age recommendation', 'choking hazard', 'CE mark'],
                'certifications': ['CPSC', 'ASTM', 'EN71'],
                'warnings': ['small parts', 'adult supervision', 'not suitable for']
            },
            'textiles': {
                'required_labels': ['care instructions', 'fiber content', 'country of origin'],
                'certifications': ['OEKO-TEX', 'GOTS', 'Fair Trade'],
                'warnings': ['flammability', 'color fastness']
            }
        }
        
    def check_compliance(self, image_analysis: Dict[str, Any], category: str) -> List[ComplianceIssue]:
        """Check if product image meets compliance requirements"""
        issues = []
        
        if category not in self.compliance_rules:
            return issues
        
        rules = self.compliance_rules[category]
        detected_labels = image_analysis.get('compliance_labels', [])
        detected_text = image_analysis.get('detected_text', '').lower()
        
        # Check required labels
        for required_label in rules['required_labels']:
            if not any(required_label in label.lower() for label in detected_labels):
                # Also check in general text
                if required_label not in detected_text:
                    issues.append(ComplianceIssue(
                        issue_type='missing_required_label',
                        severity='critical',
                        description=f"Missing required label: {required_label}",
                        regulation=self._get_regulation(category, required_label),
                        fix_suggestion=f"Add {required_label} to product packaging or image"
                    ))
        
        # Check for any certifications
        found_certifications = []
        for cert in rules['certifications']:
            if cert.lower() in detected_text or any(cert.lower() in label.lower() for label in detected_labels):
                found_certifications.append(cert)
        
        if not found_certifications and category in ['food', 'cosmetics']:
            issues.append(ComplianceIssue(
                issue_type='no_certifications',
                severity='major',
                description='No certifications visible on product',
                fix_suggestion='Consider adding relevant certifications to build trust'
            ))
        
        # Check warnings visibility
        warnings_found = False
        for warning in rules['warnings']:
            if warning in detected_text:
                warnings_found = True
                break
        
        if not warnings_found and category in ['toys', 'electronics']:
            issues.append(ComplianceIssue(
                issue_type='missing_warnings',
                severity='major',
                description='Required safety warnings not visible',
                regulation='CPSC requirements',
                fix_suggestion='Ensure safety warnings are clearly visible in main product image'
            ))
        
        # Image quality for compliance
        quality_score = float(image_analysis.get('image_quality_score', 0))
        if quality_score < 0.6:
            issues.append(ComplianceIssue(
                issue_type='poor_label_visibility',
                severity='major',
                description='Image quality too low to verify compliance labels',
                fix_suggestion='Upload higher resolution images with clear label visibility'
            ))
        
        return issues
    
    def check_brand_guidelines(self, image_analysis: Dict[str, Any], brand_guidelines: Dict[str, Any]) -> List[ComplianceIssue]:
        """Check if image meets brand guidelines"""
        issues = []
        
        # Logo placement
        if 'logo_position' in brand_guidelines:
            expected_position = brand_guidelines['logo_position']
            brand_visible = image_analysis.get('brand_visibility', False)
            
            if not brand_visible:
                issues.append(ComplianceIssue(
                    issue_type='brand_not_visible',
                    severity='major',
                    description='Brand logo not visible in image',
                    fix_suggestion=f"Place brand logo in {expected_position} corner as per guidelines"
                ))
        
        # Background color
        if 'background_color' in brand_guidelines:
            primary_color = image_analysis.get('detected_colors', [''])[0]
            if primary_color.lower() != brand_guidelines['background_color'].lower():
                issues.append(ComplianceIssue(
                    issue_type='incorrect_background',
                    severity='minor',
                    description=f"Background color {primary_color} doesn't match brand guideline {brand_guidelines['background_color']}",
                    fix_suggestion='Use approved brand background color for consistency'
                ))
        
        return issues
    
    def _get_regulation(self, category: str, label_type: str) -> str:
        """Get relevant regulation for missing label"""
        regulations = {
            'food': {
                'ingredients': 'FDA 21 CFR 101.4',
                'nutrition facts': 'FDA Nutrition Labeling',
                'allergens': 'FALCPA',
                'expiry date': 'FDA Food Code'
            },
            'cosmetics': {
                'ingredients': 'FDA Fair Packaging and Labeling Act',
                'warnings': 'FDA Cosmetic Labeling'
            },
            'electronics': {
                'CE mark': 'EU Directive 2014/30/EU',
                'FCC': 'FCC Part 15',
                'voltage': 'IEC 60950-1'
            },
            'toys': {
                'age recommendation': 'CPSC 16 CFR Part 1500',
                'choking hazard': 'CPSIA Section 104'
            }
        }
        
        return regulations.get(category, {}).get(label_type, 'Industry Standard')


class QualityAnalyzer:
    """
    Analyze image quality for e-commerce suitability
    """
    
    def __init__(self):
        self.quality_criteria = {
            'resolution': {
                'min_width': 800,
                'min_height': 800,
                'optimal_width': 1500,
                'optimal_height': 1500
            },
            'composition': {
                'product_coverage': 0.7,  # Product should cover 70% of image
                'centered': True,
                'multiple_angles': False
            },
            'lighting': {
                'brightness_range': (0.3, 0.8),
                'contrast_range': (0.4, 0.7),
                'no_shadows': True
            },
            'background': {
                'preferred': 'white',
                'acceptable': ['white', 'light gray', 'neutral']
            }
        }
        
    def analyze_quality(self, image_analysis: Dict[str, Any]) -> Dict[str, Any]:
        """Comprehensive quality analysis"""
        quality_report = {
            'overall_score': 0.0,
            'issues': [],
            'recommendations': [],
            'metrics': {}
        }
        
        # Basic quality score from AI
        ai_quality = float(image_analysis.get('image_quality_score', 0))
        quality_report['metrics']['ai_quality_score'] = ai_quality
        
        # Resolution check (simplified - would need actual dimensions)
        resolution_score = self._check_resolution(image_analysis)
        quality_report['metrics']['resolution_score'] = resolution_score
        
        # Lighting quality
        lighting_score = self._check_lighting(image_analysis)
        quality_report['metrics']['lighting_score'] = lighting_score
        
        # Background quality
        background_score = self._check_background(image_analysis)
        quality_report['metrics']['background_score'] = background_score
        
        # Calculate overall score
        quality_report['overall_score'] = np.mean([
            ai_quality,
            resolution_score,
            lighting_score,
            background_score
        ])
        
        # Generate issues and recommendations
        if resolution_score < 0.7:
            quality_report['issues'].append('Low resolution image')
            quality_report['recommendations'].append('Upload images at least 800x800 pixels')
        
        if lighting_score < 0.7:
            quality_report['issues'].append('Poor lighting quality')
            quality_report['recommendations'].append('Use bright, even lighting without harsh shadows')
        
        if background_score < 0.7:
            quality_report['issues'].append('Distracting background')
            quality_report['recommendations'].append('Use plain white or neutral background')
        
        # E-commerce specific checks
        if image_analysis.get('product_condition') == 'used':
            quality_report['issues'].append('Product appears used or damaged')
            quality_report['recommendations'].append('Photograph new/pristine products only')
        
        if not image_analysis.get('brand_visibility'):
            quality_report['recommendations'].append('Ensure brand logo is visible for authenticity')
        
        return quality_report
    
    def _check_resolution(self, image_analysis: Dict[str, Any]) -> float:
        """Check image resolution quality"""
        # Simplified - would need actual image dimensions
        # Using quality score as proxy
        quality = float(image_analysis.get('image_quality_score', 0))
        
        if quality >= 0.8:
            return 1.0
        elif quality >= 0.6:
            return 0.8
        elif quality >= 0.4:
            return 0.6
        else:
            return 0.4
    
    def _check_lighting(self, image_analysis: Dict[str, Any]) -> float:
        """Check lighting quality"""
        # Look for shadow indicators in analysis
        detected_text = image_analysis.get('detected_text', '').lower()
        full_analysis = image_analysis.get('full_analysis', '').lower()
        
        shadow_indicators = ['shadow', 'dark', 'dim', 'underexposed', 'overexposed']
        has_shadows = any(indicator in full_analysis for indicator in shadow_indicators)
        
        base_score = float(image_analysis.get('image_quality_score', 0.5))
        
        if has_shadows:
            return base_score * 0.7
        else:
            return min(base_score * 1.2, 1.0)
    
    def _check_background(self, image_analysis: Dict[str, Any]) -> float:
        """Check background quality"""
        detected_colors = image_analysis.get('detected_colors', [])
        
        if not detected_colors:
            return 0.5
        
        # Check if background is neutral
        acceptable_backgrounds = ['white', 'gray', 'grey', 'beige', 'cream']
        
        # Assuming last color is often background
        background_color = detected_colors[-1].lower() if len(detected_colors) > 1 else detected_colors[0].lower()
        
        if any(color in background_color for color in acceptable_backgrounds):
            return 1.0
        elif any(color in background_color for color in ['black', 'dark']):
            return 0.7
        else:
            return 0.5


# Helper functions
def parse_image_analysis_json(analysis_text: str) -> Dict[str, Any]:
    """Parse AI-generated analysis JSON"""
    try:
        return json.loads(analysis_text)
    except json.JSONDecodeError:
        # Fallback parsing for non-JSON responses
        logger.warning("Failed to parse as JSON, using fallback parser")
        return {
            'detected_colors': re.findall(r'color[s]?:\s*([a-zA-Z]+)', analysis_text, re.IGNORECASE),
            'detected_text': re.findall(r'text:\s*(.+)', analysis_text),
            'image_quality_score': 0.5,
            'brand_visibility': 'brand' in analysis_text.lower()
        }


def aggregate_attributes(attributes: List[ImageAttribute]) -> Dict[str, List[str]]:
    """Aggregate attributes by type"""
    aggregated = {}
    
    for attr in attributes:
        if attr.attribute_type not in aggregated:
            aggregated[attr.attribute_type] = []
        
        # Add if confidence is high enough and not duplicate
        if attr.confidence >= 0.6 and attr.value not in aggregated[attr.attribute_type]:
            aggregated[attr.attribute_type].append(attr.value)
    
    return aggregated