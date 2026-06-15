#!/bin/bash

# This script handles the base configuration common to all Arch machines.
set -e

PACKAGES=(
    "tmux"
    "vim"
    "git"
    "curl"
    "fastfetch"
    "btop"
    "pass"
    "ripgrep"
)

echo "Installing base packages..."
sudo pacman -S --needed --noconfirm --quiet "${PACKAGES[@]}"

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
