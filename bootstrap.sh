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
REPO_RAW_URL="https://raw.githubusercontent.com/hipponix/hippoarch/main"
REPO_TAR_URL="https://github.com/hipponix/hippoarch/tarball/main"

# Fetch partition library if missing
if [[ ! -f "lib/partition.sh" ]]; then
    echo "Fetching partition library from repo..."
    mkdir -p lib
    curl -sL -o lib/partition.sh "$REPO_RAW_URL/lib/partition.sh"
fi

# Fetch profile if missing locally
if [[ ! -f "$PROFILE" && "$PROFILE" != http* ]]; then
    echo "Profile '$PROFILE' not found locally, fetching from repo..."
    curl -sL --create-dirs -o "$PROFILE" "$REPO_RAW_URL/$PROFILE"
fi

# shellcheck source=/dev/null
source "$PROFILE"
# shellcheck source=/dev/null
source lib/partition.sh

if [[ -z "$ROOT_PASSWORD" || -z "$USER_PASSWORD" ]]; then
    echo "Error: ROOT_PASSWORD and USER_PASSWORD must be set in the profile."
    exit 1
fi

echo "=== Arch Linux Bootstrap: $HOSTNAME ==="

# 2. Disk Setup (Modular)
# shellcheck disable=SC2153
case $LAYOUT in
    simple)
        layout_simple "$DISK"
        ;;
    btrfs)
        layout_btrfs "$DISK"
        ;;
    *)
        echo "Error: Unknown layout '$LAYOUT'"
        exit 1
        ;;
esac

# 3. Base Installation
echo "Installing base system..."
BASE_PKGS=(base linux linux-firmware vim sudo curl)
[[ "$LAYOUT" == "btrfs" ]] && BASE_PKGS+=(btrfs-progs)

pacstrap /mnt "${BASE_PKGS[@]}"

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
echo "root:$ROOT_PASSWORD" | chpasswd

# Create User
useradd -m -G wheel "$USERNAME"
echo "$USERNAME:$USER_PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel

# Bootloader (GRUB)
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Download HippoArch for post-install
echo "Downloading HippoArch for post-install..."
cd /home/$USERNAME
mkdir hippoarch
curl -L "$REPO_TAR_URL" | tar -xz -C hippoarch --strip-components=1
chown -R $USERNAME:$USERNAME hippoarch
EOF

echo "=== Bootstrap Complete ==="
echo "Reboot, then login as $USERNAME and run: cd hippoarch && ./provision.sh [role]"
