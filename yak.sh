#!/bin/bash

# Set defaults
DEFCONFIG="yap_defconfig"
EXTRA_DEFCONFIGS=()
USE_CCACHE=0
USE_KSU=0

# Check if no arguments were given
if [ $# -eq 0 ]; then
    echo "No options were provided."
    echo "Did you know there are extra build options available?"
    read -p "Do you want to continue without any options? (yes/no) " REPLY
    case "$REPLY" in
        [yY][eE][sS]|[yY])
            echo "Continuing without extra options..."
            ;;
        *)
            echo "Available options:"
            echo "  -k       Use ksu.config"
            echo "  -C       Enable ccache"
            echo "  -yapper  Select extra defconfigs interactively"
            exit 1
            ;;
    esac
fi

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -k)
            EXTRA_DEFCONFIGS+=("yappachino/ksu.config")
            USE_KSU=1
            ;;
        -C)
            USE_CCACHE=1
            ;;
        -yapper)
            echo "Available extra defconfigs:"
            CONFIG_FILES=($(ls yappachino/yap+*.config 2>/dev/null | grep -v "ksu.config"))
            SELECTED_CONFIGS=()
            if [ ${#CONFIG_FILES[@]} -eq 0 ]; then
                echo "No extra defconfigs found."
            else
                for CONFIG in "${CONFIG_FILES[@]}"; do
                    NAME=$(basename "$CONFIG")
                    read -p "Add $NAME? (*) for yes, enter to skip: " REPLY
                    if [[ "$REPLY" == "*" ]]; then
                        SELECTED_CONFIGS+=("$CONFIG")
                    fi
                done
                EXTRA_DEFCONFIGS+=("${SELECTED_CONFIGS[@]}")
            fi
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Available options:"
            echo "  -k       Use ksu.config"
            echo "  -C       Enable ccache"
            echo "  -yapper  Select extra defconfigs interactively"
            exit 1
            ;;
    esac
    shift
done

# Clean previous build artifacts
make clean && make mrproper

# Set up environment variables
export PATH=$(pwd)/toolchain/prebuilts_clang_host_linux-x86_clang-r383902-main/bin:$PATH

if [ $USE_CCACHE -eq 1 ]; then
    export CROSS_COMPILE="ccache $(pwd)/toolchain/aarch64-linux-gnu-master/bin/aarch64-linux-gnu-"
    export CC="ccache $(pwd)/toolchain/prebuilts_clang_host_linux-x86_clang-r383902-main/bin/clang"
    export USE_CCACHE=1
    export CCACHE_DIR=~/.ccache
    ccache -M 4G
else
    export CROSS_COMPILE="$(pwd)/toolchain/aarch64-linux-gnu-master/bin/aarch64-linux-gnu-"
    export CC="$(pwd)/toolchain/prebuilts_clang_host_linux-x86_clang-r383902-main/bin/clang"
fi

export CLANG_TRIPLE=aarch64-linux-gnu-
export ARCH=arm64
export PLATFORM_VERSION=13
export KCFLAGS=-w
export CONFIG_SECTION_MISMATCH_WARN_ONLY=y

# Create output directory
mkdir -p out

# Merge defconfigs if extra ones are selected
if [ ${#EXTRA_DEFCONFIGS[@]} -gt 0 ]; then
    echo "Merging arch/arm64/configs/$DEFCONFIG with ${EXTRA_DEFCONFIGS[*]}..."
    ARCH=arm64 scripts/kconfig/merge_config.sh -m arch/arm64/configs/$DEFCONFIG ${EXTRA_DEFCONFIGS[@]}
    DEFCONFIG=".config"
fi

# Build the kernel with the merged defconfig
make -C $(pwd) O=$(pwd)/out KCFLAGS=-w CONFIG_SECTION_MISMATCH_WARN_ONLY=y LLVM=1 LLVM_IAS=1 $DEFCONFIG
make -C $(pwd) O=$(pwd)/out KCFLAGS=-w CONFIG_SECTION_MISMATCH_WARN_ONLY=y LLVM=1 LLVM_IAS=1 -j$(nproc)

# Create build directory
mkdir -p build

# Copy kernel Image to build folder
cp out/arch/arm64/boot/Image build/

# Build DTBO
make -C $(pwd) O=$(pwd)/out KCFLAGS=-w CONFIG_SECTION_MISMATCH_WARN_ONLY=y LLVM=1 LLVM_IAS=1 dtbo.img -j$(nproc)

# Copy DTBO to build folder
cp out/arch/arm64/boot/dtbo.img build/

# Define paths for boot.img components
KERNEL="build/Image"
DTBO="build/dtbo.img"
RAMDISK="ramdisk.img"  # Provide a valid ramdisk image
DTB="out/arch/arm64/boot/dtb"  # Ensure dtb exists
BOOTIMG="build/boot.img"

# Check if mkbootimg exists
MKBOOTIMG_BIN="mkbootimg"
if ! command -v $MKBOOTIMG_BIN &> /dev/null; then
    echo "Error: mkbootimg not found! Install mkbootimg or provide the correct path."
    exit 1
fi

# Generate boot.img
$MKBOOTIMG_BIN --kernel $KERNEL \
               --ramdisk $RAMDISK \
               --dtb $DTB \
               --cmdline "console=ttyS0,115200n8 earlycon=uart8250,mmio32,0x11004000" \
               --base 0x40000000 \
               --kernel_offset 0x00008000 \
               --ramdisk_offset 0x01000000 \
               --dtb_offset 0x01f00000 \
               --tags_offset 0x00000100 \
               --pagesize 2048 \
               --os_version 13.0.0 \
               --os_patch_level 2023-12-01 \
               --output $BOOTIMG

echo "Build completed! Kernel, DTBO, and boot.img are in the 'build/' directory."

