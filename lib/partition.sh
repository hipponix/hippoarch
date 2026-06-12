#!/bin/bash

# HippoArch - Partitioning Library

layout_simple() {
    local disk=$1
    echo "Using Simple GPT layout on $disk..."

    # 1. Partitioning
    sgdisk -Z "$disk"
    sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "$disk"
    sgdisk -n 2:0:0     -t 2:8304 -c 2:"ROOT" "$disk"

    # 2. Formatting
    # Handle different naming conventions (sda1 vs nvme0n1p1)
    local p1="${disk}1"
    local p2="${disk}2"
    if [[ $disk == *nvme* ]] || [[ $disk == *mmcblk* ]]; then
        p1="${disk}p1"
        p2="${disk}p2"
    fi

    echo "Formatting $p1 as FAT32 and $p2 as EXT4..."
    mkfs.fat -F 32 "$p1"
    mkfs.ext4 "$p2"

    # 3. Mounting
    echo "Mounting file systems to /mnt..."
    mount "$p2" /mnt
    mkdir -p /mnt/boot
    mount "$p1" /mnt/boot
}
