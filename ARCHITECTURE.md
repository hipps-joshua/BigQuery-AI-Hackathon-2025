# Architecture Overview

This repo implements three approaches that share a common foundation in BigQuery and Vertex AI via a single BigQuery connection (`gemini_connection`, location `us-central1`).

- Data Ingestion → BigQuery datasets per approach
- AI Models → Remote models created via BigQuery connections (text, embeddings, vision)
- Orchestration → SQL procedures/functions + Python helpers
- Monitoring → Logs + ROI/Performance dashboards

Mermaid (conceptual):
```
flowchart LR
  A[Source Data + Images] --> B(BigQuery Tables + Object Tables)
  B --> C{AI Models}
  C -->|Text| D1[ML.GENERATE_TEXT / AI.GENERATE_*]
  C -->|Embeddings| D2[ML.GENERATE_EMBEDDING + VECTOR_SEARCH]
  C -->|Vision| D3[ML.ANALYZE_IMAGE]
  D1 --> E1[Enrichment & Validation]
  D2 --> E2[Semantic Search & Dedupe]
  D3 --> E3[Quality + Compliance + Visual Search]
  E1 & E2 & E3 --> F[Dashboards & ROI]
```

- Approach 1 (AI Architect):
  - Templates + ML.GENERATE_TEXT for content, AI.GENERATE_* for structure/validation, ML.FORECAST for demand
- Approach 2 (Semantic Detective):
  - ML.GENERATE_EMBEDDING + VECTOR_SEARCH (with index) for semantic search, AI validation/explanations
- Approach 3 (Multimodal Pioneer):
  - Object Tables + ML.ANALYZE_IMAGE + multimodal embeddings for QC/compliance/visual search

See per‑approach README files for details and demo sequences.

Diagram (SVG, renders on GitHub): `architecture_diagram.svg`
