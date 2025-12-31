#!/bin/bash
#
# DocScan Installation Script
# Builds and installs docscan with MLX Metal support
#

set -e

# Configuration
INSTALL_DIR="/usr/local/lib/docscan"
BIN_DIR="/usr/local/bin"
BUILD_DIR=".build/xcode"
SCHEME="docscan"
CONFIGURATION="Release"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}==>${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}==>${NC} $1"
}

print_error() {
    echo -e "${RED}==>${NC} $1"
}

# Check if running from repository root
check_repository() {
    if [ ! -f "Package.swift" ]; then
        print_error "Error: Must run from the doc-scan-intelligent-operator-swift repository root"
        exit 1
    fi

    if ! grep -q "docscan" Package.swift 2>/dev/null; then
        print_error "Error: This doesn't appear to be the docscan repository"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."

    # Check for Xcode
    if ! command -v xcodebuild &> /dev/null; then
        print_error "Error: Xcode is required but not installed"
        print_error "Install Xcode from the App Store or run: xcode-select --install"
        exit 1
    fi

    # Check for Apple Silicon
    if [ "$(uname -m)" != "arm64" ]; then
        print_warning "Warning: This tool is optimized for Apple Silicon (M1/M2/M3/M4)"
        print_warning "It may not work correctly on Intel Macs"
    fi

    # Check macOS version
    macos_version=$(sw_vers -productVersion | cut -d. -f1)
    if [ "$macos_version" -lt 14 ]; then
        print_error "Error: macOS 14 (Sonoma) or later is required"
        exit 1
    fi

    print_success "Prerequisites check passed"
}

# Check for existing installation
check_existing_installation() {
    if [ -f "$BIN_DIR/docscan" ] || [ -d "$INSTALL_DIR" ]; then
        return 0  # Exists
    fi
    return 1  # Does not exist
}

# Get installed version (if any)
get_installed_version() {
    if [ -x "$BIN_DIR/docscan" ]; then
        "$BIN_DIR/docscan" --version 2>/dev/null || echo "unknown"
    else
        echo "not installed"
    fi
}

# Build the project
build_project() {
    print_status "Building docscan with xcodebuild..."
    print_status "This may take a few minutes on first build..."

    # Clean previous build
    rm -rf "$BUILD_DIR"

    # Build with xcodebuild
    if xcodebuild \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -destination 'platform=macOS' \
        -derivedDataPath "$BUILD_DIR" \
        build 2>&1 | grep -E "(error:|warning:|BUILD|Compiling|Linking)" | head -50; then

        # Check if build succeeded
        if [ -f "$BUILD_DIR/Build/Products/$CONFIGURATION/docscan" ]; then
            print_success "Build completed successfully"
        else
            print_error "Build failed: binary not found"
            exit 1
        fi
    else
        print_error "Build failed"
        exit 1
    fi
}

# Install the application
install_app() {
    local is_update=$1

    if [ "$is_update" = "true" ]; then
        print_status "Updating docscan..."
    else
        print_status "Installing docscan..."
    fi

    # Create installation directory
    print_status "Creating installation directory: $INSTALL_DIR"
    sudo mkdir -p "$INSTALL_DIR"

    # Copy binary
    print_status "Copying docscan binary..."
    sudo cp "$BUILD_DIR/Build/Products/$CONFIGURATION/docscan" "$INSTALL_DIR/"

    # Copy Metal library bundle
    print_status "Copying MLX Metal library bundle..."
    sudo rm -rf "$INSTALL_DIR/mlx-swift_Cmlx.bundle"
    sudo cp -R "$BUILD_DIR/Build/Products/$CONFIGURATION/mlx-swift_Cmlx.bundle" "$INSTALL_DIR/"

    # Copy Hub bundle if exists (for model downloading)
    if [ -d "$BUILD_DIR/Build/Products/$CONFIGURATION/swift-transformers_Hub.bundle" ]; then
        print_status "Copying Hub bundle..."
        sudo rm -rf "$INSTALL_DIR/swift-transformers_Hub.bundle"
        sudo cp -R "$BUILD_DIR/Build/Products/$CONFIGURATION/swift-transformers_Hub.bundle" "$INSTALL_DIR/"
    fi

    # Create wrapper script
    print_status "Creating wrapper script in $BIN_DIR..."
    sudo tee "$BIN_DIR/docscan" > /dev/null << 'WRAPPER'
#!/bin/bash
# DocScan wrapper script
# Required because MLX looks for Metal library bundle relative to working directory
# We save the original PWD so the binary can resolve relative paths correctly
export DOCSCAN_ORIGINAL_PWD="$PWD"
cd /usr/local/lib/docscan && exec ./docscan "$@"
WRAPPER
    sudo chmod +x "$BIN_DIR/docscan"

    # Set permissions
    sudo chmod +x "$INSTALL_DIR/docscan"

    print_success "Installation complete!"
}

