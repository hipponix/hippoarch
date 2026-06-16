# User Manual

Step-by-step guide to installing and provisioning an Arch Linux machine with HippoArch.

## Prerequisites

You need:
- A machine to install on (or a QEMU VM for testing)
- An Arch Linux live USB
- Network access during installation (DHCP)

## Phase 1 — Bootstrap (run from the live ISO)

### 1. Boot the live ISO

Boot the target machine from the Arch Linux live USB. You will land at a root shell.

### 2. Download bootstrap.sh

```bash
curl -LO https://raw.githubusercontent.com/hipponix/hippoarch/main/bootstrap.sh
```

### 3. Inspect available profiles

```bash
bash bootstrap.sh --list
```

This prints all available `.conf` profiles from the repository. Pick the one matching your hardware.

### 4. Download the profile locally

```bash
bash bootstrap.sh --fetch profiles/server-cwwk.conf
```

Replace `server-cwwk.conf` with the profile you picked. This downloads the profile and `lib/partition.sh` without running anything.

### 5. Edit the profile

Open the profile and set all required variables:

```bash
vim profiles/server-cwwk.conf
```

| Variable | Description | Example |
|---|---|---|
| `DISK` | Target block device (will be wiped) | `/dev/nvme0n1` |
| `HOSTNAME` | Machine hostname | `arch-server` |
| `USERNAME` | Primary user account | `nas` |
| `ROOT_PASSWORD` | Root password | `changeme123` |
| `USER_PASSWORD` | User password | `changeme123` |
| `TIMEZONE` | Timezone string | `Europe/Rome` |
| `LOCALE` | Locale | `en_US.UTF-8` |
| `LAYOUT` | Partition layout | `simple` or `btrfs` |
| `ROLE` | Hardware role to apply at provision time | `server-cwwk` |
| `EXTRA_PACKAGES` | Space-separated additional packages | `"htop iotop"` |

> `DISK` must be a block device (`/dev/nvme0n1`, `/dev/sda`, etc.). The script aborts if `DISK` is not a block device.
>
> `ROOT_PASSWORD` and `USER_PASSWORD` cannot be empty or unset. The script aborts if they are missing.

### 6. Detect your hardware (optional)

```bash
bash bootstrap.sh --detect
```

Prints CPU model, disk list, and RAM so you can confirm the right `DISK` value before writing anything.

### 7. Run the bootstrap

```bash
bash bootstrap.sh profiles/server-cwwk.conf
```

The script:

1. Validates `DISK` and asks for explicit `yes` confirmation before any write.
2. Creates a GPT partition table with a 512 MB EFI partition (FAT32) and a root partition (ext4 or btrfs depending on `LAYOUT`).
3. Installs the base Arch packages into `/mnt` via `pacstrap`.
4. Enters the new system via `arch-chroot` and applies:
   - Timezone, locale, hostname
   - Root and user accounts
   - `systemd-networkd` with DHCP for all wired adapters
   - `systemd-resolved` for DNS
   - GRUB bootloader (standalone EFI binary — works across UEFI firmwares)
   - Curated mirrorlist (pkgbuild.com, Rackspace, kernel.org)
5. Downloads HippoArch into `/home/$USERNAME/hippoarch` for use in Phase 2.
6. Writes `/etc/hippoarch.conf` and locks it immutable (`chattr +i`).

### 8. Reboot

```bash
reboot
```

Remove the USB when prompted. The machine will boot into the newly installed system.

## Phase 2 — Provisioning (run after first reboot)

### 1. Log in

Log in as `$USERNAME` (the value you set in the profile).

### 2. Navigate to the HippoArch directory

```bash
cd hippoarch
```

### 3. Run provision.sh

```bash
./provision.sh
```

`provision.sh` reads `ROLE` from `/etc/hippoarch.conf` (written during bootstrap) and applies the corresponding role configuration. It does not ask for any input.

What it does:

