#!/bin/bash
# Script to build Linux GDExtension binaries using Docker
# This solves cross-compilation issues when building from macOS

set -e

# Default values
ARCH="x86_64"
TARGET="template_debug"
PLATFORM="linux"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --target)
            TARGET="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--arch ARCH] [--target TARGET]"
            echo "  --arch ARCH     Architecture (x86_64, x86_32, arm64, arm32). Default: x86_64"
            echo "  --target TARGET Build target (template_debug, template_release, editor). Default: template_debug"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed or not in PATH"
    exit 1
fi

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
    echo "❌ Error: Docker daemon is not running"
    echo ""
    echo "To fix this:"
    echo "  1. Install Docker Desktop if you haven't:"
    echo "     brew install --cask docker"
    echo ""
    echo "  2. Start Docker Desktop:"
    echo "     open -a Docker"
    echo "     (Or use: ./start-docker.sh)"
    echo ""
    echo "  3. Wait 30-60 seconds for Docker to start"
    echo "  4. Look for the 🐳 whale icon in your menu bar"
    echo "  5. Run this command again"
    echo ""
    echo "For more help, see: DOCKER_SETUP.md"
    exit 1
fi

echo "Building Linux GDExtension for ${ARCH} (target: ${TARGET})..."
echo "Project directory: ${PROJECT_DIR}"

# Determine Docker platform and image based on target architecture
# For x86 builds on ARM64 Macs, we need to use platform emulation
if [[ "${ARCH}" == "x86_32" ]]; then
    DOCKER_PLATFORM="linux/amd64"
    IMAGE_NAME="godot-cpp-linux-builder-32bit"
    DOCKERFILE="${PROJECT_DIR}/Dockerfile.linux.32bit"
elif [[ "${ARCH}" == "x86_64" ]]; then
    DOCKER_PLATFORM="linux/amd64"
    IMAGE_NAME="godot-cpp-linux-builder-amd64"
    DOCKERFILE="${PROJECT_DIR}/Dockerfile.linux"
else
    DOCKER_PLATFORM="linux/arm64"
    IMAGE_NAME="godot-cpp-linux-builder"
    DOCKERFILE="${PROJECT_DIR}/Dockerfile.linux"
fi

# Build the Docker image if it doesn't exist
if ! docker images | grep -q "${IMAGE_NAME}"; then
    echo "Building Docker image for ${DOCKER_PLATFORM}..."
    docker build --platform "${DOCKER_PLATFORM}" \
        -f "${DOCKERFILE}" \
        -t "${IMAGE_NAME}" \
        "${PROJECT_DIR}"
fi

# Run the build inside Docker
# Mount the project directory and build directory
# Use platform specification to ensure correct architecture
docker run --rm \
    --platform "${DOCKER_PLATFORM}" \
    -v "${PROJECT_DIR}:/build" \
    -w /build \
    "${IMAGE_NAME}" \
    scons platform="${PLATFORM}" arch="${ARCH}" target="${TARGET}"

echo "Build complete! Output should be in bin/linux/"

