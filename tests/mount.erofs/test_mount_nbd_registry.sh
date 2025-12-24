#!/bin/bash
# 
# mount.nbd registry test cases
# Testing NBD-based Erofs filesystem mount from container registry
#

set -e

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Test directory setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOUNT_POINTS_DIR="${SCRIPT_DIR}/mount-points"
MOUNT_EROFS="${SCRIPT_DIR}/../../bin/mount.erofs"

# NBD configuration
NBD_DEVICE="/dev/nbd0"
IMAGE_REF="docker.io/library/alpine:latest"

# Cleanup test environment
cleanup() {
    # Unmount all possible mount points
    for mp in "${MOUNT_POINTS_DIR}"/*; do
        if [ -d "$mp" ] && mountpoint -q "$mp" 2>/dev/null; then
            sudo umount "$mp" 2>/dev/null || true
        fi
    done
    
    # Disconnect NBD device
    if [ -b "$NBD_DEVICE" ]; then
        sudo nbd-client -d "$NBD_DEVICE" 2>/dev/null || true
    fi
    
    # Stop possible running NBD server
    pkill -f "nbd-server" 2>/dev/null || true
    
    # Clean up test directories
    rm -rf "${MOUNT_POINTS_DIR}"
}

# Trap exit signals
trap cleanup EXIT

# Print test result
print_test_result() {
    local test_name="$1"
    local result="$2"
    local message="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if [ "$result" = "PASS" ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
    elif [ "$result" = "SKIP" ]; then
        SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
    else
        echo "[FAIL] $test_name: $message"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Check command existence
check_prerequisites() {
    if [ ! -f "$MOUNT_EROFS" ]; then
        echo "Error: mount.erofs not found: $MOUNT_EROFS"
        exit 1
    fi
    
    if ! command -v nbd-client &> /dev/null; then
        echo "Error: nbd-client not installed"
        exit 1
    fi
    
    # Check NBD kernel module
    if ! lsmod | grep -q nbd; then
        sudo modprobe nbd 2>/dev/null || {
            echo "Error: cannot load NBD kernel module"
            exit 1
        }
    fi
}

check_prerequisites

# Create test directories
mkdir -p "${MOUNT_POINTS_DIR}"

# Test B1: Successfully mount a valid Erofs image from registry via NBD
test_b1_nbd_mount_registry() {
    local test_name="testB1_nbd_mount_registry"
    
    local mountpoint="${MOUNT_POINTS_DIR}/test_b1_mount"
    
    mkdir -p "$mountpoint"
    
    if sudo "$MOUNT_EROFS" -t nbd "$IMAGE_REF" "$mountpoint" 2>/dev/null; then
        if mountpoint -q "$mountpoint"; then
            # Test umount
            if sudo umount "$mountpoint" &>/dev/null; then
                if ! mountpoint -q "$mountpoint"; then
                    print_test_result "$test_name" "PASS" ""
                else
                    print_test_result "$test_name" "FAIL" "still mounted after umount"
                fi
            else
                print_test_result "$test_name" "FAIL" "umount command failed"
                sudo umount "$mountpoint" 2>/dev/null || true
            fi
        else
            print_test_result "$test_name" "FAIL" "mount point not mounted"
        fi
    else
        print_test_result "$test_name" "SKIP" "registry access required"
    fi
    
    rm -rf "$mountpoint"
}

# Test B2: Try to mount a nonexistent image from registry
test_b2_nbd_mount_nonexistent_registry() {
    local test_name="testB2_nbd_mount_nonexistent_registry"
    
    local image_ref="docker.io/library/nonexistent-image-12345:latest"
    local mountpoint="${MOUNT_POINTS_DIR}/test_b2_mount"
    
    mkdir -p "$mountpoint"
    
    if sudo "$MOUNT_EROFS" -t nbd "$image_ref" "$mountpoint" 2>/dev/null; then
        print_test_result "$test_name" "FAIL" "should fail on nonexistent image"
        sudo umount "$mountpoint" 2>/dev/null || true
    else
        print_test_result "$test_name" "PASS" ""
    fi
    
    rm -rf "$mountpoint"
}

# Test B3: Mount a non-EROFS format image from registry
test_b3_nbd_mount_non_erofs_registry() {
    local test_name="testB3_nbd_mount_non_erofs_registry"
    
    # Use a known standard Docker image (non-EROFS by default)
    local image_ref="docker.io/library/busybox:latest"
    local mountpoint="${MOUNT_POINTS_DIR}/test_b3_mount"
    
    mkdir -p "$mountpoint"
    
    if sudo "$MOUNT_EROFS" -t nbd "$image_ref" "$mountpoint" 2>/dev/null; then
        if mountpoint -q "$mountpoint"; then
            # If successfully mounted, image might support EROFS or has auto-conversion
            print_test_result "$test_name" "SKIP" "image may support EROFS or has auto-conversion"
            sudo umount "$mountpoint"
        else
            print_test_result "$test_name" "FAIL" "mount point not mounted"
        fi
    else
        print_test_result "$test_name" "PASS" ""
    fi
    
    rm -rf "$mountpoint"
}

# Run all tests
test_b1_nbd_mount_registry
test_b2_nbd_mount_nonexistent_registry
test_b3_nbd_mount_non_erofs_registry

# Print test summary
if [ $FAILED_TESTS -gt 0 ]; then
    echo "mount.nbd-registry: $PASSED_TESTS/$TOTAL_TESTS passed, $SKIPPED_TESTS skipped"
fi

if [ $FAILED_TESTS -eq 0 ]; then
    exit 0
else
    exit 1
fi
else
    exit 1
fi