1. Installs base packages (`common/base.sh`): tmux, vim, git, curl, btop, fastfetch, pass, ripgrep.
2. Copies dotfiles (`.vimrc`, `.bash_aliases`) to `~/`.
3. Runs `roles/$ROLE/install.sh` for hardware-specific configuration.
4. Writes `PROVISION_TIME` to `/etc/hippoarch.conf`.

## Partition layouts

### `simple` — EFI + ext4

```
/dev/sdX1   512 MB   FAT32   /boot
/dev/sdX2   rest     ext4    /
```

Best for single-disk setups and VMs. Straightforward, no subvolumes.

### `btrfs` — EFI + btrfs with subvolumes

```
/dev/sdX1   512 MB   FAT32   /boot
/dev/sdX2   rest     btrfs   (subvolumes below)
```

Subvolumes created:

| Subvolume | Mount point |
|---|---|
| `@` | `/` |
| `@home` | `/home` |
| `@snapshots` | `/.snapshots` |
| `@var_log` | `/var/log` |
| `@docker` | `/var/lib/docker` (if applicable) |

Best for servers where you want snapshotting, separate rollback targets for `/home`, or Docker storage isolation.

## Available roles

| Role | Hardware target | What it installs |
|---|---|---|
| `server-cwwk` | CWWK 8-bay NAS motherboard | lm_sensors, IT8620 driver, NAS tooling |
| `server-k8s-master` | Kubernetes control plane node | kubeadm, kubectl, containerd |
| `server-k8s-node` | Kubernetes worker node | containerd, node agent |
| `workstation` | General-purpose desktop/laptop | Desktop packages, dev tools |

## Bootstrap options reference

| Option | Description |
|---|---|
| `bash bootstrap.sh <profile>` | Run the full installation |
| `bash bootstrap.sh --version` | Print the current HippoArch version |
| `bash bootstrap.sh --detect` | Show CPU, disk, and RAM info |
| `bash bootstrap.sh --list` | List all profiles in the repository |
| `bash bootstrap.sh --fetch-all` | Download all profiles locally |
| `bash bootstrap.sh --fetch <profile>` | Download one profile without running |

## Post-install

After provisioning, the machine is ready. A few things to know:

- **SSH is enabled** if `openssh` was included in `EXTRA_PACKAGES`. Connect as `$USERNAME` or `root`.
- **Network is managed by `systemd-networkd`**. All wired adapters get DHCP by default. Edit `/etc/systemd/network/20-wired.network` to add static addresses.
- **DNS is handled by `systemd-resolved`**. `resolv.conf` is a symlink to the stub resolver.
- **Sudo is passwordless for wheel members**. `$USERNAME` is in the `wheel` group.
- **`/etc/hippoarch.conf` is locked** (`chattr +i`). It records the installed version, bootstrap time, and provision time. To modify it: `chattr -i /etc/hippoarch.conf`.

## Troubleshooting

**Bootstrap fails with "is not a block device"**

Check `DISK` in your profile. Run `lsblk` to see available devices. Use the full path (`/dev/nvme0n1`, not `nvme0n1`).

**pacstrap fails with "error: failed to synchronize"**

The live ISO mirrors may be slow or unavailable. Try refreshing the mirror list:

```bash
reflector --country France,Germany --latest 5 --sort rate --save /etc/pacman.d/mirrorlist
pacstrap /mnt base ...
```

**Reboot hangs or falls to a GRUB shell**

The bootstrap uses a standalone GRUB EFI binary that finds the EFI partition by UUID. If booting fails, check that UEFI is enabled in the firmware settings and that Secure Boot is disabled.

**provision.sh: role script not found**

`ROLE` in `/etc/hippoarch.conf` does not match any directory under `roles/`. Edit the conf and remove the immutability flag first: `chattr -i /etc/hippoarch.conf`.

**SSH refuses connection after Phase 2**

Check that `openssh` was in `EXTRA_PACKAGES` and `sshd` is enabled:

```bash
systemctl status sshd
systemctl enable --now sshd
```
