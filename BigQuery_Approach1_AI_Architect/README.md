# 🏗️ BigQuery AI Architect - Competition Submission Guide

## 🎯 Overview
**Approach 1: Template-Based AI Orchestration Platform**
- Reusable AI-powered data enrichment templates
- Automated product catalog enhancement
- Quality validation and data governance
- 10,000%+ ROI through automation

## 🚀 Pre-Competition Setup Checklist

### 1. Google Cloud Project Setup
```bash
# Set your project ID
export PROJECT_ID="your-hackathon-project-id"
export DATASET_ID="ai_architect"
export LOCATION="us-central1"

# Enable required APIs
gcloud services enable bigquery.googleapis.com
gcloud services enable aiplatform.googleapis.com
gcloud services enable bigqueryconnection.googleapis.com

# Set default project
gcloud config set project $PROJECT_ID
```

### 2. Create BigQuery Connection (REQUIRED)
```bash
# Create the Gemini connection for AI models
bq mk --connection \
  --location=$LOCATION \
  --project_id=$PROJECT_ID \
  --connection_type=CLOUD_RESOURCE \
  gemini_connection

# Grant permissions to the connection
export CONNECTION_SA=$(bq show --connection --project_id=$PROJECT_ID --location=$LOCATION gemini_connection | grep serviceAccountId | cut -d'"' -f4)

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${CONNECTION_SA}" \
  --role="roles/aiplatform.user"
```

### 3. Run Setup Script
```bash
# Clone the repository
cd BigQuery_Approach1_AI_Architect

# Make setup script executable
chmod +x setup_bigquery.sh

# Run setup (creates all tables, procedures, and sample data)
./setup_bigquery.sh $PROJECT_ID $DATASET_ID

# Verify setup completed
bq query --use_legacy_sql=false "SELECT * FROM \`$PROJECT_ID.$DATASET_ID.products\` LIMIT 5"
```

### 4. Upload Your Product Data (Optional)
```sql
-- If you have your own product catalog CSV
bq load \
  --source_format=CSV \
  --skip_leading_rows=1 \
  --replace \
  $PROJECT_ID:$DATASET_ID.products \
  gs://your-bucket/products.csv \
  sku:STRING,brand_name:STRING,product_name:STRING,description:STRING,category:STRING,price:FLOAT64
```

## 🆘 Troubleshooting

### If queries fail:
```sql
-- Check connection
SELECT * FROM `PROJECT_ID.LOCATION.INFORMATION_SCHEMA.CONNECTIONS`
WHERE connection_id = 'gemini_connection';

-- Check model status
SELECT * FROM `PROJECT_ID.DATASET_ID.ML.MODELS`;

-- Use pre-calculated results
SELECT * FROM `PROJECT_ID.DATASET_ID.demo_results_backup`;
```
