# Model Benchmark and Discovery

## Overview
Add a `benchmark` CLI subcommand that evaluates the full document processing pipeline (categorization AND data extraction) against a user-provided corpus of labeled documents, then discovers and evaluates alternative MLX-compatible model pairs from Hugging Face so the user can identify and adopt the best-performing configuration.

## Goals
- Allow users to objectively measure how well their current model configuration performs on both categorization and data extraction using standard metrics (accuracy, precision, recall, F1 score)
- Generate ground-truth JSON sidecar files from the initial run so the user can verify and correct extracted data before benchmarking alternative models
- Automatically discover promising alternative MLX-compatible model pairs from Hugging Face
- Benchmark discovered models against the same corpus using the verified ground truth and present a ranked comparison
- Let the user update the default configuration to a better-performing model pair directly from the results

## Non-Goals
- This feature does NOT rename, move, or modify any document files — documents are read-only (only JSON sidecar files are written beside them)
- This feature does NOT train or fine-tune models — it only evaluates pre-trained models
- This feature does NOT support simultaneous benchmarking of multiple document types in a single run

## User Stories
- As a power user, I want to benchmark my current models against a labeled document set so that I can see how accurately they categorize AND extract data from documents.
- As a user, I want the initial run to produce JSON files with pre-filled extracted data so that I can quickly review and correct them to build ground truth without starting from scratch.
- As a user setting up the application for the first time, I want the tool to suggest high-performing MLX model pairs so that I don't have to manually search Hugging Face.
- As a user, I want to compare multiple model pairs side by side so that I can make an informed decision about which configuration to use.
- As a user, I want to update my default configuration from the benchmark results so that I can adopt a better model without editing config files manually.

## Proposed Solution

### CLI Subcommand

The subcommand name is `benchmark`.

The subcommand accepts:
- A required `--type` argument specifying the document type to benchmark (e.g., `invoice`, `prescription`)
- A required positional argument or `--positive-dir` for the folder of true-positive documents
- An optional `--negative-dir` for the folder of true-negative documents
- Standard flags like `--verbose` and `--config`

### Approach

**Phase A: Initial Run with Current Configuration (Ground Truth Generation)**

1. Load the currently configured VLM and TextLLM model pair from configuration
2. For each PDF document in the positive directory, run the full two-phase pipeline:
   - Phase 1: Categorization (VLM + OCR in parallel)
   - Phase 2: Data Extraction (OCR + TextLLM) — extract date and secondary field (company, doctor, etc.)
3. If a negative directory is provided, run the same pipeline on those documents
4. For each document, output one line to the command line showing:
   - The document filename
   - The categorization result (e.g., "invoice: YES" or "invoice: NO")
   - The extracted data (e.g., "date: 2025-06-27, company: DB_Fernverkehr_AG")
   - This gives the user immediate visibility into what each model produced
5. For each document, write a JSON sidecar file next to the original document with the same filename plus `.json` extension (e.g., `invoice.pdf` produces `invoice.pdf.json`). The JSON file contains:
   - The expected categorization (true/false based on which directory the document is in)
   - The extracted data fields (date, secondary field) as pre-filled by the current models
6. Compute and display accuracy, precision, recall, and F1 score in a compact, right-aligned table format

**Phase A.1: User Verification Pause**

1. After Phase A completes, display a clear message instructing the user to review and correct the JSON sidecar files for every document
2. Explain that the JSON files contain pre-filled data from the current models and serve as the ground truth for benchmarking alternative models
3. Emphasize that correctness of subsequent benchmarks depends entirely on the accuracy of these JSON files
4. Offer the user the option to open all JSON sidecar files at once in their default editor. Use `NSWorkspace.shared.open(_:)` from AppKit to open each file with the system default application for JSON files (the native macOS equivalent of the `open` command). This avoids shelling out to a subprocess and uses the platform API directly
5. Wait for the user to confirm they have reviewed and corrected the JSON files before proceeding
6. The user can also choose to cancel at this point

**Phase A.2: Hugging Face Credential Check**

1. Before searching Hugging Face, check if credentials are already stored:
   - Look up the Hugging Face username from the application's plaintext YAML configuration
   - Look up the Hugging Face API token from the macOS Keychain using the Security framework (`SecItemCopyMatching` / `SecItemAdd` / `SecItemUpdate`)
2. If credentials are not found, inform the user:
   - Explain that a Hugging Face account provides access to a wider range of models, including gated models that require authentication
   - Explain that without credentials, the search is limited to publicly accessible, non-gated models
   - Offer the user three choices: (a) enter credentials now, (b) continue without credentials (limited model selection), or (c) cancel
