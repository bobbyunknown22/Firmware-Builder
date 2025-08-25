#!/bin/bash

#================================================================================================
# Ophub Builder Script
# Description: Build OpenWrt firmware using Ophub amlogic-s9xxx-openwrt repository
# Usage: ./ophub-builder.sh [TARGET_DEVICE] [ROOTFS_FILE] [FIRMWARE_SIZE] [USER_NAME]
# Example: ./ophub-builder.sh s905x openwrt-rootfs.tar.gz 1024 "John Doe"
#================================================================================================

# Set script parameters
TARGET_DEVICE="${1}"
ROOTFS_FILE="${2}"
FIRMWARE_SIZE="${3:-1024}"
USER_NAME="${4:-Unknown User}"

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

# Download rootfs function
download_rootfs() {
    local rootfs_filename="${1}"
    
    # Check if file already exists locally (from custom build)
    if [[ -f "${rootfs_filename}" ]]; then
        log_info "RootFS file already exists locally: ${rootfs_filename}"
        return 0
    fi
    
    # Check if file exists in current directory or common locations
    local possible_locations=(
        "${rootfs_filename}"
        "./rootfs/${rootfs_filename}"
        "./ULO-Builder/rootfs/${rootfs_filename}"
        "../${rootfs_filename}"
    )
    
    for location in "${possible_locations[@]}"; do
        if [[ -f "${location}" ]]; then
            log_info "Found RootFS file at: ${location}"
            cp "${location}" "${rootfs_filename}"
            if [[ $? -eq 0 ]]; then
                log_success "RootFS file copied from ${location}"
                return 0
            fi
        fi
    done
    
    # If custom rootfs filename contains 'custom', it was built by ImageBuilder
    # and should be available locally - don't try to download
    if [[ "${rootfs_filename}" == *"custom"* ]]; then
        log_error "Custom RootFS file not found locally: ${rootfs_filename}"
        log_info "This appears to be a custom-built rootfs that should have been created by ImageBuilder."
        log_info "Please check if the ImageBuilder step completed successfully."
        return 1
    fi
    
    log_info "Downloading RootFS: ${rootfs_filename}"
    
    # Primary source: rootfs-openwrt releases (GitHub Releases API)
    log_info "Trying rootfs-openwrt releases (primary source)..."
    local releases_api="https://api.github.com/repos/armarchindo/rootfs-openwrt/releases"
    
    # Get all releases and find the download URL for our file
    log_info "Fetching releases from: ${releases_api}"
    local releases_json=$(curl -s "${releases_api}")
    
    if [[ $? -ne 0 ]] || [[ -z "${releases_json}" ]]; then
        log_warning "Failed to fetch releases from GitHub API"
    else
        # Parse JSON to find download URL for the specific file
        # First, find the asset entry that contains our filename
        local download_url=$(echo "${releases_json}" | \
            grep -A 60 "\"name\": \"${rootfs_filename}\"" | \
            grep "browser_download_url" | \
            head -n1 | \
            cut -d'"' -f4)
        
        if [[ -n "${download_url}" ]]; then
            log_info "Found file in releases: ${download_url}"
            log_info "Downloading from GitHub releases..."
            
            if curl -L -o "${rootfs_filename}" "${download_url}" --progress-bar; then
                if [[ -f "${rootfs_filename}" ]] && [[ -s "${rootfs_filename}" ]]; then
                    log_success "Downloaded from GitHub releases successfully"
                    return 0
                else
                    log_warning "Downloaded file is empty or corrupted"
                    rm -f "${rootfs_filename}"
                fi
            else
                log_warning "Download from GitHub releases failed"
            fi
        else
            log_info "File not found in any GitHub releases"
            # Debug: show what files are actually available
            log_info "Available files in releases:"
            echo "${releases_json}" | \
                grep '"name":' | \
                grep '\.tar\.gz' | \
                sed 's/.*"name": "\([^"]*\)".*/\1/' | \
                head -10
        fi
    fi
    
    # Secondary source: ULO-repository (fallback)
    log_info "Trying ULO-repository (fallback source)..."
    local ulo_repo_url="https://github.com/armarchindo/ULO-repository/raw/main/rootfs/${rootfs_filename}"
    log_info "Checking ULO-repository: ${ulo_repo_url}"
    
    if curl -s --head "${ulo_repo_url}" | head -n 1 | grep -q "200 OK"; then
        log_info "Found in ULO-repository, downloading..."
        if curl -L -o "${rootfs_filename}" "${ulo_repo_url}" --progress-bar; then
            if [[ -f "${rootfs_filename}" ]] && [[ -s "${rootfs_filename}" ]]; then
                log_success "Downloaded from ULO-repository successfully"
                return 0
            else
                log_warning "Downloaded file is empty or corrupted"
                rm -f "${rootfs_filename}"
            fi
        fi
        log_warning "Download from ULO-repository failed"
    else
        log_info "File not found in ULO-repository"
    fi
    
    # If all downloads failed, provide debugging information
    log_error "Failed to download RootFS: ${rootfs_filename}"
    log_info "All sources checked:"
    log_info "1. Primary: rootfs-openwrt releases API: ${releases_api}"
    log_info "2. Fallback: ULO-repository: ${ulo_repo_url}"
    
    # List available files for debugging
    log_info "Debugging: Listing available files..."
    
    # Check recent releases for available files
    log_info "Available files in recent releases:"
    if [[ -n "${releases_json}" ]]; then
        echo "${releases_json}" | \
            grep '"name":' | \
            grep '\.tar\.gz' | \
            sed 's/.*"name": "\([^"]*\)".*/\1/' | \
            head -10
    else
        log_warning "Could not fetch release information"
    fi
    
    # Check ULO-repository directory
    log_info "Available files in ULO-repository:"
    curl -s "https://api.github.com/repos/armarchindo/ULO-repository/contents/rootfs" 2>/dev/null | \
        grep '"name":' | \
        grep '\.tar\.gz' | \
        sed 's/.*"name": "\([^"]*\)".*/\1/' | \
        head -10 || log_warning "Could not list ULO-repository files"
    
    return 1
}

