---
layout: default
---

HippoArch automates Arch Linux installation and post-install provisioning in two phases — bootstrap from the live ISO, then provision after reboot — with no dependencies beyond bash and standard Arch tools.

Built out of necessity after one too many manual installs. Rather than reaching for Ansible, it grew from a pile of local notes into a modular, QEMU-tested framework — one late night at a time.

---

## Key features

- **Zero dependencies** — bash and standard Arch tools only
- **Profile-based** — one `.conf` file per machine defines disk, hostname, locale, role, and packages
- **Role system** — `workstation`, `server-cwwk`, `server-k8s-master`, `server-k8s-node`
- **QEMU end-to-end tested** — full two-phase install runs in CI on every push against a real Arch ISO
- **No Ansible, no overhead** — transparent, modular, easy to extend

---

## Quick start

```bash
curl -LO https://github.com/hipponix/hippoarch/releases/latest/download/hippoarch.tar.gz
tar xzf hippoarch.tar.gz && cd hippoarch
bash bootstrap.sh --list
bash bootstrap.sh profiles/workstation.conf
```

After reboot: `cd hippoarch && bash provision.sh`

---

[Full documentation and installation guide →](https://github.com/hipponix/hippoarch#readme)
