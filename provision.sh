#!/bin/bash

# HippoArch - Multi-purpose Arch Linux Setup
# Usage: ./provision.sh [role]

set -e

ROLE=$1
VALID_ROLES=("workstation" "k8s-controlplane" "k8s-node" "server")

usage() {
    echo "Usage: $0 [role]"
    echo "Available roles: ${VALID_ROLES[*]}"
    exit 1
}

# 1. Run common base configuration
echo "=== Starting Base Configuration ==="
bash common/base.sh

# 2. Run role-specific configuration
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

echo "=== Setup Finished ==="
