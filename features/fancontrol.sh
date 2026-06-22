#!/bin/bash
set -e

# shellcheck source=/dev/null
source lib/aur.sh

echo "Enabling fancontrol..."
sudo pacman -S --needed --noconfirm --quiet lm_sensors

modprobe_opts="ignore_resource_conflict=1"
[[ -n "${IT87_FORCE_ID:-}" ]] && modprobe_opts="$modprobe_opts force_id=$IT87_FORCE_ID"
echo "options it87 $modprobe_opts" | sudo tee /etc/modprobe.d/it87.conf > /dev/null
echo "it87" | sudo tee /etc/modules-load.d/it87.conf > /dev/null

_try_load_it87() { sudo modprobe it87 && lsmod | grep -q it87; }

if ! _try_load_it87; then
    if [[ "${ENABLE_AUR:-0}" != "1" ]]; then
        echo "Warning: it87 module not loaded — set ENABLE_AUR=1 to install it87-dkms-git from AUR"
        exit 0
    fi
    echo "In-kernel it87 not supported — installing it87-dkms-git from AUR..."
    sudo pacman -S --needed --noconfirm base-devel git linux-headers
    aur_install it87-dkms-git
    if ! _try_load_it87; then
        echo "Warning: it87 module not loaded — lm_sensors and fancontrol skipped"
        exit 0
    fi
fi

sudo sensors-detect --auto 2>&1 | grep -E "^(Found|Loaded|error)" || true

if ! sudo systemctl enable --now lm_sensors; then
    echo "Warning: lm_sensors failed to start"
    sudo journalctl -u lm_sensors --no-pager -n 20 || true
fi

# hwmon indices are not stable across reboots (probe order varies).
# Install a helper that rediscovers them and rewrites /etc/fancontrol on every boot.
sudo tee /usr/local/bin/hippoarch-fancontrol-setup > /dev/null <<'SETUP'
#!/bin/bash
set -e

_find_hwmon() {
    local match="$1"
    for d in /sys/class/hwmon/hwmon*; do
        if [[ "$match" == pwm ]]; then
            [[ -f "$d/pwm1" ]] && { echo "${d##*/hwmon}"; return; }
        else
            [[ "$(cat "$d/name" 2>/dev/null)" == "${match#name:}" ]] && { echo "${d##*/hwmon}"; return; }
        fi
    done
}

IT87_N=$(_find_hwmon pwm)
CORETEMP_N=$(_find_hwmon name:coretemp)

if [[ -z "$IT87_N" || -z "$CORETEMP_N" ]]; then
    echo "hippoarch-fancontrol-setup: hwmon discovery failed (it87=hwmon${IT87_N:-?} coretemp=hwmon${CORETEMP_N:-?})" >&2
    exit 1
fi

IT87_NAME=$(cat "/sys/class/hwmon/hwmon${IT87_N}/name")
IT87_PATH=$(readlink -f "/sys/class/hwmon/hwmon${IT87_N}" | sed 's|^/sys/||; s|/hwmon/hwmon[0-9]*$||')
CORETEMP_PATH=$(readlink -f "/sys/class/hwmon/hwmon${CORETEMP_N}" | sed 's|^/sys/||; s|/hwmon/hwmon[0-9]*$||')

cat > /etc/fancontrol <<EOF
INTERVAL=10
DEVPATH=hwmon${CORETEMP_N}=${CORETEMP_PATH} hwmon${IT87_N}=${IT87_PATH}
DEVNAME=hwmon${CORETEMP_N}=coretemp hwmon${IT87_N}=${IT87_NAME}
FCTEMPS=hwmon${IT87_N}/pwm1=hwmon${CORETEMP_N}/temp1_input
FCFANS=hwmon${IT87_N}/pwm1=hwmon${IT87_N}/fan1_input
MINTEMP=hwmon${IT87_N}/pwm1=40
MAXTEMP=hwmon${IT87_N}/pwm1=70
MINSTART=hwmon${IT87_N}/pwm1=60
MINSTOP=hwmon${IT87_N}/pwm1=50
MINPWM=hwmon${IT87_N}/pwm1=50
MAXPWM=hwmon${IT87_N}/pwm1=255
EOF

echo "hippoarch-fancontrol-setup: /etc/fancontrol updated (coretemp=hwmon${CORETEMP_N}, ${IT87_NAME}=hwmon${IT87_N})"
SETUP
sudo chmod +x /usr/local/bin/hippoarch-fancontrol-setup

sudo mkdir -p /etc/systemd/system/fancontrol.service.d
sudo tee /etc/systemd/system/fancontrol.service.d/10-hippoarch.conf > /dev/null <<'DROPIN'
[Service]
ExecStartPre=/usr/local/bin/hippoarch-fancontrol-setup
ReadWritePaths=/etc/fancontrol
DROPIN

sudo systemctl daemon-reload
sudo /usr/local/bin/hippoarch-fancontrol-setup

if ! sudo systemctl enable --now fancontrol; then
    echo "Warning: fancontrol failed to start"
    sudo journalctl -u fancontrol --no-pager -n 20 || true
else
    sudo systemctl status fancontrol --no-pager
fi
