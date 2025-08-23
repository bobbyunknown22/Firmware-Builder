#!/bin/bash

#================================================================================================
# Ophub Builder Script
# Description: Build OpenWrt firmware using Ophub amlogic-s9xxx-openwrt repository
# Usage: ./ophub-builder.sh [TARGET_DEVICE] [ROOTFS_FILE] [FIRMWARE_SIZE]
# Example: ./ophub-builder.sh s905x openwrt-rootfs.tar.gz 1024
#================================================================================================

# Set script parameters
TARGET_DEVICE="${1}"
ROOTFS_FILE="${2}"
FIRMWARE_SIZE="${3:-1024}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validation function
validate_params() {
    if [[ -z "${TARGET_DEVICE}" ]]; then
        log_error "Target device is required"
        echo "Usage: $0 [TARGET_DEVICE] [ROOTFS_FILE] [FIRMWARE_SIZE]"
        exit 1
    fi

    if [[ -z "${ROOTFS_FILE}" ]]; then
        log_error "RootFS file is required"
        echo "Usage: $0 [TARGET_DEVICE] [ROOTFS_FILE] [FIRMWARE_SIZE]"
        exit 1
    fi

    if [[ ! -f "${ROOTFS_FILE}" ]]; then
        log_error "RootFS file not found: ${ROOTFS_FILE}"
        echo "Available files in current directory:"
        ls -la *.tar.gz 2>/dev/null || echo "No .tar.gz files found"
        exit 1
    fi
}

# Main function
main() {
    log_info "=== Ophub Builder Setup ==="
    log_info "Target Device: ${TARGET_DEVICE}"
    log_info "RootFS File: ${ROOTFS_FILE}"
    log_info "Firmware Size: ${FIRMWARE_SIZE}MB"
    
    # Validate parameters
    validate_params
    
    # Clone Ophub repository
    log_info "Cloning Ophub repository..."
    if [[ -d "ophub-builder" ]]; then
        log_warning "Ophub builder directory already exists, removing..."
        rm -rf ophub-builder
    fi
    
    git clone https://github.com/ophub/amlogic-s9xxx-openwrt --depth 1 ophub-builder
    if [[ $? -ne 0 ]]; then
        log_error "Failed to clone Ophub repository"
        exit 1
    fi
    log_success "Ophub repository cloned successfully"
    
    # Setup RootFS directory
    log_info "Setting up RootFS directory..."
    mkdir -p ophub-builder/openwrt-armsr
    
    # Copy RootFS file to Ophub directory
    log_info "Copying RootFS file to Ophub directory..."
    cp "${ROOTFS_FILE}" ophub-builder/openwrt-armsr/
    if [[ $? -eq 0 ]]; then
        log_success "RootFS file copied successfully"
    else
        log_error "Failed to copy RootFS file"
        exit 1
    fi
    
    # List files in openwrt-armsr directory for debugging
    log_info "Files in openwrt-armsr directory:"
    ls -la ophub-builder/openwrt-armsr/
    
    # Change to Ophub directory
    cd ophub-builder
    
    # Make remake script executable
    chmod +x remake
    if [[ ! -x "remake" ]]; then
        log_error "Failed to make remake script executable"
        exit 1
    fi
    
    # Execute Ophub build
    log_info "Starting Ophub build process..."
    log_info "Running command: sudo ./remake -b ${TARGET_DEVICE} -s ${FIRMWARE_SIZE}"
    
    # Run the build command
    sudo ./remake -b "${TARGET_DEVICE}" -s "${FIRMWARE_SIZE}"
    build_result=$?
    
    if [[ ${build_result} -eq 0 ]]; then
        log_success "=== Ophub build completed successfully ==="
        
        # Check for output files
        if [[ -d "openwrt/out" ]]; then
            log_info "Build output found, copying files..."
            
            # Create output directory
            mkdir -p ../ophub-output
            
            # Copy all output files
            cp -r openwrt/out/* ../ophub-output/ 2>/dev/null
            
            # List output files
            log_info "Output files:"
            find ../ophub-output -name "*.img.gz" -o -name "*.img" | while read file; do
                log_success "Built: $(basename "$file")"
            done
            
            log_success "Output files copied to ../ophub-output/"
        else
            log_warning "No output directory found at openwrt/out"
            log_info "Checking for alternative output locations..."
            find . -name "*.img.gz" -o -name "*.img" 2>/dev/null | while read file; do
                log_info "Found image: $file"
            done
        fi
    else
        log_error "=== Ophub build failed with exit code ${build_result} ==="
        
        # Show some debugging information
        log_info "Checking for common issues..."
        
        # Check if rootfs was found
        if [[ ! -f "openwrt-armsr/"*".tar.gz" ]]; then
            log_error "No rootfs file found in openwrt-armsr/"
            ls -la openwrt-armsr/
        fi
        
        # Check available space
        df -h .
        
        exit 1
    fi
    
    # Return to original directory
    cd ..
    
    log_success "Ophub Builder script completed"
}

# Run main function
main "$@"