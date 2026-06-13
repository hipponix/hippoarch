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
SSH_TIMEOUT=60      # seconds to wait for SSH after credentials are set

VM_ROOT_PASS="hippoarch-test-root"   # ephemeral test password — only used inside the VM

SSH_OPTS=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o ConnectTimeout=5
    -o LogLevel=ERROR
    -p "$SSH_PORT"
)

# ── State ────────────────────────────────────────────────────────────────────
DISK_IMG=""
KERNEL_TMP=""
INITRD_TMP=""
OVMF_VARS_TMP=""
QEMU_PID=""

# ── Cleanup ──────────────────────────────────────────────────────────────────
cleanup() {
    [[ -n "$QEMU_PID" ]] && kill "$QEMU_PID" 2>/dev/null || true
    rm -f "$DISK_IMG" "$KERNEL_TMP" "$INITRD_TMP" "$OVMF_VARS_TMP" 2>/dev/null || true
}
trap cleanup EXIT

# ── Logging ──────────────────────────────────────────────────────────────────
log()  { printf '\e[34m[hippoarch-test]\e[0m %s\n' "$*"; }
pass() { printf '\e[32m[PASS]\e[0m %s\n' "$*"; }
fail() { printf '\e[31m[FAIL]\e[0m %s\n' "$*"; exit 1; }
warn() { printf '\e[33m[WARN]\e[0m %s\n' "$*"; }
hr()   { printf '%s\n' "────────────────────────────────────────────────────────"; }

# ── Dependency check ─────────────────────────────────────────────────────────
check_deps() {
    hr
    log "Checking dependencies..."
    local missing=()
    for dep in qemu-system-x86_64 qemu-img bsdtar ssh scp expect curl; do
        command -v "$dep" &>/dev/null || missing+=("$dep")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        echo "  Missing: ${missing[*]}"
        echo ""
        echo "  Install:"
        echo "    sudo apt install qemu-system-x86 qemu-utils libarchive-tools \\"
        echo "                     expect openssh-client curl ovmf"
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
    if [[ -f "$ISO_CACHE" ]]; then
        log "Using cached ISO: $ISO_CACHE"
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
        OVMF_VARS_TMP=$(mktemp /tmp/hippoarch-ovmf-vars-XXXXXX.fd)
        cp "$OVMF_VARS_SRC" "$OVMF_VARS_TMP"
        log "UEFI firmware: $OVMF_CODE"
        UEFI_ARGS=(-drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
                   -drive "if=pflash,format=raw,file=$OVMF_VARS_TMP")
        SKIP_PHASE2=0
    else
        warn "OVMF not found — Phase 2 (reboot into installed system) will be skipped."
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
start_vm() {
    hr
    mkdir -p "$LOG_DIR"

    local kvm_args=()
    [[ -w /dev/kvm ]] && kvm_args=(-enable-kvm -cpu host)

    local display_arg
    if [[ "$HEADLESS" == "1" ]]; then
        display_arg="-display none"
        log "Starting VM in headless mode..."
    else
        display_arg="-display gtk"
        log "Starting VM — watch the installation in the GTK window."
        log "  You can interact with the VM directly in that window."
    fi

    # Serial console exposed on a TCP port so expect can automate it.
    # In GUI mode the user also sees the graphical VGA output in the GTK window.
    # Kernel param console=ttyS0 mirrors all console output to the serial port.
    qemu-system-x86_64 \
        "${kvm_args[@]}" \
        "${UEFI_ARGS[@]}" \
        -m "$VM_RAM" \
        -smp "$VM_CPUS" \
        -kernel "$KERNEL_TMP" \
        -initrd "$INITRD_TMP" \
        -append "archisobasedir=arch archisolabel=$ISO_LABEL copytoram=n quiet rw console=ttyS0,115200" \
        -drive "file=$ISO_CACHE,format=raw,media=cdrom,readonly=on" \
        -drive "file=$DISK_IMG,format=qcow2,if=virtio,cache=writeback" \
        -boot once=d \
        -nic "user,model=virtio,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22" \
        -serial "tcp:127.0.0.1:${SERIAL_PORT},server,nowait" \
        $display_arg \
        &> "$LOG_DIR/qemu.log" &

    QEMU_PID=$!
    log "QEMU PID: $QEMU_PID  (log: $LOG_DIR/qemu.log)"

    # Give QEMU a moment to open the TCP serial port before expect connects
    sleep 3
}

# ── Serial console automation ─────────────────────────────────────────────────
# Waits for the Arch live login prompt on the serial console, sets a known root
# password so SSH can connect, then configures and starts sshd.
automate_serial() {
    hr
    log "Waiting for Arch live system on serial console (max ${BOOT_TIMEOUT}s)..."

    expect -c "
        set timeout $BOOT_TIMEOUT
        log_user 1

        spawn nc 127.0.0.1 $SERIAL_PORT

        expect {
            timeout {
                puts \"\\n[FAIL] Timed out waiting for VM login prompt.\"
                exit 1
            }
            \"login:\" {
                send \"root\\r\"
                exp_continue
            }
            \"root@archiso\" { }
        }

        # Set a known root password so SSH can connect
        send \"echo 'root:$VM_ROOT_PASS' | chpasswd\\r\"
        expect \"root@archiso\"

        # Configure sshd for password auth and start it
        send \"grep -q PermitRootLogin /etc/ssh/sshd_config || echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config\\r\"
        expect \"root@archiso\"
        send \"sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config\\r\"
        expect \"root@archiso\"
        send \"sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config\\r\"
        expect \"root@archiso\"
        send \"systemctl restart sshd\\r\"
        expect \"root@archiso\"

        puts \"\\nSSH configured on the live ISO — ready.\"
        exit 0
    " || fail "Serial console automation failed"
}

