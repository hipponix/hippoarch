#!/bin/bash

# HippoArch - Post-install provisioning
# Usage: ./provision.sh

set -e

PROVISION_START=$(date +%s)

if [[ -f /etc/hippoarch.conf ]]; then
    set -a
    # shellcheck source=/dev/null
    source /etc/hippoarch.conf
    set +a
fi

# 1. Base configuration
echo "=== Starting Base Configuration ==="
bash common/base.sh

# 2. Services
# Each entry is "package:service" — colon only when the package name differs from the service name.
# Example: "openssh:sshd fail2ban docker"
for _svc_entry in ${SERVICES:-}; do
    _pkg="${_svc_entry%%:*}"
    _svc="${_svc_entry##*:}"
    echo "=== Enabling ${_svc} ==="
    sudo pacman -S --needed --noconfirm --quiet "$_pkg"
    if ! sudo systemctl enable --now "$_svc"; then
        echo "Warning: $_svc failed to start"
        sudo journalctl -u "$_svc" --no-pager -n 20 || true
    fi
done
unset _svc_entry _pkg _svc

# 3. Features
[[ "${ENABLE_FANCONTROL:-0}" == "1" ]] && bash features/fancontrol.sh
[[ "${ENABLE_KDE:-0}"        == "1" ]] && bash features/kde.sh

# 4. AIDE — after all packages are in place so the baseline is complete
[[ "${ENABLE_AIDE:-0}"       == "1" ]] && bash features/aide.sh

# 5. Custom script
if [[ -n "${CUSTOM_SCRIPT:-}" ]]; then
    echo "=== Running custom script: $CUSTOM_SCRIPT ==="
    bash "$CUSTOM_SCRIPT"
fi

PROVISION_ELAPSED=$(( $(date +%s) - PROVISION_START ))
PROVISION_TIME="$((PROVISION_ELAPSED / 60))m $((PROVISION_ELAPSED % 60))s"

if [[ -f /etc/hippoarch.conf ]]; then
    sudo sed -i "s|^PROVISION_TIME=.*|PROVISION_TIME=\"$PROVISION_TIME\"|" /etc/hippoarch.conf
fi

echo "=== Setup Finished (${PROVISION_TIME}) ==="
