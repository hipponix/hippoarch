#!/bin/bash

# HippoArch - Multi-purpose Arch Linux Setup
# Usage: ./provision.sh [role]

set -e

PROVISION_START=$(date +%s)

if [[ -f /etc/hippoarch.conf ]]; then
    # shellcheck source=/dev/null
    source /etc/hippoarch.conf
fi

ROLE=${1:-${ROLE:-}}
VALID_ROLES=("workstation" "server-cwwk" "server-k8s-master" "server-k8s-node" "qemu-test")

usage() {
    echo "Usage: $0 [role]"
    echo "Available roles: ${VALID_ROLES[*]}"
    exit 1
}

# 1. Run common base configuration
echo "=== Starting Base Configuration ==="
bash common/base.sh

# 2. Enable SSH if requested
if [[ "${ENABLE_SSHD:-0}" == "1" ]]; then
    echo "=== Enabling SSH ==="
    sudo pacman -S --needed --noconfirm --quiet openssh
    if ! sudo systemctl enable --now sshd; then
        echo "Warning: sshd failed to start"
        sudo journalctl -u sshd --no-pager -n 20 || true
    fi
fi

# 3. Run role-specific configuration
if [[ -n "$ROLE" ]]; then
    # shellcheck disable=SC2076
    if [[ " ${VALID_ROLES[*]} " =~ " ${ROLE} " ]]; then
        ROLE_SCRIPT="roles/$ROLE/install.sh"
        if [[ -f "$ROLE_SCRIPT" ]]; then
            echo "=== Starting Role: $ROLE ==="
            bash "$ROLE_SCRIPT"
        else
            echo "Role '$ROLE' found, but no install.sh script exists yet at $ROLE_SCRIPT"
        fi
    else
        echo "Error: '$ROLE' is not a valid role."
        usage
    fi
else
    echo "No role specified. Only base configuration applied."
    echo "To apply a role, run: $0 [role]"
    echo "Available roles: ${VALID_ROLES[*]}"
fi

# 4. AIDE — run after all packages/config are applied so the baseline is complete
if [[ "${ENABLE_AIDE:-0}" == "1" ]]; then
    echo "=== Initialising AIDE (running in background) ==="
    sudo pacman -S --needed --noconfirm --quiet aide
    sudo systemd-run --unit=aide-init \
        bash -c 'aide --init && mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db'
    sudo systemctl enable aide.timer
    echo "AIDE init running in background — check: journalctl -u aide-init -f"
fi

PROVISION_ELAPSED=$(( $(date +%s) - PROVISION_START ))
PROVISION_TIME="$((PROVISION_ELAPSED / 60))m $((PROVISION_ELAPSED % 60))s"

if [[ -f /etc/hippoarch.conf ]]; then
    sudo chattr -i /etc/hippoarch.conf
    sed -i "s|^PROVISION_TIME=.*|PROVISION_TIME=\"$PROVISION_TIME\"|" /etc/hippoarch.conf
    sudo chattr +i /etc/hippoarch.conf
fi

echo "=== Setup Finished (${PROVISION_TIME}) ==="
