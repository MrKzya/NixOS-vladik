#!/usr/bin/env bash
# shellcheck shell=bash

esp_type=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
apfs_type=7c3457ef-0000-11aa-aa11-00306543ecac
root_min=$((15 * 1024 ** 3))
esp_min=$((256 * 1024 ** 2))
partition_uuid='^[[:xdigit:]]{8}(-[[:xdigit:]]{4}){3}-[[:xdigit:]]{12}$'

storage_scan() {
    devices=$(lsblk --json --bytes --paths --list --output \
        NAME,PKNAME,MAJ:MIN,SIZE,TYPE,FSTYPE,FSVER,UUID,PARTUUID,PARTTYPE,PTTYPE,LABEL,MOUNTPOINTS,RO,START)
}

storage_list() {
    jq -r '["Устройство","Байт","ФС","Метка","Монтирование"],
        (.blockdevices[] | [.name,.size,(.fstype // "-"),(.label // "-"),
          ([.mountpoints[] | select(.)] | join(","))]) | @tsv' <<< "$devices"
}

storage_candidates() {
    jq -r --arg role "$1" --arg esp "$esp_type" '
      .blockdevices[] | select(.type == "part" and (.ro | not))
      | select(if $role == "root" then .fstype == "btrfs" or .fstype == "ext4"
          else .parttype == $esp and .fstype == "vfat" and .fsver == "FAT32" end)
      | .name' <<< "$devices"
}

part_info() {
    jq -ce --arg dev "$1" '.blockdevices | map(select(.name == $dev)) |
        select(length == 1) | .[0] | select(.type == "part" and (.ro | not))' <<< "$devices"
}

mac_esp_identity() {
    local disk=$1 linux=$2
    jq -er --arg disk "$disk" --arg linux "$linux" --arg esp "$esp_type" --arg apfs "$apfs_type" '
      [.blockdevices[] | select(.pkname == $disk)] as $parts
      | ([$parts[] | select(.parttype == $esp)] | sort_by(.start | tonumber)) as $esps
      | [$parts[] | select(.parttype == $apfs)] as $apple
      | select(($esps | length) == 2 and ($apple | length) == 1)
      | select($esps[1].name == $linux and
          ($esps[0].start | tonumber) < ($apple[0].start | tonumber) and
          ($apple[0].start | tonumber) < ($esps[1].start | tonumber))
      | $esps[0].partuuid' <<< "$devices"
}

storage_check() {
    local root esp efi_disk root_disk expected
    storage_scan || return 1
    [[ $root_dev != "$esp_dev" ]] || { fail 'Корень и ESP должны быть разными разделами.'; return 1; }
    root=$(part_info "$root_dev") && esp=$(part_info "$esp_dev") ||
        { fail 'Выбранный раздел исчез или доступен только для чтения.'; return 1; }

    root_uuid=$(jq -r '.uuid // ""' <<< "$root")
    root_partuuid=$(jq -r '.partuuid // ""' <<< "$root")
    efi_partuuid=$(jq -r '.partuuid // ""' <<< "$esp")
    fs_type=$(jq -r .fstype <<< "$root")
    root_id=$(jq -r '."maj:min"' <<< "$root")
    esp_id=$(jq -r '."maj:min"' <<< "$esp")
    efi_disk=$(jq -r .pkname <<< "$esp")
    root_disk=$(jq -r .pkname <<< "$root")
    [[ $root_id != "$esp_id" && ( $fs_type == btrfs || $fs_type == ext4 ) &&
        $root_uuid =~ $partition_uuid && $root_partuuid =~ $partition_uuid &&
        $efi_partuuid =~ $partition_uuid && $root_partuuid != "$efi_partuuid" ]] ||
        { fail 'Для корневого Btrfs/Ext4 и ESP требуются разные разделы с устойчивыми идентификаторами GPT.'; return 1; }

    jq -e --arg esp "$esp_type" --argjson min "$esp_min" '
      .parttype == $esp and .fstype == "vfat" and .fsver == "FAT32" and .size >= $min
      and ((.mountpoints | map(select(. != null))) - ["/mnt/boot"] | length == 0)' <<< "$esp" >/dev/null &&
    jq -e --argjson min "$root_min" '
      .size >= $min and ((.mountpoints | map(select(. != null))) - ["/mnt"] | length == 0)
      ' <<< "$root" >/dev/null ||
        { fail 'Разделы недостаточного размера, ESP имеет неверный тип или выбранный раздел уже занят.'; return 1; }

    for expected in "$root_uuid" "$root_partuuid" "$efi_partuuid"; do
        jq -e --arg id "${expected,,}" '
            [.blockdevices[] | select([(.uuid // "" | ascii_downcase),
                (.partuuid // "" | ascii_downcase)] | index($id))] | length == 1
        ' <<< "$devices" >/dev/null ||
            { fail 'Обнаружен дубликат UUID или PARTUUID.'; return 1; }
    done

    if ! ${dry_run:-false}; then
        [[ $(readlink -e "/dev/disk/by-uuid/$root_uuid") == "$root_dev" &&
           $(readlink -e "/dev/disk/by-partuuid/$root_partuuid") == "$root_dev" &&
           $(readlink -e "/dev/disk/by-partuuid/$efi_partuuid") == "$esp_dev" ]] ||
            { fail 'Ссылки udev не совпадают с выбранными устройствами.'; return 1; }
    fi

    apple_partuuid=''
    if [[ $profile == macbook ]]; then
        [[ $root_disk == "$efi_disk" ]] && apple_partuuid=$(mac_esp_identity "$efi_disk" "$esp_dev") &&
        [[ $apple_partuuid =~ $partition_uuid && ${apple_partuuid,,} != "${efi_partuuid,,}" ]] &&
        jq -e --arg id "${apple_partuuid,,}" '
          [.blockdevices[] | select(.partuuid // "" | ascii_downcase == $id)] | length == 1
        ' <<< "$devices" >/dev/null ||
            { fail 'Не удалось однозначно отделить Apple ESP, APFS и Linux ESP на одном диске.'; return 1; }
    elif jq -e --arg a "$root_disk" --arg b "$efi_disk" '
        any(.blockdevices[]; (.pkname == $a or .pkname == $b) and
          ((.parttype // "" | ascii_downcase | endswith("-aa11-00306543ecac")) or
           (.fstype // "" | ascii_downcase | startswith("apfs"))))' <<< "$devices" >/dev/null; then
        fail 'На выбранном диске найдены разделы Apple. Для dual boot используется профиль macbook.'
        return 1
    fi
}

storage_mount_identity() {
    [[ $(findmnt -nro MAJ:MIN,FSTYPE,FSROOT --mountpoint "$1") == "$2 $3 /" ]]
}

storage_mount_layout() {
    local target_mount listing
    [[ ! -L /mnt && ! -L /mnt/boot ]] ||
        { fail 'Точка монтирования является символической ссылкой.'; return 1; }
    listing=$(findmnt -lno TARGET) || return 1
    while IFS= read -r target_mount; do
        case "$target_mount" in
            /mnt) storage_mount_identity /mnt "$root_id" "$fs_type" ||
                      { fail 'На /mnt уже смонтирована другая файловая система.'; return 1; } ;;
            /mnt/boot) storage_mount_identity /mnt/boot "$esp_id" vfat ||
                           { fail 'На /mnt/boot уже смонтирована другая файловая система.'; return 1; } ;;
            /mnt/*) fail "Посторонняя точка монтирования: $target_mount"; return 1 ;;
        esac
    done <<< "$listing"
}

free_at_least() {
    local free
    free=$(df --block-size=1 --output=avail -- "$1" | tail -n1) || return 1
    [[ $free =~ ^[[:space:]]*[0-9]+$ && $free -ge $2 ]]
}

fresh_root() {
    local found
    found=$(find "$1" -mindepth 1 -maxdepth 1 ! -name lost+found ! -name boot -print -quit) || return 1
    [[ -z $found && ! -L $1/boot ]] &&
        { [[ ! -e $1/boot ]] || [[ -d $1/boot ]]; }
}

fresh_esp() {
    local found
    found=$(find "$1" -mindepth 1 -maxdepth 1 -print -quit) || return 1
    [[ -z $found ]]
}

storage_selection() {
    printf '%s:%s:%s:%s:%s:%s' "$profile" "$root_uuid" "$root_partuuid" "$efi_partuuid" "$apple_partuuid" "$revision"
}

storage_same_selection() {
    [[ $(storage_selection) == "$mount_key" ]] ||
        fail 'Идентификаторы разделов изменились после подтверждения плана.'
}

storage_probe() {
    local root_probe=/mnt esp_probe=/mnt/boot probe_opts=ro,noload
    local existing=false
    storage_check && storage_same_selection && storage_mount_layout || return 1
    if ! findmnt -rn -M /mnt >/dev/null; then
        root_probe=$work/root-probe
        [[ $fs_type != btrfs ]] || probe_opts=ro,nologreplay,subvolid=5
        mkdir -p -- "$root_probe" && mount -t "$fs_type" -o "$probe_opts" -- "$root_dev" "$root_probe" || return 1
        probe_mounts+=("$root_probe")
    fi
    if [[ -f $root_probe/.nixos-vladik-install && ! -L $root_probe/.nixos-vladik-install ]] &&
       [[ $(<"$root_probe/.nixos-vladik-install") == "$mount_key" ]]; then
        existing=true
    else
        fresh_root "$root_probe" ||
            { fail 'Корень содержит данные или незнакомую установку.'; return 1; }
    fi
    if ! findmnt -rn -M /mnt/boot >/dev/null; then
        esp_probe=$work/esp-probe
        if [[ -d $root_probe/boot ]] && ! fresh_esp "$root_probe/boot"; then
            fail 'Каталог boot на корне уже содержит данные.'
            return 1
        fi
        mkdir -p -- "$esp_probe" && mount -t vfat -o ro -- "$esp_dev" "$esp_probe" || return 1
        probe_mounts+=("$esp_probe")
    fi
    [[ ! -e $esp_probe/EFI/APPLE ]] &&
        { "$existing" || fresh_esp "$esp_probe"; } ||
        { fail 'EFI-раздел содержит данные. Для новой установки требуется пустой Linux ESP.'; return 1; }
    if ! "$existing"; then
        free_at_least "$root_probe" "$root_min" && free_at_least "$esp_probe" "$esp_min" ||
            { fail 'Недостаточно свободного места: минимум 15 ГиБ на корне и 256 МиБ на ESP.'; return 1; }
    fi
}

storage_open() {
    local root_options=defaults
    storage_check && storage_same_selection && storage_mount_layout || return 1
    if ! findmnt -rn -M /mnt >/dev/null; then
        if [[ -e /mnt ]] && ! fresh_esp /mnt; then
            fail 'Незанятый каталог /mnt уже содержит файлы.'
            return 1
        fi
        [[ $fs_type != btrfs ]] || root_options=compress=zstd:3,noatime,subvolid=5
        mkdir -p /mnt && mount -t "$fs_type" -o "$root_options" -- "$root_dev" /mnt || return 1
        owned_mounts+=(/mnt)
    fi
    storage_mount_identity /mnt "$root_id" "$fs_type" && [[ ! -L /mnt/boot ]] || return 1
    if [[ ! -e /mnt/.nixos-vladik-install ]]; then
        fresh_root /mnt || return 1
    fi
    if ! findmnt -rn -M /mnt/boot >/dev/null; then
        mkdir -p /mnt/boot && mount -t vfat -o umask=0077 -- "$esp_dev" /mnt/boot || return 1
        owned_mounts+=(/mnt/boot)
    fi
    storage_verify || return 1
    if [[ ! -e /mnt/.nixos-vladik-install ]]; then
        # The mount may have changed since the read-only probe.
        fresh_root /mnt && fresh_esp /mnt/boot || return 1
        (set -o noclobber; printf '%s\n' "$mount_key" > /mnt/.nixos-vladik-install) || return 1
    fi
    [[ ! -L /mnt/.nixos-vladik-install && $(</mnt/.nixos-vladik-install) == "$mount_key" ]]
}

storage_verify() {
    local mountpoint options
    storage_mount_layout && storage_mount_identity /mnt "$root_id" "$fs_type" &&
        storage_mount_identity /mnt/boot "$esp_id" vfat &&
        [[ ! -e /mnt/boot/EFI/APPLE ]] || return 1
    for mountpoint in /mnt /mnt/boot; do
        options=$(findmnt -nro VFS-OPTIONS --mountpoint "$mountpoint") || return 1
        [[ ,$options, == *,rw,* ]] || { fail "$mountpoint смонтирован только для чтения."; return 1; }
    done
}
