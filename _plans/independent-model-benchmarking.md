# Implementation Plan: Independent Model Benchmarking

## Context

The current benchmark evaluates VLM+TextLLM **pairs** together, making it impossible to identify which individual model performs best for each task. This refactor splits benchmarking into two independent phases: Phase A tests VLMs on categorization only, Phase B tests TextLLMs on categorization + data extraction. The spec is at `_specs/independent-model-benchmarking.md`.

All paired-model types, methods, and tests are removed completely — no relics.

---

## Step 1: Replace Result Types

**Rewrite:** `Sources/DocScanCore/Benchmark/BenchmarkMetrics.swift`

Remove `DocumentResult`, `BenchmarkMetrics`, `ModelPairResult`. Replace with:

- `VLMDocumentResult` — per-document: `filename`, `isPositiveSample`, `predictedIsMatch`, `correct` (TP/TN), `score` (0 or 1)
- `VLMBenchmarkResult` — per-model: `modelName`, `totalScore`, `maxScore`, `score` (Double), `documentResults`, `elapsedSeconds` (TimeInterval), `isDisqualified`, `disqualificationReason`
- `TextLLMDocumentResult` — per-document: `filename`, `isPositiveSample`, `categorizationCorrect`, `extractionCorrect`, `score` (0, 1, or 2)
- `TextLLMBenchmarkResult` — same shape as VLM but with `maxScore = 2 * docCount`

---

## Step 2: Default Model Lists

**New file:** `Sources/DocScanCore/Benchmark/DefaultModelLists.swift`

`DefaultModelLists` enum with two static arrays:
- `vlmModels: [String]` — 25 curated VLMs (MLX-compatible, popular, document-relevant, true vision models)
- `textLLMModels: [String]` — comparable set of TextLLMs (purely text-based, no multimodal)

**Modify:** `Sources/DocScanCore/Configuration.swift`

Add two optional properties for overrides:
- `benchmarkVLMModels: [String]?`
- `benchmarkTextLLMModels: [String]?`

Update `CodingKeys` and ensure backward-compatible YAML decoding (nil when absent).

---

## Step 3: Text Categorization Prompt

**Modify:** `Sources/DocScanCore/DocumentType.swift`

Add a `textCategorizationPrompt` computed property — similar to `vlmPrompt` but for text-based LLM categorization of OCR text:
```
"Based on the following document text, is this an INVOICE? Answer only YES or NO."
```

This is needed because the spec benchmarks TextLLM categorization ability (not keyword detection). Each TextLLM receives OCR text and must answer YES/NO.

---

## Step 4: VLM-Only and TextLLM-Only Factories

**Modify:** `Sources/DocScanCore/Benchmark/BenchmarkEngine.swift`

Remove `DocumentDetectorFactory` protocol and `DefaultDocumentDetectorFactory` actor. Replace with:

- `VLMOnlyFactory` protocol: `preloadVLM(modelName:)`, `makeVLMProvider() -> VLMProvider?`, `releaseVLM()`
- `TextLLMOnlyFactory` protocol: `preloadTextLLM(config:)`, `makeTextLLMManager() -> TextLLMManager?`, `releaseTextLLM()`
- `DefaultVLMOnlyFactory` (actor): caches single `ModelManager`, releases with `Memory.clearCache()`
- `DefaultTextLLMOnlyFactory` (actor): caches single `TextLLMManager`, same pattern

Remove `runInitialBenchmark()` and `processInitialDocument()` — replaced by ground truth generation in Step 10.

Keep `enumeratePDFs()`, `checkExistingSidecars()`, `loadGroundTruths()` — still needed.

---

## Step 5: VLM Benchmark Engine Method

**New file:** `Sources/DocScanCore/Benchmark/BenchmarkEngine+VLM.swift`

`BenchmarkEngine.benchmarkVLM(modelName:, positivePDFs:, negativePDFs:, timeoutSeconds:, vlmFactory:) -> VLMBenchmarkResult`

For each document:
1. Convert PDF to image via `PDFUtils.pdfToImage()`
2. Call `vlmProvider.generateFromImage(image, prompt: documentType.vlmPrompt)` wrapped in `TimeoutError.withTimeout(seconds:)`
3. Parse YES/NO from response (reuse logic from `DocumentDetector.categorizeWithVLM`)
4. Score: `predictedIsMatch == isPositive` → 1, else → 0
5. Timeout → score 0, continue to next doc (NOT disqualify)

Track `Date()` elapsed time for the full model run. Release VLM after all docs.

---

