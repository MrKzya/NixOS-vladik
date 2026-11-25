#!/usr/bin/env bash
# shellcheck shell=bash

project_clone() {
    [[ ! -e $work/repo ]] || return 0
    run git -c "safe.directory=$source_dir" clone --no-local --single-branch \
        --branch installer -- "$source_dir" "$work/checkout" &&
    run git -C "$work/checkout" remote set-url origin https://github.com/MrKzya/NixOS-vladik.git &&
    mv -T -- "$work/checkout" "$work/repo"
}

config_generate() {
    local dest=$work/repo/hosts/$profile options nameserver_json='[]'
    local -a addresses=()
    project_clone || return 1
    printf '{ ... }: { imports = [ (import ../../installer/target.nix { configDir = ./.; }) ]; }\n' > "$dest/installer.local.nix" &&
    nixos-generate-config --no-filesystems --show-hardware-config > "$dest/hardware.generated.local.nix" \
        2>>"$log_file" || return 1
    mapfile -t addresses < <(dns_servers "$dns_mode")
    if (( ${#addresses[@]} )); then
        nameserver_json=$(printf '%s\n' "${addresses[@]}" | jq -R . | jq -s .) || return 1
    fi
    options=$(jq --argjson ns "$nameserver_json" --arg profile "$profile" --arg root "$root_uuid" \
        --arg fs "$fs_type" --arg efi "$efi_partuuid" --arg apple "$apple_partuuid" \
        --arg firmware "$firmware_mode" '
        . + {profile:$profile, nameservers:$ns, firmware:$firmware,
          storage:{rootUuid:$root,fsType:$fs,efiPartuuid:$efi,applePartuuid:$apple}}' <<< "$settings") || return 1
    printf '%s\n' "$options" > "$dest/settings.local.json" || return 1
    if [[ $profile == macbook && $firmware_mode == live ]]; then
        firmware_from_live "$dest/firmware/brcm" || return 1
    fi
    run nix_cmd eval --raw --no-update-lock-file "path:$work/repo#nixosConfigurations.$profile.config.system.build.toplevel.drvPath"
}

firmware_from_live() {
    local firmware
    local -a files=()
    while IFS= read -r -d '' firmware; do
        files+=("$firmware")
    done < <(find -L /lib/firmware/brcm -maxdepth 1 -type f \( \
        -name 'brcmfmac*-pcie.apple,*' -o -name 'brcmbt*apple*' \) -print0 2>/dev/null)
    (( ${#files[@]} )) ||
        { fail 'В Live не найдены подготовленные файлы Broadcom для Apple.'; return 1; }
    mkdir -p -- "$1" && cp -L -- "${files[@]}" "$1/"
}

config_save() {
    local dest=/mnt/etc/nixos/NixOS-vladik local_name relative staging
    storage_verify || return 1
    for relative in /mnt/etc /mnt/etc/nixos "$dest"; do
        [[ ! -L $relative ]] || return 1
    done
    mkdir -p /mnt/etc/nixos || return 1
    if [[ ! -e $dest ]]; then
        staging=$(mktemp -d /mnt/etc/nixos/.vladik-staging.XXXXXXXX) || return 1
        if ! cp -a -- "$work/repo/." "$staging/" || ! mv -T -- "$staging" "$dest"; then
            rm -rf -- "$staging"
            return 1
        fi
    else
        [[ -d $dest/.git && ! -L $dest/.git &&
           $(git -C "$dest" rev-parse HEAD) == "$revision" ]] ||
            { fail 'В /etc/nixos/NixOS-vladik находится другой репозиторий.'; return 1; }
        for local_name in installer.local.nix hardware.generated.local.nix settings.local.json; do
            install -m 0600 -T -- "$work/repo/hosts/$profile/$local_name" "$dest/hosts/$profile/$local_name" || return 1
        done
        if [[ $profile == macbook && $firmware_mode == live ]]; then
            mkdir -p "$dest/hosts/$profile/firmware/brcm" &&
            cp -a "$work/repo/hosts/$profile/firmware/brcm/." "$dest/hosts/$profile/firmware/brcm/" || return 1
        fi
    fi
    target_flake="path:$dest#$profile"
}
