#!/usr/bin/env bash

setup_test_env() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_DIR="$(mktemp -d)"
    CALL_LOG="$TEST_DIR/calls.log"
    touch "$CALL_LOG"

    export REPO_ROOT TEST_DIR CALL_LOG
    export PATH="$BATS_TEST_DIRNAME/mocks:$PATH"

    cp "$REPO_ROOT/bootstrap.sh" "$TEST_DIR/"
    cp "$REPO_ROOT/provision.sh" "$TEST_DIR/"
    cp "$REPO_ROOT/VERSION"      "$TEST_DIR/"

    mkdir -p "$TEST_DIR/lib" "$TEST_DIR/profiles" "$TEST_DIR/common/dotfiles"
    cp "$REPO_ROOT/lib/partition.sh" "$TEST_DIR/lib/"

    # Stub common/base.sh so it doesn't need real packages
    printf '#!/bin/bash\necho "=== base stub ==="\n' > "$TEST_DIR/common/base.sh"

    # Stub all valid roles
    local role
    for role in server workstation k8s-controlplane k8s-node; do
        mkdir -p "$TEST_DIR/roles/$role"
        printf '#!/bin/bash\necho "=== role %s stub ==="\n' "$role" \
            > "$TEST_DIR/roles/$role/install.sh"
    done
}

teardown_test_env() {
    rm -rf "$TEST_DIR"
}

# Profile with all required fields and a clearly fake disk path
make_valid_profile() {
    local path="$1"
    cat > "$path" <<'EOF'
DISK="/tmp/hippoarch_not_a_block_device"
HOSTNAME="test-host"
USERNAME="testuser"
ROOT_PASSWORD="securepassword1"
USER_PASSWORD="securepassword2"
TIMEZONE="UTC"
LOCALE="en_US.UTF-8"
LAYOUT="simple"
ROLE="server"
EOF
}

make_hippoarch_conf() {
    local path="$1"
    cat > "$path" <<'EOF'
# HippoArch Installation Record — do not edit manually
HIPPOARCH_VERSION="0.1.0"
INSTALL_TIMESTAMP="2026-06-13T10:00:00+00:00"
ARCH_ISO_VERSION="2026.06.01"
PROFILE="profiles/server-cwwk.conf"
ROLE="server"
BOOTSTRAP_TIME="5m 30s"
PROVISION_TIME=""
EOF
}

call_was_made() {
    grep -qE "$1" "$CALL_LOG"
}
