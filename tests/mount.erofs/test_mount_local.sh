#!/bin/bash

set -e

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test directory setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_IMAGES_DIR="${SCRIPT_DIR}/test-images"
MOUNT_POINTS_DIR="${SCRIPT_DIR}/mount-points"
MOUNT_EROFS="${SCRIPT_DIR}/../../bin/mount.erofs"

# Cleanup test environment
cleanup() {
    # Unmount all possible mount points
    for mp in "${MOUNT_POINTS_DIR}"/*; do
        if [ -d "$mp" ] && mountpoint -q "$mp" 2>/dev/null; then
            sudo umount "$mp" 2>/dev/null || true
        fi
    done
    # Clean up test directories
    rm -rf "${MOUNT_POINTS_DIR}"
    rm -rf "${TEST_IMAGES_DIR}"
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
    
    if ! command -v mkfs.erofs &> /dev/null; then
        export PATH="${SCRIPT_DIR}/../../bin:$PATH"
    fi
}

# Create valid test image
create_valid_image() {
    local image_path="$1"
    local temp_dir=$(mktemp -d)
    
    mkdir -p "$temp_dir/testdata"
    echo "This is a test file" > "$temp_dir/testdata/test.txt"
    echo "Another test file" > "$temp_dir/testdata/test2.txt"
    mkdir -p "$temp_dir/testdata/subdir"
    echo "File in subdirectory" > "$temp_dir/testdata/subdir/nested.txt"
    
    mkfs.erofs "$image_path" "$temp_dir" &>/dev/null
    rm -rf "$temp_dir"
}

# Create corrupted image
create_corrupted_image() {
    local image_path="$1"
    dd if=/dev/urandom of="$image_path" bs=1024 count=100 &>/dev/null
}

check_prerequisites

# Create test directories
mkdir -p "${TEST_IMAGES_DIR}"
mkdir -p "${MOUNT_POINTS_DIR}"

# Test 1: Successfully mount a valid Erofs image file
test_1_valid_mount() {
    local test_name="test1_valid_mount"
    
    local image="${TEST_IMAGES_DIR}/valid_test.erofs"
    local mountpoint="${MOUNT_POINTS_DIR}/test1_mount"
    
    mkdir -p "$mountpoint"
    create_valid_image "$image"
    
    # Try to mount
    if ! sudo "$MOUNT_EROFS" -t erofs.local "$image" "$mountpoint" &>/dev/null; then
        print_test_result "$test_name" "FAIL" "mount command failed"
        rm -f "$image"
        rm -rf "$mountpoint"
        return
    fi
    
    # Verify mount point
    if ! mountpoint -q "$mountpoint"; then
        print_test_result "$test_name" "FAIL" "mount point not mounted"
        rm -f "$image"
        rm -rf "$mountpoint"
        return
    fi
    
    # Verify file access
    if [ ! -f "$mountpoint/testdata/test.txt" ]; then
        print_test_result "$test_name" "FAIL" "mounted but cannot read files"
        sudo umount "$mountpoint" 2>/dev/null || true
        rm -f "$image"
        rm -rf "$mountpoint"
        return
    fi
    
    # Test umount
    if ! sudo umount "$mountpoint" &>/dev/null; then
        print_test_result "$test_name" "FAIL" "umount command failed"
        rm -f "$image"
        rm -rf "$mountpoint"
        return
    fi
    
    # Verify umount succeeded
    if mountpoint -q "$mountpoint"; then
        print_test_result "$test_name" "FAIL" "still mounted after umount"
        rm -f "$image"
        rm -rf "$mountpoint"
        return
    fi
    
    print_test_result "$test_name" "PASS" ""
    rm -f "$image"
    rm -rf "$mountpoint"
}

# Test 2: Try to mount a nonexistent Erofs image file
test_2_nonexistent_image() {
    local test_name="test2_nonexistent_image"
    
    local image="${TEST_IMAGES_DIR}/nonexistent.erofs"
    local mountpoint="${MOUNT_POINTS_DIR}/test2_mount"
    
    mkdir -p "$mountpoint"
    
    if sudo "$MOUNT_EROFS" -t erofs.local "$image" "$mountpoint" &>/dev/null; then
        print_test_result "$test_name" "FAIL" "should fail on nonexistent file"
        sudo umount "$mountpoint" 2>/dev/null || true
    else
        print_test_result "$test_name" "PASS" ""
    fi
    
    rm -rf "$mountpoint"
}

# Test 3: Try to mount a corrupted Erofs image file
test_3_corrupted_image() {
    local test_name="test3_corrupted_image"
    
    local image="${TEST_IMAGES_DIR}/corrupted.erofs"
    local mountpoint="${MOUNT_POINTS_DIR}/test3_mount"
    
    mkdir -p "$mountpoint"
    create_corrupted_image "$image"
    
    if sudo "$MOUNT_EROFS" -t erofs.local "$image" "$mountpoint" &>/dev/null; then
        print_test_result "$test_name" "FAIL" "should fail on corrupted file"
        sudo umount "$mountpoint" 2>/dev/null || true
    else
        print_test_result "$test_name" "PASS" ""
    fi
    
    rm -f "$image"
    rm -rf "$mountpoint"
}

# Run all tests
test_1_valid_mount
test_2_nonexistent_image
test_3_corrupted_image

if [ $FAILED_TESTS -eq 0 ]; then
    exit 0
else
    exit 1
fi
