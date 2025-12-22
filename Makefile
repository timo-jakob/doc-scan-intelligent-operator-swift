.PHONY: build release test clean install run help

# Default target
.DEFAULT_GOAL := help

# Build debug version
build:
	@echo "Building debug version..."
	swift build

# Build release version (optimized)
release:
	@echo "Building release version..."
	swift build -c release

# Run tests
test:
	@echo "Running tests..."
	swift test

# Run tests with verbose output
test-verbose:
	@echo "Running tests (verbose)..."
	swift test --verbose

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	swift package clean
	rm -rf .build

# Install to /usr/local/bin (requires sudo)
install: release
	@echo "Installing to /usr/local/bin..."
	sudo cp .build/release/docscan /usr/local/bin/
	@echo "Installation complete!"

# Uninstall from /usr/local/bin
uninstall:
	@echo "Uninstalling from /usr/local/bin..."
	sudo rm -f /usr/local/bin/docscan
	@echo "Uninstall complete!"

# Run with example file (set FILE variable)
run:
	@if [ -z "$(FILE)" ]; then \
		echo "Usage: make run FILE=path/to/invoice.pdf"; \
		exit 1; \
	fi
	swift run docscan "$(FILE)" $(ARGS)

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
	@echo "  make build           Build debug version"
	@echo "  make release         Build release version (optimized)"
	@echo "  make test            Run tests"
	@echo "  make test-verbose    Run tests with verbose output"
	@echo "  make clean           Clean build artifacts"
	@echo "  make install         Install to /usr/local/bin (requires sudo)"
	@echo "  make uninstall       Uninstall from /usr/local/bin"
	@echo "  make run FILE=...    Run with specified file"
	@echo "  make update          Update dependencies"
	@echo "  make info            Show package information"
	@echo "  make format          Format code (requires SwiftFormat)"
	@echo "  make lint            Lint code (requires SwiftLint)"
	@echo "  make help            Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make run FILE=invoice.pdf"
	@echo "  make run FILE=invoice.pdf ARGS='--dry-run -v'"