3. If the user chooses to enter credentials:
   - Prompt for the Hugging Face username — this is stored in plaintext in the YAML configuration file
   - Prompt for the Hugging Face API token — input must be masked (not echoed to the terminal) using terminal raw mode or similar technique
   - Store the API token securely in the macOS Keychain via the Security framework, using a dedicated service name (e.g., `com.docscan.huggingface`) and the username as the account identifier
   - Never write the API token to disk, logs, or configuration files
4. If credentials are already present, proceed directly to Phase B

**Phase B: Discover Alternative Models from Hugging Face**

1. Query the Hugging Face API for MLX-compatible models suitable for document categorization and extraction, authenticating with the stored token if available
2. Prefer newer versions of the currently configured models over entirely different model families
3. Prefer models with higher download counts and community engagement (popularity signal)
4. Include a range of model sizes (e.g., 2B, 4B, 7B variants) to give users size/performance trade-offs
5. Assemble 5 model pairs (each pair = 1 VLM + 1 LLM), presenting 10 models total
6. Present the suggestions interactively and let the user: (a) accept and proceed, (b) request 10 different models, or (c) cancel

**Phase B.1: Timeout Selection**

1. Before benchmarking begins, prompt the user to choose a maximum per-document processing time. Present three options:
   - 10 seconds — strict, favors fast models
   - 30 seconds — balanced (recommended default)
   - 1 minute — lenient, allows larger/slower models
2. Explain that this timeout applies to the full pipeline (categorization + data extraction) for a single document
3. If any document exceeds the timeout for a given model pair, that entire model pair is disqualified: it is excluded from the final ranked results and cannot be selected as a replacement for the current configuration
4. Display the chosen timeout clearly before benchmarking starts so the user knows what threshold is in effect

**Phase C: Benchmark Discovered Models Against Ground Truth**

1. Load the verified JSON sidecar files as ground truth for each document
2. For each accepted model pair, download and load the models
3. Run the full two-phase pipeline (categorization + data extraction) on each document, enforcing the user-chosen per-document timeout
4. If a document exceeds the timeout, immediately stop processing that document, mark the model pair as disqualified, display a message explaining the timeout violation, and skip to the next model pair
5. Determine correctness per document as a binary true/false decision: a document is "correct" only if BOTH the categorization AND every extracted data field match the ground truth exactly
6. After each non-disqualified pair completes, display its metrics (accuracy, precision, recall, F1) immediately
7. After a disqualified pair, display a summary line indicating it was disqualified due to timeout (including which document caused it)
8. Implement additional resilience measures:
   - Check available system memory before loading a model; skip if insufficient
   - Catch and report model loading failures gracefully without crashing
   - Unload each model pair after benchmarking to free memory before loading the next

**Phase D: Final Ranked Results and Configuration Update**

1. After all pairs are benchmarked, display four ranked leaderboards: best by accuracy, precision, recall, and F1 score
2. Prompt the user to optionally update their default configuration to one of the tested model pairs
3. If the user chooses to update, write the new model names to the YAML configuration file

### Key Decisions
- **Full pipeline benchmarking** — evaluating both categorization and data extraction ensures the chosen model pair performs well end-to-end, not just on classification
- **JSON sidecar files as ground truth** — writing pre-filled JSON files next to documents lets the user quickly verify and correct extracted data without building ground truth from scratch; subsequent model runs compare against these verified files
- **Binary correctness for new models** — a document result is "correct" only if categorization AND all extracted fields match ground truth; this reflects real-world usage where a wrong date or company name is a failure even if the categorization was right
- **Per-document command line output** — showing categorization and extraction results for each document during the initial run gives the user immediate visibility into model behavior before they review the JSON files
- **User verification pause** — explicitly stopping between the initial run and alternative model benchmarking ensures the ground truth is accurate before it's used for scoring
- **Keychain for API tokens, plaintext for username** — API tokens and passwords are secrets and must be stored in the macOS Keychain via the Security framework; the username is non-sensitive and stored in the YAML configuration for easy discoverability
- **Masked credential input** — API tokens are never echoed to the terminal during input, following standard security practices for secret entry
- **Graceful unauthenticated fallback** — the user can opt out of credentials entirely; the tool works with public models only and clearly communicates the limitation
- **5 model pairs, not individual models** — the application always uses a VLM+LLM pair together, so benchmarking pairs reflects real-world usage
- **Interactive model selection** — rather than automatically testing dozens of models (which is time-consuming), present curated suggestions and let the user confirm
- **User-chosen timeout with disqualification** — rather than a hardcoded or configurable timeout, the user picks from three concrete options (10s, 30s, 1min) before benchmarking; any model pair that exceeds the timeout on any document is fully disqualified, ensuring only models that meet the user's performance expectations appear in the final results
- **Memory guards** — large models can exceed available RAM on some machines; proactive checks prevent crashes and provide clear feedback
- **Immediate per-pair output** — displaying results after each model pair rather than only at the end gives the user early feedback during what can be a long-running process

