#!/usr/bin/env bats

load helpers

setup()    { setup_test_env; }
teardown() { teardown_test_env; }

# --- Flag: --detect ---

@test "--detect exits 0" {
    run bash "$TEST_DIR/bootstrap.sh" --detect
    [ "$status" -eq 0 ]
}

@test "--detect prints System section" {
    run bash "$TEST_DIR/bootstrap.sh" --detect
    [[ "$output" == *"System:"* ]]
}

@test "--detect prints Board section" {
    run bash "$TEST_DIR/bootstrap.sh" --detect
    [[ "$output" == *"Board:"* ]]
}

@test "--detect prints CPU section" {
    run bash "$TEST_DIR/bootstrap.sh" --detect
    [[ "$output" == *"CPU:"* ]]
}

@test "--detect prints Memory section" {
    run bash "$TEST_DIR/bootstrap.sh" --detect
    [[ "$output" == *"Memory:"* ]]
}

@test "--detect prints Sensors section" {
    run bash "$TEST_DIR/bootstrap.sh" --detect
    [[ "$output" == *"Sensors:"* ]]
}

@test "--detect prints Disks section" {
    run bash "$TEST_DIR/bootstrap.sh" --detect
    [[ "$output" == *"Disks:"* ]]
}

@test "--detect calls lsblk" {
    bash "$TEST_DIR/bootstrap.sh" --detect
    call_was_made "^lsblk"
}

# --- Flag: --list ---

@test "--list exits 0" {
    run bash "$TEST_DIR/bootstrap.sh" --list
    [ "$status" -eq 0 ]
}

@test "--list calls curl with GitHub API URL" {
    (cd "$TEST_DIR" && bash bootstrap.sh --list)
    call_was_made "contents/profiles"
}

@test "--list shows available profiles" {
    run bash "$TEST_DIR/bootstrap.sh" --list
    [[ "$output" == *"server-cwwk.conf"* ]]
}

# --- Flag: --fetch-all ---

@test "--fetch-all exits 0" {
    cd "$TEST_DIR"
    run bash bootstrap.sh --fetch-all
    [ "$status" -eq 0 ]
}

@test "--fetch-all downloads lib/partition.sh" {
    (cd "$TEST_DIR" && bash bootstrap.sh --fetch-all)
    [ -f "$TEST_DIR/lib/partition.sh" ]
}

@test "--fetch-all downloads profile files" {
    (cd "$TEST_DIR" && bash bootstrap.sh --fetch-all)
    [ -f "$TEST_DIR/profiles/server-cwwk.conf" ] || [ -f "$TEST_DIR/profiles/workstation.conf" ]
}

@test "--fetch-all does not start the installation" {
    (cd "$TEST_DIR" && bash bootstrap.sh --fetch-all)
    ! call_was_made "^pacstrap"
}

# --- Flag: --fetch <profile> ---

@test "--fetch exits 0 after download" {
    cd "$TEST_DIR"
    run bash bootstrap.sh --fetch profiles/server-cwwk.conf
    [ "$status" -eq 0 ]
}

@test "--fetch downloads the requested profile" {
    (cd "$TEST_DIR" && bash bootstrap.sh --fetch profiles/server-cwwk.conf)
    [ -f "$TEST_DIR/profiles/server-cwwk.conf" ]
}

@test "--fetch downloads lib/partition.sh" {
    rm -f "$TEST_DIR/lib/partition.sh"
    (cd "$TEST_DIR" && bash bootstrap.sh --fetch profiles/server-cwwk.conf)
    [ -f "$TEST_DIR/lib/partition.sh" ]
}

@test "--fetch does not run the installation" {
    (cd "$TEST_DIR" && bash bootstrap.sh --fetch profiles/server-cwwk.conf)
    ! call_was_made "^pacstrap"
}

# --- No args / missing profile ---

@test "no args exits 1" {
    cd "$TEST_DIR"
    run bash bootstrap.sh
    [ "$status" -eq 1 ]
}

@test "no args prints Usage" {
    cd "$TEST_DIR"
    run bash bootstrap.sh
    [[ "$output" == *"Usage:"* ]]
}

# --- Profile validation ---

@test "empty ROOT_PASSWORD exits 1" {
    cat > "$TEST_DIR/profiles/no-root-pass.conf" <<'EOF'
DISK="/tmp/hippoarch_not_a_block_device"
HOSTNAME="test" USERNAME="user"
ROOT_PASSWORD=""
USER_PASSWORD="pass"
TIMEZONE="UTC" LOCALE="en_US.UTF-8" LAYOUT="simple" ROLE="server"
EOF
    cd "$TEST_DIR"
    run bash bootstrap.sh profiles/no-root-pass.conf
    [ "$status" -eq 1 ]
    [[ "$output" == *"ROOT_PASSWORD"* ]]
}

@test "empty USER_PASSWORD exits 1" {
    cat > "$TEST_DIR/profiles/no-user-pass.conf" <<'EOF'
DISK="/tmp/hippoarch_not_a_block_device"
HOSTNAME="test" USERNAME="user"
ROOT_PASSWORD="pass"
USER_PASSWORD=""
TIMEZONE="UTC" LOCALE="en_US.UTF-8" LAYOUT="simple" ROLE="server"
EOF
    cd "$TEST_DIR"
    run bash bootstrap.sh profiles/no-user-pass.conf
    [ "$status" -eq 1 ]
    [[ "$output" == *"USER_PASSWORD"* ]]
}

# --- Disk validation ---

@test "non-block-device DISK exits 1" {
    make_valid_profile "$TEST_DIR/profiles/valid.conf"
    cd "$TEST_DIR"
    run bash bootstrap.sh profiles/valid.conf
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a block device"* ]]
}
