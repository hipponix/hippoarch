#!/bin/bash

# HippoArch - Bootstrap Script (Live ISO)
set -e

HIPPOARCH_VERSION=$(cat "$(dirname "$0")/VERSION" 2>/dev/null || echo "dev")
REPO_RAW_URL="${HIPPOARCH_RAW_URL:-https://raw.githubusercontent.com/hipponix/hippoarch/v0.1.0}"
REPO_TAR_URL="${HIPPOARCH_TAR_URL:-https://github.com/hipponix/hippoarch/tarball/v0.1.0}"
REPO_API_URL="https://api.github.com/repos/hipponix/hippoarch/contents"

detect_hardware() {
    echo "=== Hardware Detection ==="
    echo ""
    echo "System:"
    cat /sys/class/dmi/id/product_name 2>/dev/null || echo "  (unknown)"
    echo ""
    echo "Board:"
    cat /sys/class/dmi/id/board_name 2>/dev/null || echo "  (unknown)"
    echo ""
    echo "CPU:"
    lscpu 2>/dev/null | grep -E "^(Model name|CPU\(s\)|Thread|Core)" || echo "  (unavailable)"
    echo ""
    echo "Memory:"
    free -h 2>/dev/null | grep Mem || echo "  (unavailable)"
    echo ""
    echo "Sensors:"
    sensors 2>/dev/null | head -20 || echo "  (unavailable)"
    echo ""
    echo "Disks:"
    lsblk -d -o NAME,SIZE,MODEL 2>/dev/null | grep -v "^loop" || echo "  (unavailable)"
}

list_profiles() {
    echo "=== Available Profiles ==="
    curl -s "$REPO_API_URL/profiles" \
        | grep '"name"' \
        | sed 's/.*"name": "\([^"]*\)".*/\1/' \
        | grep '\.conf$'
}

fetch_all() {
    echo "=== Fetching All Profiles ==="
    local profiles
    profiles=$(curl -s "$REPO_API_URL/profiles" \
        | grep '"name"' \
        | sed 's/.*"name": "\([^"]*\)".*/\1/' \
        | grep '\.conf$')
    mkdir -p profiles lib
    curl -sL -o lib/partition.sh "$REPO_RAW_URL/lib/partition.sh"
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
        _fetch_name="${2#profiles/}"
        mkdir -p profiles lib
        curl -sL -o "profiles/$_fetch_name" "$REPO_RAW_URL/profiles/$_fetch_name"
        curl -sL -o lib/partition.sh "$REPO_RAW_URL/lib/partition.sh"
        echo "Fetched to profiles/$_fetch_name"
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
ROLE="${ROLE:-$(basename "$PROFILE" .conf)}"
# shellcheck source=/dev/null
source lib/partition.sh

if [[ -z "$ROOT_PASSWORD" || -z "$USER_PASSWORD" ]]; then
    echo "Error: ROOT_PASSWORD and USER_PASSWORD must be set in the profile."
    exit 1
fi

# Validate disk is a block device before any destructive action
# shellcheck disable=SC2153
if [[ ! -b "$DISK" ]]; then
    echo "Error: '$DISK' is not a block device."
    exit 1
fi

echo "Target disk:"
lsblk -d "$DISK"
echo ""
read -rp "WARNING: All data on $DISK will be erased. Type 'yes' to continue: " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Aborted."
    exit 1
fi

BOOTSTRAP_START=$(date +%s)

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
# shellcheck disable=SC2206
[[ -n "${EXTRA_PACKAGES:-}" ]] && BASE_PKGS+=($EXTRA_PACKAGES)
for _pkg in ${BASE_PKGS_REMOVE:-}; do
    _filtered=()
    for _p in "${BASE_PKGS[@]}"; do
        [[ "$_p" != "$_pkg" ]] && _filtered+=("$_p")
    done
    BASE_PKGS=("${_filtered[@]}")
done
unset _pkg _filtered _p

ENABLE_SSHD=0
[[ " ${BASE_PKGS[*]} " =~ " openssh " ]] && ENABLE_SSHD=1

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

# Optional services
[[ "$ENABLE_SSHD" == "1" ]] && systemctl enable sshd

# Network (systemd-networkd with DHCP for all wired adapters)
mkdir -p /etc/systemd/network
cat > /etc/systemd/network/20-wired.network <<NETEOF
[Match]
Type=ether

[Network]
DHCP=yes
NETEOF
systemctl enable systemd-networkd
systemctl enable systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# Don't block boot waiting for DHCP — sshd doesn't need network-online
systemctl disable systemd-networkd-wait-online 2>/dev/null || true

# Bootloader (GRUB)
pacman -S --noconfirm grub efibootmgr
# Add serial console and reduce menu timeout (grub creates /etc/default/grub on install)
sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="console=tty0 console=ttyS0,115200"|' /etc/default/grub
sed -i 's|^GRUB_TIMEOUT=.*|GRUB_TIMEOUT=2|' /etc/default/grub
# --removable skips EFI variable writes (needed inside a non-UEFI chroot)
# and creates the module tree; grub.cfg goes to /boot/grub/grub.cfg
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable
grub-mkconfig -o /boot/grub/grub.cfg
# The BOOTX64.EFI from --removable stores a prefix that OVMF cannot resolve
# when the disk interface changes (virtio→AHCI). Replace it with a standalone
# image that has grub.cfg embedded — no prefix search required at boot time.
grub-mkstandalone \
    --format=x86_64-efi \
    --output=/boot/EFI/BOOT/BOOTX64.EFI \
    "boot/grub/grub.cfg=/boot/grub/grub.cfg"

# Download HippoArch for post-install
echo "Downloading HippoArch for post-install..."
cd /home/$USERNAME
mkdir hippoarch
curl -L "$REPO_TAR_URL" | tar -xz -C hippoarch --strip-components=1
chown -R $USERNAME:$USERNAME hippoarch
EOF

BOOTSTRAP_ELAPSED=$(( $(date +%s) - BOOTSTRAP_START ))
BOOTSTRAP_TIME="$((BOOTSTRAP_ELAPSED / 60))m $((BOOTSTRAP_ELAPSED % 60))s"

# Write install record and lock it
cat > /mnt/etc/hippoarch.conf <<HICONF
ROLE="${ROLE:-}"
ENABLE_SSHD="${ENABLE_SSHD:-0}"
ENABLE_AIDE="${ENABLE_AIDE:-0}"
HIPPOARCH_VERSION="${HIPPOARCH_VERSION}"
BOOTSTRAP_TIME="${BOOTSTRAP_TIME}"
PROVISION_TIME=""
HICONF
chattr +i /mnt/etc/hippoarch.conf

echo "=== Bootstrap Complete (${BOOTSTRAP_TIME}) ==="
echo ""
read -rp "Remove the USB stick, then press y to reboot or n to exit: " choice || true
if [[ "$choice" == "y" ]]; then
    reboot
else
    echo "Reboot when ready. Login as $USERNAME and run: cd hippoarch && ./provision.sh"
fi
