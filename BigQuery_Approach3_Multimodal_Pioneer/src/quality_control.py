"""
Automated Quality Control System for E-commerce
Combines image analysis with business rules for comprehensive QC
"""

import pandas as pd
import numpy as np
from typing import Dict, List, Optional, Tuple, Any, Set
from dataclasses import dataclass, field
from datetime import datetime, timedelta
import logging
from enum import Enum

logger = logging.getLogger(__name__)


class QCStatus(Enum):
    """Quality control status levels"""
    PASSED = "passed"
    FAILED = "failed"
    WARNING = "warning"
    PENDING_REVIEW = "pending_review"


@dataclass
class QCRule:
    """Defines a quality control rule"""
    rule_id: str
    name: str
    category: str
    check_type: str  # 'image', 'data', 'compliance', 'consistency'
    severity: str  # 'critical', 'major', 'minor'
    condition: str  # SQL or Python expression
    error_message: str
    auto_fix_available: bool = False
    fix_action: Optional[str] = None


@dataclass
class QCCheckResult:
    """Result of a QC check"""
    sku: str
    rule_id: str
    status: QCStatus
    message: str
    confidence: float
    details: Dict[str, Any] = field(default_factory=dict)
    suggested_fix: Optional[str] = None
    timestamp: datetime = field(default_factory=datetime.now)


@dataclass
class QCReport:
    """Comprehensive QC report for a batch"""
    batch_id: str
    total_products: int
    checks_performed: int
    passed: int
    failed: int
    warnings: int
    critical_issues: List[QCCheckResult]
    auto_fixed: int
    processing_time_ms: float
    summary: Dict[str, Any]


