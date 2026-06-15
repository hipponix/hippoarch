#!/usr/bin/env bats
# Functional tests for layout_btrfs against a real 2 GB loopback device.
# Requires root (--privileged Docker or sudo locally).
# Tools needed: sgdisk, mkfs.fat, mkfs.btrfs, btrfs, losetup, findmnt, blkid

load 'helpers'

setup() {
    [ "$EUID" -eq 0 ] || skip "functional tests require root"
    setup_loopback
}

teardown() {
    teardown_loopback
}

@test "layout_btrfs: creates exactly 2 partitions" {
    layout_btrfs "$LOOP_DEV"
    local count
    count=$(sgdisk -p "$LOOP_DEV" | grep -cE '^ +[0-9]+')
    [ "$count" -eq 2 ]
}

@test "layout_btrfs: partition 1 is FAT32" {
    layout_btrfs "$LOOP_DEV"
    local fstype
    fstype=$(blkid -o value -s TYPE "${LOOP_DEV}p1")
    [ "$fstype" = "vfat" ]
}

@test "layout_btrfs: partition 2 is btrfs" {
    layout_btrfs "$LOOP_DEV"
    local fstype
    fstype=$(blkid -o value -s TYPE "${LOOP_DEV}p2")
    [ "$fstype" = "btrfs" ]
}

@test "layout_btrfs: subvolume @ exists" {
    layout_btrfs "$LOOP_DEV"
    btrfs subvolume list /mnt | grep -q ' path @$'
}

@test "layout_btrfs: subvolume @home exists" {
    layout_btrfs "$LOOP_DEV"
    btrfs subvolume list /mnt | grep -q ' path @home$'
}

@test "layout_btrfs: subvolume @snapshots exists" {
    layout_btrfs "$LOOP_DEV"
    btrfs subvolume list /mnt | grep -q ' path @snapshots$'
}

@test "layout_btrfs: subvolume @var_log exists" {
    layout_btrfs "$LOOP_DEV"
    btrfs subvolume list /mnt | grep -q ' path @var_log$'
}

@test "layout_btrfs: subvolume @docker exists" {
    layout_btrfs "$LOOP_DEV"
    btrfs subvolume list /mnt | grep -q ' path @docker$'
}

@test "layout_btrfs: root subvolume mounted at /mnt" {
    layout_btrfs "$LOOP_DEV"
    findmnt -n -o FSTYPE /mnt | grep -qx btrfs
}

@test "layout_btrfs: /mnt/home is mounted" {
    layout_btrfs "$LOOP_DEV"
    findmnt /mnt/home >/dev/null
}

@test "layout_btrfs: EFI partition mounted at /mnt/boot" {
    layout_btrfs "$LOOP_DEV"
    findmnt /mnt/boot >/dev/null
}
