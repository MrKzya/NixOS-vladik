#!/usr/bin/env bash
# shellcheck shell=bash

project_clone() {
    [[ ! -e $work/repo ]] || return 0
    local checkout
    checkout=$(mktemp -d "$work/checkout.XXXXXXXX") || return 1
    if ! run git -c "safe.directory=$source_dir" clone --no-local --single-branch \
        --branch installer -- "$source_dir" "$checkout" ||
       ! run git -C "$checkout" remote set-url origin https://github.com/MrKzya/NixOS-vladik.git ||
       ! mv -T -- "$checkout" "$work/repo"; then
        rm -rf -- "$checkout"
        return 1
    fi
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
    if [[ $profile == macbook ]]; then
        case "$firmware_mode" in
            live) firmware_import /lib/firmware/brcm "$dest/firmware/brcm" || return 1 ;;
            archive) firmware_import "$firmware_archive" "$dest/firmware/brcm" || return 1 ;;
        esac
    fi
    run nix_cmd eval --raw --no-update-lock-file "path:$work/repo#nixosConfigurations.$profile.config.system.build.toplevel.drvPath"
}

firmware_import() {
    local source=$1 destination=$2 listing member name
    local wifi=false calibration=false clm=false bluetooth=false
    local -a selected=()
    local -A seen=()
    if [[ -d $source ]]; then
        listing=$(find -L "$source" -maxdepth 1 -type f -printf '%f\n') || return 1
    else
        listing=$(tar -tf "$source") || return 1
    fi
    while IFS= read -r member; do
        name=${member#./}
        [[ $name =~ ^(brcmfmac[[:alnum:]]+-pcie(\.apple,[[:alnum:],_-]+)?|brcmbt[[:alnum:]]+-apple,[[:alnum:],_-]+)\.(bin|txt|clm_blob|txcap_blob|ptb|hcd)(\.(zst|xz))?$ ]] || continue
        if [[ $model == MacBookAir9,1 ]]; then
            case "$name" in
                brcmfmac4377b3-pcie.apple,formosa*.*|brcmfmac4377b3-pcie.clm_blob*|brcmfmac4377b3-pcie.txcap_blob*|brcmbt4377b3-apple,formosa*.*) ;;
                *) continue ;;
            esac
        fi
        case "$name" in
            brcmfmac*-pcie.apple,*.bin|brcmfmac*-pcie.apple,*.bin.*) wifi=true ;;
            brcmfmac*-pcie.apple,*.txt|brcmfmac*-pcie.apple,*.txt.*) calibration=true ;;
            brcmfmac*.clm_blob|brcmfmac*.clm_blob.*) clm=true ;;
            brcmbt*.bin|brcmbt*.bin.*) bluetooth=true ;;
        esac
        if [[ ${seen[$name]+found} ]]; then
            fail "Duplicate firmware filename: $name"
            return 1
        fi
        seen[$name]=1
        selected+=("$member")
    done <<< "$listing"

    if ! "$wifi" || ! "$calibration"; then
        fail 'Missing board-specific Wi-Fi firmware (.bin) or NVRAM (.txt).'
        return 1
    fi
    "$clm" || printf 'The firmware source has no CLM blob.\n'
    if ! "$bluetooth" && [[ $model == MacBookAir9,1 ]]; then
        printf 'The source has no BCM4377 Bluetooth firmware.\n'
    fi

    mkdir -p -- "$destination" || return 1
    for member in "${selected[@]}"; do
        name=${member#./}
        if [[ -d $source ]]; then
            cp -L -- "$source/$member" "$destination/$name" || return 1
        else
            # Extract bytes only. An archive entry can never set a destination pathname or symlink.
            tar -xOf "$source" -- "$member" > "$destination/$name" || return 1
        fi
        [[ -s $destination/$name ]] || { fail "Empty firmware file: $name"; return 1; }
    done
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
            { fail 'A different checkout exists at /etc/nixos/NixOS-vladik.'; return 1; }
        for local_name in installer.local.nix hardware.generated.local.nix settings.local.json; do
            install -m 0600 -T -- "$work/repo/hosts/$profile/$local_name" "$dest/hosts/$profile/$local_name" || return 1
        done
        if [[ $profile == macbook && ( $firmware_mode == live || $firmware_mode == archive ) ]]; then
            mkdir -p "$dest/hosts/$profile/firmware/brcm" &&
            cp -a "$work/repo/hosts/$profile/firmware/brcm/." "$dest/hosts/$profile/firmware/brcm/" || return 1
        fi
    fi
    target_flake="path:$dest#$profile"
}