# Uninstall the application
uninstall_app() {
    print_status "Uninstalling docscan..."

    if [ -f "$BIN_DIR/docscan" ]; then
        sudo rm -f "$BIN_DIR/docscan"
        print_status "Removed $BIN_DIR/docscan"
    fi

    if [ -d "$INSTALL_DIR" ]; then
        sudo rm -rf "$INSTALL_DIR"
        print_status "Removed $INSTALL_DIR"
    fi

    print_success "Uninstallation complete!"
}

# Show usage
show_usage() {
    echo "DocScan Installation Script"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  install     Build and install docscan (default)"
    echo "  update      Rebuild and update existing installation"
    echo "  uninstall   Remove docscan from system"
    echo "  status      Show installation status"
    echo "  help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Install or update"
    echo "  $0 install      # Fresh install"
    echo "  $0 update       # Update existing installation"
    echo "  $0 uninstall    # Remove installation"
}

# Show status
show_status() {
    echo "DocScan Installation Status"
    echo "==========================="
    echo ""

    if check_existing_installation; then
        print_success "Status: Installed"
        echo "  Binary: $BIN_DIR/docscan"
        echo "  Library: $INSTALL_DIR"
        echo "  Version: $(get_installed_version)"

        # Check components
        echo ""
        echo "Components:"
        [ -f "$INSTALL_DIR/docscan" ] && echo "  [x] docscan binary" || echo "  [ ] docscan binary"
        [ -d "$INSTALL_DIR/mlx-swift_Cmlx.bundle" ] && echo "  [x] MLX Metal library" || echo "  [ ] MLX Metal library"
        [ -d "$INSTALL_DIR/swift-transformers_Hub.bundle" ] && echo "  [x] Hub bundle" || echo "  [ ] Hub bundle"
    else
        print_warning "Status: Not installed"
    fi
}

# Main script
main() {
    local command="${1:-install}"

    case "$command" in
        install)
            check_repository
            check_prerequisites

            if check_existing_installation; then
                print_warning "docscan is already installed (version: $(get_installed_version))"
                read -p "Do you want to update it? [y/N] " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    build_project
                    install_app true
                else
                    print_status "Installation cancelled"
                    exit 0
                fi
            else
                build_project
                install_app false
            fi

            echo ""
            print_success "docscan is ready to use!"
            echo ""
            echo "Try it out:"
            echo "  docscan --help"
            echo "  docscan invoice.pdf --dry-run"
            ;;

        update)
            check_repository
            check_prerequisites

            if ! check_existing_installation; then
                print_warning "docscan is not installed. Running fresh install..."
            fi

            build_project
            install_app true

            echo ""
            print_success "docscan has been updated!"
            ;;

        uninstall)
            if ! check_existing_installation; then
                print_warning "docscan is not installed"
                exit 0
            fi

            read -p "Are you sure you want to uninstall docscan? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                uninstall_app
            else
                print_status "Uninstall cancelled"
            fi
            ;;

        status)
            show_status
            ;;

        help|--help|-h)
            show_usage
            ;;

        *)
            print_error "Unknown command: $command"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
