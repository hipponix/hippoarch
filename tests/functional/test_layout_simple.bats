#!/usr/bin/env bats
# Functional tests for layout_simple against a real 2 GB loopback device.
# Requires root (--privileged Docker or sudo locally).
# Tools needed: sgdisk, mkfs.fat, mkfs.ext4, losetup, findmnt, blkid

load 'helpers'

setup() {
    [ "$EUID" -eq 0 ] || skip "functional tests require root"
    setup_loopback
}

teardown() {
    teardown_loopback
}

@test "layout_simple: creates exactly 2 partitions" {
    layout_simple "$LOOP_DEV"
    local count
    count=$(sgdisk -p "$LOOP_DEV" | grep -cE '^ +[0-9]+')
    [ "$count" -eq 2 ]
}

@test "layout_simple: partition 1 has EFI type GUID" {
    layout_simple "$LOOP_DEV"
    sgdisk -p "$LOOP_DEV" | grep -qiE 'EF00|EFI System'
}

@test "layout_simple: partition 1 is FAT32" {
    layout_simple "$LOOP_DEV"
    local fstype
    fstype=$(blkid -o value -s TYPE "${LOOP_DEV}p1")
    [ "$fstype" = "vfat" ]
}

@test "layout_simple: partition 2 is ext4" {
    layout_simple "$LOOP_DEV"
    local fstype
    fstype=$(blkid -o value -s TYPE "${LOOP_DEV}p2")
    [ "$fstype" = "ext4" ]
}

@test "layout_simple: root partition mounted at /mnt" {
    layout_simple "$LOOP_DEV"
    findmnt /mnt >/dev/null
}

@test "layout_simple: EFI partition mounted at /mnt/boot" {
    layout_simple "$LOOP_DEV"
    findmnt /mnt/boot >/dev/null
}
