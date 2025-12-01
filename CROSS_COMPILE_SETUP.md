# Cross-Compilation Setup for macOS

This document explains how to cross-compile this library for Windows and Linux from macOS.

## Table of Contents

- [Windows Cross-Compilation](#windows-cross-compilation)
- [Linux Cross-Compilation](#linux-cross-compilation)

## Prerequisites

The MinGW-w64 toolchain has been installed via Homebrew. This provides:
- `x86_64-w64-mingw32-g++` - For 64-bit Windows builds
- `i686-w64-mingw32-g++` - For 32-bit Windows builds

## Building for Windows

### 64-bit Windows (x86_64)

```bash
scons platform=windows arch=x86_64 target=template_debug
```

### 32-bit Windows (x86_32)

```bash
scons platform=windows arch=x86_32 target=template_debug
```

## Important Notes

1. **Architecture Parameter**: Always specify the `arch` parameter explicitly. Without it, the build system will auto-detect your host architecture (ARM64 on Apple Silicon), which may not be what you want.

2. **The `bits` Parameter**: The `bits=64` parameter is not valid for this build system. Use `arch=x86_64` instead.

3. **ARM64 Windows**: If you need to build for ARM64 Windows (Windows on ARM), you'll need to install an additional toolchain. ARM64 Windows cross-compilation from macOS is not well-supported in the standard MinGW-w64 package.

## Troubleshooting

### Error: "command not found: aarch64-w64-mingw32-g++"

This means the build system detected ARM64 architecture but you're trying to build for Windows. Fix by explicitly specifying the architecture:

```bash
scons platform=windows arch=x86_64 target=template_debug
```

### Verifying Toolchain Installation

To verify the toolchains are installed:

```bash
# Check 64-bit toolchain
x86_64-w64-mingw32-g++ --version

# Check 32-bit toolchain
i686-w64-mingw32-g++ --version
```

Both should output version information without errors.

## Environment Variables

If needed, you can specify a custom MinGW prefix:

```bash
export MINGW_PREFIX=/opt/homebrew
scons platform=windows arch=x86_64
```

However, this is usually not necessary as the build system should find the tools automatically in your PATH.

---

## Linux Cross-Compilation

Cross-compiling Linux binaries from macOS is problematic because macOS uses clang, which doesn't support GCC-specific flags like `-fno-gnu-unique`. The recommended solution is to use **Docker** for Linux builds.

For more discussion on this topic, see: [Building a GDExtension for Windows and Linux on a Mac](https://forum.godotengine.org/t/building-a-gdextension-for-windows-and-linux-on-a-mac/73640/2)

### Prerequisites

1. **Docker** - Install from [docker.com](https://www.docker.com/products/docker-desktop/) or via Homebrew:
   ```bash
   brew install --cask docker
   ```
   
   Make sure Docker is running before building.

### Building for Linux with Docker

#### Using the Build Script

The easiest way is to use the provided script:

```bash
# Build for 64-bit Linux
./docker-build-linux.sh --arch x86_64 --target template_debug

# Build for 32-bit Linux
./docker-build-linux.sh --arch x86_32 --target template_debug

# Build for release
./docker-build-linux.sh --arch x86_64 --target template_release
```

#### Using Make

The Makefile has been updated to use Docker for Linux builds automatically:

```bash
# Build for 64-bit Linux (uses Docker)
make linux64-docker

# Build for 32-bit Linux (uses Docker)
make linux32-docker

# Build all platforms (Windows, macOS, Linux) - Linux uses Docker
make all
```

#### Manual Docker Build

You can also build manually using Docker:

```bash
# Build the Docker image (first time only)
docker build -f Dockerfile.linux -t godot-cpp-linux-builder .

# Run the build
docker run --rm \
    -v $(pwd):/build \
    -w /build \
    godot-cpp-linux-builder \
    scons platform=linux arch=x86_64 target=template_debug
```

### Troubleshooting Linux Builds

#### Error: "Docker daemon is not running"

Make sure Docker Desktop is started. On macOS, you can:

1. **Start Docker Desktop manually** from Applications, or
2. **Use the helper script**:
   ```bash
   ./start-docker.sh
   ```

The helper script will automatically find and start Docker Desktop, then wait for it to be ready.

You'll know Docker is ready when:
- You see the whale icon in your macOS menu bar
- Running `docker info` works without errors

#### Error: "unknown argument: '-fno-gnu-unique'"

This error occurs when trying to build Linux natively on macOS. Use Docker instead:

```bash
make linux64-docker
```

#### Error: "unsupported argument 'x86-64' to option '-march='"

This is another cross-compilation issue. Use Docker for Linux builds.

### Alternative: Native Linux Build (Not Recommended on macOS)

If you have a Linux machine or VM, you can build natively:

```bash
scons platform=linux arch=x86_64 target=template_debug
```

However, native cross-compilation from macOS to Linux is not well-supported and often fails with compiler flag incompatibilities.

