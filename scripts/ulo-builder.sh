#!/bin/bash

#================================================================================================
# ULO Builder Script
# Description: Build OpenWrt firmware using ULO-Builder repository
# Usage: ./ulo-builder.sh [TARGET_DEVICE] [KERNEL_VERSION] [ROOTFS_FILE] [PATCH_FILE] [FIRMWARE_SIZE]
# Example: ./ulo-builder.sh h618-orangepi-zero3 6.1.104-AW64-DBAI openwrt-rootfs.tar.gz patch.zip 1024
#================================================================================================

# Set script parameters
TARGET_DEVICE="${1}"
KERNEL_VERSION="${2}"
ROOTFS_FILE="${3}"
PATCH_FILE="${4}"
FIRMWARE_SIZE="${5:-1024}"

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
        echo "Usage: $0 [TARGET_DEVICE] [KERNEL_VERSION] [ROOTFS_FILE] [PATCH_FILE] [FIRMWARE_SIZE]"
        exit 1
    fi

    if [[ -z "${KERNEL_VERSION}" ]]; then
        log_error "Kernel version is required"
        echo "Usage: $0 [TARGET_DEVICE] [KERNEL_VERSION] [ROOTFS_FILE] [PATCH_FILE] [FIRMWARE_SIZE]"
        exit 1
    fi

    if [[ -z "${ROOTFS_FILE}" ]]; then
        log_error "RootFS file is required"
        echo "Usage: $0 [TARGET_DEVICE] [KERNEL_VERSION] [ROOTFS_FILE] [PATCH_FILE] [FIRMWARE_SIZE]"
        exit 1
    fi

    if [[ ! -f "${ROOTFS_FILE}" ]]; then
        log_error "RootFS file not found: ${ROOTFS_FILE}"
        echo "Available files in current directory:"
        ls -la *.tar.gz *.img.gz 2>/dev/null || echo "No rootfs files found"
        exit 1
    fi
}

# Setup ULO-Builder function
setup_ulo_builder() {
    log_info "Setting up ULO-Builder..."
    
    if [[ -d "ULO-Builder" ]]; then
        log_warning "ULO-Builder directory already exists, removing..."
        rm -rf ULO-Builder
    fi
    
    git clone https://github.com/bobbyunknown/ULO-Builder --branch dev --depth 1
    if [[ $? -ne 0 ]]; then
        log_error "Failed to clone ULO-Builder repository"
        exit 1
    fi
    log_success "ULO-Builder repository cloned successfully"
}

# Setup patch function
setup_patch() {
    if [[ -n "${PATCH_FILE}" && "${PATCH_FILE}" != "none" ]]; then
        log_info "Setting up patch: ${PATCH_FILE}"
        
        if [[ ! -f "${PATCH_FILE}" ]]; then
            log_warning "Patch file not found: ${PATCH_FILE}, continuing without patch"
            PATCH_FILE=""
            return
        fi
        
        # Clean up existing patches
        log_info "Cleaning up existing patches..."
        sudo rm -f ULO-Builder/patch/*
        
        # Copy the patch file
        cp "${PATCH_FILE}" ULO-Builder/patch/
        if [[ $? -eq 0 ]]; then
            log_success "Patch file copied successfully"
        else
            log_error "Failed to copy patch file"
            PATCH_FILE=""
        fi
    else
        log_info "No patch file specified, continuing without patch"
        PATCH_FILE=""
    fi
}

# Configure ULO-Builder function
configure_ulo_builder() {
    log_info "Configuring ULO-Builder..."
    
    cd ULO-Builder
    
    # Enable custom downloads
    log_info "Enabling custom downloads..."
    sudo sed -i 's/DOWNLOAD_CUSTOM_KERNEL=false/DOWNLOAD_CUSTOM_KERNEL=true/' ulo
    sudo sed -i 's/DOWNLOAD_CUSTOM_ROOTFS=false/DOWNLOAD_CUSTOM_ROOTFS=true/' ulo
    
    # Verify configuration
    log_info "Verifying configuration:"
    grep 'DOWNLOAD_CUSTOM' ulo
    
    cd ..
}

# Run ULO build function
run_ulo_build() {
    log_info "Starting ULO-Builder build process..."
    log_info "Target Device: ${TARGET_DEVICE}"
    log_info "Kernel Version: ${KERNEL_VERSION}"
    log_info "RootFS File: ${ROOTFS_FILE}"
    log_info "Patch File: ${PATCH_FILE:-None}"
    log_info "Firmware Size: ${FIRMWARE_SIZE}MB"
    
    cd ULO-Builder
    
    # Determine build command based on patch availability
    if [[ -n "${PATCH_FILE}" ]]; then
        log_info "Building with patch..."
        build_cmd="(echo \"y\"; echo \"2\") | sudo ./ulo -m \"${TARGET_DEVICE}\" -r \"${ROOTFS_FILE}\" -k \"${KERNEL_VERSION}\" -s ${FIRMWARE_SIZE}"
    else
        log_info "Building without patch..."
        build_cmd="(echo \"y\"; echo \"1\") | sudo ./ulo -m \"${TARGET_DEVICE}\" -r \"${ROOTFS_FILE}\" -k \"${KERNEL_VERSION}\" -s ${FIRMWARE_SIZE}"
    fi
    
    log_info "Running build command: ${build_cmd}"
    
    # Execute the build
    eval "${build_cmd}" | tee build_output.log
    build_result=${PIPESTATUS[0]}
    
    if [[ ${build_result} -eq 0 ]]; then
        log_success "=== ULO-Builder build completed successfully ==="
        
        # Check for output files
        if [[ -d "out" ]]; then
            log_info "Build output found, copying files..."
            
            # Create output directory
            mkdir -p ../ulo-output
            
            # Copy all output files
            cp -r out/* ../ulo-output/ 2>/dev/null
            
            # List output files
            log_info "Output files:"
            find ../ulo-output -name "*.img.gz" -o -name "*.img" | while read file; do
                log_success "Built: $(basename "$file")"
            done
            
            log_success "Output files copied to ../ulo-output/"
        else
            log_warning "No output directory found"
            log_info "Checking for alternative output locations..."
            find . -name "*.img.gz" -o -name "*.img" 2>/dev/null | while read file; do
                log_info "Found image: $file"
            done
        fi
    else
        log_error "=== ULO-Builder build failed with exit code ${build_result} ==="
        
        # Show build log tail for debugging
        log_info "Last 20 lines of build output:"
        tail -n 20 build_output.log
        
        exit 1
    fi
    
    cd ..
}

# Main function
main() {
    log_info "=== ULO Builder Setup ==="
    
    # Validate parameters
    validate_params
    
    # Setup ULO-Builder
    setup_ulo_builder
    
    # Configure ULO-Builder
    configure_ulo_builder
    
    # Setup patch if provided
    setup_patch
    
    # Run the build
    run_ulo_build
    
    log_success "ULO Builder script completed"
}

# Run main function
main "$@"