## Step 6: TextLLM Benchmark Engine Method

**New file:** `Sources/DocScanCore/Benchmark/BenchmarkEngine+TextLLM.swift`

`BenchmarkEngine.benchmarkTextLLM(modelName:, positivePDFs:, negativePDFs:, ocrTexts:, groundTruths:, timeoutSeconds:, textLLMFactory:) -> TextLLMBenchmarkResult`

Accepts pre-extracted `ocrTexts: [String: String]` (path → text, extracted once, shared across all models).

For each document:
1. **Categorization**: Send OCR text with `documentType.textCategorizationPrompt` to TextLLM, parse YES/NO. Wrapped in timeout.
2. **Extraction** (positive samples where categorization was correct): Call `textLLM.extractData(for:from:)` on the OCR text. Wrapped in timeout.
3. Score using `FuzzyMatcher.scoreDocument()` for extraction correctness. Negative correctly rejected → 2 pts (matches existing FuzzyMatcher behavior).

Track elapsed time. Release TextLLM after all docs.

---

## Step 7: OCR Pre-extraction Helper

**Add to** `Sources/DocScanCore/Benchmark/BenchmarkEngine.swift`

`BenchmarkEngine.preExtractOCRTexts(positivePDFs:, negativePDFs:) -> [String: String]`

For each PDF: try `PDFUtils.extractText()` (direct text), fall back to `OCREngine.extractText()` (Vision OCR). Return dictionary keyed by path.

---

## Step 8: Ground Truth Generation

**Add to** `Sources/DocScanCore/Benchmark/BenchmarkEngine.swift`

`BenchmarkEngine.generateGroundTruths(positivePDFs:, negativePDFs:, ocrTexts:) async throws -> [String: GroundTruth]`

For positive docs: run the current config's TextLLM to extract date + secondaryField, build `GroundTruth` with `isMatch: true`.
For negative docs: build `GroundTruth` with `isMatch: false`, empty date/secondaryField.
Save as JSON sidecars. Return the map.

This replaces the old `runInitialBenchmark()` + `processInitialDocument()` + `buildGroundTruth()` with a simpler flow that only does extraction (no VLM categorization needed for ground truth generation).

---

## Step 9: Refactor CLI — BenchmarkCommand

**Rewrite:** `Sources/DocScanCLI/BenchmarkCommand.swift`

- Change `negativeDir` from `@Option` to required `@Argument` (spec: "two directory paths as CLI parameters")
- Update `abstract` to "Evaluate VLMs and TextLLMs independently against labeled documents"
- Rewrite `run()`:
  1. Memory cap, parse type, load config (same as now)
  2. Validate and resolve both directories
  3. Enumerate PDFs in both dirs
  4. Timeout selection (10s/30s/60s menu)
  5. HF credentials
  6. **Phase A**: VLM categorization benchmark
  7. **Phase B**: TextLLM categorization + extraction benchmark
  8. **Recommendation**: Prompt user to update config with best VLM + best TextLLM, or keep current config
  9. Cleanup model cache

---

## Step 10: Rewrite Phase A (VLM Benchmark)

**Rewrite:** `Sources/DocScanCLI/BenchmarkCommand+PhaseA.swift`

1. Resolve VLM model list: `config.benchmarkVLMModels ?? DefaultModelLists.vlmModels`
2. For each VLM model sequentially:
   - Print `[1/25] mlx-community/Qwen2-VL-2B-Instruct-4bit`
   - Call `engine.benchmarkVLM(...)`
   - Print score + elapsed time: `Score: 92.0% (23/25) in 45.2s`
3. Return `[VLMBenchmarkResult]`

No JSON files needed. No ground truth management.

---

## Step 11: Rewrite Phase B (TextLLM Benchmark)

**Rewrite:** `Sources/DocScanCLI/BenchmarkCommand+PhaseB.swift`

1. **Ground truth management** (positive docs only):
   - Check for existing JSON sidecars via `GroundTruth.sidecarPath()`
   - If exist → prompt: reuse or regenerate (via `TerminalUtils.menu()`)
   - If regenerating/new → call `engine.generateGroundTruths(...)`, then pause for user review (press Enter to continue)
2. Pre-extract OCR text for all docs via `engine.preExtractOCRTexts()`
3. Resolve TextLLM model list: `config.benchmarkTextLLMModels ?? DefaultModelLists.textLLMModels`
4. For each TextLLM sequentially: call `engine.benchmarkTextLLM(...)`, print score + time
5. Return `[TextLLMBenchmarkResult]`

---

