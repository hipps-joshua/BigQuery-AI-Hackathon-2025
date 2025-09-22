Architecture

# BigQuery AI Hackathon – Three Complete Approaches (us-central1)

This repository contains three production‑leaning solutions aligned to the Kaggle “BigQuery AI – Building the Future of Data” hackathon:

- Approach 1 – AI Architect: Template‑driven enrichment, validation, and forecasting
- Approach 2 – Semantic Detective: Vector search + embeddings with AI validation
- Approach 3 – Multimodal Pioneer: Object Tables + vision for QC, compliance, and visual search

## Quick Start (us-central1)

1) Prerequisites
- gcloud and bq CLIs installed, authenticated
- A Google Cloud project with billing enabled

2) Create BigQuery connection (us-central1)
```
bq mk --connection \
  --location=us-central1 \
  --project_id=$PROJECT_ID \
  --connection_type=CLOUD_RESOURCE \
  gemini_connection

CONNECTION_SA=$(bq show --connection --location=us-central1 --project_id=$PROJECT_ID gemini_connection \
  | grep serviceAccountId | awk -F'\"' '{print $4}')

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${CONNECTION_SA}" \
  --role="roles/aiplatform.user"
```

3) Deploy each approach
- Approach 1: `BigQuery_Approach1_AI_Architect/setup_bigquery.sh`
- Approach 2: `BigQuery_Approach2_Semantic_Detective/setup_bigquery.sh`
- Approach 3: `BigQuery_Approach3_Multimodal_Pioneer/setup_bigquery.sh`

Each setup creates required datasets, models, sample tables, procedures, and monitoring views.

## Testing

Quick one‑liners to verify your environment. Replace bucket paths as needed.

- Test Approach 1 (AI Architect)
  - Query:
    - `SELECT AI.GENERATE('Generate a 20‑word product description for running shoes', connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection') AS description;`
  - Expect:
    - One row with column `description` (STRING) containing a short, coherent sentence or two.

- Test Approach 2 (Semantic Detective)
  - Query:
    - `SELECT * FROM ML.GENERATE_EMBEDDING(MODEL \`bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model\`, (SELECT 'running shoes' AS content)) LIMIT 1;`
  - Expect:
    - Columns: `content` (STRING), `ml_generate_embedding_result` (ARRAY<FLOAT64>), array length typically in the hundreds (e.g., ~768).

- Test Approach 3 (Multimodal Pioneer)
  - Option A: Quick multimodal embedding (image + optional text)
    - `SELECT * FROM ML.GENERATE_EMBEDDING( MODEL \`bigquery-ai-hackathon-2025.test_dataset_central.gemini_embedding_model\`, (SELECT STRUCT('gs://YOUR_BUCKET/sample-image.jpg' AS image, 'product photo' AS text) AS content)) LIMIT 1;`
  - Option B: Simple image‑quality prompt (smoke test; not strictly image‑grounded)
    - `SELECT AI.GENERATE_DOUBLE(CONCAT('Rate image quality 1‑10: ','gs://YOUR_BUCKET/sample-image.jpg'), connection_id => 'bigquery-ai-hackathon-2025.us-central1.gemini_connection') AS quality_score;`
  - Expect:
    - For embeddings: a row with `ml_generate_embedding_result` array. For the quality score: one row with `quality_score` (FLOAT64 in 0–10 range).

Notes
- If you already created Object Tables and vision models from the Approach 3 SQL, you can run the richer functions there (e.g., ML.ANALYZE_IMAGE with MODEL + TABLE). For a minimal “does it work?” check, the above one‑liners are sufficient.
- All AI.* calls require the connection id: `bigquery-ai-hackathon-2025.us-central1.gemini_connection`.

## What’s Included
- Native BigQuery AI usage: ML.GENERATE_TEXT, AI.GENERATE_BOOL/INT/DOUBLE/TABLE, ML.GENERATE_EMBEDDING, VECTOR_SEARCH, ML.FORECAST, Object Tables
- Monitoring & ROI: views and logs per approach
- Demos: reproducible SQL, notebooks, and scripts

## Submission Assets
- Writeup draft: `WRITEUP_DRAFT.md`
- Survey: `survey.txt`
- Architecture overview: `ARCHITECTURE.md` (includes a diagram placeholder)

## Architecture Diagram
See `ARCHITECTURE.md` for a high‑level diagram and links to per‑approach flows.

## Notes
- Location is standardized to `us-central1` across scripts/models (datasets, models, and the Gemini connection). Use `us-central1` unless you explicitly adapt the SQL to another location.
- If you see old references to `vertex_ai_connection` or other regions in TODO docs, prefer the scripts in this repo which are updated to `gemini_connection` and `us-central1`.
- For large demos, use precomputed results/views to keep costs low.

For a quick judge/demo flow (5–10 minutes), see `UPLOAD_INSTRUCTIONS.md`.

## License
- Will comply with Kaggle winner requirements (CC BY 4.0) if awarded.

## Architecture

Architecture
