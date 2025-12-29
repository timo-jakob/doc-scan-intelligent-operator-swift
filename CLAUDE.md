# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Workflow

**IMPORTANT: Always use GitHub Flow for bug fixes and feature development**

When fixing bugs or implementing features, you MUST:

1. **Create a new branch** from `main` with a descriptive name:
   ```bash
   git checkout -b fix/issue-description
   # or
   git checkout -b feature/feature-name
   ```

2. **Commit changes** to the branch (NOT directly to `main`)
   - Use clear, descriptive commit messages
   - Include the Claude Code co-authorship footer

3. **Open a Pull Request** when ready for review:
   ```bash
   gh pr create --title "Fix: Description" --body "..."
   ```

4. **Do NOT commit directly to `main`** - all changes should go through Pull Requests

Branch naming conventions:
- Bug fixes: `fix/short-description`
- Features: `feature/short-description`
- Refactoring: `refactor/short-description`
- Documentation: `docs/short-description`

## Project Overview

**doc-scan-intelligent-operator-swift** - Swift rewrite of the AI-powered invoice detection and renaming system, optimized for Apple Silicon using MLX Vision-Language Models. Built entirely in Swift for maximum performance and native macOS integration.

**Key Focus**: Native macOS invoice processing with format `YYYY-MM-DD_Rechnung_Company.pdf`

**Architecture**: Two-phase verification system:
- **Phase 1**: Categorization (VLM + OCR in parallel) - "Is this an invoice?"
- **Phase 2**: Data Extraction (OCR + TextLLM only) - Extract date and company

## Technology Stack

- **Language**: Swift 6.0+
- **Platform**: macOS 14.0+ (Sonoma or later)
- **AI/ML Framework**: MLX Swift (Vision-Language Models on Apple Silicon)
- **Package Manager**: Swift Package Manager (SPM)
- **Interface**: Command-line interface using ArgumentParser
- **Document Processing**: PDFKit (PDF to image), AppKit (image handling)
- **Configuration**: YAML-based (using Yams)
- **Testing**: XCTest framework

## Development Commands

### Building

**IMPORTANT: MLX Swift requires Xcode to compile Metal shaders**

The `swift build` command cannot compile Metal shaders, which causes the VLM to fail with:
```
MLX error: Failed to load the default metallib. library not found
```

**Use `xcodebuild` for full functionality:**

```bash
# Build with xcodebuild (required for VLM/Metal support)
xcodebuild -scheme docscan -configuration Debug -destination 'platform=macOS' build

# The binary will be at:
# ~/Library/Developer/Xcode/DerivedData/doc-scan-intelligent-operator-swift-*/Build/Products/Debug/docscan

# Alternative: Open in Xcode and build with ⌘+B
open Package.swift
```

**For OCR-only testing (no VLM):**
```bash
# swift build works for OCR-only mode
swift build

# Run with --auto-resolve ocr to skip VLM
.build/debug/docscan invoice.pdf --dry-run --auto-resolve ocr
```

```bash
# Clean build artifacts
swift package clean
```

### Running

```bash
# Run the Xcode-built binary (full VLM + OCR support)
~/Library/Developer/Xcode/DerivedData/doc-scan-intelligent-operator-swift-*/Build/Products/Debug/docscan invoice.pdf

# Run with arguments
~/Library/Developer/Xcode/DerivedData/doc-scan-intelligent-operator-swift-*/Build/Products/Debug/docscan invoice.pdf --dry-run -v

# Run the release binary
.build/release/docscan invoice.pdf
```

### Testing

```bash
# Run all tests
swift test

# Run with verbose output
swift test --verbose

# Run specific test suite
swift test --filter ConfigurationTests
swift test --filter FileRenamerTests
swift test --filter InvoiceDetectorTests

# Generate code coverage (requires Xcode)
swift test --enable-code-coverage
```

### Code Quality

```bash
# Format code (if SwiftFormat is installed)
swiftformat .

# Lint code (if SwiftLint is installed)
swiftlint

# Update dependencies
swift package update
```

## Project Architecture

### Core Components

The project follows a modular Swift architecture:

1. **Configuration (`Configuration.swift`)** - YAML-based configuration
   - Model settings (name, cache directory)
   - Generation parameters (max tokens, temperature)
   - PDF processing settings (DPI)
   - Output formatting (date format, filename pattern)
   - Supports loading from YAML files using Yams

