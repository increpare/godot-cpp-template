# Docker Setup for Linux Cross-Compilation

## Quick Installation

You have the Docker CLI installed, but you need **Docker Desktop** to run the Docker daemon required for Linux builds.

### Option 1: Install via Homebrew (Recommended)

Run this command in your terminal (you'll be prompted for your password):

```bash
brew install --cask docker
```

After installation, start Docker Desktop:

```bash
open -a Docker
```

### Option 2: Download from Docker Website

1. Visit: https://www.docker.com/products/docker-desktop/
2. Download Docker Desktop for Mac (Apple Silicon or Intel, as appropriate)
3. Open the downloaded `.dmg` file
4. Drag Docker.app to your Applications folder
5. Open Docker Desktop from Applications

## Verify Installation

Once Docker Desktop is installed and running:

1. Look for the whale icon 🐳 in your macOS menu bar
2. Wait 30-60 seconds for Docker to fully start
3. Verify it's working:

```bash
docker info
```

You should see Docker system information (not an error).

## After Docker is Running

Once Docker is running, you can complete your Linux build:

```bash
# Build just Linux
make linux64-docker

# Or build all platforms
make all
```

## Quick Start Script

You can also use the helper script once Docker Desktop is installed:

```bash
./start-docker.sh
```

This will automatically find and start Docker Desktop for you.

## Troubleshooting

**Problem:** `Error: Docker daemon is not running`

**Solution:** Make sure Docker Desktop is running. Check your menu bar for the Docker whale icon. If it's not there:
1. Open Docker Desktop from Applications
2. Wait for it to start (30-60 seconds)
3. Try your build again

**Problem:** Docker Desktop won't start

**Solution:** 
- Make sure you have enough disk space
- Check System Preferences > Security & Privacy to allow Docker if prompted
- Restart your Mac if needed

