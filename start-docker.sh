#!/bin/bash
# Helper script to start Docker Desktop on macOS

echo "Checking Docker status..."

# Check if Docker daemon is already running
if docker info &> /dev/null; then
    echo "✓ Docker is already running!"
    exit 0
fi

echo "Docker daemon is not running."

# Try to find Docker Desktop
DOCKER_APP="/Applications/Docker.app"
if [ -d "$DOCKER_APP" ]; then
    echo "Found Docker Desktop at $DOCKER_APP"
    echo "Starting Docker Desktop..."
    open "$DOCKER_APP"
    echo ""
    echo "Please wait for Docker Desktop to start (this may take 30-60 seconds)."
    echo "You'll see a whale icon in your menu bar when it's ready."
    echo ""
    echo "Waiting for Docker to be ready..."
    
    # Wait up to 60 seconds for Docker to start
    for i in {1..60}; do
        if docker info &> /dev/null; then
            echo "✓ Docker is now running!"
            exit 0
        fi
        echo -n "."
        sleep 1
    done
    echo ""
    echo "Docker didn't start within 60 seconds. Please check Docker Desktop manually."
    exit 1
else
    echo "Error: Docker Desktop not found at $DOCKER_APP"
    echo ""
    echo "Please install Docker Desktop from:"
    echo "  https://www.docker.com/products/docker-desktop/"
    echo ""
    echo "Or install via Homebrew:"
    echo "  brew install --cask docker"
    exit 1
fi

