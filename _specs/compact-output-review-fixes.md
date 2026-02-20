# Compact Output Review Fixes

## Summary

Address all issues raised in the Claude code review of PR #32 (compact single-line output).
Three items are blocking correctness bugs; the rest are code quality and UX improvements.

## Source

Claude review: https://github.com/timo-jakob/doc-scan-intelligent-operator-swift/pull/32#issuecomment-3937188715

---

## Blocking Bugs

### 1. Infinite loop on EOF in `resolveConflictCompact`

**File:** `Sources/DocScanCLI/DocScanCommand.swift`

When `readLine()` returns `nil` (stdin closed, piped input, CI environment), the while loop in
`resolveConflictCompact` spins forever. The same problem exists in `interactiveResolveVerbose`.

**Fix:** Add an `else` branch that throws `ExitCode.failure` when `readLine()` returns `nil`.

### 2. No TTY check before using `\r` to rewrite lines

**File:** `Sources/DocScanCLI/DocScanCommand.swift`

The progress bar and conflict prompt use `\r` to overwrite the current terminal line in-place.
When stdout is redirected to a file or piped (`docscan invoice.pdf | tee out.txt`), the `\r` is
written as a literal character and the output becomes garbled.

**Fix:** Add a `isInteractiveTerminal: Bool` helper using `isatty(STDOUT_FILENO)`. When not
running in a TTY, skip the `\r` overwrite and fall back to printing each progress update on a new
line instead.

### 3. Fragile timeout detection via string-contains

**File:** `Sources/DocScanCore/DocumentDetector.swift` and `Sources/DocScanCLI/DocScanCommand.swift`

Both the compact and verbose output paths detect timeouts by checking whether `method` contains the
string `"timeout"`:

```swift
let vlmTimedOut = categorization.vlmResult.method.contains("timeout")
```

This silently breaks if the display label ever changes.

**Fix:** Add a dedicated `var isTimedOut: Bool` computed property to `CategorizationResult` that
checks the authoritative source rather than parsing a display string.

---

## Code Quality

### 4. Fake confidence percentages are misleading

**File:** `Sources/DocScanCLI/DocScanCommand.swift`, `Sources/DocScanCore/DocumentDetector.swift`

The values returned by `confidenceScore` (92, 68, 8, 32, …) are hardcoded constants — the models
do not produce them. Displaying `VLM 92%` implies a precise, measured probability when it is
actually a constant mapped from a qualitative tier.

**Fix (chosen approach):** Replace the numeric display with qualitative tier labels in the compact
output. Show `VLM: high · OCR: medium` instead of `VLM 92% · OCR 68%`. Remove the `confidenceScore`
computed property from `CategorizationResult` since it is no longer needed, and update compact
Phase 1 output methods accordingly.

Update the spec file `_specs/compact-single-line-output.md` to reflect the new format.

### 5. `writeStdout` missing `private`

**File:** `Sources/DocScanCLI/DocScanCommand.swift`

`writeStdout` is the only helper in its extension that is not declared `private`. This is an
oversight — mark it `private`.

### 6. `preload` guard readability in `ModelManager`

**File:** `Sources/DocScanCore/ModelManager.swift`

The guard condition `guard currentModelName != modelName || loadedModel == nil` is logically
correct but the intent reads more clearly when the `nil` check comes first:
`guard loadedModel == nil || currentModelName != modelName`.

---

## Tests

No tests were added in PR #32 for the new paths. Add unit tests covering:

- `CategorizationResult.isTimedOut` (both true and false cases)
- `resolveConflictCompact` with auto-resolve (`vlm`, `ocr`, and invalid)
- `determineIsMatchCompact`: agreement (match), agreement (no match), VLM timeout, OCR timeout
- `ModelManager.preload` early-return when model already loaded
- `TextLLMManager.preload` early-return when model already loaded
- The compact Phase 2 output line format (`printCompactPhase2`)

---

## Spec Alignment

### 7. Update spec: remove byte-count from progress bar

The spec `_specs/compact-single-line-output.md` shows `1.2 GB / 2.3 GB` in the download progress
line. The MLX progress callback does not expose byte totals, so this was never implemented. Update
the spec to remove the byte-count element and reflect the actual output.

### 8. Update spec: sequential vs. parallel startup lines

The spec implies both model lines are printed upfront simultaneously (with the second showing
`waiting…` while the first downloads). The implementation prints each line only after the previous
model finishes loading. Update the spec to document the sequential behaviour as the accepted design.

---

## Acceptance Criteria

- [ ] `resolveConflictCompact` exits with failure instead of looping when stdin is closed
- [ ] `interactiveResolveVerbose` exits with failure instead of looping when stdin is closed
- [ ] No `\r` characters written when stdout is not a TTY; progress falls back to newline output
- [ ] `CategorizationResult` exposes `isTimedOut: Bool`; no code checks `.method.contains("timeout")`
- [ ] Compact Phase 1 line shows qualitative tiers (`high`/`medium`/`low`) not numeric percentages
- [ ] `confidenceScore` computed property removed from `CategorizationResult`
- [ ] `writeStdout` is `private`
- [ ] `preload` guard in `ModelManager` has `loadedModel == nil` as the first condition
- [ ] New unit tests pass for all paths listed in the Tests section
- [ ] Spec file updated to match actual output format (no byte count, sequential startup)
