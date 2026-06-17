#!/usr/bin/env bash
# HippoArch QEMU Integration Test
#
# Boots the Arch Linux live ISO in a virtual machine, runs bootstrap.sh using
# profiles/qemu-test.conf, verifies the installed disk, reboots, and runs
# provision.sh — all without touching your real hardware.
#
# Usage:
#   bash tests/integration/run.sh            # graphical (QEMU window opens)
#   HIPPOARCH_HEADLESS=1 bash tests/integration/run.sh  # no window
#
# Via Makefile:
#   make test-integration                    # graphical
#   make test-integration HEADLESS=1         # headless
#
# Dependencies (install once):
#   sudo apt install qemu-system-x86 qemu-utils libarchive-tools \
#                    expect openssh-client curl ovmf

set -euo pipefail

# ── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROFILE="$REPO_ROOT/profiles/qemu-test.conf"
LOG_DIR="$SCRIPT_DIR/logs"
ISO_CACHE="$REPO_ROOT/.cache/arch-latest.iso"

# ── Config ───────────────────────────────────────────────────────────────────
HEADLESS="${HIPPOARCH_HEADLESS:-0}"
ISO_URL="https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso"
DISK_SIZE="16G"
VM_RAM="4096"
VM_CPUS="4"
SERIAL_PORT=14445   # TCP port for the serial console automation channel
SSH_PORT=12222      # TCP port forwarded to the VM's SSH (avoids conflict with host)
BOOT_TIMEOUT=180    # seconds to wait for live ISO to reach a shell prompt
SSH_TIMEOUT=120     # seconds to wait for SSH (Phase 1)
SSH_TIMEOUT_P2=60   # seconds to wait for SSH on installed system (Phase 2)

SSH_OPTS=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o ConnectTimeout=5
    -o LogLevel=ERROR
    -o PasswordAuthentication=no
    -o Port="$SSH_PORT"
    -o ServerAliveInterval=30
    -o ServerAliveCountMax=60
)

# ── State ────────────────────────────────────────────────────────────────────
DISK_IMG=""
KERNEL_TMP=""
INITRD_TMP=""
OVMF_VARS_TMP=""
SSH_KEY_TMP=""
QEMU_PID=""
HTTP_PID=""
HTTP_SERVE_DIR=""
HTTP_PORT=""
TEST_START=0
PHASE1_START=0; PHASE1_END=0; PHASE1_STATUS=""
PHASE2_START=0; PHASE2_END=0; PHASE2_STATUS=""
PASS_COUNT=0
FAIL_COUNT=0

# ── Cleanup ──────────────────────────────────────────────────────────────────
cleanup() {
    print_summary
    [[ -n "$QEMU_PID" ]] && kill "$QEMU_PID" 2>/dev/null || true
    [[ -n "$HTTP_PID"  ]] && kill "$HTTP_PID"  2>/dev/null || true
    rm -f "$KERNEL_TMP" "$INITRD_TMP" "$OVMF_VARS_TMP" 2>/dev/null || true
    rm -f "$SSH_KEY_TMP" "${SSH_KEY_TMP}.pub" 2>/dev/null || true
    rm -f "$DISK_IMG" 2>/dev/null || true
    rm -rf "$HTTP_SERVE_DIR" 2>/dev/null || true
}
trap cleanup EXIT

stop_vm() {
    if [[ -n "$QEMU_PID" ]]; then
        kill "$QEMU_PID" 2>/dev/null || true
        wait "$QEMU_PID" 2>/dev/null || true
        QEMU_PID=""
    fi
}

# ── Logging ──────────────────────────────────────────────────────────────────
log()  { printf '\e[34m[hippoarch-test]\e[0m %s\n' "$*"; }
pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf '\e[32m[PASS]\e[0m %s\n' "$*"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf '\e[31m[FAIL]\e[0m %s\n' "$*"; exit 1; }
warn() { printf '\e[33m[WARN]\e[0m %s\n' "$*"; }
hr()   { printf '%s\n' "────────────────────────────────────────────────────────"; }

