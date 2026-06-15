#!/usr/bin/env bats

load helpers

setup()    { setup_test_env; }
teardown() {
    # Clean up any directories created under /mnt by layout functions
    rm -rf /mnt/home /mnt/.snapshots /mnt/var /mnt/boot 2>/dev/null || true
    teardown_test_env
}

# --- layout_simple: partition naming ---

@test "layout_simple uses sata suffix for non-nvme disk" {
    # shellcheck source=/dev/null
    source "$TEST_DIR/lib/partition.sh"
    layout_simple "/tmp/hippoarch_sda"
    call_was_made "mkfs.fat.*hippoarch_sda1$"
    call_was_made "mkfs.ext4.*hippoarch_sda2$"
}

@test "layout_simple uses nvme 'p' suffix for nvme disk" {
    source "$TEST_DIR/lib/partition.sh"
    layout_simple "/dev/nvme0n1"
    call_was_made "mkfs.fat.*nvme0n1p1$"
    call_was_made "mkfs.ext4.*nvme0n1p2$"
}

@test "layout_simple uses 'p' suffix for mmcblk disk" {
    source "$TEST_DIR/lib/partition.sh"
    layout_simple "/dev/mmcblk0"
    call_was_made "mkfs.fat.*mmcblk0p1$"
    call_was_made "mkfs.ext4.*mmcblk0p2$"
}

@test "layout_simple calls sgdisk to partition the disk" {
    source "$TEST_DIR/lib/partition.sh"
    layout_simple "/tmp/hippoarch_sda"
    call_was_made "^sgdisk"
}

@test "layout_simple formats EFI partition as FAT32" {
    source "$TEST_DIR/lib/partition.sh"
    layout_simple "/tmp/hippoarch_sda"
    call_was_made "mkfs.fat -F 32"
}

# --- layout_btrfs: subvolumes ---

@test "layout_btrfs creates @ subvolume" {
    source "$TEST_DIR/lib/partition.sh"
    layout_btrfs "/tmp/hippoarch_btrfs"
    call_was_made "btrfs subvolume create /mnt/@$"
}

@test "layout_btrfs creates @home subvolume" {
    source "$TEST_DIR/lib/partition.sh"
    layout_btrfs "/tmp/hippoarch_btrfs"
    call_was_made "btrfs subvolume create /mnt/@home$"
}

@test "layout_btrfs creates @snapshots subvolume" {
    source "$TEST_DIR/lib/partition.sh"
    layout_btrfs "/tmp/hippoarch_btrfs"
    call_was_made "btrfs subvolume create /mnt/@snapshots$"
}

@test "layout_btrfs creates @var_log subvolume" {
    source "$TEST_DIR/lib/partition.sh"
    layout_btrfs "/tmp/hippoarch_btrfs"
    call_was_made "btrfs subvolume create /mnt/@var_log$"
}

@test "layout_btrfs creates @docker subvolume" {
    source "$TEST_DIR/lib/partition.sh"
    layout_btrfs "/tmp/hippoarch_btrfs"
    call_was_made "btrfs subvolume create /mnt/@docker$"
}

# --- layout_btrfs: mount options ---

@test "layout_btrfs mounts with noatime option" {
    source "$TEST_DIR/lib/partition.sh"
    layout_btrfs "/tmp/hippoarch_btrfs"
    call_was_made "mount.*noatime"
}

@test "layout_btrfs mounts with zstd compression" {
    source "$TEST_DIR/lib/partition.sh"
    layout_btrfs "/tmp/hippoarch_btrfs"
    call_was_made "mount.*compress=zstd"
}

@test "layout_btrfs mounts with commit interval" {
    source "$TEST_DIR/lib/partition.sh"
    layout_btrfs "/tmp/hippoarch_btrfs"
    call_was_made "mount.*commit=120"
}

@test "layout_btrfs uses nvme 'p' suffix" {
    source "$TEST_DIR/lib/partition.sh"
    layout_btrfs "/dev/nvme0n1"
    call_was_made "mkfs.btrfs.*nvme0n1p2$"
}

@test "layout_simple uses 'p' suffix for loop device" {
    source "$TEST_DIR/lib/partition.sh"
    layout_simple "/dev/loop0"
    call_was_made "mkfs.fat.*loop0p1$"
    call_was_made "mkfs.ext4.*loop0p2$"
}

@test "layout_btrfs uses 'p' suffix for loop device" {
    source "$TEST_DIR/lib/partition.sh"
    layout_btrfs "/dev/loop0"
    call_was_made "mkfs.btrfs.*loop0p2$"
}
