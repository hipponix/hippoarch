#!/bin/bash

# Server specific configuration (Optimized for CWWK 8-bay motherboard)
set -e

echo "Applying Server role..."

# ITE IT8620 sensor chip on CWWK boards
sudo pacman -S --needed --noconfirm --quiet lm_sensors
echo "options it87 ignore_resource_conflict=1" | sudo tee /etc/modprobe.d/it87.conf > /dev/null
echo "it87" | sudo tee /etc/modules-load.d/it87.conf > /dev/null
sudo sensors-detect --auto 2>&1 | grep -E "^(Found|Loaded|error)" || true
sudo systemctl enable --now lm_sensors

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