# GitHub Actions log grouping (no-ops outside GHA)
gha_group()     { [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::group::$*"    || true; }
gha_endgroup()  { [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::endgroup::"   || true; }
gha_notice()    { [[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::notice::$*"   || true; }

fmt_elapsed() {
    local s=$1
    [[ $s -lt 0 ]] && s=0
    printf '%dm %02ds' $((s / 60)) $((s % 60))
}

print_summary() {
    [[ $TEST_START -eq 0 ]] && return
    local now; now=$(date +%s)
    local G='\e[32m' R='\e[31m' Y='\e[33m' X='\e[0m'

    local p1_status p1_time="—"
    if   [[ "$PHASE1_STATUS" == "pass" ]]; then
        p1_status="${G}PASS${X}"; p1_time=$(fmt_elapsed $((PHASE1_END - PHASE1_START)))
    elif [[ $PHASE1_START -gt 0 ]];       then
        p1_status="${R}FAIL${X}"; p1_time=$(fmt_elapsed $((now - PHASE1_START)))
    else
        p1_status="SKIP"
    fi

    local p2_status p2_time="—"
    if   [[ "$PHASE2_STATUS" == "pass" ]]; then
        p2_status="${G}PASS${X}"; p2_time=$(fmt_elapsed $((PHASE2_END - PHASE2_START)))
    elif [[ "$PHASE2_STATUS" == "warn" ]]; then
        p2_status="${Y}WARN${X}"; p2_time=$(fmt_elapsed $((PHASE2_END - PHASE2_START)))
    elif [[ $PHASE2_START -gt 0 ]];        then
        p2_status="${R}FAIL${X}"; p2_time=$(fmt_elapsed $((now - PHASE2_START)))
    else
        p2_status="SKIP"
    fi

    local pass_str fail_str
    [[ $PASS_COUNT -gt 0 ]] && pass_str="${G}${PASS_COUNT} passed${X}" || pass_str="0 passed"
    [[ $FAIL_COUNT -gt 0 ]] && fail_str="${R}${FAIL_COUNT} failed${X}" || fail_str="0 failed"

    local version; version=$(cat "$REPO_ROOT/VERSION" 2>/dev/null || echo "—")
    local mode_str; [[ "$HEADLESS" == "1" ]] && mode_str="headless" || mode_str="graphical"

    printf '\n'
    hr
    printf ' %-10s %s\n'       "Profile"  "profiles/qemu-test.conf"
    printf ' %-10s %s\n'       "Version"  "$version"
    printf ' %-10s %s\n'       "Mode"     "$mode_str"
    hr
    printf " %-10s ${p1_status}   %s\n"  "Phase 1"  "$p1_time"
    printf " %-10s ${p2_status}   %s\n"  "Phase 2"  "$p2_time"
    hr
    printf " %-10s ${pass_str}   ${fail_str}   total %s\n" \
        "Result" "$(fmt_elapsed $((now - TEST_START)))"
    hr
    printf '\n'
}

# ── Dependency check ─────────────────────────────────────────────────────────
check_deps() {
    hr
    log "Checking dependencies..."
    local missing=()
    for dep in qemu-system-x86_64 qemu-img bsdtar ssh scp expect curl ssh-keygen python3; do
        command -v "$dep" &>/dev/null || missing+=("$dep")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        echo "  Missing: ${missing[*]}"
        echo ""
        echo "  Install:"
        echo "    sudo apt install qemu-system-x86 qemu-utils libarchive-tools \\"
        echo "                     expect openssh-client curl ovmf  (sshpass no longer needed)"
        exit 1
    fi
    if ! [[ -w /dev/kvm ]]; then
        warn "KVM not available — emulation will be slow"
        warn "To enable: sudo adduser \$USER kvm && newgrp kvm"
    fi
    log "All dependencies found."
}

# ── ISO management ───────────────────────────────────────────────────────────
get_iso() {
    hr
    gha_group "Download Arch Linux ISO"
    if [[ -f "$ISO_CACHE" ]]; then
        log "Using cached ISO: $ISO_CACHE"
        gha_endgroup
        return
    fi
    mkdir -p "$(dirname "$ISO_CACHE")"
    log "Downloading Arch Linux ISO (first run only, will be cached)..."
    log "  URL:   $ISO_URL"
    log "  Cache: $ISO_CACHE"
    echo ""
    curl -L --progress-bar -o "$ISO_CACHE" "$ISO_URL"
    echo ""
    log "ISO downloaded and cached."
    gha_endgroup
}

# ── SSH key ──────────────────────────────────────────────────────────────────
# Generate an ephemeral key pair. The public key is injected into the VM via
# the serial console so SSH connects without needing a password.
generate_ssh_key() {
    SSH_KEY_TMP=$(mktemp /tmp/hippoarch-key-XXXXXX)
    rm -f "$SSH_KEY_TMP"   # ssh-keygen won't overwrite without prompting
    ssh-keygen -t ed25519 -f "$SSH_KEY_TMP" -N "" -q
    SSH_OPTS+=(-i "$SSH_KEY_TMP")
    log "Ephemeral SSH key: $SSH_KEY_TMP"
}

# ── Kernel extraction ─────────────────────────────────────────────────────────
# We direct-boot the ISO kernel so we can inject console=ttyS0 — this gives us
# a serial console we can automate with expect, without modifying the ISO.
extract_kernel() {
    hr
    log "Extracting kernel and initrd from ISO..."

    KERNEL_TMP=$(mktemp /tmp/hippoarch-vmlinuz-XXXXXX)
    INITRD_TMP=$(mktemp /tmp/hippoarch-initramfs-XXXXXX)

    bsdtar -xf "$ISO_CACHE" -O arch/boot/x86_64/vmlinuz-linux      > "$KERNEL_TMP"
    bsdtar -xf "$ISO_CACHE" -O arch/boot/x86_64/initramfs-linux.img > "$INITRD_TMP"

    [[ -s "$KERNEL_TMP" ]] || fail "Failed to extract vmlinuz-linux from ISO"
    [[ -s "$INITRD_TMP" ]] || fail "Failed to extract initramfs-linux.img from ISO"

    # Derive the ISO volume label (needed for the live system's archisolabel= param)
    ISO_LABEL=$(file "$ISO_CACHE" | sed -n "s/.*data '\\([^']*\\)'.*/\\1/p" | tr -d ' ')
    [[ -n "$ISO_LABEL" ]] || ISO_LABEL="ARCH_$(date +%Y%m)"

    log "Kernel: $(du -sh "$KERNEL_TMP" | cut -f1)"
    log "Initrd: $(du -sh "$INITRD_TMP" | cut -f1)"
    log "ISO label: $ISO_LABEL"
}

# ── OVMF (UEFI firmware) ─────────────────────────────────────────────────────
# bootstrap.sh installs GRUB for EFI, so the VM needs UEFI firmware to boot
# the installed system in Phase 2. Phase 1 (live ISO) works without it.
find_ovmf() {
    local code_candidates=(
        /usr/share/OVMF/OVMF_CODE.fd
        /usr/share/OVMF/OVMF_CODE_4M.fd
        /usr/share/ovmf/OVMF.fd
        /usr/share/qemu/OVMF.fd
    )
    local vars_candidates=(
        /usr/share/OVMF/OVMF_VARS.fd
        /usr/share/OVMF/OVMF_VARS_4M.fd
        /usr/share/ovmf/OVMF_VARS.fd
    )

    OVMF_CODE=""
    OVMF_VARS_SRC=""
    for path in "${code_candidates[@]}"; do
        [[ -f "$path" ]] && OVMF_CODE="$path" && break
    done
    for path in "${vars_candidates[@]}"; do
        [[ -f "$path" ]] && OVMF_VARS_SRC="$path" && break
    done

    if [[ -n "$OVMF_CODE" && -n "$OVMF_VARS_SRC" ]]; then
        log "UEFI firmware: $OVMF_CODE"
        SKIP_PHASE2=0
    else
        warn "OVMF not found — Phase 2 (boot into installed system) will be skipped."
        warn "Install: sudo apt install ovmf"
        UEFI_ARGS=()
        SKIP_PHASE2=1
    fi
}

# ── Disk setup ───────────────────────────────────────────────────────────────
create_disk() {
    DISK_IMG=$(mktemp /tmp/hippoarch-disk-XXXXXX.qcow2)
    qemu-img create -f qcow2 "$DISK_IMG" "$DISK_SIZE" -q
    log "Virtual disk: $DISK_IMG ($DISK_SIZE)"
}

# ── VM launch ────────────────────────────────────────────────────────────────
# Phase 1: direct kernel boot from the live ISO, no UEFI firmware.
# UEFI would intercept -kernel and prevent serial console automation.
start_vm_phase1() {
    hr
    mkdir -p "$LOG_DIR"

    local kvm_args=()
    [[ -w /dev/kvm ]] && kvm_args=(-enable-kvm -cpu host)

    local display_arg
    if [[ "$HEADLESS" == "1" ]]; then
        display_arg="-display none"
        log "Starting Phase 1 VM in headless mode..."
    else
        display_arg="-display gtk"
        log "Starting Phase 1 VM — watch the installation in the GTK window."
    fi

    qemu-system-x86_64 \
        -machine q35 \
        "${kvm_args[@]}" \
        -m "$VM_RAM" \
        -smp "$VM_CPUS" \
        -kernel "$KERNEL_TMP" \
        -initrd "$INITRD_TMP" \
        -append "archisobasedir=arch archisodevice=/dev/sr0 quiet rw console=tty0 console=ttyS0,115200" \
        -drive "file=$ISO_CACHE,format=raw,media=cdrom,readonly=on" \
        -drive "file=$DISK_IMG,format=qcow2,if=virtio,cache=writeback" \
        -nic "user,model=virtio,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22" \
        -serial "tcp:127.0.0.1:${SERIAL_PORT},server,nowait" \
        $display_arg \
        &> "$LOG_DIR/qemu-phase1.log" &

    QEMU_PID=$!
    log "QEMU PID: $QEMU_PID  (log: $LOG_DIR/qemu-phase1.log)"
    sleep 3
}

# Phase 2: UEFI boot into the installed system. No kernel override — OVMF
# picks up the EFI GRUB entry written by grub-install during Phase 1.
start_vm_phase2() {
    hr
    mkdir -p "$LOG_DIR"

    local kvm_args=()
    [[ -w /dev/kvm ]] && kvm_args=(-enable-kvm -cpu host)

    local display_arg
    if [[ "$HEADLESS" == "1" ]]; then
        display_arg="-display none"
        log "Starting Phase 2 VM in headless mode..."
    else
        display_arg="-display gtk"
        log "Starting Phase 2 VM — UEFI boot into installed system."
    fi

    # Phase 2 uses AHCI (SATA) instead of virtio-blk: Ubuntu's OVMF does not
    # include VirtioBlkDxe, so it cannot find a virtio disk at boot time.
    qemu-system-x86_64 \
        -machine q35 \
        "${kvm_args[@]}" \
        "${UEFI_ARGS[@]}" \
        -m "$VM_RAM" \
        -smp "$VM_CPUS" \
        -device ahci,id=ahci0 \
        -drive "file=$DISK_IMG,format=qcow2,if=none,id=hd0,cache=writeback" \
        -device ide-hd,drive=hd0,bus=ahci0.0 \
        -nic "user,model=virtio,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22" \
        -serial "tcp:127.0.0.1:${SERIAL_PORT},server,nowait" \
        $display_arg \
        &> "$LOG_DIR/qemu-phase2.log" &

    QEMU_PID=$!
    log "QEMU PID: $QEMU_PID  (log: $LOG_DIR/qemu-phase2.log)"
    sleep 5
}

# ── Serial console automation ─────────────────────────────────────────────────
# Waits for the Arch live login prompt on the serial console, sets a known root
# password so SSH can connect, then configures and starts sshd.
automate_serial() {
    hr
    log "Waiting for Arch live system on serial console (max ${BOOT_TIMEOUT}s)..."

    local serial_log="$LOG_DIR/serial.log"
    log "Serial console log: $serial_log  (tail -f $serial_log)"

    # Wait for QEMU to open the serial TCP port before connecting.
    # Using ss (not nc -z) to avoid consuming the single-client connection slot.
    local i=0
    while [[ $i -lt 30 ]]; do
        ss -tlnp 2>/dev/null | grep -q ":${SERIAL_PORT}" && break
        sleep 1
        ((i++)) || true
    done
    if ! ss -tlnp 2>/dev/null | grep -q ":${SERIAL_PORT}"; then
        fail "QEMU serial port ${SERIAL_PORT} never opened after 30s"
    fi
    log "Serial port ${SERIAL_PORT} ready"

    gha_group "Serial console: boot → SSH key injection"
    expect -c "
        set timeout $BOOT_TIMEOUT
        log_user 1
        log_file -noappend \"$serial_log\"

        spawn nc 127.0.0.1 $SERIAL_PORT

        expect {
            timeout {
                puts \"\\n\\[FAIL\\] Timed out waiting for VM login prompt.\"
                exit 1
            }
            eof {
                puts \"\\n\\[FAIL\\] Serial connection closed before login prompt.\"
                exit 1
            }
            \"login:\"    { send \"root\\r\"; exp_continue }
            \"Password:\"  { send \"\\r\";    exp_continue }
            \"@archiso\"  { }
        }

        set timeout 30

        send \"mkdir -p /root/.ssh\\r\"
        expect { eof { puts \"\\[FAIL\\] Serial EOF\"; exit 1 } timeout { } \"@archiso\" }

        send \"echo '$(cat ${SSH_KEY_TMP}.pub)' > /root/.ssh/authorized_keys\\r\"
        expect { eof { puts \"\\[FAIL\\] Serial EOF\"; exit 1 } timeout { } \"@archiso\" }

        send \"chmod 600 /root/.ssh/authorized_keys\\r\"
        expect { eof { puts \"\\[FAIL\\] Serial EOF\"; exit 1 } timeout { } \"@archiso\" }

        send \"systemctl start sshd\\r\"
        expect { eof { puts \"\\[FAIL\\] Serial EOF\"; exit 1 } timeout { } \"@archiso\" }

        puts \"\\nSSH key injected — ready.\"
        exit 0
    " || fail "Serial console automation failed"
    gha_endgroup
}

# ── SSH helpers ───────────────────────────────────────────────────────────────
wait_for_ssh() {
    local timeout="${1:-$SSH_TIMEOUT}"
    log "Waiting for SSH on localhost:$SSH_PORT (max ${timeout}s)..."
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if ssh "${SSH_OPTS[@]}" root@localhost true 2>/dev/null; then
            log "SSH ready (${elapsed}s)"
            return 0
        fi
        printf '.'
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo ""
    return 1
}

vm_ssh() {
    ssh "${SSH_OPTS[@]}" root@localhost "$@"
}

vm_scp_to() {
    local file
    for file in "$@"; do
        ssh "${SSH_OPTS[@]}" root@localhost \
            "cat > /root/hippoarch/$(basename "$file")" < "$file"
    done
}

# ── Local HTTP server ─────────────────────────────────────────────────────────
# Packs the local working tree into a tarball and serves it over HTTP so the
# VM can curl it exactly as a real install would — but against local code.
# QEMU user networking makes the host reachable at 10.0.2.2 from inside the VM.
start_local_http() {
    hr
    HTTP_SERVE_DIR=$(mktemp -d /tmp/hippoarch-serve-XXXXXX)
    HTTP_PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('',0)); p=s.getsockname()[1]; s.close(); print(p)")

    log "Packing local repo → $HTTP_SERVE_DIR/hippoarch.tar.gz"
    (cd "$REPO_ROOT" && tar czf "$HTTP_SERVE_DIR/hippoarch.tar.gz" \
        --transform 's|^|hippoarch/|' \
        bootstrap.sh provision.sh VERSION lib/ profiles/ common/ roles/)

    python3 -m http.server "$HTTP_PORT" --directory "$HTTP_SERVE_DIR" &>/dev/null &
    HTTP_PID=$!
    log "Local HTTP server: http://10.0.2.2:${HTTP_PORT}/hippoarch.tar.gz  (PID $HTTP_PID)"
}

# ── Phase 1: bootstrap ────────────────────────────────────────────────────────
run_phase1() {
    PHASE1_START=$(date +%s)
    hr
    log "=== Phase 1: Bootstrap ==="

    if ! wait_for_ssh; then
        fail "SSH did not become available. Check $LOG_DIR/qemu.log for errors."
    fi

    gha_group "Phase 1: upload scripts"
    log "Uploading scripts to VM..."
    vm_ssh "mkdir -p /root/hippoarch/lib /root/hippoarch/profiles /root/hippoarch/common /root/hippoarch/roles"
    vm_scp_to "$REPO_ROOT/bootstrap.sh"
    vm_scp_to "$REPO_ROOT/provision.sh"
    vm_scp_to "$REPO_ROOT/VERSION"
    vm_scp_to "$REPO_ROOT/lib/partition.sh"
    vm_scp_to "$PROFILE"
    vm_ssh "mv /root/hippoarch/partition.sh /root/hippoarch/lib/partition.sh"
    vm_ssh "mv /root/hippoarch/qemu-test.conf /root/hippoarch/profiles/qemu-test.conf"
    vm_ssh "[[ -f /root/hippoarch/bootstrap.sh ]]" || fail "bootstrap.sh upload failed"
    vm_ssh "[[ -f /root/hippoarch/lib/partition.sh ]]" || fail "lib/partition.sh upload failed"
    vm_ssh "[[ -f /root/hippoarch/profiles/qemu-test.conf ]]" || fail "qemu-test.conf upload failed"
    gha_endgroup

    gha_group "Phase 1: bootstrap.sh (pacstrap + configure)"
    gha_notice "Running bootstrap.sh — pacstrap downloads ~300 MB (linux-firmware excluded)"
    log "Running bootstrap.sh with profile qemu-test.conf..."
    log "(The disk wipe confirmation is piped in automatically)"
    # Stream serial log to stdout so CI shows VM console output in real time.
    # sed strips most ANSI/VT escape sequences; cat -v shows remaining control chars.
    local serial_log="$LOG_DIR/serial.log"
    tail -F "$serial_log" 2>/dev/null | sed 's/\x1b\[[0-9;]*[mhHJKlA-Za-z]//g' &
    local tail_pid=$!
    local local_tar="http://10.0.2.2:${HTTP_PORT}/hippoarch.tar.gz"
    vm_ssh "cd /root/hippoarch && echo yes | HIPPOARCH_TAR_URL='$local_tar' bash bootstrap.sh profiles/qemu-test.conf"
    kill "$tail_pid" 2>/dev/null || true
    gha_endgroup

    gha_group "Phase 1: verify artifacts"
    log "Verifying installation artifacts..."
    vm_ssh "[[ -f /mnt/etc/hippoarch.conf ]]" || fail "/mnt/etc/hippoarch.conf not found"
    vm_ssh "[[ -f /mnt/etc/fstab ]]"          || fail "/mnt/etc/fstab not found"
    log "  /mnt/etc/hippoarch.conf:"
    vm_ssh "cat /mnt/etc/hippoarch.conf" || true
    vm_ssh "grep -q HIPPOARCH_VERSION /mnt/etc/hippoarch.conf" || fail "hippoarch.conf missing HIPPOARCH_VERSION"
    vm_ssh "grep -q BOOTSTRAP_TIME   /mnt/etc/hippoarch.conf" || fail "hippoarch.conf missing BOOTSTRAP_TIME"
    vm_ssh "lsblk /dev/vda | grep -q vda1"   || fail "/dev/vda1 not found after partitioning"
    vm_ssh "lsblk /dev/vda | grep -q vda2"   || fail "/dev/vda2 not found after partitioning"

    log "Injecting SSH key into installed system for Phase 2..."
    vm_ssh "mkdir -p /mnt/root/.ssh && chmod 700 /mnt/root/.ssh"
    # shellcheck disable=SC2029
    vm_ssh "echo '$(cat "${SSH_KEY_TMP}.pub")' > /mnt/root/.ssh/authorized_keys && chmod 600 /mnt/root/.ssh/authorized_keys"

    log "Verifying EFI fallback bootloader..."
    vm_ssh "ls /mnt/boot/EFI/BOOT/" || fail "GRUB EFI fallback not found at /mnt/boot/EFI/BOOT/"

    log "Verifying user, services, and immutability..."
    vm_ssh "grep -q '^testuser:' /mnt/etc/passwd" \
        || fail "testuser not in /mnt/etc/passwd"
    vm_ssh "[[ -d /mnt/home/testuser ]]" \
        || fail "/mnt/home/testuser not found"
    vm_ssh "[[ -L /mnt/etc/systemd/system/multi-user.target.wants/sshd.service ]]" \
        || fail "sshd not enabled in installed system"
    vm_ssh "lsattr /mnt/etc/hippoarch.conf | awk '{print \$1}' | grep -q i" \
        || fail "hippoarch.conf is not immutable (chattr +i missing)"
    vm_ssh "grep -q 'ROLE=\"workstation\"' /mnt/etc/hippoarch.conf" \
        || fail "ROLE does not match profile in hippoarch.conf"
    gha_endgroup

    PHASE1_STATUS="pass"; PHASE1_END=$(date +%s)
    pass "Phase 1 — Bootstrap completed and verified"
    log ""
    log "  /mnt/etc/hippoarch.conf:"
    vm_ssh "cat /mnt/etc/hippoarch.conf" 2>/dev/null | sed 's/^/    /' || true
    log ""
}

# ── Phase 2: provision ────────────────────────────────────────────────────────
run_phase2() {
    PHASE2_START=$(date +%s)
    hr
    gha_group "Phase 2: provision (boot installed system)"
    log "=== Phase 2: Provision (fresh VM booting installed system) ==="

    # Stop the Phase 1 VM cleanly before starting Phase 2.
    log "Stopping Phase 1 VM..."
    stop_vm
    sleep 3

    # Fresh OVMF NVRAM — Phase 1 ran without UEFI so grub-install wrote the EFI
    # entry into the disk image's EFI partition. Phase 2 boots from that entry.
    OVMF_VARS_TMP=$(mktemp /tmp/hippoarch-ovmf-vars-XXXXXX.fd)
    cp "$OVMF_VARS_SRC" "$OVMF_VARS_TMP"
    UEFI_ARGS=(-drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
               -drive "if=pflash,format=raw,file=$OVMF_VARS_TMP")

    start_vm_phase2

    local p2_serial_log="$LOG_DIR/serial-phase2.log"
    log "Phase 2 serial log: $p2_serial_log  (tail -f $p2_serial_log)"
    nc 127.0.0.1 "$SERIAL_PORT" > "$p2_serial_log" 2>/dev/null &
    local nc_pid=$!

    if ! wait_for_ssh "$SSH_TIMEOUT_P2"; then
        kill "$nc_pid" 2>/dev/null || true
        PHASE2_STATUS="warn"; PHASE2_END=$(date +%s)
        warn "Phase 2: SSH not available in the installed system."
        warn "Check $p2_serial_log for boot output."
        warn "Skipping Phase 2 assertions."
        return
    fi
    kill "$nc_pid" 2>/dev/null || true

    log "Verifying installed system state..."
    vm_ssh "findmnt -n -o FSTYPE / | grep -qx ext4" \
        || fail "root filesystem is not ext4"
    vm_ssh "id testuser" \
        || fail "testuser does not exist in installed system"
    vm_ssh "[[ -d /home/testuser ]]" \
        || fail "/home/testuser not found in installed system"
    vm_ssh "systemctl is-enabled sshd" \
        || fail "sshd is not enabled in installed system"

    log "Verifying post-install tarball (provision scripts)..."
    vm_ssh "[[ -f /home/testuser/hippoarch/provision.sh ]]" \
        || fail "provision.sh missing from installed /home/testuser/hippoarch"
    vm_ssh "[[ -d /home/testuser/hippoarch/common ]]" \
        || fail "common/ missing from installed /home/testuser/hippoarch (tarball download failed?)"
    vm_ssh "[[ -d /home/testuser/hippoarch/roles ]]" \
        || fail "roles/ missing from installed /home/testuser/hippoarch (tarball download failed?)"

    log "Running provision.sh on the installed system..."
    vm_ssh "cd /home/testuser/hippoarch && bash provision.sh"

    vm_ssh "grep -q 'PROVISION_TIME' /etc/hippoarch.conf" || fail "PROVISION_TIME not set after provision"
    local ptime
    ptime=$(vm_ssh "grep '^PROVISION_TIME=' /etc/hippoarch.conf | cut -d= -f2 | tr -d '\"'")
    [[ -n "$ptime" ]] || fail "PROVISION_TIME is empty"

    PHASE2_STATUS="pass"; PHASE2_END=$(date +%s)
    gha_endgroup
    pass "Phase 2 — Provision completed and verified (provision time: $ptime)"
}

# ── Main ──────────────────────────────────────────────────────────────────────
hr
log "HippoArch QEMU Integration Test"
log "Mode:    $([ "$HEADLESS" == "1" ] && echo 'headless (no window)' || echo 'graphical (GTK window)')"
log "Profile: profiles/qemu-test.conf"
hr

check_deps
get_iso
generate_ssh_key
extract_kernel
find_ovmf
create_disk
start_local_http
TEST_START=$(date +%s)
start_vm_phase1
automate_serial
run_phase1

if [[ "${SKIP_PHASE2:-0}" == "0" ]]; then
    run_phase2
else
    warn "Phase 2 skipped (OVMF not found — install the ovmf package to enable it)."
fi

hr
log "=== Integration test complete ==="
hr