## Step 12: Delete Old Phase Files and Paired Benchmark Code

**Delete files:**
- `Sources/DocScanCLI/BenchmarkCommand+PhaseC.swift` (paired model benchmark loop)
- `Sources/DocScanCLI/BenchmarkCommand+PhaseD.swift` (paired leaderboard + config update)
- `Sources/DocScanCore/Benchmark/BenchmarkEngine+Benchmark.swift` (paired `benchmarkModelPair()`)

**Remove from `HuggingFaceClient.swift`:**
- `ModelPair` struct
- `discoverModelPairs()` method

Keep: `searchVLMModels()`, `searchTextModels()`, `isModelGated()`, `HFModel`, `HFGated` — still used for model discovery and gated-model checks.

---

## Step 13: Recommendation + Config Update

**New phase in** `Sources/DocScanCLI/BenchmarkCommand.swift` (inline or small extension)

After both leaderboards are displayed:
1. Identify the best VLM (highest score, lowest time as tiebreaker)
2. Identify the best TextLLM (same criteria)
3. Show recommendation: "Best VLM: X (score%), Best TextLLM: Y (score%)"
4. Prompt user:
   - `[1] Update config to use best VLM + best TextLLM`
   - `[2] Keep current configuration`
5. If user selects update → save config via `Configuration.save()`

---

## Step 14: New Leaderboard Display

**Rewrite:** `Sources/DocScanCLI/TerminalUtils.swift`

Remove `ModelPairResultRow`, `ScoreBreakdown`, `formatMetricsTable()`, `formatLeaderboard()`. Replace with:

- `VLMResultRow`: `modelName`, `score`, `totalScore`, `maxScore`, `truePositives`, `trueNegatives`, `falsePositives`, `falseNegatives`, `elapsedSeconds`, `isDisqualified`, `disqualificationReason`
- `TextLLMResultRow`: `modelName`, `score`, `totalScore`, `maxScore`, `fullyCorrectCount`, `partiallyCorrectCount`, `fullyWrongCount`, `elapsedSeconds`, `isDisqualified`, `disqualificationReason`
- `formatVLMLeaderboard(results:)` — columns: #, Model, Score%, Points, TP/TN/FP/FN, Time, Status. Sorted by score desc, time asc for ties.
- `formatTextLLMLeaderboard(results:)` — columns: #, Model, Score%, Points, 2s/1s/0s, Time, Status. Same sort.

Keep: `prompt()`, `promptMasked()`, `menu()`, `confirm()`, `formatPercent()`, `leftPadded()` — shared utilities.

---

## Step 15: Update Cleanup

**Rewrite:** `Sources/DocScanCore/Benchmark/BenchmarkEngine+Cleanup.swift`

Remove `cleanupBenchmarkedModels(benchmarkedPairs:, keepVLM:, keepText:)`. Replace with:

`cleanupBenchmarkedModels(modelNames: [String], keepModel: String?)` — generic version that works for a flat list of model names. Reuses same HF cache path deletion logic. Called twice: once for VLMs, once for TextLLMs.

---

## Step 16: Rewrite Tests

**Delete entirely:**
- `Tests/DocScanCoreTests/BenchmarkEngineTests.swift` — tests old `runInitialBenchmark()`, `benchmarkModelPair()`, `MockDocumentDetectorFactory`
- `Tests/DocScanCoreTests/BenchmarkEngineTests+Extended.swift` — tests old skip paths, negative dir handling for paired flow
- `Tests/DocScanCoreTests/BenchmarkEngineTests+Coverage.swift` — tests old cleanup, timeout, memory for paired flow
- `Tests/DocScanCoreTests/TerminalUtilsTests.swift` — tests `ModelPairResult`, `ModelPairResultRow`, paired leaderboard sorting

**Rewrite:**
- `Tests/DocScanCoreTests/BenchmarkMetricsTests.swift` — replace `DocumentResult`/`BenchmarkMetrics`/`ModelPairResult` tests with tests for `VLMDocumentResult`, `VLMBenchmarkResult`, `TextLLMDocumentResult`, `TextLLMBenchmarkResult`
- `Tests/DocScanCoreTests/HuggingFaceClientTests.swift` — remove `discoverModelPairs()` tests, keep `searchVLMModels()`, `searchTextModels()`, auth, error handling tests
- `Tests/DocScanCoreTests/ConfigurationTests+Benchmark.swift` — update for new `benchmarkVLMModels`/`benchmarkTextLLMModels` config properties

