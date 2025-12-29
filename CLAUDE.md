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

**doc-scan-intelligent-operator-swift** - Swift rewrite of the AI-powered document detection and renaming system, optimized for Apple Silicon using MLX Vision-Language Models. Built entirely in Swift for maximum performance and native macOS integration.

**Key Focus**: Native macOS document processing with intelligent categorization and data extraction.

**Supported Document Types**:
- **Invoice** (`--type invoice`): Invoices, bills, receipts → `YYYY-MM-DD_Rechnung_{company}.pdf`
- **Prescription** (`--type prescription`): Doctor's prescriptions → `YYYY-MM-DD_Rezept_{doctor}.pdf`

**Architecture**: Two-phase verification system:
- **Phase 1**: Categorization (VLM + OCR in parallel) - "Does this match the document type?"
- **Phase 2**: Data Extraction (OCR + TextLLM only) - Extract date and secondary field (company/doctor)

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
   - `extractData(for:from:)` - Generic extraction for any document type
   - Extracts date and secondary field (company for invoices, doctor for prescriptions)
   - More accurate than VLM for structured data extraction
   - Separate from VLM to optimize for each task

5. **OCR Engine (`OCREngine.swift`)** - Native text recognition using Apple Vision
   - Extracts text from images using Vision framework
   - `detectKeywords(for:from:)` - Generic keyword detection for any document type
   - Supports multiple languages (DE, EN, FR, ES) per document type
   - Invoice keywords: rechnung, invoice, facture, factura, etc.
   - Prescription keywords: rezept, verordnung, prescription, arzt, etc.
   - Provides complete document data extraction pipeline

6. **Document Detector (`DocumentDetector.swift`)** - Two-phase verification system
   - Configurable for any `DocumentType` (invoice, prescription, etc.)
   - **Phase 1: Categorization** (VLM + OCR in parallel)
     - VLM answers: "Is this a [document type]? YES/NO"
     - OCR uses type-specific keyword detection
     - If both agree → proceed automatically
     - If conflict → user chooses (or `--auto-resolve`)
   - **Phase 2: Data Extraction** (OCR + TextLLM only)
     - Uses cached OCR text from Phase 1
     - TextLLM extracts date and secondary field
     - No VLM involvement (more accurate)
   - Returns `CategorizationVerification` and `ExtractionResult`
   - Generates type-specific filenames from extracted data

7. **Document Type (`DocumentType.swift`)** - Document type definitions
   - Enum defining supported document types (invoice, prescription)
   - Contains type-specific: keywords, VLM prompts, filename patterns
   - Easily extensible for new document types

8. **String Utils (`StringUtils.swift`)** - String sanitization utilities
   - `sanitizeCompanyName()` - Sanitizes company names for filenames
   - `sanitizeDoctorName()` - Removes titles (Dr., Prof., etc.) and sanitizes for filenames

9. **File Renamer (`FileRenamer.swift`)** - Safe file operations
   - Renames files with extracted data
   - Handles filename collisions (adds _1, _2, etc.)
   - Supports dry-run mode
   - In-place or directory-based renaming

10. **Errors (`Errors.swift`)** - Error handling
    - Custom `DocScanError` enum
    - Localized error descriptions
    - Comprehensive error types for all failure modes

11. **CLI (`DocScanCommand.swift`)** - Command-line interface
    - Built with swift-argument-parser
    - Async/await support
    - `--type invoice|prescription` to select document type
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
              │  VLM: "Is this a [type]? YES/NO"      │
              │  OCR: Type-specific keyword detection  │
              │                                        │
              │  Both agree? → Proceed                 │
              │  Conflict?   → User chooses / auto     │
              └────────────────────────────────────────┘
                                ↓
              ┌─────── PHASE 2: Data Extraction ──────┐
              │  (OCR + TextLLM only)                 │
              │                                        │
              │  Use cached OCR text                  │
              │  TextLLM extracts: date + secondary   │
              │  (company for invoice, doctor for Rx) │
              └────────────────────────────────────────┘
                                ↓
              Type-specific Filename → Safe Renaming
```

### Document Processing Workflow (Two-Phase)

1. **Validation**: Check if file is valid PDF using PDFKit
2. **Conversion**: Convert first page to NSImage (configurable DPI)

**PHASE 1: Categorization (Parallel)**

3. **VLM Categorization**: Simple prompt asking "Is this a [document type]? YES/NO"
4. **OCR Categorization**: Extract text + type-specific keyword detection
   - Invoice: rechnung, invoice, facture, etc.
   - Prescription: rezept, verordnung, arzt, etc.
   - OCR text is cached for Phase 2
5. **Agreement Check**:
   - **Both agree (match)**: Proceed to Phase 2
   - **Both agree (no match)**: Exit
   - **Conflict**: User chooses or `--auto-resolve vlm|ocr`

**PHASE 2: Data Extraction (Sequential)**

6. **TextLLM Extraction**: Analyze cached OCR text to extract:
   - Document date (formatted as YYYY-MM-DD)
   - Secondary field (company for invoices, doctor for prescriptions)
7. **Filename Generation**: Create type-specific filename:
   - Invoice: `{date}_Rechnung_{company}.pdf`
   - Prescription: `{date}_Rezept_{doctor}.pdf`
8. **Renaming**: Safely rename with collision handling

### How Parallel Processing Works (Phase 1)

Phase 1 (Categorization) uses Swift's structured concurrency (`Task`) to run VLM and OCR categorization simultaneously.

#### Implementation Details

**Location**: `Sources/DocScanCore/DocumentDetector.swift` - `categorize()` method

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
# Invoice detection
docscan invoice.pdf -v --type invoice

# Prescription detection
docscan prescription.pdf -v --type prescription
```

