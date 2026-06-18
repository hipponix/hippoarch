#!/usr/bin/env bats

load helpers

CONF_PATH="/etc/hippoarch.conf"

setup() {
    setup_test_env
    make_hippoarch_conf "$CONF_PATH"
}

teardown() {
    rm -f "$CONF_PATH"
    teardown_test_env
}

# --- Services loop ---

@test "SERVICES entry installs the package" {
    cd "$TEST_DIR"
    run bash provision.sh
    call_was_made "pacman.*openssh"
}

@test "SERVICES entry enables the service" {
    cd "$TEST_DIR"
    run bash provision.sh
    call_was_made "systemctl enable --now sshd"
}

@test "no SERVICES runs base configuration only" {
    sed -i 's/^SERVICES=.*/SERVICES=""/' "$CONF_PATH"
    cd "$TEST_DIR"
    run bash provision.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"base stub"* ]]
}

# --- Feature flags ---

@test "ENABLE_FANCONTROL=1 runs features/fancontrol.sh" {
    sed -i 's/^ENABLE_FANCONTROL=.*/ENABLE_FANCONTROL=1/' "$CONF_PATH"
    cd "$TEST_DIR"
    run bash provision.sh
    [[ "$output" == *"fancontrol stub"* ]]
}

@test "ENABLE_KDE=1 runs features/kde.sh" {
    sed -i 's/^ENABLE_KDE=.*/ENABLE_KDE=1/' "$CONF_PATH"
    cd "$TEST_DIR"
    run bash provision.sh
    [[ "$output" == *"kde stub"* ]]
}

@test "ENABLE_AIDE=1 runs features/aide.sh" {
    sed -i 's/^ENABLE_AIDE=.*/ENABLE_AIDE=1/' "$CONF_PATH"
    cd "$TEST_DIR"
    run bash provision.sh
    [[ "$output" == *"aide stub"* ]]
}

@test "CUSTOM_SCRIPT is executed when set" {
    local script="$TEST_DIR/custom.sh"
    printf '#!/bin/bash\necho "custom script ran"\n' > "$script"
    echo "CUSTOM_SCRIPT=$script" >> "$CONF_PATH"
    cd "$TEST_DIR"
    run bash provision.sh
    [[ "$output" == *"custom script ran"* ]]
}

# --- Timing and conf update ---

@test "PROVISION_TIME is written to /etc/hippoarch.conf" {
    (cd "$TEST_DIR" && bash provision.sh)
    local value
    value=$(grep "^PROVISION_TIME=" "$CONF_PATH" | cut -d= -f2 | tr -d '"')
    [[ -n "$value" ]]
}

@test "PROVISION_TIME format is Xm Ys" {
    (cd "$TEST_DIR" && bash provision.sh)
    local value
    value=$(grep "^PROVISION_TIME=" "$CONF_PATH" | cut -d= -f2 | tr -d '"')
    [[ "$value" =~ ^[0-9]+m\ [0-9]+s$ ]]
}
