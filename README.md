# HippoArch

These are my personal notes and scripts for configuring my local Arch Linux workstations and servers.

I built this because I found myself repeating the same installation and configuration steps over and over—especially when setting up new hardware like my CWWK 8-bay motherboard. I wanted a way to automate the process without the complexity and extra layers of Ansible or other heavy configuration management frameworks. 

I'm sharing these notes here in the hope that they might be helpful to anyone else looking for a simple, zero-dependency way to manage their Arch fleet.

## Directory Structure

```text
hippoarch/
├── bootstrap.sh            # Step 1: Run from Live ISO
├── provision.sh            # Step 2: Run after reboot
├── profiles/               # Machine-specific settings (.conf files)
├── lib/                    # Shared logic (partitioning engine)
├── common/                 # Configurations shared by ALL machines
│   ├── base.sh             # Core package install & system tweaks
│   ├── dotfiles/           # .vimrc, .bash_aliases
│   └── hardware/           # Hardware-specific configs (fancontrol)
└── roles/                  # Role-specific logic (server, k8s, etc.)
```

## Installation Steps

### 1. Bootstrap (Live ISO)
Boot from the Arch Live ISO, download the repository, and run the bootstrap with a profile:
```bash
git clone https://github.com/hipponix/hippoarch.git
cd hippoarch
./bootstrap.sh profiles/server-cwwk.conf
```
*Note: Check `profiles/server-cwwk.conf` first to ensure the `DISK` variable is correct.*

### 2. Provisioning (Post-Reboot)
After the machine reboots, login and run the role-specific setup:
```bash
cd hippoarch
./provision.sh [role]
```

## Available Roles
- `server` (Optimized for CWWK motherboard + fancontrol)
- `workstation`
- `k8s-controlplane`
- `k8s-node`

## Customization
- **Profiles**: Add a new `.conf` file in `profiles/` for each new machine.
- **Layouts**: Core partitioning logic lives in `lib/partition.sh`.

## TODO
- [ ] Implement `k8s-controlplane` and `k8s-node` installation logic.
- [ ] Add support for LVM, BTRFS, and LUKS encryption in `lib/partition.sh`.
- [ ] Expand the `workstation` role with GUI and developer-specific packages.
- [ ] Add a `common/network.sh` for standardizing static IPs or wireless setup.
- [ ] Implement a validation check for the `DISK` variable in `bootstrap.sh` to prevent accidental data loss.
- [ ] Add functional tests using QEMU/KVM to verify `bootstrap.sh` in a virtual environment.
- [ ] Integrate `shfmt` into the CI pipeline for consistent script formatting.
- [ ] Add a "Dry Run" mode to `provision.sh` to preview changes without applying them.


## References
- [Arch Wiki: Lm_sensors](https://wiki.archlinux.org/title/Lm_sensors)
- [CWWK Motherboard Specs](https://cwwkpc.com/products/cwwk-nas-motherboard-8-bay-core-i5-8265u-4c-8t-mini-itx-pc-mainboard-white-m11-2-x-nvme-pcie3-0-x2-dual-2-5gbe-i226v-lan-ddr4-16gb-ram-128gb-ssd-pcie-x4-slot-tf-hd-dp)
