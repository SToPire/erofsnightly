#!/bin/bash
# 
# mount.nbd 本地文件测试用例
# 用于测试通过NBD协议挂载本地Erofs文件系统功能
#

set -e

# 测试计数器
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 测试目录设置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_IMAGES_DIR="${SCRIPT_DIR}/test-images"
MOUNT_POINTS_DIR="${SCRIPT_DIR}/mount-points"
MOUNT_EROFS="${SCRIPT_DIR}/../../bin/mount.erofs"

# NBD configuration
NBD_DEVICE="/dev/nbd0"

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
    rm -rf "${TEST_IMAGES_DIR}"
    rm -f /tmp/nbd-server-*.conf
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

# 创建有效的测试镜像
create_valid_image() {
  Create valid test image
create_valid_image() {
    local image_path="$1"
    local temp_dir=$(mktemp -d)
    
    mkdir -p "$temp_dir/testdata"
    echo "This is a test file for NBD" > "$temp_dir/testdata/test.txt"
    echo "Another test file" > "$temp_dir/testdata/test2.txt"
    mkdir -p "$temp_dir/testdata/subdir"
    echo "File in subdirectory" > "$temp_dir/testdata/subdir/nested.txt"
    
    mkfs.erofs "$image_path" "$temp_dir" &>/dev/null
    rm -rf "$temp_dir"
}

# Create non-EROFS format image
create_non_erofs_image() {
    local image_path="$1"
    dd if=/dev/zero of="$image_path" bs=1M count=10 &>/dev/null
    mkfs.ext4 -F "$image_path" &>/dev/null
}

check_prerequisites

# Create test directories
mkdir -p "${TEST_IMAGES_DIR}"
mkdir -p "${MOUNT_POINTS_DIR}"

# Check if should run testst_name="$1"
    if [ -z "$TEST_FILTER" ]; then
        return 0
    elif [[ "$test_name" == *"$TEST_FILTER"* ]]; then
        return 0
    else
        return 1
    fi
}

# Test A1: Successfully mount a valid local Erofs image file via NBD
test_a1_nbd_mount_local_file() {
    local test_name="testA1_nbd_mount_local_file"
    should_run_test "$test_name" || return 0
    
    local image="${TEST_IMAGES_DIR}/nbd_local_valid.erofs"
    local mountpoint="${MOUNT_POINTS_DIR}/test_a1_mount"
    
    mkdir -p "$mountpoint"
    create_valid_image "$image"
    
    if sudo "$MOUNT_EROFS" -t nbd "$image" "$mountpoint" &>/dev/null; then
        if mountpoint -q "$mountpoint"; then
            if [ -f "$mountpoint/testdata/test.txt" ]; then
                content=$(cat "$mountpoint/testdata/test.txt")
                if [[ "$content" == *"NBD"* ]]; then
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
                    print_test_result "$test_name" "FAIL" "file content incorrect"
                    sudo umount "$mountpoint" 2>/dev/null || true
                fi
            else
                print_test_result "$test_name" "FAIL" "mounted but cannot read files"
                sudo umount "$mountpoint" 2>/dev/null || true
            fi
        else
            print_test_result "$test_name" "FAIL" "mount point not mounted"
        fi
    else
        print_test_result "$test_name" "FAIL" "mount command failed"
    fi
    
    rm -f "$image"
    rm -rf "$mountpoint"
}

# Test A2: Try to mount a non-EROFS format local file via NBD
test_a2_nbd_mount_non_erofs_local() {
    local test_name="testA2_nbd_mount_non_erofs_local"
    
    local image="${TEST_IMAGES_DIR}/non_erofs.img"
    local mountpoint="${MOUNT_POINTS_DIR}/test_a2_mount"
    
    mkdir -p "$mountpoint"
    create_non_erofs_image "$image"
    
    if sudo "$MOUNT_EROFS" -t nbd "$image" "$mountpoint" &>/dev/null; then
        print_test_result "$test_name" "FAIL" "should fail on non-EROFS file"
        sudo umount "$mountpoint" 2>/dev/null || true
    else
        print_test_result "$test_name" "PASS" ""
    fi
    
    rm -f "$image"
    rm -rf "$mountpoint"
}

# Run all tests
test_a1_nbd_mount_local_file
test_a2_nbd_mount_non_erofs_local

# Print test summary
if [ $FAILED_TESTS -gt 0 ]; then
    echo "mount.nbd-local: $PASSED_TESTS/$TOTAL_TESTS passed"
fi

if [ $FAILED_TESTS -eq 0 ]; then
    exit 0
else
    exit 1
fi
