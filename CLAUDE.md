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

```bash
# Debug build
swift build

# Release build (optimized)
swift build -c release

# Clean build artifacts
swift package clean
```

### Running

```bash
# Run directly with SPM
swift run docscan invoice.pdf

# Run with arguments
swift run docscan invoice.pdf --dry-run -v

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
   - Loads Vision-Language Models with MLX
   - Caches models locally
   - Manages model downloads from Hugging Face
   - Validates disk space before downloading
   - **NOTE**: VLM inference is currently a placeholder and needs full MLX integration

4. **OCR Engine (`OCREngine.swift`)** - Native text recognition using Apple Vision
   - Extracts text from images using Vision framework
   - Detects invoice indicators in multiple languages (DE, EN, FR, ES)
   - Extracts dates using regex patterns (ISO, European, US formats)
   - Extracts company names using keyword matching and heuristics
   - Provides complete invoice data extraction pipeline

5. **Invoice Detector (`InvoiceDetector.swift`)** - Dual verification system
   - **Runs VLM and OCR in parallel** using Swift concurrency (Task-based)
   - Compares results from both methods automatically
   - Detects conflicts in: invoice detection, date, company name
   - Returns `VerificationResult` with both method outputs
   - Generates standardized filenames from agreed/chosen data
   - Supports multiple date formats

6. **File Renamer (`FileRenamer.swift`)** - Safe file operations
   - Renames files with extracted data
   - Handles filename collisions (adds _1, _2, etc.)
   - Supports dry-run mode
   - In-place or directory-based renaming

7. **Errors (`Errors.swift`)** - Error handling
   - Custom `DocScanError` enum
   - Localized error descriptions
   - Comprehensive error types for all failure modes

8. **CLI (`main.swift`)** - Command-line interface
   - Built with swift-argument-parser
   - Async/await support
   - Displays dual verification results in formatted table
   - Interactive conflict resolution when VLM and OCR disagree
   - Clear user feedback with progress indicators

### Data Flow

```
PDF File → PDF Validation → PDF to Image → Dual Verification
                                              ├─> VLM Analysis
                                              └─> OCR Analysis
                                                     ↓
                                            Result Comparison
                                            ├─> Agreement → Auto-proceed
                                            └─> Conflict → User chooses
                                                     ↓
                                           Filename Generation →
                                           Safe File Renaming
```

### Invoice Processing Workflow (Dual Verification)

1. **Validation**: Check if file is valid PDF using PDFKit
2. **Conversion**: Convert first page to NSImage (configurable DPI)
3. **Parallel Dual Verification**: Run both methods concurrently using Swift Tasks
   - **VLM Path**:
     - Detect if document is invoice via LLM prompt
     - Extract date and company via structured LLM prompts
   - **OCR Path**:
     - Extract all text using Vision framework
     - Detect invoice keywords (Rechnung, Invoice, Facture, etc.)
     - Parse dates using regex patterns
     - Extract company using heuristics and keywords
4. **Comparison**: Automatic comparison of both results
   - Check: Invoice detection match?
   - Check: Date match?
   - Check: Company name match?
5. **Resolution**:
   - **If agree**: Proceed automatically
   - **If conflict**: Display both results, user chooses
6. **Filename Generation**: Create `{date}_Rechnung_{company}.pdf`
7. **Renaming**: Safely rename with collision handling

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

This project is designed to leverage MLX Swift for Apple Silicon acceleration:

- Models are loaded from Hugging Face using MLX Swift
- Inference runs natively on Apple Neural Engine
- Models are automatically downloaded and cached locally
- MLX compatibility is assumed for models
- Disk space is checked before downloading

**Current Status:**
- MLX dependencies are included in Package.swift
- ModelManager structure is in place
- **VLM inference is a placeholder** - needs actual MLX VLM implementation
- See `ModelManager.swift:performInference()` for integration point

**Integration TODO:**
- Implement actual VLM model loading using MLX Swift
- Add image preprocessing for specific VLM models
- Implement token generation and decoding
- Add support for different VLM architectures (Qwen-VL, Pixtral, etc.)

## Testing Strategy

Tests use XCTest with Swift's native testing features:

- `ConfigurationTests.swift` - Configuration loading and defaults
- `FileRenamerTests.swift` - File operations and collision handling
- `InvoiceDetectorTests.swift` - Filename generation and data validation
- **Note**: Full integration tests require VLM implementation

Testing best practices:
- Use temporary directories for file operations
- Clean up test artifacts in `tearDown()`
- Test both success and failure cases
- Use `XCTAssertThrowsError` for error cases

## Key Implementation Notes

### Adding New Features

When adding new features:
1. Add implementation to appropriate module in `Sources/DocScanCore/`
2. Update tests in `Tests/DocScanCoreTests/`
3. Update CLI in `Sources/DocScanCLI/main.swift` if needed
4. Update README.md with new functionality
5. Follow Swift naming conventions and style

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

### MLX VLM Implementation

When implementing actual VLM inference:
1. Study mlx-swift-examples for VLM patterns
2. Implement model loading in `ModelManager.swift`
3. Add image preprocessing pipeline
4. Implement token generation
5. Add proper error handling
6. Update tests with mocked inference

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
- Complete MLX VLM integration
- Batch processing support
- macOS Quick Actions integration
- SwiftUI GUI application
- Watch folder mode
- OCR fallback for scanned documents
- iCloud Drive integration
- Finder extension
- Preview Quick Look plugin

## Code Style

Follow Swift best practices:
- Use Swift naming conventions (lowerCamelCase for variables, UpperCamelCase for types)
- Prefer `let` over `var` when possible
- Use guard statements for early returns
- Document public APIs with doc comments
- Keep functions focused and small
- Use extensions to organize code
- Prefer value types (struct) over reference types (class) when appropriate