# ── SSH helpers ───────────────────────────────────────────────────────────────
wait_for_ssh() {
    log "Waiting for SSH on localhost:$SSH_PORT (max ${SSH_TIMEOUT}s)..."
    local elapsed=0
    while [[ $elapsed -lt $SSH_TIMEOUT ]]; do
        if sshpass -p "$VM_ROOT_PASS" ssh "${SSH_OPTS[@]}" root@localhost true 2>/dev/null; then
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
    sshpass -p "$VM_ROOT_PASS" ssh "${SSH_OPTS[@]}" root@localhost "$@"
}

vm_scp_to() {
    sshpass -p "$VM_ROOT_PASS" scp "${SSH_OPTS[@]}" "$@" root@localhost:/root/hippoarch/
}

# ── Phase 1: bootstrap ────────────────────────────────────────────────────────
run_phase1() {
    hr
    log "=== Phase 1: Bootstrap ==="

    if ! wait_for_ssh; then
        fail "SSH did not become available. Check $LOG_DIR/qemu.log for errors."
    fi

    log "Uploading scripts to VM..."
    vm_ssh "mkdir -p /root/hippoarch/lib /root/hippoarch/profiles /root/hippoarch/common /root/hippoarch/roles"
    vm_scp_to "$REPO_ROOT/bootstrap.sh"
    vm_scp_to "$REPO_ROOT/provision.sh"
    vm_scp_to "$REPO_ROOT/VERSION"
    vm_scp_to "$REPO_ROOT/lib/partition.sh"
    vm_scp_to "$PROFILE"

    log "Running bootstrap.sh with profile qemu-test.conf..."
    log "(The disk wipe confirmation is piped in automatically)"
    vm_ssh "cd /root/hippoarch && echo yes | bash bootstrap.sh profiles/qemu-test.conf"

    log "Verifying installation artifacts..."
    vm_ssh "[[ -f /mnt/etc/hippoarch.conf ]]" || fail "/mnt/etc/hippoarch.conf not found"
    vm_ssh "[[ -f /mnt/etc/fstab ]]"          || fail "/mnt/etc/fstab not found"
    vm_ssh "grep -q HIPPOARCH_VERSION /mnt/etc/hippoarch.conf" || fail "hippoarch.conf missing HIPPOARCH_VERSION"
    vm_ssh "grep -q BOOTSTRAP_TIME   /mnt/etc/hippoarch.conf" || fail "hippoarch.conf missing BOOTSTRAP_TIME"
    vm_ssh "lsblk /dev/vda | grep -q vda1"   || fail "/dev/vda1 not found after partitioning"
    vm_ssh "lsblk /dev/vda | grep -q vda2"   || fail "/dev/vda2 not found after partitioning"

    pass "Phase 1 — Bootstrap completed and verified"
    log ""
    log "  /mnt/etc/hippoarch.conf:"
    vm_ssh "cat /mnt/etc/hippoarch.conf" | sed 's/^/    /'
    log ""
}

# ── Phase 2: provision ────────────────────────────────────────────────────────
run_phase2() {
    hr
    log "=== Phase 2: Provision (after reboot) ==="

    log "Rebooting VM into the installed system..."
    vm_ssh "reboot" || true
    sleep 10

    # After reboot, QEMU uses -boot once=d which already set the disk as the
    # one-time boot target for the first boot. Subsequent boots default to disk.
    # The VM now boots the freshly installed Arch, which has sshd enabled.

    VM_ROOT_PASS="$(grep ROOT_PASSWORD "$PROFILE" | cut -d= -f2 | tr -d '"')"

    if ! wait_for_ssh; then
        warn "Phase 2: SSH not available in the installed system."
        warn "This is expected if openssh was not included in the profile's EXTRA_PACKAGES."
        warn "Skipping Phase 2 assertions."
        return
    fi

    log "Running provision.sh on the installed system..."
    vm_ssh "cd /home/testuser/hippoarch && bash provision.sh"

    vm_ssh "grep -q 'PROVISION_TIME' /etc/hippoarch.conf" || fail "PROVISION_TIME not set after provision"
    local ptime
    ptime=$(vm_ssh "grep '^PROVISION_TIME=' /etc/hippoarch.conf | cut -d= -f2 | tr -d '\"'")
    [[ -n "$ptime" ]] || fail "PROVISION_TIME is empty"

    pass "Phase 2 — Provision completed and verified (time: $ptime)"
}

# ── Main ──────────────────────────────────────────────────────────────────────
hr
log "HippoArch QEMU Integration Test"
log "Mode:    $([ "$HEADLESS" == "1" ] && echo 'headless (no window)' || echo 'graphical (GTK window)')"
log "Profile: profiles/qemu-test.conf"
hr

check_deps
get_iso
extract_kernel
find_ovmf
create_disk
start_vm
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
