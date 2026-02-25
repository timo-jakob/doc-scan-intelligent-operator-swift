# Plan: Collection-Based VLM Model Selection

## Context

Currently, Phase A (VLM benchmark) draws models from a hardcoded 46-model list in `DefaultModelLists.vlmModels`, with an optional config-based override via `BenchmarkSettings.vlmModels`. This plan replaces that with live HuggingFace API discovery: the user names a model family (e.g., "Qwen3-VL", "FastVLM") and the system finds all MLX-compatible VLM variants automatically.

Spec: `_specs/collection-based-vlm-selection.md`

## Resolved Open Questions

- **`--limit`**: Yes. Default 25, overridable via `--limit <n>`.
- **Gated models**: Include them but print a `(gated)` annotation next to the model name in the discovery listing.
- **mlx-community prefix**: No. Rely purely on the `mlx` tag filter to avoid excluding models like `apple/FastVLM-*`.

## Files to Modify

| File | Change |
|------|--------|
| `Sources/DocScanCore/Benchmark/HuggingFaceClient.swift` | Add `searchVLMCollection()`, remove `searchVLMModels()` |
| `Sources/DocScanCore/Benchmark/DefaultModelLists.swift` | Remove `vlmModels` list |
| `Sources/DocScanCore/Configuration.swift` | Remove `vlmModels` from `BenchmarkSettings` |
| `Sources/DocScanCLI/BenchmarkCommand.swift` | Add `--collection` and `--limit` options, add collection resolution logic |
| `Sources/DocScanCLI/BenchmarkCommand+PhaseA.swift` | Use resolved collection models instead of config/defaults |
| `Tests/DocScanCoreTests/HuggingFaceClientTests.swift` | Replace `searchVLMModels` tests with `searchVLMCollection` tests |
| `Tests/DocScanCoreTests/ConfigurationTests+Benchmark.swift` | Remove/update tests referencing `vlmModels` |

## Steps

### Step 1: Add `searchVLMCollection()` to HuggingFaceClient

**File**: `Sources/DocScanCore/Benchmark/HuggingFaceClient.swift`

Add a new public method that:
- Takes `collection: String` and `limit: Int = 25`
- Builds query: `"{collection}"` with `pipeline_tag=image-text-to-text` as an additional query parameter
- Calls existing `searchModels(query:limit:)` (requires making `searchModels` support the extra `pipeline_tag` parameter, OR add a new private `searchModelsWithPipelineTag` that appends `&pipeline_tag=image-text-to-text` to the path)
- Post-filters results: keep only models where `tags` contains `"mlx"`
- Returns `[HFModel]` (already sorted by downloads from the API)

Remove the old `searchVLMModels()` method.

### Step 2: Remove `vlmModels` from DefaultModelLists

**File**: `Sources/DocScanCore/Benchmark/DefaultModelLists.swift`

Delete the entire `vlmModels` static property (lines 6-46). Keep `textLLMModels` unchanged.

If `DefaultModelLists` only has `textLLMModels` left, update the doc comment accordingly.

### Step 3: Remove `vlmModels` from BenchmarkSettings and Configuration

**File**: `Sources/DocScanCore/Configuration.swift`

- Remove `vlmModels` property from `BenchmarkSettings`
- Remove `vlmModels` from `BenchmarkSettings.init()`
- Remove `benchmarkVLMModels` from `Configuration.init(from:)` decoding
- Remove `benchmarkVLMModels` from `Configuration.encode(to:)` encoding
- Remove the `benchmarkVLMModels` coding key if it becomes unused (check if the key is only used for VLM)

### Step 4: Add `--collection` and `--limit` CLI options

**File**: `Sources/DocScanCLI/BenchmarkCommand.swift`

Add two new `@Option` properties:
```
@Option(name: .long, help: "VLM model family to benchmark (e.g. Qwen3-VL, FastVLM)")
var collection: String?

@Option(name: .long, help: "Maximum number of VLM models to discover (default: 25)")
var limit: Int = 25
```

Add a new private method `resolveVLMCollection() async throws -> [String]`:
1. If `collection` is non-nil, use it directly
2. If `collection` is nil, call `TerminalUtils.prompt("Enter VLM model family/collection (e.g. Qwen3-VL, FastVLM):")`
3. If the prompt result is nil or empty after trimming, print error and throw `ExitCode.failure`
4. Create `HuggingFaceClient` (with optional API token from keychain)
5. Call `client.searchVLMCollection(collection: name, limit: limit)`
6. If results are empty, print `"No MLX-compatible VLM models found for '\(name)'"` and throw `ExitCode.failure`
7. Print discovered models with numbering: `"  1. mlx-community/Qwen2-VL-2B-Instruct-4bit"`, annotating gated models with `(gated)`
8. Return the array of `modelId` strings

In `run()`, call `resolveVLMCollection()` after `promptHuggingFaceCredentials()` and before `runPhaseA()`. Pass the result to `runPhaseA()`.

### Step 5: Update Phase A to accept model list parameter

**File**: `Sources/DocScanCLI/BenchmarkCommand+PhaseA.swift`

Change `runPhaseA()` signature to accept a `vlmModels: [String]` parameter.

Replace line 18:
```swift
let vlmModels = configuration.benchmark.vlmModels ?? DefaultModelLists.vlmModels
```
with direct use of the passed-in `vlmModels` parameter.

Update the call site in `BenchmarkCommand.swift` `run()` to pass the resolved models.

### Step 6: Update HuggingFaceClient tests

**File**: `Tests/DocScanCoreTests/HuggingFaceClientTests.swift`

- Replace all `searchVLMModels()` calls with `searchVLMCollection(collection:)` calls
- Update `testSearchRequestUsesCorrectBaseURL` to check for `pipeline_tag=image-text-to-text` in the URL
- Add a test for MLX tag filtering: mock returns 3 models (2 with `"mlx"` tag, 1 without) → assert only 2 are returned
- Add a test for gated model annotation: mock returns a gated model → assert `isGated` is true on the result
- Update error tests (`testNetworkErrorThrows`, `testUnauthorizedThrows`, `testForbiddenThrows`, `testRateLimitedRetriesThenThrows`, `testEmptyResultsDoNotCrash`) to use the new method name

### Step 7: Update Configuration tests

**File**: `Tests/DocScanCoreTests/ConfigurationTests+Benchmark.swift`

- Remove `testBenchmarkVLMModelsSetter` (tests `config.benchmark.vlmModels`)
- Remove `testDefaultBenchmarkModelListsAreNil` assertion for `vlmModels` (keep `textLLMModels` assertion)
- Remove `testCustomBenchmarkModelLists` VLM assertions (keep textLLM assertions)
- Update `testYAMLRoundTripWithBenchmarkModels` to only test `textLLMModels`
- Update `testYAMLRoundTripWithAllBenchmarkFields` to remove `vlmModels`
- Update `testBenchmarkSettingsEquatable` to not use `vlmModels`
- Update `testYAMLBackwardsCompatibilityWithoutBenchmarkModels` — keep only `textLLMModels` assertion

## Verification

1. `swift test` — all tests pass (with updated/removed tests)
2. `make lint` — 0 violations
3. Manual: `xcodebuild` build succeeds
4. Manual: `docscan benchmark pos/ neg/ --collection Qwen3-VL --limit 3` discovers models and runs Phase A

## Dependency Order

Steps 1-3 are independent and can be done in any order. Step 4 depends on Step 1 (needs `searchVLMCollection`). Step 5 depends on Step 4 (call site change). Steps 6-7 depend on Steps 1-3 respectively (test the new code).

Recommended order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → verify.
