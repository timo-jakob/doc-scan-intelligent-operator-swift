# Plan: Phase B Progress Display

## Context

Phase A (VLM benchmark) has a real-time per-document progress line (`✓ .f...  ✗ ......`). Phase B (TextLLM benchmark) currently processes documents silently with no progress output. This change adds two labeled progress lines to Phase B — one for categorization and one for data extraction — using two-pass rendering.

## File to Modify

`Sources/DocScanCore/Benchmark/BenchmarkEngine+TextLLM.swift` — this is the **only** file that changes.

## Changes

### 1. Add `processTextLLMDocuments()` method

Add a new private method in the existing `private extension BenchmarkEngine` block (after `prepareTextLLM`, before `benchmarkTextLLMDocument`). This mirrors Phase A's `processVLMDocuments()` pattern.

**Pass 1 — Categorization line (real-time):**
- Print `    Cat: ✓ ` prefix, then `.` or `f` per positive doc, then `  ✗ ` separator, then `.` or `f` per negative doc
- `fflush(stdout)` after every character
- Buffer extraction character per positive doc: `n` if categorization failed, otherwise `.` or `f` based on `extractionCorrect`
- Negative docs are NOT added to the extraction buffer

**Pass 2 — Extraction line (from buffer):**
- Print `    Ext: ✓ ` prefix, then all buffered characters in one go
- Only printed if buffer is non-empty (i.e., there are positive samples)

### 2. Update `benchmarkTextLLM()` to call the new method

Replace the two `for` loops (lines 45-55) with:
```swift
let startTime = Date()
let documentResults = await processTextLLMDocuments(
    positivePDFs: positivePDFs,
    negativePDFs: negativePDFs,
    context: context
)
```

## Expected Output

```
    Cat: ✓ .f.....  ✗ ......
    Ext: ✓ .n.....
```

- `Cat:` covers all documents (positive + negative)
- `Ext:` covers positive documents only
- `.` = correct, `f` = incorrect, `n` = not assessed (categorization failed)

## Reference Files (read-only)

- `Sources/DocScanCore/Benchmark/BenchmarkEngine+VLM.swift` — `processVLMDocuments()` (lines 59-94) is the pattern to follow
- `Sources/DocScanCore/Benchmark/BenchmarkMetrics.swift` — `TextLLMDocumentResult` fields: `categorizationCorrect`, `extractionCorrect`, `isPositiveSample`

## Verification

1. `swift test` — all 589 existing tests must pass (no test changes needed; progress output goes to stdout and doesn't affect return values)
2. `make lint` — 0 violations
