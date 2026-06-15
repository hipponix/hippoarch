#!/bin/bash

# HippoArch - Partitioning Library

layout_simple() {
    local disk=$1
    echo "Using Simple GPT layout on $disk..."

    # 1. Partitioning
    # GPT type codes: ef00 = EFI System Partition, 8304 = Linux x86-64 root
    sgdisk -Z "$disk"
    sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "$disk"
    sgdisk -n 2:0:0     -t 2:8304 -c 2:"ROOT" "$disk"

    # 2. Formatting
    # Handle different naming conventions (sda1 vs nvme0n1p1 vs loop0p1)
    local p1="${disk}1"
    local p2="${disk}2"
    if [[ $disk == *nvme* ]] || [[ $disk == *mmcblk* ]] || [[ $disk == *loop* ]]; then
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

layout_btrfs() {
    local disk=$1
    local mount_opts="noatime,compress=zstd,commit=120"
    echo "Using Btrfs layout on $disk..."

    # 1. Partitioning
    # GPT type codes: ef00 = EFI System Partition, 8304 = Linux x86-64 root
    sgdisk -Z "$disk"
    sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "$disk"
    sgdisk -n 2:0:0     -t 2:8304 -c 2:"ROOT" "$disk"

    # 2. Formatting
    local p1="${disk}1"
    local p2="${disk}2"
    if [[ $disk == *nvme* ]] || [[ $disk == *mmcblk* ]] || [[ $disk == *loop* ]]; then
        p1="${disk}p1"
        p2="${disk}p2"
    fi

    echo "Formatting $p1 as FAT32 and $p2 as Btrfs..."
    mkfs.fat -F 32 "$p1"
    mkfs.btrfs -f "$p2"

    # 3. Create Subvolumes
    echo "Creating Btrfs subvolumes..."
    mount "$p2" /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@snapshots
    btrfs subvolume create /mnt/@var_log
    btrfs subvolume create /mnt/@docker
    umount /mnt

    # 4. Mounting Subvolumes
    echo "Mounting subvolumes..."
    mount -o "$mount_opts,subvol=@" "$p2" /mnt
    mkdir -p /mnt/{home,.snapshots,var/log,var/lib/docker,boot}
    
    mount -o "$mount_opts,subvol=@home" "$p2" /mnt/home
    mount -o "$mount_opts,subvol=@snapshots" "$p2" /mnt/.snapshots
    mount -o "$mount_opts,subvol=@var_log" "$p2" /mnt/var/log
    mount -o "$mount_opts,subvol=@docker" "$p2" /mnt/var/lib/docker
    mount "$p1" /mnt/boot
}