class QualityControlSystem:
    """
    Comprehensive quality control system for e-commerce products
    """
    
    def __init__(self, project_id: str, dataset_id: str):
        self.project_id = project_id
        self.dataset_id = dataset_id
        self.dataset_ref = f"{project_id}.{dataset_id}"
        
        # Initialize QC rules
        self.rules = self._initialize_rules()
        
        # Thresholds
        self.thresholds = {
            'image_quality_min': 0.6,
            'price_variance_max': 0.5,  # 50% variance from category average
            'description_min_length': 50,
            'title_max_length': 80,
            'duplicate_similarity_threshold': 0.95
        }
        
    def _initialize_rules(self) -> Dict[str, QCRule]:
        """Initialize all QC rules"""
        rules = {}
        
        # Image quality rules
        rules['IMG001'] = QCRule(
            rule_id='IMG001',
            name='Minimum Image Quality',
            category='image',
            check_type='image',
            severity='critical',
            condition='quality_score >= 0.6',
            error_message='Image quality below acceptable threshold',
            auto_fix_available=False
        )
        
        rules['IMG002'] = QCRule(
            rule_id='IMG002',
            name='Brand Logo Visibility',
            category='image',
            check_type='image',
            severity='major',
            condition='brand_visible = true OR brand_name IS NULL',
            error_message='Brand logo not visible in image',
            auto_fix_available=False
        )
        
        rules['IMG003'] = QCRule(
            rule_id='IMG003',
            name='Color Accuracy',
            category='image',
            check_type='consistency',
            severity='major',
            condition='listed_color = detected_color OR listed_color IS NULL',
            error_message='Product color does not match listing',
            auto_fix_available=True,
            fix_action='UPDATE color FROM image detection'
        )
        
        # Data completeness rules
        rules['DATA001'] = QCRule(
            rule_id='DATA001',
            name='Required Fields Complete',
            category='data',
            check_type='data',
            severity='critical',
            condition='sku IS NOT NULL AND product_name IS NOT NULL AND price > 0',
            error_message='Missing required product information',
            auto_fix_available=False
        )
        
        rules['DATA002'] = QCRule(
            rule_id='DATA002',
            name='Description Quality',
            category='data',
            check_type='data',
            severity='major',
            condition='LENGTH(description) >= 50',
            error_message='Product description too short',
            auto_fix_available=True,
            fix_action='GENERATE description using AI'
        )
        
        rules['DATA003'] = QCRule(
            rule_id='DATA003',
            name='Price Reasonableness',
            category='data',
            check_type='data',
            severity='major',
            condition='price BETWEEN category_min_price * 0.5 AND category_max_price * 2',
            error_message='Price outside reasonable range for category',
            auto_fix_available=False
        )
        
        # Compliance rules
        rules['COMP001'] = QCRule(
            rule_id='COMP001',
            name='Category Compliance Labels',
            category='compliance',
            check_type='compliance',
            severity='critical',
            condition='compliance_labels_found OR category NOT IN regulated_categories',
            error_message='Missing required compliance labels for regulated category',
            auto_fix_available=False
        )
        
        rules['COMP002'] = QCRule(
            rule_id='COMP002',
            name='Age Restriction Labels',
            category='compliance',
            check_type='compliance',
            severity='critical',
            condition='age_restriction_visible OR category != "toys"',
            error_message='Missing age restriction label for toy products',
            auto_fix_available=False
        )
        
        # Consistency rules
        rules['CONS001'] = QCRule(
            rule_id='CONS001',
            name='No Duplicate SKUs',
            category='consistency',
            check_type='consistency',
            severity='critical',
            condition='duplicate_count = 0',
            error_message='Duplicate SKU detected',
            auto_fix_available=True,
            fix_action='MERGE duplicate products'
        )
        
        rules['CONS002'] = QCRule(
            rule_id='CONS002',
            name='Brand Name Consistency',
            category='consistency',
            check_type='consistency',
            severity='minor',
            condition='brand_name = standardized_brand',
            error_message='Brand name not standardized',
            auto_fix_available=True,
            fix_action='UPDATE to standardized brand name'
        )
        
        return rules
    
    def run_comprehensive_qc(self, product_table: str, image_analysis_table: str, batch_size: int = 1000) -> QCReport:
        """
        Run comprehensive quality control checks
        """
        start_time = datetime.now()
        batch_id = f"QC_{start_time.strftime('%Y%m%d_%H%M%S')}"
        
        # Get product count
        count_query = f"SELECT COUNT(*) as count FROM `{self.dataset_ref}.{product_table}`"
        total_products = self._execute_query(count_query).iloc[0]['count']
        
        # Run all QC checks
        all_results = []
        
        # Image quality checks
        image_results = self._run_image_checks(product_table, image_analysis_table)
        all_results.extend(image_results)
        
        # Data completeness checks
        data_results = self._run_data_checks(product_table)
        all_results.extend(data_results)
        
        # Compliance checks
        compliance_results = self._run_compliance_checks(product_table, image_analysis_table)
        all_results.extend(compliance_results)
        
        # Consistency checks
        consistency_results = self._run_consistency_checks(product_table)
        all_results.extend(consistency_results)
        
        # Auto-fix where possible
        auto_fixed_count = self._apply_auto_fixes(all_results, product_table)
        
        # Generate report
        execution_time = (datetime.now() - start_time).total_seconds() * 1000
        
        return self._generate_report(
            batch_id,
            total_products,
            all_results,
            auto_fixed_count,
            execution_time
        )
    
    def _run_image_checks(self, product_table: str, image_analysis_table: str) -> List[QCCheckResult]:
        """Run image quality checks"""
        results = []
        
        query = f"""
        WITH image_checks AS (
            SELECT 
                p.sku,
                p.brand_name,
                p.listed_color,
                a.quality_score,
                a.brand_visible,
                a.primary_color as detected_color,
                a.compliance_labels,
                
                -- Image quality check
                CAST(a.quality_score AS FLOAT64) >= {self.thresholds['image_quality_min']} as img_quality_pass,
                
                -- Brand visibility check
                (a.brand_visible = 'true' OR p.brand_name IS NULL) as brand_check_pass,
                
                -- Color accuracy check
                (LOWER(p.listed_color) = LOWER(a.primary_color) OR p.listed_color IS NULL) as color_check_pass
                
            FROM `{self.dataset_ref}.{product_table}` p
            LEFT JOIN `{self.dataset_ref}.{image_analysis_table}` a
                ON p.sku = a.sku
        )
        SELECT * FROM image_checks
        WHERE NOT img_quality_pass 
            OR NOT brand_check_pass 
            OR NOT color_check_pass
        """
        
        df = self._execute_query(query)
        
        for _, row in df.iterrows():
            # Image quality
            if not row['img_quality_pass']:
                results.append(QCCheckResult(
                    sku=row['sku'],
                    rule_id='IMG001',
                    status=QCStatus.FAILED,
                    message=self.rules['IMG001'].error_message,
                    confidence=0.9,
                    details={'quality_score': row['quality_score']},
                    suggested_fix='Upload higher quality product image'
                ))
            
            # Brand visibility
            if not row['brand_check_pass']:
                results.append(QCCheckResult(
                    sku=row['sku'],
                    rule_id='IMG002',
                    status=QCStatus.WARNING,
                    message=self.rules['IMG002'].error_message,
                    confidence=0.8,
                    details={'brand_name': row['brand_name']},
                    suggested_fix='Ensure brand logo is visible in main image'
                ))
            
            # Color accuracy
            if not row['color_check_pass']:
                results.append(QCCheckResult(
                    sku=row['sku'],
                    rule_id='IMG003',
                    status=QCStatus.WARNING,
                    message=self.rules['IMG003'].error_message,
                    confidence=0.85,
                    details={
                        'listed_color': row['listed_color'],
                        'detected_color': row['detected_color']
                    },
                    suggested_fix=f"Update color to: {row['detected_color']}"
                ))
        
        return results
    
    def _run_data_checks(self, product_table: str) -> List[QCCheckResult]:
        """Run data quality checks"""
        results = []
        
        query = f"""
        WITH data_checks AS (
            SELECT 
                p.*,
                LENGTH(p.description) as desc_length,
                AVG(p.price) OVER (PARTITION BY p.category) as category_avg_price,
                MIN(p.price) OVER (PARTITION BY p.category) as category_min_price,
                MAX(p.price) OVER (PARTITION BY p.category) as category_max_price,
                
                -- Required fields check
                (p.sku IS NOT NULL AND p.product_name IS NOT NULL AND p.price > 0) as required_fields_pass,
                
                -- Description quality
                LENGTH(p.description) >= {self.thresholds['description_min_length']} as desc_quality_pass,
                
                -- Price reasonableness
                p.price BETWEEN 
                    AVG(p.price) OVER (PARTITION BY p.category) * (1 - {self.thresholds['price_variance_max']})
                    AND AVG(p.price) OVER (PARTITION BY p.category) * (1 + {self.thresholds['price_variance_max']})
                as price_reasonable
                
            FROM `{self.dataset_ref}.{product_table}` p
        )
        SELECT * FROM data_checks
        WHERE NOT required_fields_pass 
            OR NOT desc_quality_pass 
            OR NOT price_reasonable
        """
        
        df = self._execute_query(query)
        
        for _, row in df.iterrows():
            # Required fields
            if not row['required_fields_pass']:
                results.append(QCCheckResult(
                    sku=row.get('sku', 'UNKNOWN'),
                    rule_id='DATA001',
                    status=QCStatus.FAILED,
                    message=self.rules['DATA001'].error_message,
                    confidence=1.0,
                    details={
                        'missing_fields': [
                            field for field in ['sku', 'product_name', 'price']
                            if not row.get(field) or (field == 'price' and row.get(field, 0) <= 0)
                        ]
                    }
                ))
            
            # Description quality
            if not row['desc_quality_pass']:
                results.append(QCCheckResult(
                    sku=row['sku'],
                    rule_id='DATA002',
                    status=QCStatus.WARNING,
                    message=self.rules['DATA002'].error_message,
                    confidence=1.0,
                    details={
                        'description_length': row['desc_length'],
                        'minimum_required': self.thresholds['description_min_length']
                    },
                    suggested_fix='Generate expanded description using AI'
                ))
            
            # Price reasonableness
            if not row['price_reasonable']:
                results.append(QCCheckResult(
                    sku=row['sku'],
                    rule_id='DATA003',
                    status=QCStatus.WARNING,
                    message=self.rules['DATA003'].error_message,
                    confidence=0.9,
                    details={
                        'price': row['price'],
                        'category_avg': row['category_avg_price'],
                        'variance': abs(row['price'] - row['category_avg_price']) / row['category_avg_price']
                    },
                    suggested_fix='Review pricing against category benchmarks'
                ))
        
        return results
    
    def _run_compliance_checks(self, product_table: str, image_analysis_table: str) -> List[QCCheckResult]:
        """Run compliance checks"""
        results = []
        
        regulated_categories = ['food', 'cosmetics', 'electronics', 'toys', 'baby_products']
        
        query = f"""
        WITH compliance_checks AS (
            SELECT 
                p.sku,
                p.category,
                p.subcategory,
                a.compliance_labels,
                a.detected_text,
                
                -- Check if regulated category
                p.category IN ({','.join([f"'{cat}'" for cat in regulated_categories])}) as is_regulated,
                
                -- Check compliance labels
                ARRAY_LENGTH(a.compliance_labels) > 0 as has_compliance_labels,
                
                -- Age restriction for toys
                (p.category = 'toys' AND a.detected_text LIKE '%age%') as has_age_restriction
                
            FROM `{self.dataset_ref}.{product_table}` p
            LEFT JOIN `{self.dataset_ref}.{image_analysis_table}` a
                ON p.sku = a.sku
        )
        SELECT * FROM compliance_checks
        WHERE (is_regulated AND NOT has_compliance_labels)
            OR (category = 'toys' AND NOT has_age_restriction)
        """
        
        df = self._execute_query(query)
        
        for _, row in df.iterrows():
            # Regulated category compliance
            if row['is_regulated'] and not row['has_compliance_labels']:
                results.append(QCCheckResult(
                    sku=row['sku'],
                    rule_id='COMP001',
                    status=QCStatus.FAILED,
                    message=self.rules['COMP001'].error_message,
                    confidence=0.95,
                    details={
                        'category': row['category'],
                        'compliance_labels_found': row['compliance_labels'] or []
                    },
                    suggested_fix=f'Add required compliance labels for {row["category"]} products'
                ))
            
            # Age restriction for toys
            if row['category'] == 'toys' and not row['has_age_restriction']:
                results.append(QCCheckResult(
                    sku=row['sku'],
                    rule_id='COMP002',
                    status=QCStatus.FAILED,
                    message=self.rules['COMP002'].error_message,
                    confidence=0.9,
                    details={'category': 'toys'},
                    suggested_fix='Add age restriction label to toy product image'
                ))
        
        return results
    
    def _run_consistency_checks(self, product_table: str) -> List[QCCheckResult]:
        """Run data consistency checks"""
        results = []
        
        # Check for duplicate SKUs
        dup_query = f"""
        WITH duplicate_check AS (
            SELECT 
                sku,
                COUNT(*) as dup_count,
                STRING_AGG(DISTINCT product_name, '; ') as product_names,
                STRING_AGG(DISTINCT CAST(price AS STRING), '; ') as prices
            FROM `{self.dataset_ref}.{product_table}`
            GROUP BY sku
            HAVING COUNT(*) > 1
        )
        SELECT * FROM duplicate_check
        """
        
        dup_df = self._execute_query(dup_query)
        
        for _, row in dup_df.iterrows():
            results.append(QCCheckResult(
                sku=row['sku'],
                rule_id='CONS001',
                status=QCStatus.FAILED,
                message=self.rules['CONS001'].error_message,
                confidence=1.0,
                details={
                    'duplicate_count': row['dup_count'],
                    'product_names': row['product_names'],
                    'prices': row['prices']
                },
                suggested_fix='Merge or differentiate duplicate SKUs'
            ))
        
        # Check brand standardization
        brand_query = f"""
        WITH brand_check AS (
            SELECT 
                p.sku,
                p.brand_name,
                b.standardized_brand,
                p.brand_name != b.standardized_brand as needs_standardization
            FROM `{self.dataset_ref}.{product_table}` p
            LEFT JOIN `{self.dataset_ref}.brand_mapping` b
                ON LOWER(p.brand_name) = LOWER(b.original_brand)
            WHERE p.brand_name IS NOT NULL
                AND b.standardized_brand IS NOT NULL
                AND p.brand_name != b.standardized_brand
        )
        SELECT * FROM brand_check WHERE needs_standardization
        """
        
        brand_df = self._execute_query(brand_query)
        
        for _, row in brand_df.iterrows():
            results.append(QCCheckResult(
                sku=row['sku'],
                rule_id='CONS002',
                status=QCStatus.WARNING,
                message=self.rules['CONS002'].error_message,
                confidence=0.95,
                details={
                    'current_brand': row['brand_name'],
                    'standardized_brand': row['standardized_brand']
                },
                suggested_fix=f"Update brand to: {row['standardized_brand']}"
            ))
        
        return results
    
    def _apply_auto_fixes(self, results: List[QCCheckResult], product_table: str) -> int:
        """Apply automatic fixes where available"""
        fixed_count = 0
        
        # Group fixes by type
        color_fixes = [r for r in results if r.rule_id == 'IMG003' and r.status == QCStatus.WARNING]
        desc_fixes = [r for r in results if r.rule_id == 'DATA002' and r.status == QCStatus.WARNING]
        brand_fixes = [r for r in results if r.rule_id == 'CONS002' and r.status == QCStatus.WARNING]
        
        # Apply color fixes
        if color_fixes:
            color_update = f"""
            UPDATE `{self.dataset_ref}.{product_table}` p
            SET listed_color = a.primary_color
            FROM `{self.dataset_ref}.image_analysis` a
            WHERE p.sku = a.sku
                AND p.sku IN ({','.join([f"'{r.sku}'" for r in color_fixes])})
                AND a.primary_color IS NOT NULL
            """
            self._execute_update(color_update)
            fixed_count += len(color_fixes)
        
        # Note: Other auto-fixes would require AI generation which we simulate
        # In production, these would call AI.GENERATE functions
        
        return fixed_count
    
    def _generate_report(
        self,
        batch_id: str,
        total_products: int,
        results: List[QCCheckResult],
        auto_fixed: int,
        execution_time: float
    ) -> QCReport:
        """Generate comprehensive QC report"""
        
        # Count by status
        status_counts = {
            QCStatus.PASSED: 0,
            QCStatus.FAILED: len([r for r in results if r.status == QCStatus.FAILED]),
            QCStatus.WARNING: len([r for r in results if r.status == QCStatus.WARNING]),
            QCStatus.PENDING_REVIEW: len([r for r in results if r.status == QCStatus.PENDING_REVIEW])
        }
        
        # Products that passed all checks
        failed_skus = set(r.sku for r in results)
        passed_count = total_products - len(failed_skus)
        
        # Critical issues
        critical_issues = [r for r in results if r.rule_id in ['IMG001', 'DATA001', 'COMP001', 'CONS001']]
        
        # Summary by category
        category_summary = {}
        for rule_id, rule in self.rules.items():
            category = rule.category
            if category not in category_summary:
                category_summary[category] = {
                    'total_checks': 0,
                    'failures': 0,
                    'warnings': 0
                }
            
            rule_results = [r for r in results if r.rule_id == rule_id]
            category_summary[category]['total_checks'] += len(rule_results)
            category_summary[category]['failures'] += len([r for r in rule_results if r.status == QCStatus.FAILED])
            category_summary[category]['warnings'] += len([r for r in rule_results if r.status == QCStatus.WARNING])
        
        return QCReport(
            batch_id=batch_id,
            total_products=total_products,
            checks_performed=len(self.rules) * total_products,
            passed=passed_count,
            failed=status_counts[QCStatus.FAILED],
            warnings=status_counts[QCStatus.WARNING],
            critical_issues=critical_issues,
            auto_fixed=auto_fixed,
            processing_time_ms=execution_time,
            summary={
                'by_category': category_summary,
                'pass_rate': (passed_count / total_products * 100) if total_products > 0 else 0,
                'critical_issue_rate': (len(critical_issues) / total_products * 100) if total_products > 0 else 0,
                'auto_fix_rate': (auto_fixed / len(results) * 100) if results else 0
            }
        )
    
    def _execute_query(self, query: str) -> pd.DataFrame:
        """Execute query and return DataFrame (simulated)"""
        # In production, this would use BigQuery client
        return pd.DataFrame()
    
    def _execute_update(self, query: str) -> None:
        """Execute update query (simulated)"""
        # In production, this would use BigQuery client
        pass