2. **PDF Utils (`PDFUtils.swift`)** - PDF processing using PDFKit
   - Validates PDF files
   - Converts PDF pages to NSImage
   - Configurable DPI (default: 150)
   - Optimized for invoice processing

3. **Model Manager (`ModelManager.swift`)** - VLM loading and inference
   - Loads Vision-Language Models using `loadModel()` and `ChatSession` API
   - Uses proper image handling via temporary file URLs
   - Caches models locally in `~/.cache/docscan/models`
   - Manages model downloads from Hugging Face with progress tracking
   - Supports Qwen2-VL series models optimized for Apple Silicon
   - **Used for categorization only** (simple YES/NO invoice detection)

4. **Text LLM Manager (`TextLLMManager.swift`)** - Text-based LLM for data extraction
   - Uses Qwen2.5-7B-Instruct for analyzing OCR text
   - Extracts invoice date and company name from text
   - More accurate than VLM for structured data extraction
   - Separate from VLM to optimize for each task

5. **OCR Engine (`OCREngine.swift`)** - Native text recognition using Apple Vision
   - Extracts text from images using Vision framework
   - Detects invoice indicators in multiple languages (DE, EN, FR, ES)
   - `detectInvoiceKeywords()` - Returns confidence and reason for categorization
   - `extractDateAndCompany()` - Uses TextLLM for accurate data extraction
   - Provides complete invoice data extraction pipeline

6. **Invoice Detector (`InvoiceDetector.swift`)** - Two-phase verification system
   - **Phase 1: Categorization** (VLM + OCR in parallel)
     - VLM answers: "Is this an invoice? YES/NO"
     - OCR uses keyword detection (rechnung, invoice, etc.)
     - If both agree → proceed automatically
     - If conflict → user chooses (or `--auto-resolve`)
   - **Phase 2: Data Extraction** (OCR + TextLLM only)
     - Uses cached OCR text from Phase 1
     - TextLLM extracts date and company
     - No VLM involvement (more accurate)
   - Returns `CategorizationVerification` and `ExtractionResult`
   - Generates standardized filenames from extracted data

7. **File Renamer (`FileRenamer.swift`)** - Safe file operations
   - Renames files with extracted data
   - Handles filename collisions (adds _1, _2, etc.)
   - Supports dry-run mode
   - In-place or directory-based renaming

8. **Errors (`Errors.swift`)** - Error handling
   - Custom `DocScanError` enum
   - Localized error descriptions
   - Comprehensive error types for all failure modes

9. **CLI (`DocScanCommand.swift`)** - Command-line interface
   - Built with swift-argument-parser
   - Async/await support
   - Two-phase display with clear separation
   - Shows categorization results (Phase 1)
   - Shows extraction results (Phase 2)
   - Interactive conflict resolution for categorization disagreements
   - `--auto-resolve vlm|ocr` for automation/testing

### Data Flow

```
PDF File → PDF Validation → PDF to Image
                                ↓
              ┌─────── PHASE 1: Categorization ───────┐
              │  (VLM + OCR in parallel)              │
              │                                        │
              │  VLM: "Is this an invoice? YES/NO"    │
              │  OCR: Keyword detection + cache text   │
              │                                        │
              │  Both agree? → Proceed                 │
              │  Conflict?   → User chooses / auto     │
              └────────────────────────────────────────┘
                                ↓
              ┌─────── PHASE 2: Data Extraction ──────┐
              │  (OCR + TextLLM only)                 │
              │                                        │
              │  Use cached OCR text                  │
              │  TextLLM extracts: date, company      │
              └────────────────────────────────────────┘
                                ↓
              Filename Generation → Safe File Renaming
```

### Invoice Processing Workflow (Two-Phase)

1. **Validation**: Check if file is valid PDF using PDFKit
2. **Conversion**: Convert first page to NSImage (configurable DPI)

**PHASE 1: Categorization (Parallel)**

3. **VLM Categorization**: Simple prompt asking "Is this an invoice? YES/NO"
4. **OCR Categorization**: Extract text + keyword detection (rechnung, invoice, etc.)
   - OCR text is cached for Phase 2
5. **Agreement Check**:
   - **Both agree (invoice)**: Proceed to Phase 2
   - **Both agree (not invoice)**: Exit
   - **Conflict**: User chooses or `--auto-resolve vlm|ocr`

**PHASE 2: Data Extraction (Sequential)**

6. **TextLLM Extraction**: Analyze cached OCR text to extract:
   - Invoice date (formatted as YYYY-MM-DD)
   - Company name (sanitized for filename)
