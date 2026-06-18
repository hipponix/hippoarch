#!/bin/bash
set -e

echo "Enabling fancontrol..."
sudo pacman -S --needed --noconfirm --quiet lm_sensors

modprobe_opts="ignore_resource_conflict=1"
[[ -n "${IT87_FORCE_ID:-}" ]] && modprobe_opts="$modprobe_opts force_id=$IT87_FORCE_ID"
echo "options it87 $modprobe_opts" | sudo tee /etc/modprobe.d/it87.conf > /dev/null
echo "it87" | sudo tee /etc/modules-load.d/it87.conf > /dev/null

if sudo modprobe it87 2>/dev/null && lsmod | grep -q it87; then
    sudo sensors-detect --auto 2>&1 | grep -E "^(Found|Loaded|error)" || true

    if ! sudo systemctl enable --now lm_sensors; then
        echo "Warning: lm_sensors failed to start"
        sudo journalctl -u lm_sensors --no-pager -n 20 || true
    fi

    if [[ -f "common/hardware/fancontrol" ]]; then
        sudo cp common/hardware/fancontrol /etc/fancontrol
        if ! sudo systemctl enable --now fancontrol; then
            echo "Warning: fancontrol failed to start"
            sudo journalctl -u fancontrol --no-pager -n 20 || true
        else
            sudo systemctl status fancontrol --no-pager
        fi
    else
        echo "Warning: common/hardware/fancontrol not found — skipping fancontrol"
    fi
else
    echo "Warning: it87 module not loaded — lm_sensors and fancontrol skipped"
fi
