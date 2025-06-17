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

# Install Go if needed
install_go() {
    print_header "Installing Go"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Check if Go is already installed and compatible
    if command -v go >/dev/null 2>&1; then
        local go_version=$(go version | awk '{print $3}')
        local go_major=$(echo $go_version | sed 's/go//' | cut -d. -f1)
        local go_minor=$(echo $go_version | sed 's/go//' | cut -d. -f2)
        
        if [[ $go_major -gt 1 ]] || [[ $go_major -eq 1 && $go_minor -ge 19 ]]; then
            print_status "Go is already installed: $go_version"
            return 0
        else
            print_warning "Go version $go_version is too old, installing latest"
        fi
    else
        print_info "Go not found, installing latest version"
    fi
    
    # Detect architecture
    local arch=$(uname -m)
    local go_arch
    case "$arch" in
        x86_64) go_arch="amd64" ;;
        aarch64|arm64) go_arch="arm64" ;;
        armv7l) go_arch="armv6l" ;;
        *) 
            print_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
    
    # Get latest Go version
    print_info "Fetching latest Go version..."
    local latest_go=$(curl -s https://go.dev/VERSION?m=text | head -1)
    if [[ -z "$latest_go" ]]; then
        latest_go="go1.21.5"  # Fallback version
        print_warning "Could not fetch latest version, using fallback: $latest_go"
    else
        print_info "Latest Go version: $latest_go"
    fi
    
    # Download and install Go
    local go_download_url="https://go.dev/dl/${latest_go}.linux-${go_arch}.tar.gz"
    local go_install_dir="/usr/local"
    local go_archive="/tmp/${latest_go}.linux-${go_arch}.tar.gz"
    
    print_info "Downloading Go from: $go_download_url"
    if wget -O "$go_archive" "$go_download_url"; then
        print_status "Go downloaded successfully"
    else
        print_error "Failed to download Go"
        exit 1
    fi
    
    # Remove old Go installation
    if [[ -d "$go_install_dir/go" ]]; then
        print_info "Removing old Go installation"
        rm -rf "$go_install_dir/go"
    fi
    
    # Extract new Go
    print_info "Installing Go to $go_install_dir"
    if tar -C "$go_install_dir" -xzf "$go_archive"; then
        print_status "Go extracted successfully"
        rm "$go_archive"
    else
        print_error "Failed to extract Go"
        exit 1
    fi
    
    # Add Go to PATH for current session
    export PATH="$go_install_dir/go/bin:$PATH"
    
    # Update system PATH
    if ! grep -q "/usr/local/go/bin" /etc/environment 2>/dev/null; then
        print_info "Adding Go to system PATH"
        echo 'PATH="/usr/local/go/bin:$PATH"' >> /etc/environment
    fi
    
    # Add to profile files
    for profile_file in /etc/profile /root/.bashrc /root/.profile; do
        if [[ -f "$profile_file" ]] && ! grep -q "/usr/local/go/bin" "$profile_file"; then
            echo 'export PATH="/usr/local/go/bin:$PATH"' >> "$profile_file"
        fi
    done
    
    # Verify installation
    if command -v go >/dev/null 2>&1; then
        local installed_version=$(go version)
        print_status "Go installed successfully: $installed_version"
    else
        print_error "Go installation verification failed"
        exit 1
    fi
    
    echo
}

# Check and install prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        print_warning "Not running as root - may need sudo for Go installation"
        print_info "Run with sudo for automatic Go installation"
    fi
    
    # Install essential packages
    print_info "Installing essential packages..."
    if command -v apt >/dev/null 2>&1; then
        apt update -qq
        apt install -y wget curl git build-essential
    elif command -v yum >/dev/null 2>&1; then
        yum install -y wget curl git gcc gcc-c++ make
    else
        print_warning "Package manager not detected - ensure wget, curl, git are installed"
    fi
    
    # Install Go
    install_go
    
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
    
    # Check if running as root for Go installation
    if [[ $EUID -ne 0 ]]; then
        print_warning "Not running as root - checking if Go is available"
        if ! command -v go >/dev/null 2>&1; then
            print_error "Go not found and not running as root"
            print_info "Please run as root to auto-install Go, or install Go manually:"
            print_info "  sudo $0"
            print_info "  Or: wget https://go.dev/dl/go1.21.5.linux-amd64.tar.gz"
            exit 1
        fi
    fi
    
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