7. **Filename Generation**: Create `{date}_Rechnung_{company}.pdf`
8. **Renaming**: Safely rename with collision handling

### How Parallel Processing Works (Phase 1)

Phase 1 (Categorization) uses Swift's structured concurrency (`Task`) to run VLM and OCR categorization simultaneously.

#### Implementation Details

**Location**: `Sources/DocScanCore/InvoiceDetector.swift` - `categorize()` method

**Step 1: Both Tasks Start Immediately**
```swift
// VLM categorization starts immediately
let vlmTask = Task {
    try await self.categorizeWithVLM(image: image)
}

// OCR categorization starts immediately (also caches text for Phase 2)
let ocrTask = Task {
    try await self.categorizeWithOCR(image: image)
}
```

**Step 2: Wait for Both to Complete**
```swift
// Wait for VLM to finish
vlm = try await vlmTask.value

// Wait for OCR to finish
ocr = try await ocrTask.value
```

#### Execution Timeline

```
Time 0ms:  PDF converted to image

Time 10ms: VLM Task starts ────────────────┐  (asks "Invoice? YES/NO")
           OCR Task starts ───────┐         │  (keyword detection)
                                  │         │
                                  ▼         ▼
           Both running in parallel

Time 1s:   OCR finishes ─────────X         │  (keywords found, text cached)
           VLM still running ───────────────┤

Time 3s:   VLM finishes ─────────────────X    (answers "YES")

           Compare categorization results
           If agree → Phase 2 (extraction)
```

#### Why Two Phases?

1. **VLM is good at categorization** - Simple YES/NO questions work well
2. **VLM is poor at data extraction** - Often reads wrong dates/companies
3. **OCR+TextLLM is accurate for extraction** - Text-based analysis is more reliable
4. **Parallel categorization saves time** - Both methods run simultaneously
5. **OCR text is cached** - No need to re-extract in Phase 2

#### Verification in Verbose Mode

```bash
docscan invoice.pdf -v
```

Output shows the two-phase flow (searchable PDF example):
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 PHASE 1: Categorization (VLM + OCR in parallel)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

VLM: Starting categorization...
PDF: Using direct text extraction for categorization...
VLM response: Yes
✅ VLM and PDF text agree: This IS an invoice

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📄 PHASE 2: Data Extraction (OCR + TextLLM)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Extracting invoice data (OCR+TextLLM)...
   📅 Date: 2025-06-27
   🏢 Company: DB_Fernverkehr_AG
```

For scanned PDFs (no extractable text), the output shows:
```
VLM: Starting categorization...
OCR: Starting Vision OCR (scanned document)...
OCR: Extracted 1413 characters
VLM response: Yes
✅ VLM and Vision OCR agree: This IS an invoice
```

### Configuration

Configuration is loaded from YAML files with the following precedence:
1. CLI arguments (highest priority)
2. Custom config file (via `-c/--config`)
3. Default configuration in `Configuration.swift`

Example configuration:
```yaml
modelName: mlx-community/Qwen2-VL-2B-Instruct-4bit
modelCacheDir: ~/.cache/docscan/models
maxTokens: 256
temperature: 0.1
pdfDPI: 150
verbose: false
dateFormat: yyyy-MM-dd
filenamePattern: "{date}_Rechnung_{company}.pdf"
```

## MLX Integration

This project leverages MLX Swift for Apple Silicon acceleration with two model types:

### VLM (Vision-Language Model) - Categorization Only

Used in Phase 1 for simple invoice detection (YES/NO):

- Models: Qwen2-VL series (2B, 7B variants)
- Task: "Is this an invoice?" → YES/NO
- Loaded via `ModelManager.swift`

```swift
// Simple categorization prompt
let prompt = "Is this document an INVOICE? Answer YES or NO"
let response = try await session.respond(to: prompt, image: .url(tempURL))
```

### Text LLM - Data Extraction

Used in Phase 2 for accurate data extraction from OCR text:

- Model: `mlx-community/Qwen2.5-7B-Instruct-4bit`
- Task: Extract date and company from text
- Loaded via `TextLLMManager.swift`

```swift
// Data extraction from OCR text
let (date, company) = try await textLLM.extractDateAndCompany(from: ocrText)
```

### Why Two Model Types?

| Task | VLM | TextLLM | Winner |
|------|-----|---------|--------|
| "Is this an invoice?" | ✅ Good | ✅ Good | Both work |
| Extract date | ❌ Often wrong | ✅ Accurate | TextLLM |
| Extract company | ❌ Picks wrong text | ✅ Accurate | TextLLM |

VLMs excel at visual understanding but struggle with precise text extraction. TextLLMs working on OCR output are more reliable for structured data.

### Supported Models

**VLM (Categorization):**
- `mlx-community/Qwen2-VL-2B-Instruct-4bit` (faster)
- `mlx-community/Qwen2-VL-7B-Instruct-4bit` (more accurate)

**TextLLM (Extraction):**
- `mlx-community/Qwen2.5-7B-Instruct-4bit` (recommended)

### Build Requirements

**Important**: MLX requires Xcode build for proper Metal library bundling:
```bash
# SPM build has Metal library issues
swift build  # ❌ May fail at runtime

