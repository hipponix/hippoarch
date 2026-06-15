#!/usr/bin/env bash

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=/dev/null
source "$REPO_ROOT/lib/partition.sh"

setup_loopback() {
    LOOP_IMG=$(mktemp /tmp/hippoarch-func-XXXXXX.img)
    truncate -s 2G "$LOOP_IMG"
    LOOP_DEV=$(losetup --find --show --partscan "$LOOP_IMG")
    export LOOP_DEV LOOP_IMG
}

teardown_loopback() {
    umount -R /mnt 2>/dev/null || true
    [[ -n "${LOOP_DEV:-}" ]] && losetup -d "$LOOP_DEV" 2>/dev/null || true
    [[ -n "${LOOP_IMG:-}" ]] && rm -f "$LOOP_IMG"
}
