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

# --- Role detection ---

@test "reads ROLE from /etc/hippoarch.conf" {
    # conf has ROLE=server-cwwk; provision.sh must log the server-cwwk role stub
    cd "$TEST_DIR"
    run bash provision.sh
    [[ "$output" == *"role server-cwwk stub"* ]]
}

@test "CLI arg overrides ROLE from conf" {
    cd "$TEST_DIR"
    run bash provision.sh workstation
    [[ "$output" == *"role workstation stub"* ]]
}

@test "invalid role exits 1" {
    cd "$TEST_DIR"
    run bash provision.sh nonexistent-role
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a valid role"* ]]
}

@test "no role applies base configuration only" {
    # Remove ROLE from conf and run without arg
    sed -i 's/^ROLE=.*/ROLE=""/' "$CONF_PATH"
    cd "$TEST_DIR"
    run bash provision.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"base stub"* ]]
    [[ "$output" == *"No role specified"* ]]
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

@test "chattr -i called before conf update" {
    (cd "$TEST_DIR" && bash provision.sh)
    call_was_made "chattr -i $CONF_PATH"
}

@test "chattr +i called after conf update" {
    (cd "$TEST_DIR" && bash provision.sh)
    call_was_made "chattr \+i $CONF_PATH"
}
