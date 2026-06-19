#!/bin/bash
set -e

# shellcheck source=/dev/null
source lib/aur.sh

if [[ "${ENABLE_AUR:-0}" != "1" ]]; then
    echo "Warning: aide is AUR-only — set ENABLE_AUR=1 in your profile to install it"
    exit 0
fi

echo "Initialising AIDE (running in background)..."
sudo pacman -S --needed --noconfirm base-devel git
if ! aur_install aide; then
    echo "Warning: aide failed to build — skipping AIDE setup (AUR package may be broken)"
    exit 0
fi
sudo systemd-run --unit=aide-init \
    bash -c 'aide --init && mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db'
sudo systemctl enable aide.timer
echo "AIDE init running in background — check: journalctl -u aide-init -f"
