# Phase B Progress Display

## Overview
Add real-time per-document progress display to Phase B (TextLLM benchmark), matching the existing Phase A style. Phase B evaluates two aspects per document — categorization and data extraction — so the display uses two progress lines instead of one.

## Goals
- Show real-time per-document progress during Phase B benchmark runs, matching Phase A's visual style
- Display categorization results on the first line and data extraction results on the second line
- Introduce a third progress character (`n`) for documents where data extraction is not applicable because categorization already failed
- Give developers immediate visual feedback on which documents pass or fail each aspect

## Non-Goals
- Changing Phase A's existing progress display
- Modifying scoring logic or benchmark results
- Changing the leaderboard or summary output format
- Adding progress display to any other part of the system

## User Stories
- As a developer running Phase B benchmarks, I want to see real-time progress for each document so that I can monitor the benchmark as it runs rather than waiting for the final summary.
- As a developer, I want to see categorization and data extraction results on separate lines so that I can immediately tell which aspect is failing for which documents.
- As a developer, I want to see at a glance when data extraction was skipped (because categorization failed) so that I can distinguish "not tested" from "tested and failed".

## Proposed Solution

### Approach

Add two real-time progress lines to Phase B's `benchmarkTextLLM()` method, printed character-by-character as each document is processed — identical to how Phase A prints its single progress line.

**Line 1 — Categorization:**
Displays categorization results for all documents (positive then negative), using the same format as Phase A:

```
    ✓ .f.....f.f.........  ✗ ......
```

- `.` = categorization correct
- `f` = categorization incorrect

**Line 2 — Data Extraction (positive examples only):**
Displays data extraction results for positive examples only. Negative examples are omitted entirely because extraction is never assessed for them (no ground-truth data to compare against — every result would be `n`).

```
    ✓ .n.....n.n.........
```

- `.` = extraction correct
- `f` = extraction incorrect
- `n` = not assessed (categorization was incorrect for this document, so extraction was skipped)

**Rendering strategy: Two-pass rendering**
The categorization line is printed in real time (character by character as each document is processed). Extraction results are buffered during this pass. Once all documents complete, the extraction line is printed from the buffer. This is consistent with Phase A's pattern and avoids ANSI cursor manipulation.

### Key Decisions
- Use `n` (not assessed) as the third character rather than `-` or `s` (skip) because it clearly communicates that the test was not applicable rather than deliberately skipped or a separator
- Display categorization first, extraction second — this mirrors the logical processing order (categorization determines whether extraction runs)
- Negative examples are omitted from the extraction line entirely because extraction scoring does not apply to them (no ground-truth data) — displaying only `n` characters would add noise without information
- Two-pass rendering is preferred over ANSI cursor manipulation for simplicity and terminal compatibility

## Acceptance Criteria
- [ ] Phase B prints a real-time categorization progress line in the same style as Phase A (`✓ .f...  ✗ ......`)
- [ ] Phase B prints a data extraction progress line immediately after the categorization line
- [ ] Extraction line uses `.` for correct, `f` for incorrect, and `n` for not assessed
- [ ] Documents where categorization is incorrect show `n` on the extraction line
- [ ] Extraction line only covers positive examples; negative examples are omitted
- [ ] Progress characters are flushed to stdout immediately (no buffering) for real-time display
- [ ] Existing Phase A progress display is unchanged
- [ ] Scoring logic and benchmark results are unchanged
- [ ] All existing tests continue to pass

## Open Questions
- Should there be a label prefix on each line (e.g. `Cat: ✓ ...` and `Ext: ✓ ...`) to clarify what each line represents, or is the positional convention (line 1 = categorization, line 2 = extraction) sufficient? Yes, please add labels for clarity.
