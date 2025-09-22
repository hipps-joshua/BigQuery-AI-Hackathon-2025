# 🚀 BigQuery AI Competition - Upload & Run Instructions

## Quick Start (5 Minutes)

### Step 1: Upload the Data to BigQuery

1. **Open BigQuery Console**
   ```
   https://console.cloud.google.com/bigquery
   ```

2. **Create Dataset (if not exists)**
   - Project: `bigquery-ai-hackathon-2025`
   - Dataset ID: `test_dataset_central`
   - Location: `us-central1`

3. **Upload the CSV File**
   - Click on your dataset `test_dataset_central`
   - Click "CREATE TABLE"
   - Source: "Upload" 
   - Select file: `enterprise_data.csv`
   - Table name: `enterprise_data`
   - Schema: Auto-detect ✓
   - Click "Create Table"

### Step 2: Run the Queries

1. **Open BigQuery SQL Workspace**

2. **Copy queries from:** `queries_for_uploaded_data.sql`

3. **Run in this order:**
   - Step 1: Verify Data Upload (instant)
   - Step 2: AI Analysis (30-60 seconds)
   - Step 3: Pattern Discovery (10 seconds)
   - Step 4: Executive Dashboard (10 seconds)
   - Step 5: Business Recommendations (10 seconds)

## 📊 What You'll See

### After Step 1 (Data Verification):
```
source_type    | record_count
---------------|-------------
chat_log       | 2
email          | 2
github_issue   | 5
hacker_news    | 5
stackoverflow  | 5
support_ticket | 3
```

### After Step 2 (AI Analysis):
- AI-generated summaries for each item
- Urgency flags (true/false)
- Sentiment scores (-10 to +10)
- Main topics extracted
- Business impact assessment

### After Step 3 (Pattern Discovery):
```
topic         | mentions | platforms | sentiment | urgent_count
--------------|----------|-----------|-----------|-------------
TensorFlow    | 4        | 2         | -3.5      | 2
Python        | 3        | 2         | 1.2       | 1
Performance   | 3        | 3         | -2.1      | 2
```

### After Step 4 (Executive Dashboard):
- Total items analyzed: 22
- Urgent items: 7
- Average sentiment: -0.5
- AI-generated executive summary

### After Step 5 (Business Recommendations):
AI generates specific recommendations like:
```
1. PRIORITY HIGH: Fix TensorFlow memory issues
   Impact: Prevent production failures
   Timeline: 1 week

2. PRIORITY HIGH: Address security vulnerability
   Impact: Protect customer data
   Timeline: Immediate

3. PRIORITY MEDIUM: Improve Apple Silicon support
   Impact: Retain Mac developer base
   Timeline: 1 month
```

## 🏆 Competition Alignment

This demonstrates:

### ✅ Approach 1: AI Architect
- `AI.GENERATE()` - Text summaries and insights
- `AI.GENERATE_BOOL()` - Urgency detection
- `AI.GENERATE_DOUBLE()` - Sentiment scoring

### ✅ Approach 2: Semantic Detective  
- Cross-platform pattern analysis
- Topic clustering across sources
- Correlation insights

### ✅ Approach 3: Multimodal Pioneer
- Combined structured + unstructured analysis
- Executive dashboard with metrics
- AI-generated recommendations

## 🔧 Troubleshooting

### If you get "Table not found":
- Ensure CSV is uploaded as `enterprise_data` table
- Check dataset name is `test_dataset_central`
- Verify project is `bigquery-ai-hackathon-2025`

### If AI functions fail:
- Check connection string: `bigquery-ai-hackathon-2025.us-central1.gemini_connection`
- Ensure Gemini connection is configured
- Verify billing is enabled

## 📁 Files You Need

1. **enterprise_data.csv** - The data to upload (22 records)
2. **queries_for_uploaded_data.sql** - SQL queries to run
3. **UPLOAD_INSTRUCTIONS.md** - This file

## 🔥 Pro Tips

- Run queries one at a time to see results build up
- The AI analysis (Step 2) takes longest - be patient
- Results prove we're solving real enterprise data chaos
- All 22 records represent realistic business data:
  - 5 GitHub issues (bugs, features)
  - 5 Stack Overflow questions (developer problems)
  - 5 Hacker News stories (market trends)
  - 3 Support tickets (customer issues)
  - 2 Emails (internal communications)
  - 2 Chat logs (team discussions)

## 🌟 Success Criteria

✅ Upload data successfully  
✅ Run all 5 query steps  
✅ See AI-generated insights  
✅ Get business recommendations  
✅ Prove all 3 approaches work  

---

**Time to complete: 5-10 minutes**  
**Queries to run: 5 steps**  
**Business value: Immediate insights from chaos**