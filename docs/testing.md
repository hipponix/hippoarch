# Testing

HippoArch uses three independent test layers and a separate VM lifecycle. Each layer has its own `make` target and can run without the others, with the exception of `make test-integration` which requires a prior `make build`.

## Quick reference

| Target | Needs image | Time | What it validates |
|---|---|---|---|
| `make test-unit` | No | ~10s | Script logic (mocked) |
| `make test-functional` | No | ~30s | Real partitioning on loopback devices |
| `make build` | No | ~5–15 min | Full install + provision in QEMU |
| `make test-integration` | Yes | ~2 min | System state assertions against saved image |

## Layer 1 — Unit tests (`make test-unit`)

Runs via Docker using the official `bats/bats:1.11.0` image. No root, no block devices, no network.

```bash
make test-unit
```

Files: `tests/*.bats`, `tests/helpers.bash`, `tests/mocks/`

All system calls (`pacstrap`, `arch-chroot`, `sgdisk`, `mkfs.*`, etc.) are intercepted by mock scripts under `tests/mocks/`. Tests verify control flow, argument passing, error handling, and flag detection (e.g. loop device `p`-suffix naming).

Adding a test: create a new `tests/test_*.bats` file. Use `load helpers` at the top; the helpers configure `PATH` to put `tests/mocks/` first.

## Layer 2 — Functional tests (`make test-functional`)

Runs via Docker with `--privileged` to get access to real loopback devices. Tests call the actual partition functions from `lib/partition.sh` against a temporary image file.

```bash
make test-functional
```

Files: `tests/functional/test_layout_simple.bats`, `tests/functional/test_layout_btrfs.bats`, `tests/functional/helpers.bash`

The `helpers.bash` for functional tests creates a 2 GB image, mounts it as a loop device, sources `lib/partition.sh`, and tears everything down in `teardown()`. Tests inspect partition GUIDs, filesystem types, and btrfs subvolume layout directly with `blkid`, `findmnt`, and `btrfs subvolume list`.

Run both unit and functional at once:

```bash
make test
```

## Layer 3 — Build (`make build`)

Boots the Arch Linux live ISO in QEMU, runs the full `bootstrap.sh` + `provision.sh` pipeline, verifies the result with ~15 assertions, and saves the disk image if everything passes.

```bash
make build           # headless (default)
make build HEADLESS=0  # with a visible QEMU window
```

**What happens:**

1. Downloads the Arch ISO (cached at `.cache/arch-latest.iso` — only downloaded once).
2. Generates a persistent SSH key at `.cache/hippoarch-ssh.key` and injects it into the live ISO via serial console automation, and into the installed system for Phase 2 and future `make ssh` use.
3. **Phase 1 (Bootstrap):** Boots the live ISO with direct kernel boot, runs `bootstrap.sh profiles/qemu-test.conf`, verifies GRUB EFI binary size (>2 MB confirms `grub-mkstandalone` succeeded), checks partitions, users, services, and immutability.
4. **Phase 2 (Provision):** Reboots into the installed system via OVMF UEFI + AHCI, runs `provision.sh`, verifies `PROVISION_TIME` and presence of all role files.

**Artifacts on success:**

| File | Description |
|---|---|
| `.cache/hippoarch-built.qcow2` | The verified disk image |
| `.cache/hippoarch-ssh.key` | SSH private key (already injected into the image) |
| `tests/integration/logs/report.txt` | Full build report |
| `tests/integration/logs/qemu-phase1.log` | QEMU stdout for Phase 1 |
| `tests/integration/logs/qemu-phase2.log` | QEMU stdout for Phase 2 |
| `tests/integration/logs/serial.log` | Serial console output (Phase 1) |
| `tests/integration/logs/serial-phase2.log` | Serial console output (Phase 2) |

If the build fails, the disk image and SSH key are deleted. Re-run `make build` to start fresh.

**Dependencies:**

```bash
make install-deps   # installs everything including ovmf, expect, qemu
```

Or manually:

```bash
sudo apt install qemu-system-x86 qemu-utils libarchive-tools expect openssh-client curl ovmf
```

KVM access speeds things up significantly:

```bash
sudo adduser $USER kvm && newgrp kvm
```

## Layer 4 — Integration tests (`make test-integration`)

Boots the saved image (with `snapshot=on` so the image is never modified) and runs a suite of assertions over SSH.

```bash
make test-integration             # headless (default)
make test-integration HEADLESS=0  # with a visible QEMU window
```

If no image exists, the command exits immediately with a message telling you to run `make build` first.

Assertions checked:

- Root filesystem is ext4
- `testuser` account exists with a home directory
- `sshd` is enabled
- `/etc/hippoarch.conf` is present and contains `PROVISION_TIME`
- Provision scripts (`provision.sh`, `common/`, `roles/`) are present in `/home/testuser/hippoarch/`
- `systemd-resolved` and `systemd-networkd` are enabled

Because `snapshot=on` is set, you can run `make test-integration` multiple times against the same image. Each run boots from the same clean state.

Logs: `tests/integration/logs/test.log`, `tests/integration/logs/test-serial.log`

## VM lifecycle

After a successful `make build`, the saved image can be booted interactively for manual inspection.

```bash
make vm-start            # boot in background (headless)
make vm-start HEADLESS=0 # boot with GTK window
make ssh                 # SSH in (starts VM if not running)
make vm-stop             # shut down the VM
```

`make ssh` automatically starts the VM if it is not already running, waits for SSH to come up, then opens an interactive session.

```
root password:     hippoarch-test-root
testuser password: hippoarch-test-user
```

The VM runs with `snapshot=on`, so nothing you do inside it persists. The saved image is always the post-provision state from `make build`.

State files created by `vm-start` and cleaned up by `vm-stop`:

| File | Description |
|---|---|
| `.cache/vm.pid` | PID of the running QEMU process |
| `.cache/hippoarch-ovmf-vars.fd` | Copy of OVMF VARS (writeable, discarded on stop) |

## Directory structure

```text
tests/
├── helpers.bash                  # Unit test: mocked PATH setup
├── mocks/                        # 18+ mock scripts (log calls, exit 0)
├── test_partition.bats           # Unit: partition.sh logic
├── functional/
│   ├── helpers.bash              # Functional: loopback setup/teardown
│   ├── test_layout_simple.bats   # Functional: simple layout assertions
│   └── test_layout_btrfs.bats    # Functional: btrfs layout assertions
└── integration/
    ├── lib.sh                    # Shared constants and helpers
    ├── build.sh                  # Image builder (Phase 1 + Phase 2)
    ├── test.sh                   # Integration assertions
    ├── vm-start.sh               # Boot saved image in background
    ├── vm-stop.sh                # Stop the VM
    ├── vm-ssh.sh                 # Open interactive SSH session
    └── logs/                     # All QEMU and serial logs (gitignored)
```

## CI

The pre-push hook (`hooks/pre-push`) runs `make lint`, `make security`, and `make test-syntax` automatically. Wire it once:

```bash
make install-deps
```

`make test-unit` and `make test-functional` can run in CI with Docker available. `make build` and `make test-integration` require KVM or bare-metal QEMU and are typically run locally before pushing.
