# Independent Model Benchmarking

## Overview
Restructure the benchmarking system to evaluate VLMs and TextLLMs independently rather than as paired combinations. This allows finding the best model for each task (categorization vs. data extraction) on its own merits, producing clearer and more actionable results.

## Goals
- Benchmark VLMs independently for categorization accuracy across positive and negative document examples
- Benchmark TextLLMs independently for both categorization and data extraction accuracy
- Support a large pool of candidate models (starting with 25 VLMs)
- Provide a clear, separate scoring system for each model type
- Manage reference data (JSON ground-truth files) with interactive review workflow

## Non-Goals
- Testing model pairs or combined pipelines (explicitly removed)
- Changing the production two-phase architecture (VLM + TextLLM)
- Benchmarking OCR engines or PDF conversion quality
- Automated model selection or deployment after benchmarking
- Persisting benchmark results to disk (CSV/JSON reports); results are terminal output only

## User Stories
- As a developer, I want to benchmark VLMs independently so that I can identify the single best model for document categorization.
- As a developer, I want to benchmark TextLLMs independently so that I can identify the single best model for both categorization and data extraction.
- As a developer, I want the benchmark to accept a positive and a negative directory for a single document type so that expected outcomes are clear without needing JSON ground-truth files for VLM categorization tests.
- As a developer, I want to be prompted about existing JSON reference files so that I can reuse previously validated ground-truth data or regenerate it when needed.
- As a developer, I want a review step after JSON generation so that I can verify the ground-truth data before it is used for scoring.

## Proposed Solution

### Approach

The benchmark is split into two independent phases that run sequentially.

**Phase A: VLM Categorization Benchmark**

Each benchmark run targets a single document type (e.g., invoice or prescription). The user provides two directory paths as CLI parameters: one containing positive examples (documents that are the target type) and one containing negative examples (documents that are not the target type). Each candidate VLM is run against all documents in both directories. No JSON ground-truth files are needed for this phase.

Scoring per document per model:
- **Positive examples**: Correctly categorized as the target type (true positive) → **1 point**; incorrectly rejected (false negative) → **0 points**
- **Negative examples**: Correctly rejected as not the target type (true negative) → **1 point**; incorrectly categorized as the target type (false positive) → **0 points**

A configurable per-model timeout is applied to each inference call. The user selects from 10s, 30s, or 60s before the benchmark starts. If a model exceeds the timeout on a document, that document scores 0 for the model.

Results are aggregated per model and presented as a ranked table. The total elapsed time for the entire assessment of each model is recorded and displayed alongside the final score.

**Phase B: TextLLM Categorization + Extraction Benchmark**

Run each candidate TextLLM against the same positive and negative reference documents for the given document type. This phase tests two capabilities: categorization (from OCR text) and data extraction (date + secondary field). JSON ground-truth files are required for the extraction scoring of positive examples.

Before running this phase:
1. Check if JSON ground-truth files already exist for the reference documents.
2. If they exist, prompt the user: reuse existing files or regenerate.
3. If regenerating or creating for the first time, generate the JSON files, then pause and ask the user to review them before continuing.
4. Once the user confirms, proceed with the benchmark.

Scoring per document per model:
- Both categorization and data extraction correct: **2 points**
- Only one of categorization or data extraction correct: **1 point**
- Neither correct: **0 points**

The same per-model timeout applies as in Phase A.

Results are aggregated per model and presented as a ranked table. The total elapsed time for the entire assessment of each model is recorded and displayed alongside the final score.

### Ground-Truth JSON Schema

Each reference document has a corresponding JSON file used for TextLLM data extraction scoring only. The file is stored alongside the PDF (same name, `.json` extension). Categorization correctness is not determined from the JSON — it is derived from the application parameters (which directory a document is in defines whether it is a positive or negative example).

```json
{
  "date": "2025-11-26",
  "documentType": "invoice",
  "isMatch": true,
  "metadata": {
    "generatedAt": "2026-02-22T18:46:12Z",
    "textModel": "mlx-community/Qwen2.5-7B-Instruct-4bit",
    "vlmModel": "mlx-community/Qwen2-VL-2B-Instruct-4bit",
    "verified": false
  },
  "secondaryField": "Autohaus_Hoffmann_e.K."
}
```

