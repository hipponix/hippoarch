#!/usr/bin/env bash

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=/dev/null
source "$REPO_ROOT/lib/partition.sh"

setup_loopback() {
    LOOP_IMG=$(mktemp /tmp/hippoarch-func-XXXXXX)
    truncate -s 2G "$LOOP_IMG"
    LOOP_DEV=$(losetup --find --show --partscan "$LOOP_IMG")
    export LOOP_DEV LOOP_IMG
}

teardown_loopback() {
    umount -R /mnt 2>/dev/null || true
    # Detach any sub-loops backed by the same image (created by _resolve_parts)
    if [[ -n "${LOOP_IMG:-}" ]]; then
        losetup -a 2>/dev/null \
            | awk -v img="($LOOP_IMG)" '$0 ~ img {split($1,a,":"); print a[1]}' \
            | xargs -r losetup -d 2>/dev/null || true
    fi
    [[ -n "${LOOP_IMG:-}" ]] && rm -f "$LOOP_IMG"
}