# Handle rootfs format conversion if needed
handle_rootfs_format() {
    local rootfs_file="${1}"
    
    if [[ ! -f "${rootfs_file}" ]]; then
        log_error "RootFS file not found: ${rootfs_file}"
        return 1
    fi
    
    # Check if file is .img.gz and Ophub might need .tar.gz
    if [[ "${rootfs_file}" == *.img.gz ]]; then
        log_info "RootFS is .img.gz format, checking if conversion is needed..."
        
        # For now, we'll use it as-is since Ophub can handle various formats
        # The key is to place it in the correct directory
        log_info "Using .img.gz file directly (Ophub can handle this format)"
    elif [[ "${rootfs_file}" == *.tar.gz ]]; then
        log_info "RootFS is .tar.gz format (preferred for Ophub)"
    else
        log_warning "Unknown rootfs format: ${rootfs_file}"
        log_info "Proceeding anyway, Ophub will validate the format"
    fi
    
    return 0
}
# Validation function
validate_params() {
    if [[ -z "${TARGET_DEVICE}" ]]; then
        log_error "Target device is required"
        echo "Usage: $0 [TARGET_DEVICE] [ROOTFS_FILE] [FIRMWARE_SIZE] [USER_NAME]"
        exit 1
    fi

    if [[ -z "${ROOTFS_FILE}" ]]; then
        log_error "RootFS file is required"
        echo "Usage: $0 [TARGET_DEVICE] [ROOTFS_FILE] [FIRMWARE_SIZE] [USER_NAME]"
        exit 1
    fi

    # Note: We don't check if file exists here since we'll download it if needed
    log_info "Parameters validated successfully"
    log_info "Built by: ${USER_NAME}"
}

# Main function
main() {
    log_info "=== Ophub Builder Setup ==="
    log_info "Target Device: ${TARGET_DEVICE}"
    log_info "RootFS File: ${ROOTFS_FILE}"
    log_info "Firmware Size: ${FIRMWARE_SIZE}MB"
    
    # Validate parameters
    validate_params
    
    # Download rootfs if needed
    log_info "Checking RootFS availability..."
    if ! download_rootfs "${ROOTFS_FILE}"; then
        log_error "Failed to obtain RootFS file"
        exit 1
    fi
    
    # Verify rootfs file exists and is valid
    if [[ ! -f "${ROOTFS_FILE}" ]]; then
        log_error "RootFS file still not found after download attempt: ${ROOTFS_FILE}"
        exit 1
    fi
    
    # Check file size to ensure it's not corrupted
    local file_size=$(stat -f%z "${ROOTFS_FILE}" 2>/dev/null || stat -c%s "${ROOTFS_FILE}" 2>/dev/null || echo "0")
    if [[ "${file_size}" -lt 1000000 ]]; then  # Less than 1MB is likely corrupted
        log_error "RootFS file appears to be corrupted (size: ${file_size} bytes)"
        log_info "Removing corrupted file and retrying..."
        rm -f "${ROOTFS_FILE}"
        if ! download_rootfs "${ROOTFS_FILE}"; then
            log_error "Failed to re-download RootFS file"
            exit 1
        fi
    fi
    
    log_success "RootFS file ready: ${ROOTFS_FILE} (size: ${file_size} bytes)"
    
    # Handle rootfs format if needed
    log_info "Validating RootFS format..."
    if ! handle_rootfs_format "${ROOTFS_FILE}"; then
        log_error "RootFS format validation failed"
        exit 1
    fi
    
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
            
            # Create sanitized user name for filename (replace spaces and special chars)
            SAFE_USER_NAME=$(echo "${USER_NAME}" | tr ' ' '_' | sed 's/[^a-zA-Z0-9_-]//g')
            
            # Copy and rename files to include user name
            find openwrt/out -name "*.img.gz" | while read file; do
                filename=$(basename "$file")
                # Insert user name before the file extension
                new_filename="${filename%.img.gz}_by_${SAFE_USER_NAME}.img.gz"
                cp "$file" "../ophub-output/$new_filename"
                log_success "Built: $new_filename"
            done
            
            # Also copy .img files if they exist
            find openwrt/out -name "*.img" | while read file; do
                filename=$(basename "$file")
                # Insert user name before the file extension
                new_filename="${filename%.img}_by_${SAFE_USER_NAME}.img"
                cp "$file" "../ophub-output/$new_filename" 2>/dev/null || true
                log_success "Built: $new_filename"
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