**New:**
- `Tests/DocScanCoreTests/BenchmarkEngineVLMTests.swift` — test `benchmarkVLM()` with mock factory: TP, TN, FP, FN, timeout=0 per doc, elapsed time recorded
- `Tests/DocScanCoreTests/BenchmarkEngineTextLLMTests.swift` — test `benchmarkTextLLM()`: score 0/1/2, negative rejection=2, timeout=0
- `Tests/DocScanCoreTests/TerminalUtilsTests.swift` — new tests for `VLMResultRow`, `TextLLMResultRow`, leaderboard sorting with elapsed time

---

## Key Design Decisions

| Decision | Rationale |
|---|---|
| Remove all paired types and tests | Clean project, no relics from old approach |
| TextLLM categorization via LLM prompt (not keyword detection) | Keyword detection is model-independent → identical scores for all TextLLMs → useless benchmark. LLM prompt tests actual model capability. |
| Timeout per-inference scores 0, does NOT disqualify | Spec says "timed-out inference scores 0 for that document" |
| Negative correctly rejected = 2 pts (TextLLM) | Matches existing `FuzzyMatcher.scoreDocument()` behavior |
| OCR text pre-extracted once | Avoids redundant OCR across N TextLLM models; ensures consistent input |
| `negativeDir` becomes required `@Argument` | Spec: "two directory paths as CLI parameters" |
| Post-benchmark recommendation | User can update config with best VLM + best TextLLM, or keep current |

---

## Files Summary

| Action | File |
|---|---|
| Rewrite | `Sources/DocScanCore/Benchmark/BenchmarkMetrics.swift` |
| Create | `Sources/DocScanCore/Benchmark/DefaultModelLists.swift` |
| Modify | `Sources/DocScanCore/Configuration.swift` |
| Modify | `Sources/DocScanCore/DocumentType.swift` |
| Rewrite | `Sources/DocScanCore/Benchmark/BenchmarkEngine.swift` |
| Create | `Sources/DocScanCore/Benchmark/BenchmarkEngine+VLM.swift` |
| Create | `Sources/DocScanCore/Benchmark/BenchmarkEngine+TextLLM.swift` |
| Delete | `Sources/DocScanCore/Benchmark/BenchmarkEngine+Benchmark.swift` |
| Rewrite | `Sources/DocScanCore/Benchmark/BenchmarkEngine+Cleanup.swift` |
| Modify | `Sources/DocScanCore/Benchmark/HuggingFaceClient.swift` |
| Rewrite | `Sources/DocScanCLI/BenchmarkCommand.swift` |
| Rewrite | `Sources/DocScanCLI/BenchmarkCommand+PhaseA.swift` |
| Rewrite | `Sources/DocScanCLI/BenchmarkCommand+PhaseB.swift` |
| Delete | `Sources/DocScanCLI/BenchmarkCommand+PhaseC.swift` |
| Delete | `Sources/DocScanCLI/BenchmarkCommand+PhaseD.swift` |
| Rewrite | `Sources/DocScanCLI/TerminalUtils.swift` |
| Delete | `Tests/DocScanCoreTests/BenchmarkEngineTests.swift` |
| Delete | `Tests/DocScanCoreTests/BenchmarkEngineTests+Extended.swift` |
| Delete | `Tests/DocScanCoreTests/BenchmarkEngineTests+Coverage.swift` |
| Delete | `Tests/DocScanCoreTests/TerminalUtilsTests.swift` |
| Rewrite | `Tests/DocScanCoreTests/BenchmarkMetricsTests.swift` |
| Modify | `Tests/DocScanCoreTests/HuggingFaceClientTests.swift` |
| Modify | `Tests/DocScanCoreTests/ConfigurationTests+Benchmark.swift` |
| Create | `Tests/DocScanCoreTests/BenchmarkEngineVLMTests.swift` |
| Create | `Tests/DocScanCoreTests/BenchmarkEngineTextLLMTests.swift` |
| Create | `Tests/DocScanCoreTests/TerminalUtilsTests.swift` (new) |

**Untouched:** `ScanCommand`, `DocumentDetector`, `ModelManager`, `TextLLMManager`, `OCREngine`, `PDFUtils`, `FileRenamer`, `StringUtils`, `Errors.swift`, `GroundTruth.swift`, `FuzzyMatcher.swift`, `KeychainManager.swift`

---

## Verification

1. `swift test` — all new tests pass, no old test relics remain
2. `xcodebuild -scheme docscan -configuration Debug build` — compiles
3. Manual test: `docscan benchmark /path/to/positive /path/to/negative --type invoice -v` with a small set of docs and 1-2 models in config override