## Acceptance Criteria
- [ ] A `benchmark` subcommand is added to the CLI that accepts `--type`, a positive directory, and an optional negative directory
- [ ] The initial run with configured models executes the full pipeline: categorization AND data extraction
- [ ] Each document produces one command-line output line showing filename, categorization result, and all extracted data fields
- [ ] A JSON sidecar file is written next to each document (e.g., `invoice.pdf.json`) containing the expected categorization and pre-filled extracted data
- [ ] After the initial run, the tool pauses and instructs the user to review/correct the JSON files before continuing
- [ ] The tool offers to open all JSON sidecar files in the default editor using `NSWorkspace.shared.open(_:)` (native macOS API, no subprocess)
- [ ] Metrics (accuracy, precision, recall, F1) for the current configuration are displayed in a compact table with right-aligned numbers
- [ ] Before searching Hugging Face, the tool checks for stored credentials (username in config, API token in Keychain)
- [ ] If credentials are missing, the user is informed that unauthenticated access limits available models (no gated models)
- [ ] The user can enter credentials interactively: username stored in YAML config, API token stored in macOS Keychain via Security framework
- [ ] API token input is masked (not echoed to the terminal)
- [ ] API tokens are never written to disk, logs, or configuration files — only stored in the Keychain
- [ ] The user can choose to skip credentials and continue with public models only
- [ ] After credential check, the tool queries Hugging Face for MLX-compatible alternative models (authenticated if credentials are available)
- [ ] The tool presents 5 model pairs (10 models) and offers the user three choices: proceed, request alternatives, or cancel
- [ ] Model suggestions prefer newer versions of configured models, popular models, and include varied sizes
- [ ] Each discovered model pair is benchmarked using the full pipeline against the verified JSON ground truth
- [ ] A document is scored as "correct" only if categorization AND all extracted data fields match the ground truth
- [ ] Results are shown after each model pair completes
- [ ] Before benchmarking alternative models, the user is prompted to choose a per-document timeout: 10 seconds, 30 seconds, or 1 minute
- [ ] The chosen timeout applies to the full pipeline (categorization + extraction) per document
- [ ] If any document exceeds the timeout, the entire model pair is disqualified and excluded from final rankings
- [ ] Disqualified model pairs are clearly marked with the reason (timeout) and the document that caused it
- [ ] Disqualified model pairs cannot be selected as a replacement for the current configuration
- [ ] The tool handles out-of-memory conditions gracefully (skip model, report error, continue)
- [ ] After all benchmarks, four ranked leaderboards are displayed (accuracy, precision, recall, F1)
- [ ] The user can choose to update the default model configuration to one of the benchmarked pairs
- [ ] No documents are renamed, moved, or modified — only JSON sidecar files are written

## Open Questions
- How should the tool handle models that are gated and require accepting license terms on Hugging Face even with a valid API token (some models need explicit web-based license acceptance)? the application should stop in this case and ask the user to either skip this model pair or open a browser, goto the model page, accept the license, and then return to the tool to continue benchmarking. Offer the user to open the model page in their default browser using `NSWorkspace.shared.open(_:)` with the model's Hugging Face URL
- Should the negative directory be truly optional, or should the tool warn that metrics like precision and specificity are undefined without negatives? It should be optional but the user should be warned cleary that some metrics don't apply without negative samples, and the results will focus on recall and accuracy instead.
- For data extraction comparison, should field matching be exact string match or allow fuzzy matching (e.g., date format normalization, minor whitespace differences)? it should definitely be fuzzy matching. So for example 1.0 or 1 or 1.00 is the same.
- If JSON sidecar files already exist from a previous run, should the tool skip regeneration and reuse them (allowing re-benchmarking without re-running the initial phase)? if the JSON file already exists, the tool should prompt the user: "A JSON sidecar file already exists for this document. Do you want to (a) reuse the existing file, (b) regenerate it with current models, or (c) cancel benchmarking?" This allows users to quickly re-benchmark with the same ground truth or update it if they have made changes to their models since the last run.
