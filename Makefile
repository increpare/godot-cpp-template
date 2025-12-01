TARGET = template_debug

BASE = scons target=$(TARGET) $(EXTRA_ARGS)
LINUX = $(BASE) platform=linux
WINDOWS = $(BASE) platform=windows
MACOS = $(BASE) platform=macos


.PHONY: usage
usage:
	@echo -e "Specify one of the available targets:\n"
	@LC_ALL=C $(MAKE) -pRrq -f $(lastword $(MAKEFILE_LIST)) : 2>/dev/null | awk -v RS= -F: '/(^|\n)# Files(\n|$$)/,/(^|\n)# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' | sort | grep -E -v -e '^[^[:alnum:]]' -e '^$@$$'
	@echo -e "\nDefine the SCons target with TARGET, and pass extra SCons arguments with EXTRA_ARGS."


linux:
	@echo "⚠️  WARNING: Native Linux builds don't work on macOS!"
	@echo ""
	@echo "You need to use Docker-based builds instead:"
	@echo "  make linux64-docker  (recommended for macOS)"
	@echo "  make linux-docker    (builds both 32 and 64-bit)"
	@echo ""
	@echo "Or skip Linux:  make all-no-linux"
	@exit 1

linux32: SConstruct
	@echo "⚠️  Native Linux builds don't work on macOS. Use: make linux32-docker"
	@exit 1

linux64: SConstruct
	@echo "⚠️  Native Linux builds don't work on macOS. Use: make linux64-docker"
	@exit 1

# Docker-based Linux builds (recommended for macOS)
linux-docker:
	make linux32-docker
	make linux64-docker

linux32-docker:
	@./docker-build-linux.sh --arch x86_32 --target $(TARGET)

linux64-docker:
	@./docker-build-linux.sh --arch x86_64 --target $(TARGET)


windows:
	make windows32
	make windows64

windows32: SConstruct
	$(WINDOWS) arch=x86_32

windows64: SConstruct
	$(WINDOWS) arch=x86_64


macos: SConstruct
	$(MACOS)


# Deploy built binaries to shared drive
deploy:
	@echo "Deploying to egg folder..."
	@rm -rf ~/Documents/vbox_shared_drive/egg-game/bin
	@cp -r demo/bin ~/Documents/vbox_shared_drive/egg-game/bin
	@echo "Deployment complete!"

# Build for windows64, macos, and linux64
# Uses Docker for Linux builds (recommended for macOS cross-compilation)
all: windows64 macos linux64-docker deploy

# Build for windows64 and macos only (skip Linux - no Docker needed)
all-no-linux: windows64 macos deploy

