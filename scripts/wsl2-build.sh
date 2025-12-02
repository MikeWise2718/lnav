#!/bin/bash
#
# lnav WSL2 Build Script
# ======================
#
# This script clones lnav from GitHub and builds it in WSL2's native
# filesystem for optimal performance.
#
# USAGE:
#   1. Copy this script to WSL2:
#      cp /mnt/d/cpp/lnav/scripts/wsl2-build.sh ~/
#   2. Run it:
#      bash ~/wsl2-build.sh
#
#   Or run directly from Windows filesystem:
#      bash /mnt/d/cpp/lnav/scripts/wsl2-build.sh
#
# OPTIONS:
#   --repo URL      Git repository URL (default: your fork)
#   --branch NAME   Branch to build (default: master)
#   --with-rust     Include Rust/PRQL support (adds ~5min to build)
#   --static        Build a static binary
#   --clean         Remove existing source and rebuild from scratch
#   --install       Install after building (requires sudo)
#   --jobs N        Number of parallel jobs (default: auto-detect)
#   --help          Show this help message
#
# The script will:
#   1. Clone the repo to ~/lnav-src (WSL2 native filesystem = fast!)
#   2. Install required Ubuntu packages
#   3. Build in ~/lnav-build
#   4. Optionally install to /usr/local/bin
#
# REQUIREMENTS:
#   - WSL2 with Ubuntu 22.04 or later
#   - Internet connection
#   - sudo access for installing dependencies
#

set -e  # Exit on error
set -o pipefail

# =============================================================================
# Configuration
# =============================================================================

# Default to your fork
DEFAULT_REPO="https://github.com/MikeWise2718/lnav.git"
DEFAULT_BRANCH="master"

# Build locations (in WSL2 native filesystem for speed)
SOURCE_DIR="$HOME/lnav-src"
BUILD_DIR="$HOME/lnav-build"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default options
REPO_URL="$DEFAULT_REPO"
BRANCH="$DEFAULT_BRANCH"
WITH_RUST=0
STATIC_BUILD=0
CLEAN_BUILD=0
DO_INSTALL=0
JOBS=$(nproc 2>/dev/null || echo 4)

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

show_help() {
    head -45 "$0" | grep -E "^#" | sed 's/^# \?//'
    exit 0
}

check_wsl() {
    if ! grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null; then
        log_warn "This doesn't appear to be WSL2. Script may still work on native Linux."
    else
        log_info "WSL2 environment detected"
    fi
}

check_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log_info "Detected: $NAME $VERSION_ID"
        if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
            log_warn "This script is optimized for Ubuntu/Debian. Package names may differ."
        fi
    fi
}

# =============================================================================
# Parse Arguments
# =============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --repo)
            REPO_URL="$2"
            shift 2
            ;;
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --with-rust)
            WITH_RUST=1
            shift
            ;;
        --static)
            STATIC_BUILD=1
            shift
            ;;
        --clean)
            CLEAN_BUILD=1
            shift
            ;;
        --install)
            DO_INSTALL=1
            shift
            ;;
        --jobs)
            JOBS="$2"
            shift 2
            ;;
        --help|-h)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# =============================================================================
# Main Script
# =============================================================================

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           lnav WSL2 Build Script                             ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

check_wsl
check_distro

echo ""
log_info "Repository:       $REPO_URL"
log_info "Branch:           $BRANCH"
log_info "Source directory: $SOURCE_DIR"
log_info "Build directory:  $BUILD_DIR"
log_info "Parallel jobs:    $JOBS"
log_info "With Rust:        $([ $WITH_RUST -eq 1 ] && echo 'Yes' || echo 'No')"
log_info "Static build:     $([ $STATIC_BUILD -eq 1 ] && echo 'Yes' || echo 'No')"

# =============================================================================
# Step 1: Install Dependencies
# =============================================================================

log_step "Step 1/5: Installing build dependencies"

# Check if we need to install packages
PACKAGES_NEEDED=0
REQUIRED_PACKAGES=(
    build-essential
    autoconf
    automake
    libtool
    pkg-config
    libpcre2-dev
    libsqlite3-dev
    zlib1g-dev
    libbz2-dev
    libcurl4-openssl-dev
    libarchive-dev
    libunistring-dev
    libncurses-dev
    libreadline-dev
    re2c
    git
)

for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        PACKAGES_NEEDED=1
        log_info "Missing package: $pkg"
    fi
done

if [ $PACKAGES_NEEDED -eq 1 ]; then
    log_info "Installing required packages (requires sudo)..."

    # Use DEBIAN_FRONTEND to make apt non-interactive
    export DEBIAN_FRONTEND=noninteractive

    sudo apt-get update -qq

    sudo apt-get install -y -qq "${REQUIRED_PACKAGES[@]}"

    log_success "Dependencies installed"
else
    log_success "All required packages already installed"
fi

