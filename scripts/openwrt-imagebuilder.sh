#!/bin/bash

# OpenWrt ImageBuilder Script
# Usage: ./openwrt-imagebuilder.sh <version> <packages>

set -e  # Exit on any error

VERSION="$1"
PACKAGES="$2"

if [ -z "$VERSION" ]; then
    echo "Error: OpenWrt version is required"
    echo "Usage: $0 <version> <packages>"
    exit 1
fi

echo "=== OpenWrt ImageBuilder Setup ==="
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
sudo apt-get update && sudo apt-get install -y zstd xz-utils

# Download ImageBuilder with fallback
echo "Downloading OpenWrt ImageBuilder..."
IMAGEBUILDER_URL="https://downloads.openwrt.org/releases/${VERSION}/targets/armsr/armv8/openwrt-imagebuilder-${VERSION}-armsr-armv8.Linux-x86_64.tar.zst"
echo "Trying: $IMAGEBUILDER_URL"

if ! wget --spider "$IMAGEBUILDER_URL" 2>/dev/null; then
    echo "Warning: .tar.zst not found, trying .tar.xz format..."
    IMAGEBUILDER_URL="https://downloads.openwrt.org/releases/${VERSION}/targets/armsr/armv8/openwrt-imagebuilder-${VERSION}-armsr-armv8.Linux-x86_64.tar.xz"
    echo "Trying: $IMAGEBUILDER_URL"
    wget -O openwrt-imagebuilder.tar.xz "$IMAGEBUILDER_URL"
    FILE_EXT="xz"
else
    wget -O openwrt-imagebuilder.tar.zst "$IMAGEBUILDER_URL"
    FILE_EXT="zst"
fi

# Extract ImageBuilder
echo "Extracting OpenWrt ImageBuilder..."
if [ "$FILE_EXT" = "zst" ]; then
    tar --zstd -xf openwrt-imagebuilder.tar.zst
else
    tar -xf openwrt-imagebuilder.tar.xz
fi

# Find extracted directory
IMAGEBUILDER_DIR=$(find . -maxdepth 1 -name "openwrt-imagebuilder-*" -type d | head -1)
if [ -z "$IMAGEBUILDER_DIR" ]; then
    echo "Error: OpenWrt ImageBuilder directory not found after extraction!"
    ls -la
    exit 1
fi

echo "Found OpenWrt ImageBuilder directory: $IMAGEBUILDER_DIR"
cd "$IMAGEBUILDER_DIR"

# Configure .config to generate only tar.gz rootfs
echo "Configuring ImageBuilder for tar.gz output only..."
sed -i 's/CONFIG_TARGET_ROOTFS_EXT4FS=y/# CONFIG_TARGET_ROOTFS_EXT4FS is not set/' .config 2>/dev/null || true
sed -i 's/CONFIG_TARGET_ROOTFS_SQUASHFS=y/# CONFIG_TARGET_ROOTFS_SQUASHFS is not set/' .config 2>/dev/null || true
sed -i 's/CONFIG_GRUB_EFI_IMAGES=y/# CONFIG_GRUB_EFI_IMAGES is not set/' .config 2>/dev/null || true
sed -i 's/CONFIG_TARGET_IMAGES_GZIP=y/# CONFIG_TARGET_IMAGES_GZIP is not set/' .config 2>/dev/null || true

# Ensure tar.gz is enabled
if ! grep -q "CONFIG_TARGET_ROOTFS_TARGZ=y" .config; then
    echo "CONFIG_TARGET_ROOTFS_TARGZ=y" >> .config
fi

echo "ImageBuilder configured to generate only rootfs.tar.gz"

# Install build dependencies
echo "Installing build dependencies..."
wait_for_apt_lock
sudo apt-get install -y build-essential clang flex bison g++ gawk \
    gcc-multilib g++-multilib gettext git libncurses5-dev libssl-dev \
    python3-setuptools rsync swig unzip zlib1g-dev file wget

# Build custom rootfs
echo "Building OpenWrt custom rootfs..."
if [ -n "$PACKAGES" ]; then
    echo "Building with custom packages: $PACKAGES"
    make image PROFILE=generic PACKAGES="$PACKAGES" ROOTFS_PARTSIZE=1024
else
    echo "Building with default packages"
    make image PROFILE=generic ROOTFS_PARTSIZE=1024
fi

# Find generated rootfs (tar.gz format for ULO-Builder)
ROOTFS_FILE=$(find bin/targets/armsr/armv8/ -name "*rootfs*.tar.gz" | head -1)
if [ -z "$ROOTFS_FILE" ]; then
    echo "Error: No rootfs.tar.gz file found!"
    echo "Available files:"
    find bin/targets/armsr/armv8/ -name "*rootfs*" -o -name "*.tar.gz"
    exit 1
fi

# Generate output filename
CUSTOM_ROOTFS_NAME="openwrt-${VERSION}-custom-armsr-armv8-generic-rootfs.tar.gz"

# Copy to the appropriate builder directory based on builder type
echo "Copying rootfs to appropriate builder directory..."

# Check which builder is being used (from GitHub Actions environment)
BUILDER_TYPE="${GITHUB_EVENT_INPUTS_BUILDER_TYPE:-ulo}"  # Default to ULO if not set
echo "Builder type: $BUILDER_TYPE"

if [ "$BUILDER_TYPE" = "ophub" ]; then
    echo "Copying rootfs for Ophub Builder..."
    # For Ophub, copy to root directory where Ophub script can find it
    cp "$ROOTFS_FILE" "../$CUSTOM_ROOTFS_NAME"
    echo "Copied to: ../$CUSTOM_ROOTFS_NAME"
else
    echo "Copying rootfs for ULO-Builder..."
    # For ULO, copy to ULO-Builder/rootfs as before
    mkdir -p ../ULO-Builder/rootfs
    cp "$ROOTFS_FILE" "../ULO-Builder/rootfs/$CUSTOM_ROOTFS_NAME"
    echo "Copied to: ULO-Builder/rootfs/$CUSTOM_ROOTFS_NAME"
fi

echo "=== OpenWrt ImageBuilder Complete ==="
echo "Generated: $CUSTOM_ROOTFS_NAME"
if [ "$BUILDER_TYPE" = "ophub" ]; then
    echo "Location: ../$CUSTOM_ROOTFS_NAME (for Ophub Builder)"
else
    echo "Location: ULO-Builder/rootfs/$CUSTOM_ROOTFS_NAME (for ULO-Builder)"
fi

# Export environment variable for GitHub Actions
echo "CUSTOM_ROOTFS_NAME=$CUSTOM_ROOTFS_NAME" >> $GITHUB_ENV
echo "ROOTFS_FILENAME=$CUSTOM_ROOTFS_NAME" >> $GITHUB_ENV