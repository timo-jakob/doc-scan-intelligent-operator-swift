# Compact Single-Line Output Format

## Summary

Redesign the CLI output to be compact and multi-file friendly. Each processing phase should produce at most one line of output in the happy path, making it easy to scan results when processing many documents in sequence.

## Problem

The current output is verbose and multi-line per document. When processing multiple files, the terminal fills up quickly and it becomes hard to find the relevant result for each file. Headers, separators, and multi-line phase blocks make it hard to compare outcomes at a glance.

## Goals

- On startup: print 1 line per model showing which model is in use
- If a model is not cached locally: show a 1-line download progress bar per model before processing begins
- Phase 1 (Categorisation) output: exactly 1 line
- Phase 2 (Data Extraction) output: exactly 1 line
- Extracted values summary: exactly 1 line
- Conflict prompts (user resolution): exactly 1 line
- Keep all emoji icons — they aid quick visual scanning
- Output must be well-aligned and readable in a standard terminal (80+ columns)
- Show confidence level for VLM and OCR categorisation results on each Phase 1 line
- When a document is not recognised, report it as "unknown document" — not as a negation of the expected type (e.g. never say "not an invoice")

## Non-Goals

- No changes to the underlying detection or extraction logic
- No changes to verbose/debug mode (existing `-v` flag behaviour may remain unchanged or be separately scoped)
- No changes to dry-run or auto-resolve logic beyond their display lines

## Desired Output Format

### Startup — Models Already Cached

Two lines printed once at the start of every run:

```
🤖 VLM    mlx-community/Qwen2-VL-2B-Instruct-4bit
📝 Text   mlx-community/Qwen2.5-7B-Instruct-4bit
```

### Startup — Models Need Downloading

When one or both models are not yet in the local cache, a progress bar is shown on the same line, updating in place until the download completes. One line per model:

```
🤖 VLM    mlx-community/Qwen2-VL-2B-Instruct-4bit  ⬇️  [████████░░░░░░░░]  52%  1.2 GB / 2.3 GB
📝 Text   mlx-community/Qwen2.5-7B-Instruct-4bit   ⬇️  [░░░░░░░░░░░░░░░░]   0%  waiting…
```

Once a download finishes, the line resolves to the standard ready format:

```
🤖 VLM    mlx-community/Qwen2-VL-2B-Instruct-4bit  ✅ ready
📝 Text   mlx-community/Qwen2.5-7B-Instruct-4bit   ✅ ready
```

Downloads run sequentially (VLM first, then Text model). Processing begins only after both models are ready.

### Happy Path (no conflict)

One line per phase, one summary line. Confidence is shown as a percentage for VLM and OCR separately:

```
📋 Phase 1  ✅ invoice  VLM 94% · OCR 87%
📄 Phase 2  ✅ extracted  2025-06-27 · DB_Fernverkehr_AG
✏️  Renamed  invoice.pdf → 2025-06-27_Rechnung_DB_Fernverkehr_AG.pdf
```

### Conflict Path (user prompt on one line)

Confidence is shown per source to help the user decide:

```
📋 Phase 1  ⚠️  conflict  VLM=YES 91% · OCR=NO 43%  →  Use [v]lm or [o]cr?
```

### Not a Match (document type unknown)

When neither VLM nor OCR recognise the document as any known type, report it as unknown — never as a negation of the requested type:

```
📋 Phase 1  ❌ unknown document  VLM 12% · OCR 8%
```

### Dry Run

```
✏️  Dry run  invoice.pdf → 2025-06-27_Rechnung_DB_Fernverkehr_AG.pdf
```

## Acceptance Criteria

- [ ] On startup, exactly 2 lines are printed showing the VLM and Text model names
- [ ] When models are already cached, no progress bar is shown
- [ ] When a model needs downloading, a 1-line progress bar per model updates in place until complete
- [ ] Processing does not begin until both models are ready
- [ ] Processing a single recognised document produces exactly 3 lines of output (Phase 1, Phase 2, rename/dry-run)
- [ ] A conflict prompt fits on one line and accepts a single keypress response
- [ ] A document not matching any known type produces exactly 1 line reading "unknown document" — no mention of any specific document type
- [ ] Phase 1 line always shows VLM confidence % and OCR confidence %
- [ ] Conflict line shows per-source confidence to help user decide
- [ ] All lines stay within 100 characters for typical inputs
- [ ] Icons are preserved on each line
- [ ] Output is unchanged when `-v` / `--verbose` flag is used (verbose mode keeps its existing detail)

## Out of Scope

- Batch/folder processing mode (separate feature)
- Parallel model downloads (downloads are sequential: VLM first, then Text model)
- Colour/ANSI formatting beyond existing icons
