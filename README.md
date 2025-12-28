# DocScan - Intelligent Invoice Processing for macOS

[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014%2B-blue.svg)](https://www.apple.com/macos)
[![MLX](https://img.shields.io/badge/MLX-Swift-green.svg)](https://github.com/ml-explore/mlx-swift)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

An AI-powered invoice detection and renaming system built in Swift, optimized for Apple Silicon using MLX Vision-Language Models. Analyzes PDF invoices, extracts key information (date, invoicing party), and renames files intelligently.

This is the Swift version of [doc-scan-intelligent-operator](https://github.com/timo-jakob/doc-scan-intelligent-operator), rewritten for native macOS performance with MLX acceleration.

## Features

- **Dual Verification System**: Runs both VLM and OCR in parallel for maximum accuracy
  - Automatic processing when both methods agree
  - Interactive conflict resolution when results differ
  - Combines AI intelligence with traditional OCR reliability
- **AI-Powered Invoice Detection**: Uses Vision-Language Models to identify invoices
- **Native OCR Integration**: Apple Vision framework for text recognition
- **Smart Data Extraction**: Automatically extracts invoice date and company name
- **Intelligent Renaming**: Generates standardized filenames (e.g., `2024-12-15_Rechnung_Acme-Corp.pdf`)
- **Apple Silicon Optimized**: Leverages MLX for high-performance inference on M1/M2/M3 Macs
- **Collision Handling**: Automatically handles duplicate filenames
- **Dry Run Mode**: Preview changes before applying them
- **Configurable**: YAML-based configuration with CLI overrides
- **Native macOS**: Built with Swift for optimal performance and system integration

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

### Basic Usage

```bash
# Analyze and rename an invoice
docscan invoice.pdf

# Dry run (preview without renaming)
docscan invoice.pdf --dry-run

# Verbose output
docscan invoice.pdf -v
```

### Advanced Options

```bash
# Use a different VLM model
docscan invoice.pdf -m mlx-community/Qwen2-VL-7B-Instruct-4bit

# Use custom configuration
docscan invoice.pdf -c config.yaml

# Specify custom cache directory
docscan invoice.pdf --cache-dir /Volumes/External/models
```

## Configuration

Create a `config.yaml` file:

```yaml
# Model configuration
modelName: mlx-community/Qwen2-VL-2B-Instruct-4bit
modelCacheDir: ~/.cache/docscan/models

# Generation parameters
maxTokens: 256
temperature: 0.1

# PDF processing
pdfDPI: 150

# Output configuration
dateFormat: yyyy-MM-dd
filenamePattern: "{date}_Rechnung_{company}.pdf"

# Logging
verbose: false
```

## How It Works - Dual Verification

DocScan uses a unique **dual verification** approach that combines AI and traditional OCR:

1. **PDF Validation**: Checks if the file is a valid PDF
2. **Image Conversion**: Converts the first page to an image using PDFKit
3. **Parallel Processing**: Runs both methods simultaneously
   - **VLM Path**: Vision-Language Model analyzes the image
   - **OCR Path**: Apple Vision framework extracts text and patterns
4. **Result Comparison**: Compares outputs from both methods
   - ✅ **Agreement**: If both agree, proceeds automatically
   - ⚠️ **Conflict**: If they differ, displays both results and asks user to choose
5. **Data Validation**: Ensures date and company name are extracted
6. **Filename Generation**: Creates a standardized filename based on the pattern
7. **Safe Renaming**: Renames the file with collision detection

### Example Output (Agreement)

```
Running dual verification (VLM + OCR in parallel)...

╔══════════════════════════════════════════════════╗
║         Dual Verification Results              ║
╠══════════════════════════════════════════════════╣
║ VLM Results:                                    ║
║   Is Invoice: ✅ Yes                             ║
║   Date: 2024-12-15                              ║
║   Company: Acme Corporation                     ║
║                                                 ║
║ OCR Results:                                    ║
║   Is Invoice: ✅ Yes                             ║
║   Date: 2024-12-15                              ║
║   Company: Acme Corporation                     ║
╚══════════════════════════════════════════════════╝

✅ VLM and OCR agree - proceeding automatically
```

### Example Output (Conflict)

```
╔══════════════════════════════════════════════════╗
║         Dual Verification Results              ║
╠══════════════════════════════════════════════════╣
║ VLM Results:                                    ║
║   Date: 2024-12-15                              ║
║   Company: Acme Corp                            ║
║ OCR Results:                                    ║
║   Date: 2024-12-16                              ║
║   Company: Acme Corporation GmbH                ║
╚══════════════════════════════════════════════════╝

⚠️  CONFLICTS DETECTED:
   - Date
   - Company name

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  CONFLICT RESOLUTION REQUIRED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Conflict: Invoice Date
  [1] VLM says: 2024-12-15
  [2] OCR says: 2024-12-16
Enter your choice: 2

Conflict: Company Name
  [1] VLM says: Acme Corp
  [2] OCR says: Acme Corporation GmbH
Enter your choice: 2
```

## Architecture

```
┌─────────────────┐
│   CLI (main)    │  ← ArgumentParser-based command-line interface
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ InvoiceDetector │  ← Orchestrates the invoice analysis workflow
└────────┬────────┘
         │
    ┌────┴────┬──────────┬─────────────┐
    ▼         ▼          ▼             ▼
┌─────────┐ ┌────────┐ ┌────────────┐ ┌──────────┐
│PDFUtils │ │ Model  │ │   File     │ │  Config  │
│         │ │Manager │ │  Renamer   │ │          │
└─────────┘ └────────┘ └────────────┘ └──────────┘
```

### Core Components

- **PDFUtils**: PDF validation and image conversion using PDFKit
- **ModelManager**: VLM loading, caching, and inference using MLX
- **InvoiceDetector**: Invoice detection and data extraction
- **FileRenamer**: Safe file renaming with collision handling
- **Configuration**: YAML-based configuration management

## Supported Models

DocScan works with MLX-compatible Vision-Language Models:

- `mlx-community/Qwen2-VL-2B-Instruct-4bit` (Default, recommended)
- `mlx-community/Qwen2-VL-7B-Instruct-4bit`
- `mlx-community/pixtral-12b-4bit`
- Any MLX-compatible VLM on Hugging Face

Models are automatically downloaded and cached on first use.

## Development

### Running Tests

```bash
# Run all tests
swift test

# Run specific test suite
swift test --filter ConfigurationTests
swift test --filter FileRenamerTests
swift test --filter InvoiceDetectorTests
```

### Project Structure

```
doc-scan-intelligent-operator-swift/
├── Sources/
│   ├── DocScanCore/          # Core library
│   │   ├── Configuration.swift
│   │   ├── PDFUtils.swift
│   │   ├── ModelManager.swift
│   │   ├── InvoiceDetector.swift
│   │   ├── FileRenamer.swift
│   │   └── Errors.swift
│   └── DocScanCLI/           # CLI executable
│       └── main.swift
├── Tests/
│   └── DocScanCoreTests/     # Unit tests
├── Package.swift
├── README.md
└── CLAUDE.md
```

### Building and Running

```bash
# Build with xcodebuild (required for VLM/Metal support)
xcodebuild -scheme docscan -configuration Debug -destination 'platform=macOS' build

# Run from Xcode DerivedData directory
cd ~/Library/Developer/Xcode/DerivedData/doc-scan-intelligent-operator-swift-*/Build/Products/Debug
./docscan invoice.pdf --dry-run -v

# Alternative: Build with swift (OCR-only, no VLM)
swift build
.build/debug/docscan invoice.pdf --dry-run --auto-resolve ocr
```

## Roadmap

- [ ] Complete MLX VLM integration (currently placeholder)
- [ ] Batch processing support
- [ ] Watch folder mode for automatic processing
- [ ] Support for additional document types
- [ ] GUI application using SwiftUI
- [ ] Integration with macOS Quick Actions
- [ ] OCR fallback for scanned documents
- [ ] Multi-language support enhancement

## Comparison with Python Version

| Feature | Swift (This Project) | Python Original |
|---------|---------------------|-----------------|
| Platform | macOS only | Cross-platform |
| Performance | Native, MLX-optimized | Good (MLX) |
| Installation | Single binary | Python + venv |
| Memory Usage | Lower | Higher |
| Startup Time | Instant | ~1-2s (Python init) |
| System Integration | Native macOS | CLI only |
| Development | Swift/Xcode | Python |

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
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

---

Made with ❤️ for Apple Silicon
