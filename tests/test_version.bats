#!/usr/bin/env bats

load helpers

setup()    { setup_test_env; }
teardown() { teardown_test_env; }

@test "VERSION file exists" {
    [ -f "$REPO_ROOT/VERSION" ]
}

@test "VERSION contains a valid semver string" {
    local version
    version=$(cat "$REPO_ROOT/VERSION")
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "--version exits 0" {
    run bash "$TEST_DIR/bootstrap.sh" --version
    [ "$status" -eq 0 ]
}

@test "--version prints HippoArch" {
    run bash "$TEST_DIR/bootstrap.sh" --version
    [[ "$output" == *"HippoArch"* ]]
}

@test "--version output matches VERSION file" {
    local expected
    expected=$(cat "$REPO_ROOT/VERSION")
    run bash "$TEST_DIR/bootstrap.sh" --version
    [[ "$output" == *"$expected"* ]]
}
