#!/bin/bash

# HippoArch - Bootstrap Script (Live ISO)
set -e

PROFILE=$1

if [[ -z "$PROFILE" || ! -f "$PROFILE" ]]; then
    echo "Usage: $0 <profile_path>"
    echo "Example: $0 profiles/server-cwwk.conf"
    exit 1
fi

# 1. Load Profile and Libraries
source "$PROFILE"
source lib/partition.sh

echo "=== Arch Linux Bootstrap: $HOSTNAME ==="

# 2. Disk Setup (Modular)
case $LAYOUT in
    simple)
        layout_simple "$DISK"
        ;;
    *)
        echo "Error: Unknown layout '$LAYOUT'"
        exit 1
        ;;
esac

# 3. Base Installation
echo "Installing base system..."
pacstrap /mnt base linux linux-firmware git vim sudo

# 4. Generate FSTAB
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# 5. Chroot Configuration
echo "Configuring system via chroot..."
arch-chroot /mnt /bin/bash <<EOF
# Timezone and Clock
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Localization
echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

# Network
echo "$HOSTNAME" > /etc/hostname

# Root password
echo "root:password" | chpasswd

# Create User
useradd -m -G wheel "$USERNAME"
echo "$USERNAME:password" | chpasswd
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel

# Bootloader (GRUB)
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Clone HippoArch for post-install
cd /home/$USERNAME
git clone https://github.com/hipponix/hippoarch.git
chown -R $USERNAME:$USERNAME hippoarch
EOF

echo "=== Bootstrap Complete ==="
echo "Reboot, then login as $USERNAME and run: cd hippoarch && ./provision.sh [role]"
