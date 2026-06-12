#!/bin/bash

# This script handles the base configuration common to all Arch machines.
set -e

PACKAGES=(
    "tmux"
    "vim"
    "git"
    "curl"
    "fastfetch"
    "lm_sensors"
    "btop"
    "pass"
    "ripgrep"
)

echo "Installing base packages..."
sudo pacman -S --needed --noconfirm --quiet "${PACKAGES[@]}"

echo "Configuring hardware drivers..."
# Load ITE Driver for IT8620 (common on these boards)
if [[ -d "/etc/modprobe.d" ]]; then
    echo "options it87 ignore_resource_conflict=1" | sudo tee /etc/modprobe.d/it87.conf > /dev/null
    echo "it87" | sudo tee /etc/modules-load.d/it87.conf > /dev/null
fi

echo "Probing sensors..."
sudo sensors-detect --auto > /dev/null 2>&1
sudo systemctl enable --now lm_sensors

echo "Deploying common dotfiles..."
for file in .vimrc .bash_aliases; do
    src="common/dotfiles/$file"
    if [[ -f "$src" ]]; then
        cp "$src" ~/"$file"
        echo " -> $file copied to ~/"
    fi
done

# Ensure .bash_aliases is sourced
if ! grep -Fq '. ~/.bash_aliases' ~/.bashrc; then
    echo "Adding .bash_aliases to .bashrc..."
    cat >> ~/.bashrc << 'EOF'

# Load custom aliases
[[ -f ~/.bash_aliases ]] && . ~/.bash_aliases
EOF
fi
