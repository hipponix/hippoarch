#!/bin/bash
set -e

echo "Installing KDE Plasma..."
sudo pacman -S --needed --noconfirm --quiet plasma-meta sddm
if ! sudo systemctl enable sddm; then
    echo "Warning: sddm failed to enable"
    sudo journalctl -u sddm --no-pager -n 20 || true
fi
