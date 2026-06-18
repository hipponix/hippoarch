#!/bin/bash
set -e

echo "Initialising AIDE (running in background)..."
sudo pacman -S --needed --noconfirm --quiet aide
sudo systemd-run --unit=aide-init \
    bash -c 'aide --init && mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db'
sudo systemctl enable aide.timer
echo "AIDE init running in background — check: journalctl -u aide-init -f"
