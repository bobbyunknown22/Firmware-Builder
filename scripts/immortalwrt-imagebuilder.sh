#!/bin/bash

# ImmortalWrt ImageBuilder Script  
# Usage: ./immortalwrt-imagebuilder.sh <version> <packages>

set -e  # Exit on any error

VERSION="$1"
PACKAGES="$2"

if [ -z "$VERSION" ]; then
    echo "Error: ImmortalWrt version is required"
    echo "Usage: $0 <version> <packages>"
    exit 1
fi

echo "=== ImmortalWrt ImageBuilder Setup ==="
echo "Version: $VERSION"
echo "Packages: ${PACKAGES:-'default'}"

# Function to wait for apt lock
wait_for_apt_lock() {
    echo "Waiting for apt lock to be released..."
    while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        echo "Waiting for other apt process to finish..."
        sleep 5
    done
}

# Install required tools
echo "Installing extraction tools..."
wait_for_apt_lock
sudo apt-get update && sudo apt-get install -y xz-utils

# Download ImmortalWrt ImageBuilder
echo "Downloading ImmortalWrt ImageBuilder..."
IMAGEBUILDER_URL="https://downloads.immortalwrt.org/releases/${VERSION}/targets/armsr/armv8/immortalwrt-imagebuilder-${VERSION}-armsr-armv8.Linux-x86_64.tar.xz"
echo "Downloading from: $IMAGEBUILDER_URL"

wget -O immortalwrt-imagebuilder.tar.xz "$IMAGEBUILDER_URL"

# Extract ImageBuilder
echo "Extracting ImmortalWrt ImageBuilder..."
tar -xf immortalwrt-imagebuilder.tar.xz

# Find extracted directory
IMAGEBUILDER_DIR=$(find . -maxdepth 1 -name "immortalwrt-imagebuilder-*" -type d | head -1)
if [ -z "$IMAGEBUILDER_DIR" ]; then
    echo "Error: ImmortalWrt ImageBuilder directory not found after extraction!"
    ls -la
    exit 1
fi

echo "Found ImmortalWrt ImageBuilder directory: $IMAGEBUILDER_DIR"
cd "$IMAGEBUILDER_DIR"

# Install build dependencies
echo "Installing build dependencies..."
wait_for_apt_lock
sudo apt-get install -y build-essential clang flex bison g++ gawk \
    gcc-multilib g++-multilib gettext git libncurses5-dev libssl-dev \
    python3-setuptools rsync swig unzip zlib1g-dev file wget

# Build custom rootfs
echo "Building ImmortalWrt custom rootfs..."
if [ -n "$PACKAGES" ]; then
    echo "Building with custom packages: $PACKAGES"
    make image PROFILE=generic PACKAGES="$PACKAGES" ROOTFS_PARTSIZE=1024
else
    echo "Building with default packages"
    make image PROFILE=generic ROOTFS_PARTSIZE=1024
fi

# Find generated rootfs
ROOTFS_FILE=$(find bin/targets/armsr/armv8/ -name "*rootfs*.img.gz" | head -1)
if [ -z "$ROOTFS_FILE" ]; then
    echo "Error: No rootfs file found!"
    exit 1
fi

# Generate output filename
CUSTOM_ROOTFS_NAME="immortalwrt-${VERSION}-custom-armsr-armv8-generic-ext4-rootfs.img.gz"

# Copy to ULO-Builder
echo "Copying rootfs to ULO-Builder..."
mkdir -p ../ULO-Builder/rootfs
cp "$ROOTFS_FILE" "../ULO-Builder/rootfs/$CUSTOM_ROOTFS_NAME"

echo "=== ImmortalWrt ImageBuilder Complete ==="
echo "Generated: $CUSTOM_ROOTFS_NAME"
echo "Location: ULO-Builder/rootfs/$CUSTOM_ROOTFS_NAME"

# Export environment variable for GitHub Actions
echo "CUSTOM_ROOTFS_NAME=$CUSTOM_ROOTFS_NAME" >> $GITHUB_ENV
echo "ROOTFS_FILENAME=$CUSTOM_ROOTFS_NAME" >> $GITHUB_ENV