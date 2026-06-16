#!/bin/bash

# HippoArch - Partitioning Library

# Resolve partition device nodes after sgdisk writes the table.
# On real block devices the kernel creates nodes automatically. Inside
# containers without udev those nodes never appear, so we fall back to
# offset-based sub-loop devices and symlink them to the expected paths.
# Sets globals: _PART1, _PART2, _PART_SUBS (space-separated sub-loop devs)
_resolve_parts() {
    local disk=$1
    local p1 p2
    if [[ $disk == *nvme* ]] || [[ $disk == *mmcblk* ]] || [[ $disk == *loop* ]]; then
        p1="${disk}p1"; p2="${disk}p2"
    else
        p1="${disk}1"; p2="${disk}2"
    fi

    # Try kernel partition nodes first (real hardware or udev-enabled containers).
    # Only accept native block device nodes — not symlinks we created in a prior run.
    blockdev --rereadpt "$disk" 2>/dev/null || true
    local i=0
    while [[ ((! -b "$p1" || -L "$p1") || (! -b "$p2" || -L "$p2")) && $i -lt 10 ]]; do
        sleep 0.5; ((i++)) || true
    done
    if [[ -b "$p1" && ! -L "$p1" ]]; then
        _PART1="$p1"; _PART2="$p2"; _PART_SUBS=""; return
    fi

    # No partition nodes appeared — create offset-based sub-loops.
    local img_file
    img_file=$(losetup -a 2>/dev/null \
        | awk -v d="${disk}:" '$1==d{gsub(/[()]/,"", $NF); print $NF}')
    if [[ -z "$img_file" ]]; then
        _PART1="$p1"; _PART2="$p2"; _PART_SUBS=""; return
    fi

    local s1 s2
    s1=$(sgdisk -i 1 "$disk" 2>/dev/null | awk '/First sector/{print $3}')
    s2=$(sgdisk -i 2 "$disk" 2>/dev/null | awk '/First sector/{print $3}')

    _PART1=$(losetup -f)
    losetup -o $((s1 * 512)) "$_PART1" "$img_file"
    _PART2=$(losetup -f)
    losetup -o $((s2 * 512)) "$_PART2" "$img_file"
    _PART_SUBS="$_PART1 $_PART2"

    # Symlink expected paths so blkid/findmnt callers still work
    ln -sf "$_PART1" "$p1" 2>/dev/null || true
    ln -sf "$_PART2" "$p2" 2>/dev/null || true
}

layout_simple() {
    local disk=$1
    echo "Using Simple GPT layout on $disk..."

    # 1. Partitioning
    # GPT type codes: ef00 = EFI System Partition, 8304 = Linux x86-64 root
    sgdisk -Z "$disk"
    sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "$disk"
    sgdisk -n 2:0:0     -t 2:8304 -c 2:"ROOT" "$disk"

    _resolve_parts "$disk"
    local p1="$_PART1" p2="$_PART2"

    echo "Formatting $p1 as FAT32 and $p2 as EXT4..."
    mkfs.fat -F 32 "$p1"
    mkfs.ext4 "$p2"

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

    _resolve_parts "$disk"
    local p1="$_PART1" p2="$_PART2"

    echo "Formatting $p1 as FAT32 and $p2 as Btrfs..."
    mkfs.fat -F 32 "$p1"
    mkfs.btrfs -f "$p2"

    echo "Creating Btrfs subvolumes..."
    mount "$p2" /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@snapshots
    btrfs subvolume create /mnt/@var_log
    btrfs subvolume create /mnt/@docker
    umount /mnt

    echo "Mounting subvolumes..."
    mount -o "$mount_opts,subvol=@" "$p2" /mnt
    mkdir -p /mnt/{home,.snapshots,var/log,var/lib/docker,boot}

    mount -o "$mount_opts,subvol=@home"     "$p2" /mnt/home
    mount -o "$mount_opts,subvol=@snapshots" "$p2" /mnt/.snapshots
    mount -o "$mount_opts,subvol=@var_log"  "$p2" /mnt/var/log
    mount -o "$mount_opts,subvol=@docker"   "$p2" /mnt/var/lib/docker
    mount "$p1" /mnt/boot
}
