#!/bin/bash

# Netmaker Source Build Script
# Builds Netmaker from source with custom parameters embedded

set -euo pipefail

SCRIPT_VERSION="1.0.0"
BUILD_DIR="/tmp/netmaker-build"
OUTPUT_DIR="$(pwd)/binaries"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_info() { echo -e "${BLUE}[i]${NC} $1"; }
print_header() { echo -e "${CYAN}[BUILD]${NC} $1"; }

# Show banner
show_banner() {
    clear
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║                     Netmaker Source Build Script                         ║
║                                                                           ║
║    Builds Netmaker from source with embedded build parameters            ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo
    print_info "Version: $SCRIPT_VERSION"
    print_info "Build Directory: $BUILD_DIR"
    print_info "Output Directory: $OUTPUT_DIR"
    echo
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root - this is fine but not required for building"
    fi
    
    # Check Go installation
    if command -v go >/dev/null 2>&1; then
        local go_version=$(go version | awk '{print $3}')
        print_status "Go is installed: $go_version"
        
        # Check Go version (need 1.19+)
        local go_major=$(echo $go_version | sed 's/go//' | cut -d. -f1)
        local go_minor=$(echo $go_version | sed 's/go//' | cut -d. -f2)
        
        if [[ $go_major -gt 1 ]] || [[ $go_major -eq 1 && $go_minor -ge 19 ]]; then
            print_status "Go version is compatible"
        else
            print_error "Go version 1.19+ required, found $go_version"
            print_info "Install newer Go: https://golang.org/dl/"
            exit 1
        fi
    else
        print_error "Go is not installed"
        print_info "Install Go: https://golang.org/dl/"
        print_info "Or run: apt install golang-go (may be older version)"
        exit 1
    fi
    
    # Check git
    if ! command -v git >/dev/null 2>&1; then
        print_error "Git is not installed"
        print_info "Install with: apt install git"
        exit 1
    fi
    
    # Check make
    if ! command -v make >/dev/null 2>&1; then
        print_warning "Make is not installed - will use go build directly"
    fi
    
    print_status "Prerequisites check completed"
    echo
}

# Get build configuration
get_build_config() {
    print_header "Build Configuration"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Default values
    DEFAULT_VERSION="v0.21.0"
    DEFAULT_MQTT_HOST="127.0.0.1"
    DEFAULT_MQTT_PORT="1883"
    DEFAULT_API_HOST="0.0.0.0"
    DEFAULT_API_PORT="8081"
    DEFAULT_GRPC_PORT="8082"
    
    print_info "Configure build parameters to embed in binary:"
    echo
    
    read -p "Netmaker version/tag [$DEFAULT_VERSION]: " VERSION
    VERSION="${VERSION:-$DEFAULT_VERSION}"
    
    read -p "Default MQTT host [$DEFAULT_MQTT_HOST]: " MQTT_HOST
    MQTT_HOST="${MQTT_HOST:-$DEFAULT_MQTT_HOST}"
    
    read -p "Default MQTT port [$DEFAULT_MQTT_PORT]: " MQTT_PORT
    MQTT_PORT="${MQTT_PORT:-$DEFAULT_MQTT_PORT}"
    
    read -p "Default API host [$DEFAULT_API_HOST]: " API_HOST
    API_HOST="${API_HOST:-$DEFAULT_API_HOST}"
    
    read -p "Default API port [$DEFAULT_API_PORT]: " API_PORT
    API_PORT="${API_PORT:-$DEFAULT_API_PORT}"
    
    read -p "Default gRPC port [$DEFAULT_GRPC_PORT]: " GRPC_PORT
    GRPC_PORT="${GRPC_PORT:-$DEFAULT_GRPC_PORT}"
    
    echo
    print_info "Build configuration:"
    echo "  • Version: $VERSION"
    echo "  • MQTT: $MQTT_HOST:$MQTT_PORT"
    echo "  • API: $API_HOST:$API_PORT"
    echo "  • gRPC: $API_HOST:$GRPC_PORT"
    echo
}

# Clean and prepare build directory
prepare_build_dir() {
    print_header "Preparing Build Directory"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Clean previous build
    if [[ -d "$BUILD_DIR" ]]; then
        print_info "Cleaning previous build directory..."
        rm -rf "$BUILD_DIR"
    fi
    
    # Create build directory
    mkdir -p "$BUILD_DIR"
    mkdir -p "$OUTPUT_DIR"
    
    print_status "Build directory prepared: $BUILD_DIR"
}

# Clone Netmaker source
clone_source() {
    print_header "Cloning Netmaker Source"
    echo "────────────────────────────────────────────────────────────────────────"
    
    print_info "Cloning Netmaker repository..."
    cd "$BUILD_DIR"
    
    if git clone https://github.com/gravitl/netmaker.git; then
        print_status "Repository cloned successfully"
    else
        print_error "Failed to clone repository"
        exit 1
    fi
    
    cd netmaker
    
    # Checkout specific version if not latest
    if [[ "$VERSION" != "latest" && "$VERSION" != "main" ]]; then
        print_info "Checking out version: $VERSION"
        if git checkout "$VERSION"; then
            print_status "Checked out version: $VERSION"
        else
            print_warning "Failed to checkout $VERSION, using main branch"
        fi
    fi
    
    # Show current commit
    local commit_hash=$(git rev-parse --short HEAD)
    local commit_date=$(git log -1 --format="%cd" --date=short)
    print_info "Building from commit: $commit_hash ($commit_date)"
}