| Field | Description |
|---|---|
| `date` | Expected document date (YYYY-MM-DD) |
| `documentType` | The document type this ground-truth applies to (e.g., `invoice`, `prescription`) |
| `isMatch` | Whether this document is a positive match for the given document type |
| `metadata.generatedAt` | ISO 8601 timestamp of when the JSON was generated |
| `metadata.textModel` | TextLLM used to generate the ground-truth data |
| `metadata.vlmModel` | VLM used to generate the ground-truth data |
| `metadata.verified` | Whether the user has reviewed and confirmed the data |
| `secondaryField` | Expected secondary value (company name for invoices, doctor name for prescriptions) |

For negative examples, `isMatch` is `false` and `date`/`secondaryField` may be empty since extraction scoring does not apply.

### Model Selection

Candidate models are sourced from Hugging Face and selected based on three criteria:

1. **MLX compatibility** — Only models available as MLX-converted weights (typically from the `mlx-community` namespace or with MLX-compatible formats).
2. **Popularity** — Prefer models with high download counts and community adoption.
3. **Document relevance** — Prefer models whose descriptions mention document understanding, document parsing, OCR, invoice processing, or similar capabilities.

**VLM candidates** must be true Vision-Language Models that accept image input. Models that are text-only or have vision mentioned only in the name but lack actual image input support must be excluded.

**TextLLM candidates** must be purely text-based language models. Multimodal models (those accepting image, audio, or video input) must be excluded, even if they could technically be used in text-only mode. This ensures the benchmark measures text reasoning ability without any visual processing overhead or architecture differences.

The initial target is 25 VLMs and a comparable set of TextLLMs. The concrete model lists are curated once during implementation and hardcoded as defaults, but the system should allow overriding them via configuration.

### Key Decisions
- VLM and TextLLM benchmarks are fully decoupled so each model type can be evaluated and compared in isolation.
- Folder-based category ground truth for VLMs eliminates the need for JSON metadata during categorization-only tests, keeping setup simple.
- JSON ground-truth files are only required for TextLLM extraction benchmarks where structured data (date, company/doctor) must be verified.
- Interactive prompts (reuse/regenerate JSON, review before continuing) keep the user in control of data quality without requiring separate tooling.
- The 25-model target for VLMs is a starting point; the system should handle an arbitrary number of models.
- Models are sourced from Hugging Face, filtered by MLX compatibility, popularity, and document-processing relevance.
- VLM list strictly excludes text-only models; TextLLM list strictly excludes multimodal models. This separation is enforced during curation.

## Acceptance Criteria
- [ ] VLM benchmark runs each candidate model against all reference documents and scores categorization only
- [ ] VLM benchmark derives expected outcome from which directory (positive/negative) a document belongs to, no JSON files needed
- [ ] TextLLM benchmark runs each candidate model against all reference documents and scores both categorization and extraction
- [ ] TextLLM benchmark consults JSON ground-truth files for data extraction scoring only; categorization correctness is derived from directory placement
- [ ] If JSON files exist, user is prompted to reuse or regenerate
- [ ] If JSON files are generated (new or regenerated), user is prompted to review before benchmark continues
- [ ] Application pauses and waits for explicit user confirmation after JSON review
- [ ] Scoring follows the defined point system (VLM: 0-1, TextLLM: 0-2)
- [ ] Results are presented as ranked tables per model type
- [ ] Total elapsed time per model is measured and displayed alongside its final score
- [ ] Each benchmark run targets a single document type with two directory paths (positive and negative) configurable via CLI parameters
- [ ] Positive documents are scored as true positive (1) or false negative (0)
- [ ] Negative documents are scored as true negative (1) or false positive (0)
- [ ] System supports an arbitrary number of candidate models (not hardcoded to 25)
- [ ] Old paired-model benchmarking behavior is removed or replaced
- [ ] VLM candidate list contains only true Vision-Language Models (image input required)
- [ ] TextLLM candidate list contains only purely text-based models (no multimodal models)
- [ ] Models are sourced from Hugging Face, selected by MLX compatibility, popularity, and document-processing relevance
- [ ] Default model lists are hardcoded but can be overridden via configuration
- [ ] Per-model inference timeout is configurable (10s, 30s, or 60s), selected by the user before the benchmark starts
- [ ] A timed-out inference scores 0 for that document

## Open Questions
None — all questions resolved.
