#!/bin/bash

# Workstation specific configuration
set -e

echo "Applying Workstation role..."

PACKAGES=("man-db" "man-pages")
sudo pacman -S --needed --noconfirm --quiet "${PACKAGES[@]}"
