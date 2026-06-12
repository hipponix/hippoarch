#!/bin/bash

# Server specific configuration (Optimized for CWWK 8-bay motherboard)
set -e

echo "Applying Server role..."

# Fancontrol is specific to this motherboard setup
if [[ -f "common/hardware/fancontrol" ]]; then
    echo "Configuring fancontrol for CWWK hardware..."
    sudo cp common/hardware/fancontrol /etc/fancontrol
    sudo systemctl enable --now fancontrol
    sudo systemctl status fancontrol --no-pager
else
    echo "Warning: common/hardware/fancontrol not found."
fi

# Add more server specific packages here (Docker, Nginx, etc.)
# PACKAGES=("docker" "docker-compose")
# sudo pacman -S --needed --noconfirm "${PACKAGES[@]}"