# Optional: Install Rust
if [ $WITH_RUST -eq 1 ]; then
    # Always source cargo env if it exists (needed for configure to find cargo)
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    fi

    if ! command -v cargo &>/dev/null; then
        log_info "Installing Rust toolchain..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --quiet
        source "$HOME/.cargo/env"
        log_success "Rust installed"
    else
        log_success "Rust already installed: $(cargo --version)"
    fi
fi

# =============================================================================
# Step 2: Clone or Update Repository
# =============================================================================

log_step "Step 2/5: Getting source code from GitHub"

if [ $CLEAN_BUILD -eq 1 ] && [ -d "$SOURCE_DIR" ]; then
    log_info "Removing existing source directory (--clean specified)..."
    rm -rf "$SOURCE_DIR"
fi

if [ -d "$SOURCE_DIR/.git" ]; then
    log_info "Source directory exists, updating..."
    cd "$SOURCE_DIR"

    # Fetch and reset to ensure clean state
    git fetch origin
    git checkout "$BRANCH"
    git reset --hard "origin/$BRANCH"
    git clean -fdx

    log_success "Repository updated to latest $BRANCH"
else
    log_info "Cloning repository..."
    git clone --branch "$BRANCH" "$REPO_URL" "$SOURCE_DIR"
    cd "$SOURCE_DIR"
    log_success "Repository cloned"
fi

# Show commit info
COMMIT_HASH=$(git rev-parse --short HEAD)
COMMIT_MSG=$(git log -1 --pretty=format:"%s")
log_info "Building commit: $COMMIT_HASH - $COMMIT_MSG"

# =============================================================================
# Step 3: Run autogen.sh
# =============================================================================

log_step "Step 3/5: Running autogen.sh"

cd "$SOURCE_DIR"

./autogen.sh

log_success "autogen.sh completed"

# =============================================================================
# Step 4: Configure
# =============================================================================

log_step "Step 4/5: Configuring build"

# Clean build directory if requested
if [ $CLEAN_BUILD -eq 1 ] && [ -d "$BUILD_DIR" ]; then
    log_info "Removing existing build directory..."
    rm -rf "$BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Build configure arguments
CONFIGURE_ARGS=""

if [ $WITH_RUST -eq 0 ]; then
    CONFIGURE_ARGS="$CONFIGURE_ARGS --without-cargo"
fi

if [ $STATIC_BUILD -eq 1 ]; then
    CONFIGURE_ARGS="$CONFIGURE_ARGS --enable-static"
fi

# Run configure
log_info "Running configure with: $CONFIGURE_ARGS"

if [ $STATIC_BUILD -eq 1 ]; then
    "$SOURCE_DIR/configure" \
        $CONFIGURE_ARGS \
        LDFLAGS="-static" \
        CPPFLAGS="-O2" \
        CXXFLAGS="-O2" \
        CFLAGS="-O2" \
        --prefix=/usr/local
else
    "$SOURCE_DIR/configure" \
        $CONFIGURE_ARGS \
        CPPFLAGS="-O2" \
        CXXFLAGS="-O2" \
        CFLAGS="-O2" \
        --prefix=/usr/local
fi

log_success "Configuration completed"

# =============================================================================
# Step 5: Build
# =============================================================================

log_step "Step 5/5: Building lnav"

log_info "Building with $JOBS parallel jobs..."
log_info "This may take 3-10 minutes depending on your hardware."
echo ""

# Build
make -j$JOBS

log_success "Build completed!"

# =============================================================================
# Optional: Install
# =============================================================================

if [ $DO_INSTALL -eq 1 ]; then
    log_step "Installing lnav"
    sudo make install
    log_success "lnav installed to /usr/local/bin/lnav"
fi

# =============================================================================
# Summary and Testing
# =============================================================================

log_step "Build Complete!"

BINARY_PATH="$BUILD_DIR/src/lnav"

if [ -x "$BINARY_PATH" ]; then
    log_success "Binary location: $BINARY_PATH"
    echo ""

    # Show version
    log_info "Version info:"
    "$BINARY_PATH" -V
    echo ""

    # Quick functional test
    log_info "Quick functional test:"
    TEST_LOG="Dec 02 12:00:00 testhost myapp[1234]: Build successful - lnav is working!"
    echo "$TEST_LOG" | "$BINARY_PATH" -n
    echo ""

    # File size
    BINARY_SIZE=$(du -h "$BINARY_PATH" | cut -f1)
    log_info "Binary size: $BINARY_SIZE"
    echo ""

    # Usage hints
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Usage Examples${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  # Run directly:"
    echo "  $BINARY_PATH /var/log/syslog"
    echo ""
    echo "  # View Windows log files:"
    echo "  $BINARY_PATH /mnt/c/path/to/logfile.log"
    echo ""
    echo "  # Add alias to ~/.bashrc:"
    echo "  echo 'alias lnav=\"$BINARY_PATH\"' >> ~/.bashrc"
    echo ""

    if [ $DO_INSTALL -eq 1 ]; then
        echo "  # Or just run (already installed):"
        echo "  lnav /var/log/syslog"
        echo ""
    fi
else
    log_error "Binary not found at expected location!"
    log_error "Check build output above for errors."
    exit 1
fi

log_success "All done!"