class QCMonitor:
    """
    Monitor QC metrics over time
    """
    
    def __init__(self, project_id: str, dataset_id: str):
        self.project_id = project_id
        self.dataset_id = dataset_id
        self.dataset_ref = f"{project_id}.{dataset_id}"
        
    def get_qc_trends(self, days: int = 30) -> pd.DataFrame:
        """Get QC trends over time"""
        query = f"""
        WITH daily_qc AS (
            SELECT 
                DATE(timestamp) as date,
                COUNT(DISTINCT sku) as products_checked,
                COUNTIF(status = 'passed') as passed,
                COUNTIF(status = 'failed') as failed,
                COUNTIF(status = 'warning') as warnings,
                COUNTIF(rule_id IN ('IMG001', 'DATA001', 'COMP001')) as critical_issues,
                AVG(confidence) as avg_confidence
            FROM `{self.dataset_ref}.qc_results`
            WHERE timestamp >= DATE_SUB(CURRENT_DATE(), INTERVAL {days} DAY)
            GROUP BY date
        )
        SELECT 
            *,
            passed / products_checked * 100 as pass_rate,
            critical_issues / products_checked * 100 as critical_rate,
            SUM(products_checked) OVER (ORDER BY date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) as weekly_volume
        FROM daily_qc
        ORDER BY date DESC
        """
        
        return pd.DataFrame()  # Simulated
    
    def get_top_issues(self, limit: int = 10) -> pd.DataFrame:
        """Get most common QC issues"""
        query = f"""
        SELECT 
            rule_id,
            rule_name,
            category,
            COUNT(*) as occurrence_count,
            COUNT(DISTINCT sku) as affected_products,
            AVG(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) * 100 as failure_rate,
            STRING_AGG(DISTINCT suggested_fix, '; ' LIMIT 3) as common_fixes
        FROM `{self.dataset_ref}.qc_results` r
        JOIN `{self.dataset_ref}.qc_rules` rules
            ON r.rule_id = rules.rule_id
        WHERE timestamp >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
        GROUP BY rule_id, rule_name, category
        ORDER BY occurrence_count DESC
        LIMIT {limit}
        """
        
        return pd.DataFrame()  # Simulated