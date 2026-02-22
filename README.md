# DocScan - Intelligent Document Processing for macOS

[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014%2B-blue.svg)](https://www.apple.com/macos)
[![MLX](https://img.shields.io/badge/MLX-Swift-green.svg)](https://github.com/ml-explore/mlx-swift)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=timo-jakob_doc-scan-intelligent-operator-swift&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=timo-jakob_doc-scan-intelligent-operator-swift)
[![Reliability Rating](https://sonarcloud.io/api/project_badges/measure?project=timo-jakob_doc-scan-intelligent-operator-swift&metric=reliability_rating)](https://sonarcloud.io/summary/new_code?id=timo-jakob_doc-scan-intelligent-operator-swift)
[![Security Rating](https://sonarcloud.io/api/project_badges/measure?project=timo-jakob_doc-scan-intelligent-operator-swift&metric=security_rating)](https://sonarcloud.io/summary/new_code?id=timo-jakob_doc-scan-intelligent-operator-swift)
[![Maintainability Rating](https://sonarcloud.io/api/project_badges/measure?project=timo-jakob_doc-scan-intelligent-operator-swift&metric=sqale_rating)](https://sonarcloud.io/summary/new_code?id=timo-jakob_doc-scan-intelligent-operator-swift)
[![Coverage](https://sonarcloud.io/api/project_badges/measure?project=timo-jakob_doc-scan-intelligent-operator-swift&metric=coverage)](https://sonarcloud.io/summary/new_code?id=timo-jakob_doc-scan-intelligent-operator-swift)
[![Lines of Code](https://sonarcloud.io/api/project_badges/measure?project=timo-jakob_doc-scan-intelligent-operator-swift&metric=ncloc)](https://sonarcloud.io/summary/new_code?id=timo-jakob_doc-scan-intelligent-operator-swift)

An AI-powered document detection and renaming system built in Swift, optimized for Apple Silicon using MLX Vision-Language Models. Analyzes PDF documents, extracts key information, and renames files intelligently.

Supported document types:
- **Invoice** (`--type invoice`): Invoices, bills, receipts → `YYYY-MM-DD_Rechnung_{company}.pdf`
- **Prescription** (`--type prescription`): Doctor's prescriptions → `YYYY-MM-DD_Rezept_{doctor}.pdf`

This is the Swift version of [doc-scan-intelligent-operator](https://github.com/timo-jakob/doc-scan-intelligent-operator), rewritten for native macOS performance with MLX acceleration.

## Features

- **Two-Phase Verification**: Parallel VLM + OCR categorization (Phase 1), then accurate TextLLM data extraction (Phase 2)
- **Multi-Document-Type Support**: Invoice and prescription detection with type-specific keywords and extraction
- **Model Benchmarking**: Discover and evaluate model pairs against a labeled corpus to find the best combination
- **AI-Powered Categorization**: Vision-Language Models identify document types (YES/NO)
- **Native OCR Integration**: Apple Vision framework for text recognition and keyword detection
- **Smart Data Extraction**: TextLLM extracts date and secondary field (company/doctor) from OCR text
- **Intelligent Renaming**: Generates standardized filenames with collision handling
- **Apple Silicon Optimized**: Leverages MLX for high-performance inference on M1/M2/M3/M4 Macs
- **Dry Run Mode**: Preview changes before applying them
- **Configurable**: YAML-based configuration with CLI overrides
- **Pre-flight Memory Check**: Estimates model memory requirements and skips pairs that would exceed available RAM

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon Mac (M1/M2/M3/M4)
- Xcode 15.0 or later (for building)
- Swift 6.0 or later

## Installation

### Quick Install (Recommended)

```bash
# Clone the repository
git clone https://github.com/timo-jakob/doc-scan-intelligent-operator-swift.git
cd doc-scan-intelligent-operator-swift

# Run the install script
./install.sh
```

The install script will:
- Check prerequisites (Xcode, macOS version, Apple Silicon)
- Build docscan with xcodebuild (required for Metal/VLM support)
- Install to `/usr/local/lib/docscan` with wrapper script in `/usr/local/bin`
- Detect and update existing installations

### Install Script Commands

```bash
./install.sh              # Install or update (prompts if already installed)
./install.sh install      # Fresh install
./install.sh update       # Rebuild and update existing installation
./install.sh uninstall    # Remove docscan from system
./install.sh status       # Show installation status
```

### Manual Installation

<details>
<summary>Click to expand manual installation steps</summary>

**Important**: MLX Swift requires Xcode to compile Metal shaders. Using `swift build` will result in runtime errors ("Failed to load the default metallib") when trying to use the VLM.

```bash
# Build with xcodebuild (required for Metal/VLM support)
xcodebuild -scheme docscan -configuration Release -destination 'platform=macOS' -derivedDataPath .build/xcode build

# Install binary AND Metal library bundle (must be in same directory)
sudo mkdir -p /usr/local/lib/docscan
sudo cp .build/xcode/Build/Products/Release/docscan /usr/local/lib/docscan/
sudo cp -R .build/xcode/Build/Products/Release/mlx-swift_Cmlx.bundle /usr/local/lib/docscan/

# Create wrapper script (MLX requires the bundle to be in the same directory as the binary or in the working directory)
sudo tee /usr/local/bin/docscan > /dev/null << 'EOF'
#!/bin/bash
cd /usr/local/lib/docscan || exit 1; exec ./docscan "$@"
EOF
sudo chmod +x /usr/local/bin/docscan
```

</details>

### OCR-Only Mode (No VLM)

If you only need OCR-based detection (no VLM), you can use `swift build`:

```bash
swift build -c release
sudo cp .build/release/docscan /usr/local/bin/

# Use with --auto-resolve ocr to skip VLM
docscan invoice.pdf --auto-resolve ocr
```

## Quick Start

### Scanning Documents

```bash
# Analyze and rename an invoice
docscan scan invoice.pdf

# Detect a prescription
docscan scan prescription.pdf --type prescription

# Dry run (preview without renaming)
docscan scan invoice.pdf --dry-run

# Verbose output
docscan scan invoice.pdf -v

# Use a different VLM model
docscan scan invoice.pdf -m mlx-community/Qwen2-VL-7B-Instruct-4bit

# Use custom configuration
docscan scan invoice.pdf -c config.yaml
```

### Benchmarking Model Pairs

```bash
# Benchmark against a labeled corpus
docscan benchmark ./test-data/positive --negative-dir ./test-data/negative --type invoice -v
```

The benchmark runs through four phases:
1. **Phase A**: Initial benchmark with current model pair, generates ground truth sidecar files
2. **Phase B**: Discovers alternative model pairs from Hugging Face (50 pairs by default, diagonal interleaving for diverse coverage)
3. **Phase C**: Benchmarks discovered pairs against verified ground truths with configurable timeouts
4. **Phase D**: Displays a leaderboard and lets you choose which model pair to adopt

## CLI Reference

### `docscan scan` (default subcommand)

Scan and rename a single PDF document.

| Argument/Option | Description |
|---|---|
| `<pdf-path>` | Path to the PDF file to analyze (required) |
| `-t, --type` | Document type: `invoice` (default) or `prescription` |
| `-c, --config` | Path to YAML configuration file |
| `-m, --model` | VLM model for categorization |
| `-d, --dry-run` | Preview changes without renaming |
| `-v, --verbose` | Enable verbose output |
| `--cache-dir` | Directory to cache downloaded models |
| `--max-tokens` | Maximum tokens to generate |
| `--temperature` | Temperature for generation (0.0-1.0) |
| `--pdf-dpi` | DPI for PDF to image conversion (default: 150) |
| `--auto-resolve` | Auto-resolve categorization conflicts: `vlm` or `ocr` |

### `docscan benchmark`

Evaluate model pairs against a labeled document corpus.

| Argument/Option | Description |
|---|---|
| `<positive-dir>` | Directory containing positive sample PDFs (required) |
| `--negative-dir` | Directory containing negative sample PDFs |
| `-t, --type` | Document type: `invoice` (default) or `prescription` |
| `-c, --config` | Path to YAML configuration file |
| `-v, --verbose` | Enable verbose output |

## Configuration

Create a `config.yaml` file:

```yaml
# VLM model for categorization (Phase 1)
modelName: mlx-community/Qwen2-VL-2B-Instruct-4bit

# Text LLM model for data extraction (Phase 2)
textModelName: mlx-community/Qwen2.5-7B-Instruct-4bit

# Model cache directory
modelCacheDir: ~/.cache/docscan/models

# Generation parameters
maxTokens: 256
temperature: 0.1

# PDF processing
pdfDPI: 150

# Output configuration
output:
  dateFormat: yyyy-MM-dd
  filenamePattern: "{date}_Rechnung_{company}.pdf"

# Logging
verbose: false

# Hugging Face username (for model discovery in benchmark)
huggingFaceUsername: your-username
```

## How It Works - Two-Phase Architecture

DocScan uses a **two-phase verification** approach that separates categorization from data extraction for optimal accuracy:

### Phase 1: Categorization (VLM + OCR in parallel)

Both methods run simultaneously using Swift structured concurrency:
- **VLM**: Vision-Language Model answers "Is this a [document type]? YES/NO"
- **OCR**: Apple Vision extracts text and detects type-specific keywords (rechnung, rezept, etc.)

If both agree, proceed automatically. If they conflict, the user chooses (or `--auto-resolve` picks one).

### Phase 2: Data Extraction (OCR + TextLLM)

Uses the cached OCR text from Phase 1 — no re-extraction needed:
- **TextLLM** (Qwen2.5-7B) analyzes the OCR text to extract:
  - Document date (formatted as YYYY-MM-DD)
  - Secondary field: company name (invoices) or doctor name (prescriptions)
- More accurate than VLM for structured data extraction

### Why Two Phases?

| Task | VLM | TextLLM | Winner |
|------|-----|---------|--------|
| "Is this a [type]?" | Good | Good | Both work |
| Extract date | Often wrong | Accurate | TextLLM |
| Extract company/doctor | Picks wrong text | Accurate | TextLLM |

### Example Output

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 PHASE 1: Categorization (VLM + OCR in parallel)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

VLM: Starting categorization for invoice...
PDF: Using direct text extraction for categorization...
VLM response: Yes
 VLM and PDF text agree: This IS an invoice

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 PHASE 2: Data Extraction (OCR + TextLLM)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Extracting invoice data (OCR+TextLLM)...
   Date: 2025-06-27
   Company: DB_Fernverkehr_AG
```

## Benchmarking

The `benchmark` subcommand evaluates different model combinations to find the best-performing pair for your document type.

### Scoring System

Each document is scored on a 0-1-2 point scale:

| Categorization | Extraction | Score |
|---|---|---|
| Correct | Correct | **2** |
| Correct | Wrong | **1** |
| Wrong | — | **0** |

The aggregate score is `totalPoints / (2 * documentCount)`, normalized to [0.0, 1.0].

### Benchmark Phases

**Phase A** — Run the current model pair against all PDFs in the corpus. Generates ground truth `.json` sidecar files next to each PDF. You can verify and edit these sidecars before proceeding.

**Phase B** — Discover alternative model pairs from Hugging Face. Uses diagonal interleaving to ensure diverse VLM and text model coverage. Default: 50 pairs (option to request 100).

**Phase B.1** — Choose a per-document timeout (10s/30s/60s) for benchmark runs.

**Phase C** — Benchmark each discovered pair against the verified ground truths. Includes pre-flight memory checks to skip pairs that would exceed available RAM. Retries automatically on HTTP 429 rate limits.

**Phase D** — Displays a leaderboard of all tested pairs (including Phase A) sorted by score. Presents a numbered menu to choose which pair to adopt — the selected pair's models are written back to your configuration.

### Ground Truth Sidecars

Phase A generates a `.json` sidecar for each PDF (e.g., `invoice.pdf.json`) containing:
- `isMatch`: Whether the document matches the type
- `date`: Extracted date
- `secondaryField`: Company name or doctor name
- `patientName`: Patient name (prescriptions only)
- `metadata`: Model versions, generation timestamp, verification status

You can manually edit these files to correct any extraction errors before running Phase C.

## Architecture

```
┌─────────────────┐
│  DocScanRoot    │  ← ArgumentParser root command (v2.0.0)
└────────┬────────┘
         │
    ┌────┴────┐
    ▼         ▼
┌────────┐ ┌───────────────┐
│  scan  │ │   benchmark   │
└───┬────┘ └───────┬───────┘
    │              │
    ▼              ▼
┌────────────────────────────────────┐
│         DocumentDetector           │  ← Two-phase orchestration
│  Phase 1: VLM + OCR (parallel)    │
│  Phase 2: OCR + TextLLM           │
└────────┬───────────────────────────┘
         │
    ┌────┼────────┬──────────┬───────────┐
    ▼    ▼        ▼          ▼           ▼
┌──────┐┌──────┐┌─────────┐┌──────────┐┌────────┐
│PDF   ││Model ││TextLLM  ││OCR       ││File    │
│Utils ││Mgr   ││Manager  ││Engine    ││Renamer │
└──────┘└──────┘└─────────┘└──────────┘└────────┘

Benchmark module:
┌─────────────────┐  ┌──────────────────┐  ┌──────────────┐
│ BenchmarkEngine │  │ HuggingFaceClient│  │ FuzzyMatcher │
│ + Memory check  │  │ + 429 retry      │  │ + Scoring    │
└─────────────────┘  └──────────────────┘  └──────────────┘
```

### Core Components

| Component | Purpose |
|---|---|
| `DocumentDetector` | Two-phase orchestration: categorization then extraction |
| `ModelManager` | VLM loading and inference (categorization only) |
| `TextLLMManager` | Text LLM for accurate data extraction from OCR text |
| `OCREngine` | Apple Vision text recognition and keyword detection |
| `PDFUtils` | PDF validation and image conversion using PDFKit |
| `FileRenamer` | Safe file renaming with collision handling |
| `Configuration` | YAML-based configuration with static defaults |
| `DocumentType` | Enum defining document types, keywords, and prompts |
| `StringUtils` | Company/doctor name sanitization for filenames |
| `DateUtils` | Date parsing and formatting |

### Benchmark Components

| Component | Purpose |
|---|---|
| `BenchmarkEngine` | Orchestrates benchmark runs, PDF enumeration, sidecar management |
| `BenchmarkEngine+Memory` | Pre-flight memory estimation from model parameter counts |
| `HuggingFaceClient` | Model discovery with diagonal interleaving and 429 retry |
| `BenchmarkMetrics` | Score-based metrics (0/1/2 per document) |
| `FuzzyMatcher` | Field-level comparison with fuzzy matching |
| `GroundTruth` | Sidecar file format for ground truth data |
| `KeychainManager` | Secure storage for Hugging Face API tokens |

## Supported Models

### VLM (Categorization)

- `mlx-community/Qwen2-VL-2B-Instruct-4bit` (default, faster)
- `mlx-community/Qwen2-VL-7B-Instruct-4bit` (more accurate)
- Any MLX-compatible VLM on Hugging Face

### Text LLM (Extraction)

- `mlx-community/Qwen2.5-7B-Instruct-4bit` (default, recommended)

Models are automatically downloaded and cached on first use. The benchmark subcommand can discover and evaluate alternative models from Hugging Face.

## Development

### Building and Running

```bash
# Build with xcodebuild (required for VLM/Metal support)
xcodebuild -scheme docscan -configuration Debug -destination 'platform=macOS' build

# Run from Xcode DerivedData directory
~/Library/Developer/Xcode/DerivedData/doc-scan-intelligent-operator-swift-*/Build/Products/Debug/docscan scan invoice.pdf --dry-run -v

# Alternative: Build with swift (OCR-only, no VLM)
swift build
.build/debug/docscan scan invoice.pdf --dry-run --auto-resolve ocr
```

### Running Tests

```bash
# Run all tests
swift test

# Run specific test suite
swift test --filter ConfigurationTests
swift test --filter BenchmarkEngineTests
swift test --filter HuggingFaceClientTests
swift test --filter FuzzyMatcherTests

# Run with verbose output
swift test --verbose
```

### Code Quality

```bash
# Format code
make format

# Lint code
make lint
```

### Project Structure

```
doc-scan-intelligent-operator-swift/
├── Sources/
│   ├── DocScan/
│   │   └── DocScan.swift                     # Entry point
│   ├── DocScanCLI/                           # CLI layer
│   │   ├── DocScanRoot.swift                 # Root command (scan, benchmark)
│   │   ├── DocScanCommand.swift              # scan subcommand
│   │   ├── DocScanCommand+Phase1.swift       # Categorization display
│   │   ├── DocScanCommand+Phase2.swift       # Extraction display
│   │   ├── BenchmarkCommand.swift            # benchmark subcommand
│   │   ├── BenchmarkCommand+PhaseA.swift     # Initial benchmark
│   │   ├── BenchmarkCommand+PhaseB.swift     # Model discovery
│   │   ├── BenchmarkCommand+PhaseC.swift     # Pair evaluation
│   │   ├── BenchmarkCommand+PhaseD.swift     # Leaderboard & adoption
│   │   └── TerminalUtils.swift               # Terminal formatting
│   └── DocScanCore/                          # Core library
│       ├── Configuration.swift
│       ├── DocumentType.swift
│       ├── DocumentDetector.swift
│       ├── DocumentDetector+Filename.swift
│       ├── ModelManager.swift
│       ├── TextLLMManager.swift
│       ├── OCREngine.swift
│       ├── PDFUtils.swift
│       ├── FileRenamer.swift
│       ├── StringUtils.swift
│       ├── DateUtils.swift
│       ├── PathUtils.swift
│       ├── DocumentData.swift
│       ├── Errors.swift
│       └── Benchmark/
│           ├── BenchmarkEngine.swift
│           ├── BenchmarkEngine+Memory.swift
│           ├── BenchmarkMetrics.swift
│           ├── FuzzyMatcher.swift
│           ├── GroundTruth.swift
│           ├── HuggingFaceClient.swift
│           └── KeychainManager.swift
├── Tests/
│   └── DocScanCoreTests/                     # Unit tests (500+ tests)
├── Package.swift
├── README.md
└── CLAUDE.md
```

## Roadmap

- [x] ~~Complete MLX VLM integration~~
- [x] ~~Support for additional document types~~ (invoice, prescription)
- [x] ~~OCR fallback for scanned documents~~
- [x] ~~Multi-language keyword support~~ (DE, EN, FR, ES)
- [x] ~~Model benchmarking and discovery~~
- [ ] Batch processing support
- [ ] Watch folder mode for automatic processing
- [ ] GUI application using SwiftUI
- [ ] Integration with macOS Quick Actions
- [ ] Multi-page document support
- [ ] iCloud Drive integration

## Comparison with Python Version

| Feature | Swift (This Project) | Python Original |
|---------|---------------------|-----------------|
| Platform | macOS only | Cross-platform |
| Performance | Native, MLX-optimized | Good (MLX) |
| Installation | Single binary | Python + venv |
| Memory Usage | Lower | Higher |
| Startup Time | Instant | ~1-2s (Python init) |
| System Integration | Native macOS | CLI only |
| Document Types | Invoice, Prescription | Invoice only |
| Benchmarking | Built-in | None |

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git switch -c feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built on top of [MLX Swift](https://github.com/ml-explore/mlx-swift) by Apple
- Inspired by the original [doc-scan-intelligent-operator](https://github.com/timo-jakob/doc-scan-intelligent-operator)
- Uses Vision-Language Models from the MLX community

## Support

If you encounter any issues or have questions:

- Open an issue on [GitHub Issues](https://github.com/timo-jakob/doc-scan-intelligent-operator-swift/issues)
- Check the [original Python version](https://github.com/timo-jakob/doc-scan-intelligent-operator) for similar problems
