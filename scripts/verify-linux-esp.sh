#!/usr/bin/env bash

verify_linux_esp() {
    local linux macos source mounted
    local esp_type=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
    linux=$(readlink -e -- "$1") && macos=$(readlink -e -- "$2") &&
    source=$(findmnt --noheadings --raw --mountpoint /boot --output SOURCE) &&
    mounted=$(readlink -e -- "$source") &&
    test -b "$linux" && test -b "$macos" && [[ $linux != "$macos" && $mounted == "$linux" ]] &&
    [[ $(findmnt --noheadings --raw --mountpoint /boot --output FSTYPE) == vfat &&
       $(findmnt --noheadings --raw --mountpoint /boot --output FSROOT) == / ]] &&
    # nixos-enter has the block nodes, but not necessarily the Live udev database.
    [[ $(lsblk --properties-by blkid -dn -o PARTTYPE -- "$linux") == "$esp_type" &&
       $(lsblk --properties-by blkid -dn -o PARTTYPE -- "$macos") == "$esp_type" ]] &&
    [[ ! -e /boot/EFI/APPLE && ! -L /boot/EFI/APPLE ]]
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    if ! verify_linux_esp "$@"; then
        printf '%s\n' 'Refusing to update GRUB: /boot is not the confirmed Linux GPT ESP.' >&2
        exit 1
    fi
fi
