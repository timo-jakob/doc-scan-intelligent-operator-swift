# Collection-Based VLM Model Selection

## Overview
Replace the hardcoded VLM model list with dynamic discovery from HuggingFace. The user specifies a model family name (e.g., "Qwen3-VL", "FastVLM") and the benchmark automatically discovers all MLX-compatible VLM variants in that family, then benchmarks them. This makes model selection flexible and always up-to-date without maintaining a curated list.

## Goals
- Let the user specify a model family/collection name via CLI to control which VLM models are benchmarked
- Automatically discover MLX-compatible VLM models matching that family on HuggingFace
- Remove the hardcoded `DefaultModelLists.vlmModels` list and popularity-based ordering
- Keep the existing benchmarking workflow (Phase A execution, scoring, leaderboard) unchanged

## Non-Goals
- Changing TextLLM (Phase B) model selection — that stays as-is for now
- Modifying the benchmark execution engine, scoring, or result display
- Supporting HuggingFace's "Collections" feature (curated pages with hex IDs) — we use the simpler model search API
- Offline/cached model discovery — always queries HuggingFace live
- Filtering by quantization level (4-bit vs 8-bit) — all MLX VLM matches are included

## User Stories
- As a developer, I want to benchmark all Qwen3-VL variants by running `docscan benchmark pos/ neg/ --collection Qwen3-VL` so that I can find the best model in that family for my use case.
- As a developer, I want to benchmark Apple's FastVLM models by specifying `--collection FastVLM` so that I can evaluate a new model family without editing any config files.
- As a developer, I want the benchmark to automatically find all MLX-compatible VLM variants in a family so that I don't need to manually look up and list model IDs.

## Proposed Solution

### Approach

Add a new `--collection` CLI option to the benchmark command. When provided, the benchmark queries the HuggingFace model search API to discover models matching the family name that are both MLX-compatible and vision-language models. The discovered model list replaces the hardcoded default and feeds into the existing Phase A benchmarking loop unchanged.

**Discovery logic:**
1. Query `GET /api/models?search=mlx+{collection}&pipeline_tag=image-text-to-text&sort=downloads&direction=-1&limit=50`
2. Filter results to those whose `tags` array contains `"mlx"`
3. Optionally filter out gated models (which require approval and would fail to download)
4. Use the resulting model IDs as the VLM model list for Phase A

The HuggingFace API returns models sorted by downloads (most popular first). The `pipeline_tag=image-text-to-text` filter ensures only vision-language models are returned. The post-filter on the `"mlx"` tag ensures MLX compatibility since the search query alone may return non-MLX results.

**CLI interface:**
- `--collection <name>` — required argument specifying the model family (e.g., "Qwen3-VL", "FastVLM", "InternVL2")
- The existing `--vlm-models` config override is removed along with `DefaultModelLists.vlmModels`

**What gets removed:**
- `DefaultModelLists.vlmModels` — the hardcoded 46-model list
- `BenchmarkSettings.vlmModels` — the config-based override (replaced by `--collection`)
- `HuggingFaceClient.searchVLMModels()` — the unused popularity-based search (replaced by collection-based search)

### Key Decisions
- Use the HuggingFace model search API (`/api/models?search=...`) rather than the Collections API (`/api/collections/{slug}`) because search is simpler (no collection hex ID needed), works with any keyword, and doesn't require model families to have a curated HuggingFace collection page
- `--collection` is required for VLM benchmarking (no default fallback) — this makes the user's intent explicit and avoids silently benchmarking a large default set
- Filter by both `pipeline_tag=image-text-to-text` (server-side) and `tags` containing `"mlx"` (client-side) for reliable results — the search query alone is not a precise filter
- Sort by downloads descending so the most popular/tested variants appear first in the benchmark run

## Acceptance Criteria
- [ ] `docscan benchmark pos/ neg/ --collection Qwen3-VL` discovers and benchmarks all MLX VLM models matching "Qwen3-VL"
- [ ] `docscan benchmark pos/ neg/ --collection FastVLM` discovers and benchmarks all MLX VLM models matching "FastVLM"
- [ ] The `--collection` option is required — omitting it produces a clear error message
- [ ] Discovered models are printed before benchmarking starts (so the user sees what will be tested)
- [ ] If no models are found for the given collection name, the benchmark exits with a clear error
- [ ] `DefaultModelLists.vlmModels` and the hardcoded VLM model list are removed
- [ ] `HuggingFaceClient` has a new method for collection-based model discovery
- [ ] Phase A benchmarking workflow (execution, scoring, leaderboard, progress display) is unchanged
- [ ] Phase B (TextLLM) model selection is unchanged
- [ ] All existing tests pass (with updates to tests that reference `DefaultModelLists.vlmModels`)
- [ ] `make lint` passes with 0 violations

## Open Questions
- Should there be a `--limit` option to cap the number of discovered models (e.g., `--limit 5` to only test the top 5 by downloads)?
- Should gated models be silently filtered out, or should they appear in the list with a warning that they may fail without a HuggingFace token?
- Should the search also include the `"mlx-community/"` namespace prefix automatically (e.g., searching "mlx-community Qwen3-VL") to prioritize community-converted MLX models, or rely purely on the `mlx` tag filter?
