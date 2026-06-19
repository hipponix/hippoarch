#!/bin/bash

aur_install() {
    local pkg="$1"
    local tmp
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' RETURN
    git clone "https://aur.archlinux.org/${pkg}.git" "$tmp/${pkg}"
    (cd "$tmp/${pkg}" && makepkg -si --noconfirm --skippgpcheck)
}
