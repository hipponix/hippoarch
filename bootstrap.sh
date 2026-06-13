#!/bin/bash

# HippoArch - Bootstrap Script (Live ISO)
set -e

HIPPOARCH_VERSION=$(cat "$(dirname "$0")/VERSION" 2>/dev/null || echo "dev")
REPO_RAW_URL="https://raw.githubusercontent.com/hipponix/hippoarch/main"
REPO_TAR_URL="https://github.com/hipponix/hippoarch/tarball/main"
REPO_API_URL="https://api.github.com/repos/hipponix/hippoarch/contents"

detect_hardware() {
    echo "=== Hardware Detection ==="
    lscpu | grep -E "^(Model name|CPU\(s\)|Thread|Core)"
    lsblk -d -o NAME,SIZE,MODEL | grep -v "^loop"
    free -h | grep Mem
}

list_profiles() {
    echo "=== Available Profiles ==="
    curl -s "$REPO_API_URL/profiles" \
        | grep '"name"' \
        | sed 's/.*"name": "\(.*\)".*/\1/' \
        | grep '\.conf$'
}

fetch_all() {
    echo "=== Fetching All Profiles ==="
    local profiles
    profiles=$(curl -s "$REPO_API_URL/profiles" \
        | grep '"name"' \
        | sed 's/.*"name": "\(.*\)".*/\1/' \
        | grep '\.conf$')
    mkdir -p profiles
    while IFS= read -r name; do
        echo "Fetching $name..."
        curl -sL -o "profiles/$name" "$REPO_RAW_URL/profiles/$name"
    done <<< "$profiles"
    echo "Done. Profiles saved to profiles/"
}

case "${1:-}" in
    --version)
        echo "HippoArch $HIPPOARCH_VERSION"
        exit 0
        ;;
    --detect)
        detect_hardware
        exit 0
        ;;
    --list)
        list_profiles
        exit 0
        ;;
    --fetch-all)
        fetch_all
        exit 0
        ;;
    --fetch)
        [[ -z "${2:-}" ]] && { echo "Usage: $0 --fetch <profile_name>"; exit 1; }
        mkdir -p profiles
        curl -sL -o "profiles/$2" "$REPO_RAW_URL/profiles/$2"
        echo "Fetched to profiles/$2"
        exit 0
        ;;
esac

PROFILE=${1:-}
FETCH_ONLY=${FETCH_ONLY:-0}

if [[ -z "$PROFILE" ]]; then
    echo "Usage: $0 <profile_path>"
    echo "       $0 --version"
    echo "       $0 --detect"
    echo "       $0 --list"
    echo "       $0 --fetch-all"
    echo "       $0 --fetch <profile_name>"
    echo "Example: $0 profiles/server-cwwk.conf"
    exit 1
fi

# 1. Load Profile and Libraries

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

if [[ "$FETCH_ONLY" == "1" ]]; then
    echo "Fetched: $PROFILE"
    exit 0
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