# Use Xcode build instead
xcodebuild -scheme docscan -configuration Debug build  # ✅ Works
```

## Testing Strategy

Tests use XCTest with Swift's native testing features:

- `ConfigurationTests.swift` - Configuration loading and defaults
- `FileRenamerTests.swift` - File operations and collision handling
- `InvoiceDetectorTests.swift` - Filename generation and data validation
- `OCREngineTests.swift` - OCR text extraction and parsing
- `VerificationTests.swift` - Dual verification result comparison

**Integration Testing:**
Full end-to-end testing with real invoices:
```bash
# Test with auto-resolve for non-interactive testing
.build/debug/docscan invoice.pdf -v --dry-run --auto-resolve ocr

# Test with 7B VLM model
.build/debug/docscan invoice.pdf -v --dry-run -m "mlx-community/Qwen2-VL-7B-Instruct-4bit" --auto-resolve ocr
```

Testing best practices:
- Use temporary directories for file operations
- Clean up test artifacts in `tearDown()`
- Test both success and failure cases
- Use `XCTAssertThrowsError` for error cases

## SonarQube Cloud Integration

The project uses SonarQube Cloud for code quality analysis. Analysis runs automatically on:
- Push to `main` branch
- Pull requests targeting `main`

### Setup Requirements

1. **Add SONAR_TOKEN secret to GitHub repository:**
   - Go to [SonarQube Cloud](https://sonarcloud.io) → Your Account → Security
   - Generate a new token
   - Add it to GitHub: Repository → Settings → Secrets → Actions → New secret
   - Name: `SONAR_TOKEN`, Value: your generated token

2. **Project Configuration:**
   - Organization: `timo-jakob-github`
   - Project Key: `timo-jakob_doc-scan-intelligent-operator-swift`
   - Configuration file: `sonar-project.properties`

### What Gets Analyzed

- Source code in `Sources/`
- Test code in `Tests/`
- Code coverage from xcodebuild tests
- SwiftLint issues (if SwiftLint is installed)

### Quality Gate

The workflow includes a Quality Gate check that will:
- Pass if the code meets quality standards
- Fail if new code introduces issues above thresholds

### Quality Requirements (MUST follow)

**IMPORTANT**: Before merging any PR, ensure the following requirements are met:

1. **Check SonarQube Status**: Always verify the SonarQube Cloud analysis passes on PRs
   - Use `gh pr checks <PR_NUMBER>` to check status
   - Wait for the "SonarQube Code Analysis" check to complete

2. **No Code Smells**: Zero code smells of any category are allowed
   - Fix all code smells before merging
   - This includes: complexity, duplication, maintainability issues

3. **Test Coverage**: Minimum **90% test coverage on new code**
   - All new functions and methods must have tests
   - Move logic to testable locations (DocScanCore) when needed
   - Run `swift test` locally before pushing

4. **Workflow**:
   - Write tests alongside new code, not as an afterthought
   - If SonarQube fails, fix issues and push again
   - Never merge with failing quality checks

## Snyk Security Analysis

The project uses Snyk for security vulnerability scanning. Analysis runs automatically on:
- Push to `main` branch
- Pull requests targeting `main`
- Weekly schedule (Sundays at midnight) to catch new vulnerabilities

### Setup Requirements

1. **Add SNYK_TOKEN secret to GitHub repository:**
   - Go to [Snyk](https://app.snyk.io) → Account Settings → Auth Token
   - Copy your API token
   - Add it to GitHub: Repository → Settings → Secrets → Actions → New secret
   - Name: `SNYK_TOKEN`, Value: your API token

2. **Organization Configuration:**
   - Organization: `timo-jakob`

### What Gets Scanned

- **Snyk Open Source**: Scans Swift Package Manager dependencies for known vulnerabilities
- **Snyk Code**: Static analysis of source code for security issues

### Monitoring

On pushes to `main`, dependencies are monitored in Snyk dashboard for ongoing vulnerability tracking.

## Key Implementation Notes

### Modifying Configuration

To add new configuration options:
1. Add property to `Configuration` struct
2. Update `init()` with default value
3. Add to YAML encoding/decoding (automatic with Codable)
4. Update CLI to accept override if needed
5. Update example in README.md

### Working with PDFs

PDFKit integration notes:
- Always validate PDFs before processing
- Handle multi-page PDFs (currently only first page)
- Consider memory usage for high DPI conversions
- NSImage quality depends on DPI setting

### Two-Phase Architecture

The system uses a two-phase approach for optimal accuracy:

1. **Phase 1: Categorization (Parallel)**
   - VLM: Simple YES/NO question
   - OCR: Keyword detection
   - Both run in parallel using Swift Tasks
   - OCR caches text for Phase 2

2. **Phase 2: Data Extraction (OCR+TextLLM)**
   - Uses cached OCR text (no re-extraction needed)
   - TextLLM extracts date and company
   - More accurate than VLM for structured data

**Key Design Decisions:**
- VLM is only used for categorization (what it's good at)
- Data extraction uses TextLLM (more accurate)
- OCR text is cached between phases (efficiency)
- Conflicts only occur in categorization (simpler resolution)

### Adding New Features

When adding new features:
1. Add implementation to appropriate module in `Sources/DocScanCore/`
2. Update tests in `Tests/DocScanCoreTests/`
3. Update CLI in `Sources/DocScanCLI/DocScanCommand.swift` if needed
4. Update CLAUDE.md with new functionality
5. Follow Swift naming conventions and style

### Error Handling

Always use `DocScanError` for domain-specific errors:
- Throw, don't fatalError() or force unwrap
- Provide descriptive error messages
- Use localized descriptions
- Handle errors gracefully in CLI

## Dependencies

All dependencies are managed via Swift Package Manager:

- **swift-argument-parser**: CLI argument parsing
- **mlx-swift**: MLX framework for Apple Silicon ML
- **Yams**: YAML parsing for configuration

To add a new dependency:
1. Add to `Package.swift` dependencies array
2. Add to target dependencies
3. Import in Swift files as needed
4. Update README.md if user-facing

## Platform Considerations

### macOS-Only Features
- PDFKit for PDF processing
- AppKit for image handling
- Metal/MLX for ML acceleration
- Native file system integration

### Performance
- MLX provides native Apple Silicon acceleration
- Async/await for non-blocking operations
- Minimal memory footprint
- Fast startup time (no Python initialization)

## Troubleshooting

### Build Issues
- Ensure macOS 14.0+ and Xcode 15.0+
- Clean build folder: `swift package clean`
- Reset package cache: `rm -rf .build`
- Update dependencies: `swift package update`

### Runtime Issues
- Check model cache directory exists and is writable
- Verify sufficient disk space for models
- Ensure PDF files are valid and readable
- Check MLX is available on Apple Silicon

### Testing Issues
- Ensure temporary directories are cleaned up
- Check file permissions for test files
- Verify test resources exist

## Comparison with Python Version

Key differences from the original Python implementation:

| Aspect | Swift | Python |
|--------|-------|--------|
| Dependencies | SPM, native libs | pip, venv |
| PDF Processing | PDFKit | PyMuPDF |
| Images | AppKit | Pillow |
| ML Framework | MLX Swift | MLX Python |
| Config | Yams | PyYAML |
| CLI | ArgumentParser | argparse |
| Testing | XCTest | pytest |
| Async | async/await | asyncio |

## Future Enhancements

Potential areas for improvement:
- Batch processing support
- macOS Quick Actions integration
- SwiftUI GUI application
- Watch folder mode
- Multi-page invoice support
- iCloud Drive integration
- Finder extension
- Preview Quick Look plugin
- Additional document types (receipts, contracts, etc.)

## Code Style

Follow Swift best practices:
- Use Swift naming conventions (lowerCamelCase for variables, UpperCamelCase for types)
- Prefer `let` over `var` when possible
- Use guard statements for early returns
- Document public APIs with doc comments
- Keep functions focused and small
- Use extensions to organize code
- Prefer value types (struct) over reference types (class) when appropriate
