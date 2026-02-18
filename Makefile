.PHONY: build release test test-verbose clean install uninstall run update info format lint help

# Default target
.DEFAULT_GOAL := help

SHELL         := /bin/bash
SCHEME        := docscan
DERIVED_DATA  := $(HOME)/Library/Developer/Xcode/DerivedData
DEBUG_DIR     := $(DERIVED_DATA)/doc-scan-intelligent-operator-swift-*/Build/Products/Debug
RELEASE_DIR   := $(DERIVED_DATA)/doc-scan-intelligent-operator-swift-*/Build/Products/Release

# Use xcbeautify to filter xcodebuild output if available, otherwise fall back to -quiet
XCBEAUTIFY    := $(shell command -v xcbeautify 2>/dev/null)
ifdef XCBEAUTIFY
    XCODE_OUTPUT = 2>&1 | xcbeautify
else
    XCODE_OUTPUT = -quiet
endif

# Build debug version
build:
	@echo "Building debug version..."
	set -o pipefail && xcodebuild -scheme $(SCHEME) -configuration Debug -destination 'platform=macOS' build $(XCODE_OUTPUT)

# Build release version (optimized)
release:
	@echo "Building release version..."
	set -o pipefail && xcodebuild -scheme $(SCHEME) -configuration Release -destination 'platform=macOS' build $(XCODE_OUTPUT)

# Run tests (swift test is correct here — tests mock all MLX inference)
test:
	@echo "Running tests..."
	swift test

# Run tests with verbose output
test-verbose:
	@echo "Running tests (verbose)..."
	swift test --verbose

# Clean all build artifacts including DerivedData
clean:
	@echo "Cleaning build artifacts..."
	swift package clean
	rm -rf .build
	rm -rf $(DERIVED_DATA)/doc-scan-intelligent-operator-swift-*

# Install to /usr/local/bin (requires sudo)
install: release
	@echo "Installing to /usr/local/bin..."
	@BINARY=$$(ls $(RELEASE_DIR)/docscan 2>/dev/null | head -1); \
	if [ -z "$$BINARY" ]; then \
		echo "Release binary not found. Run 'make release' first."; \
		exit 1; \
	fi; \
	sudo cp "$$BINARY" /usr/local/bin/docscan
	@echo "Installation complete!"

# Uninstall from /usr/local/bin
uninstall:
	@echo "Uninstalling from /usr/local/bin..."
	sudo rm -f /usr/local/bin/docscan
	@echo "Uninstall complete!"

# Run with a document file: make run FILE=path/to/doc.pdf [ARGS='--dry-run -v']
run:
	@if [ -z "$(FILE)" ]; then \
		echo "Usage: make run FILE=path/to/document.pdf"; \
		exit 1; \
	fi
	@BINARY=$$(ls $(DEBUG_DIR)/docscan 2>/dev/null | head -1); \
	if [ -z "$$BINARY" ]; then \
		echo "Debug binary not found. Run 'make build' first."; \
		exit 1; \
	fi; \
	"$$BINARY" "$(FILE)" $(ARGS)

# Update dependencies
update:
	@echo "Updating dependencies..."
	swift package update

# Show package info
info:
	@echo "Package information:"
	swift package describe

# Format code (requires SwiftFormat)
format:
	@if command -v swiftformat >/dev/null 2>&1; then \
		echo "Formatting code..."; \
		swiftformat .; \
	else \
		echo "SwiftFormat not installed. Install with: brew install swiftformat"; \
	fi

# Lint code (requires SwiftLint)
lint:
	@if command -v swiftlint >/dev/null 2>&1; then \
		echo "Linting code..."; \
		swiftlint; \
	else \
		echo "SwiftLint not installed. Install with: brew install swiftlint"; \
	fi

# Help
help:
	@echo "DocScan - Makefile commands"
	@echo ""
	@echo "Usage:"
	@echo "  make build           Build debug version (xcodebuild)"
	@echo "  make release         Build release version (xcodebuild, optimized)"
	@echo "  make test            Run unit tests"
	@echo "  make test-verbose    Run unit tests with verbose output"
	@echo "  make clean           Clean all build artifacts including DerivedData"
	@echo "  make install         Build release and install to /usr/local/bin"
	@echo "  make uninstall       Remove from /usr/local/bin"
	@echo "  make run FILE=...    Run debug binary with specified file"
	@echo "  make update          Update Swift package dependencies"
	@echo "  make info            Show package information"
	@echo "  make format          Format code (requires SwiftFormat)"
	@echo "  make lint            Lint code (requires SwiftLint)"
	@echo "  make help            Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make run FILE=invoice.pdf"
	@echo "  make run FILE=invoice.pdf ARGS='--dry-run -v'"
	@echo ""
	@echo "Tip: Install xcbeautify for cleaner build output:"
	@echo "  brew install xcbeautify"