# Build Netmaker with embedded parameters
build_netmaker() {
    print_header "Building Netmaker"
    echo "────────────────────────────────────────────────────────────────────────"
    
    cd "$BUILD_DIR/netmaker"
    
    # Set build variables
    local BUILD_TIME=$(date -u '+%Y-%m-%d_%H:%M:%S')
    local GIT_COMMIT=$(git rev-parse --short HEAD)
    local BUILD_VERSION="$VERSION-ghostbridge"
    
    print_info "Setting up Go module..."
    export GO111MODULE=on
    export CGO_ENABLED=0
    export GOOS=linux
    export GOARCH=amd64
    
    # Download dependencies
    if go mod download; then
        print_status "Dependencies downloaded"
    else
        print_warning "Some dependencies may have failed to download"
    fi
    
    # Build with embedded parameters
    print_info "Building Netmaker binary with embedded parameters..."
    
    local LDFLAGS=(
        "-w" "-s"  # Reduce binary size
        "-X 'main.version=$BUILD_VERSION'"
        "-X 'main.buildTime=$BUILD_TIME'"
        "-X 'main.gitCommit=$GIT_COMMIT'"
        "-X 'github.com/gravitl/netmaker/config.defaultMQTTHost=$MQTT_HOST'"
        "-X 'github.com/gravitl/netmaker/config.defaultMQTTPort=$MQTT_PORT'"
        "-X 'github.com/gravitl/netmaker/config.defaultAPIHost=$API_HOST'"
        "-X 'github.com/gravitl/netmaker/config.defaultAPIPort=$API_PORT'"
        "-X 'github.com/gravitl/netmaker/config.defaultGRPCPort=$GRPC_PORT'"
    )
    
    print_info "Build flags: ${LDFLAGS[*]}"
    
    if go build -ldflags "${LDFLAGS[*]}" -o netmaker .; then
        print_status "Netmaker binary built successfully"
    else
        print_error "Build failed"
        exit 1
    fi
    
    # Copy binary to output directory
    local output_binary="$OUTPUT_DIR/netmaker-$BUILD_VERSION-$(date +%Y%m%d)"
    cp netmaker "$output_binary"
    
    # Create symlink to latest
    cd "$OUTPUT_DIR"
    ln -sf "$(basename "$output_binary")" netmaker-latest
    
    print_status "Binary saved: $output_binary"
    print_status "Symlink created: $OUTPUT_DIR/netmaker-latest"
    
    # Show binary info
    local binary_size=$(du -h "$output_binary" | cut -f1)
    print_info "Binary size: $binary_size"
    
    # Test binary
    if "$output_binary" --version >/dev/null 2>&1; then
        print_status "Binary is functional"
        print_info "Version info: $("$output_binary" --version)"
    else
        print_warning "Binary may have issues - test manually"
    fi
}

# Cleanup
cleanup() {
    print_header "Cleanup"
    echo "────────────────────────────────────────────────────────────────────────"
    
    if [[ -d "$BUILD_DIR" ]]; then
        print_info "Removing build directory..."
        rm -rf "$BUILD_DIR"
        print_status "Build directory cleaned"
    fi
}

# Show completion summary
show_completion() {
    print_header "Build Complete!"
    echo "════════════════════════════════════════════════════════════════════════"
    echo
    
    print_status "🎉 Netmaker build completed successfully!"
    echo
    
    echo -e "${CYAN}📋 Build Summary:${NC}"
    echo "  • Version: $BUILD_VERSION"
    echo "  • Embedded MQTT: $MQTT_HOST:$MQTT_PORT"
    echo "  • Embedded API: $API_HOST:$API_PORT"
    echo "  • Binary location: $OUTPUT_DIR/netmaker-latest"
    echo
    
    echo -e "${CYAN}🚀 Usage:${NC}"
    echo "  • Copy to container: pct push <id> $OUTPUT_DIR/netmaker-latest /usr/local/bin/netmaker"
    echo "  • Run deploy script and choose 'Use existing binary'"
    echo "  • Test binary: $OUTPUT_DIR/netmaker-latest --version"
    echo
    
    echo -e "${CYAN}📁 Files:${NC}"
    ls -la "$OUTPUT_DIR/"
    echo
    
    echo "════════════════════════════════════════════════════════════════════════"
}

# Main execution
main() {
    show_banner
    check_prerequisites
    get_build_config
    prepare_build_dir
    clone_source
    build_netmaker
    cleanup
    show_completion
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Netmaker build completed successfully"
}

main "$@"