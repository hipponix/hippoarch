---
layout: default
---

HippoArch automates Arch Linux installation and post-install provisioning in two phases — bootstrap from the live ISO, then provision after reboot — with no dependencies beyond bash and standard Arch tools.

Built out of necessity after one too many manual installs. Rather than reaching for Ansible, it grew from a pile of local notes into a modular, QEMU-tested framework — one late night at a time.

---

## What it does

**Phase 1 — Bootstrap** runs from the live Arch ISO. It partitions the disk, installs the base system, and drops `provision.sh` into the new user's home.

**Phase 2 — Provisioning** runs after the first reboot. It installs packages, configures hardware and sensors, deploys dotfiles, and applies the role-specific setup defined in the profile.

---

## Key features

- **Zero dependencies** — bash and standard Arch tools only
- **Profile-based** — one `.conf` file per machine defines disk, hostname, locale, role, and packages
- **Role system** — `workstation`, `server-cwwk`, `server-k8s-master`, `server-k8s-node`
- **QEMU end-to-end tested** — full two-phase install runs in CI on every push against a real Arch ISO
- **No Ansible, no overhead** — transparent, modular, easy to extend

---

## Quick start

Download and extract the latest release on a live Arch ISO:

```bash
curl -LO https://github.com/hipponix/hippoarch/releases/latest/download/hippoarch.tar.gz
tar xzf hippoarch.tar.gz && cd hippoarch
bash bootstrap.sh --list
bash bootstrap.sh profiles/workstation.conf
```

After reboot:

```bash
cd hippoarch
bash provision.sh
```

---

## Links

- [GitHub repository](https://github.com/hipponix/hippoarch)
- [Releases](https://github.com/hipponix/hippoarch/releases)
- [Testing strategy](docs/testing.md)
- [User manual](docs/user-manual.md)