Output shows the two-phase flow (invoice example with searchable PDF):
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 PHASE 1: Categorization (VLM + OCR in parallel)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

VLM: Starting categorization for invoice...
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

Prescription example output:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 PHASE 1: Categorization (VLM + OCR in parallel)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

VLM: Starting categorization for prescription...
✅ VLM and PDF text agree: This IS a prescription

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📄 PHASE 2: Data Extraction (OCR + TextLLM)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Extracting prescription data (OCR+TextLLM)...
   📅 Date: 2025-04-08
   👨‍⚕️ Doctor: Gesine_Kaiser
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

Used in Phase 1 for simple document type detection (YES/NO):

- Models: Qwen2-VL series (2B, 7B variants)
- Task: "Is this a [document type]?" → YES/NO
- Loaded via `ModelManager.swift`

```swift
// Document type determines the prompt
let prompt = documentType.vlmPrompt  // e.g., "Is this document an INVOICE?"
let response = try await vlmProvider.generateFromImage(image, prompt: prompt)
```

### Text LLM - Data Extraction

Used in Phase 2 for accurate data extraction from OCR text:

- Model: `mlx-community/Qwen2.5-7B-Instruct-4bit`
- Task: Extract date and secondary field from text
- Loaded via `TextLLMManager.swift`

```swift
// Generic extraction for any document type
let result = try await textLLM.extractData(for: documentType, from: ocrText)
// result.date, result.secondaryField (company or doctor)
```

### Why Two Model Types?

| Task | VLM | TextLLM | Winner |
|------|-----|---------|--------|
| "Is this a [type]?" | ✅ Good | ✅ Good | Both work |
| Extract date | ❌ Often wrong | ✅ Accurate | TextLLM |
| Extract secondary field | ❌ Picks wrong text | ✅ Accurate | TextLLM |

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
- `InvoiceDetectorTests.swift` - Document detection, filename generation, multi-type support
- `OCREngineTests.swift` - OCR text extraction and keyword detection for all document types
- `VerificationTests.swift` - Categorization result comparison and display labels
- `DocumentTypeTests.swift` - Document type enum properties and keywords
- `StringUtilsTests.swift` - Company and doctor name sanitization

**Integration Testing:**
Full end-to-end testing with real documents:
```bash
# Test invoice detection
.build/debug/docscan invoice.pdf -v --dry-run --auto-resolve ocr

# Test prescription detection
.build/debug/docscan prescription.pdf -v --dry-run --type prescription --auto-resolve ocr

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
   - VLM: Simple YES/NO question ("Is this a [type]?")
   - OCR: Type-specific keyword detection
   - Both run in parallel using Swift Tasks
   - OCR caches text for Phase 2

2. **Phase 2: Data Extraction (OCR+TextLLM)**
   - Uses cached OCR text (no re-extraction needed)
   - TextLLM extracts date and secondary field (company/doctor/etc.)
   - More accurate than VLM for structured data

**Key Design Decisions:**
- VLM is only used for categorization (what it's good at)
- Data extraction uses TextLLM (more accurate)
- OCR text is cached between phases (efficiency)
- Conflicts only occur in categorization (simpler resolution)
- Document types are extensible via `DocumentType` enum

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

## Adding New Document Types

To add a new document type (e.g., contracts, receipts):

1. **Update `DocumentType.swift`**:
   ```swift
   public enum DocumentType: String, CaseIterable, Codable {
       case invoice
       case prescription
       case contract  // New type
   }
   ```

2. **Add type-specific properties**:
   - `displayName` - Human-readable name
   - `germanName` - German translation for filename
   - `vlmPrompt` - VLM categorization prompt
   - `strongKeywords` - High-confidence keywords
   - `mediumKeywords` - Medium-confidence keywords
   - `defaultFilenamePattern` - Filename template

3. **Update `TextLLMManager.swift`**:
   - Add extraction prompt for the new type
   - Define what secondary field to extract

4. **Update `StringUtils.swift`** (if needed):
   - Add sanitization function for the secondary field

5. **Add tests** for the new document type

## Future Enhancements

Potential areas for improvement:
- Batch processing support
- macOS Quick Actions integration
- SwiftUI GUI application
- Watch folder mode
- Multi-page document support
- iCloud Drive integration
- Finder extension
- Preview Quick Look plugin
- Additional document types (contracts, receipts, bank statements, etc.)

## Code Style

Follow Swift best practices:
- Use Swift naming conventions (lowerCamelCase for variables, UpperCamelCase for types)
- Prefer `let` over `var` when possible
- Use guard statements for early returns
- Document public APIs with doc comments
- Keep functions focused and small
- Use extensions to organize code
- Prefer value types (struct) over reference types (class) when appropriate
