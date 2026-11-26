#!/usr/bin/env bash
# shellcheck shell=bash

esp_type=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
apfs_type=7c3457ef-0000-11aa-aa11-00306543ecac
root_min=$((15 * 1024 ** 3))
esp_min=$((256 * 1024 ** 2))
partition_uuid='^[[:xdigit:]]{8}(-[[:xdigit:]]{4}){3}-[[:xdigit:]]{12}$'

storage_scan() {
    devices=$(lsblk --json --bytes --paths --list --output \
        NAME,PKNAME,MAJ:MIN,SIZE,TYPE,FSTYPE,FSVER,UUID,PARTUUID,PARTTYPE,PTTYPE,PTUUID,LABEL,MOUNTPOINTS,RO,START)
}

storage_list() {
    jq -r 'def size: if . >= 1073741824 then ((. / 1073741824 * 10 | round) / 10 | tostring) + " GiB"
           else ((. / 1048576 | round) | tostring) + " MiB" end;
        ["Device","Size","Filesystem","Label","Mount point"],
        (.blockdevices[] | [.name,(.size | size),(.fstype // "-"),(.label // "-"),
          ([.mountpoints[]? | select(.)] | join(","))]) | map(gsub("[^ -~]"; "?")) | @tsv' <<< "$devices"
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

storage_partition_ref() {
    jq -ce --arg name "$1" '
        .blockdevices as $devices |
        $devices[] | select(.name == $name and .type == "part" and (.ro | not)) as $part |
        [$devices[] | select(.name == $part.pkname and .type == "disk" and .pttype == "gpt")] |
        select(length == 1) | .[0] as $disk |
        select([$devices[] | select(.type == "disk" and .ptuuid == $disk.ptuuid)] | length == 1) |
        {disk:$disk.ptuuid,part:$part.partuuid,uuid:$part.uuid,fs:$part.fstype} |
        select(all(.[]; type == "string" and length > 0))
    ' <<< "$devices"
}

storage_restore_partition() {
    local reference=$1 name match='' actual
    [[ $reference != null ]] || return 0
    while IFS= read -r name; do
        actual=$(storage_partition_ref "$name") || continue
        if jq -e --argjson ref "$reference" '. == $ref' <<< "$actual" >/dev/null; then
            [[ -z $match ]] || return 1
            match=$name
        fi
    done < <(jq -r --argjson ref "$reference" '.blockdevices[] | select(.partuuid == $ref.part) | .name' <<< "$devices")
    [[ -n $match ]] && printf '%s\n' "$match"
}

storage_check_refs() {
    local live_root live_esp
    live_root=$(storage_partition_ref "$root_dev") &&
    live_esp=$(storage_partition_ref "$esp_dev") &&
    jq -en --argjson root "$live_root" --argjson esp "$live_esp" \
        --argjson expected_root "$root_ref" --argjson expected_esp "$esp_ref" \
        '$root == $expected_root and $esp == $expected_esp' >/dev/null ||
        fail 'Disk or partition identifiers changed. Re-select the root and EFI partitions.'
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
    [[ $root_dev != "$esp_dev" ]] || { fail 'Root and EFI must be separate partitions.'; return 1; }
    root=$(part_info "$root_dev") && esp=$(part_info "$esp_dev") ||
        { fail 'A selected partition is missing or read-only.'; return 1; }

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
        { fail 'Select distinct Btrfs/ext4 and EFI partitions with stable GPT identifiers.'; return 1; }

    jq -e --arg esp "$esp_type" --argjson min "$esp_min" '
      .parttype == $esp and .fstype == "vfat" and .fsver == "FAT32" and .size >= $min
      and ((.mountpoints | map(select(. != null))) - ["/mnt/boot"] | length == 0)' <<< "$esp" >/dev/null &&
    jq -e --argjson min "$root_min" '
      .size >= $min and ((.mountpoints | map(select(. != null))) - ["/mnt"] | length == 0)
      ' <<< "$root" >/dev/null ||
        { fail 'A partition is too small, has the wrong filesystem or is already in use.'; return 1; }

    for expected in "$root_uuid" "$root_partuuid" "$efi_partuuid"; do
        jq -e --arg id "${expected,,}" '
            [.blockdevices[] | select([(.uuid // "" | ascii_downcase),
                (.partuuid // "" | ascii_downcase)] | index($id))] | length == 1
        ' <<< "$devices" >/dev/null ||
            { fail 'Duplicate filesystem UUID or GPT PARTUUID detected.'; return 1; }
    done

    if ! ${dry_run:-false}; then
        [[ $(readlink -e "/dev/disk/by-uuid/$root_uuid") == "$root_dev" &&
           $(readlink -e "/dev/disk/by-partuuid/$root_partuuid") == "$root_dev" &&
           $(readlink -e "/dev/disk/by-partuuid/$efi_partuuid") == "$esp_dev" ]] ||
            { fail 'udev links do not match the selected devices.'; return 1; }
    fi

    apple_partuuid=''
    if [[ $profile == macbook ]]; then
        [[ $root_disk == "$efi_disk" ]] && apple_partuuid=$(mac_esp_identity "$efi_disk" "$esp_dev") &&
        [[ $apple_partuuid =~ $partition_uuid && ${apple_partuuid,,} != "${efi_partuuid,,}" ]] &&
        jq -e --arg id "${apple_partuuid,,}" '
          [.blockdevices[] | select(.partuuid // "" | ascii_downcase == $id)] | length == 1
        ' <<< "$devices" >/dev/null ||
            { fail 'Cannot identify distinct Apple EFI, APFS and Linux EFI partitions on the same disk.'; return 1; }
    elif jq -e --arg a "$root_disk" --arg b "$efi_disk" '
        any(.blockdevices[]; (.pkname == $a or .pkname == $b) and
          ((.parttype // "" | ascii_downcase | endswith("-aa11-00306543ecac")) or
           (.fstype // "" | ascii_downcase | startswith("apfs"))))' <<< "$devices" >/dev/null; then
        fail 'Apple partitions found on this disk. Select the macbook profile for dual boot.'
        return 1
    fi
}

storage_mount_identity() {
    local target=$1 expected=$2 fs=$3 row source actual_fs fsroot options resolved details
    row=$(findmnt --json --mountpoint "$target" --output SOURCE,FSTYPE,FSROOT,FS-OPTIONS) || return 1
    row=$(jq -er '.filesystems | select(length == 1) | .[0] |
        [.source,.fstype,.fsroot,."fs-options"] | join(" ")' <<< "$row") || return 1
    read -r source actual_fs fsroot options <<< "$row"
    [[ $actual_fs == "$fs" && $fsroot == / ]] || return 1

    if [[ $fs == btrfs ]]; then
        source=${source%\[/\]}
        [[ ,$options, == *,subvolid=5,* && ,$options, == *,subvol=/,* ]] || return 1
    fi
    [[ $source == /dev/* ]] || return 1
    resolved=$(readlink -e -- "$source") && test -b "$resolved" &&
        [[ $(lsblk -dnro MAJ:MIN -- "$resolved") == "$expected" ]] || return 1

    if [[ $fs == btrfs ]]; then
        details=$(btrfs filesystem show --raw "$target") || return 1
        grep -Eq '^[[:space:]]*Total devices 1([[:space:]]|$)' <<< "$details"
    fi
}

storage_mount_layout() {
    local target_mount listing
    [[ ! -L /mnt && ! -L /mnt/boot ]] ||
        { fail 'A mount point is a symbolic link.'; return 1; }
    listing=$(findmnt -lno TARGET) || return 1
    while IFS= read -r target_mount; do
        case "$target_mount" in
            /mnt) storage_mount_identity /mnt "$root_id" "$fs_type" ||
                      { fail 'Unexpected filesystem or subvolume mounted at /mnt.'; return 1; } ;;
            /mnt/boot) storage_mount_identity /mnt/boot "$esp_id" vfat ||
                           { fail 'Unexpected filesystem mounted at /mnt/boot.'; return 1; } ;;
            /mnt/*) fail "Unrelated mount point: $target_mount"; return 1 ;;
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
        { fail 'Partition identities changed after confirmation.'; return 1; }
    storage_check_refs
}

storage_probe() {
    local root_probe=/mnt esp_probe=/mnt/boot probe_opts=ro,noload
    local existing=false
    storage_check && storage_same_selection && storage_mount_layout || return 1
    if ! findmnt -rn -M /mnt >/dev/null; then
        root_probe=$work/root-probe
        [[ $fs_type != btrfs ]] || probe_opts=ro,rescue=nologreplay,subvolid=5
        mkdir -p -- "$root_probe" && mount -t "$fs_type" -o "$probe_opts" -- "$root_dev" "$root_probe" || return 1
        probe_mounts+=("$root_probe")
        storage_mount_identity "$root_probe" "$root_id" "$fs_type" ||
            { fail 'Root must be the selected filesystem. Btrfs must use one device and subvolid=5.'; return 1; }
    fi
    if [[ -f $root_probe/.nixos-vladik-install && ! -L $root_probe/.nixos-vladik-install ]] &&
       [[ $(<"$root_probe/.nixos-vladik-install") == "$mount_key" ]]; then
        existing=true
    else
        fresh_root "$root_probe" ||
            { fail 'Root contains existing data or an unrecognized installation.'; return 1; }
    fi
    if ! findmnt -rn -M /mnt/boot >/dev/null; then
        esp_probe=$work/esp-probe
        if [[ -d $root_probe/boot ]] && ! fresh_esp "$root_probe/boot"; then
            fail 'The root partition already contains a non-empty boot directory.'
            return 1
        fi
        mkdir -p -- "$esp_probe" && mount -t vfat -o ro -- "$esp_dev" "$esp_probe" || return 1
        probe_mounts+=("$esp_probe")
        storage_mount_identity "$esp_probe" "$esp_id" vfat ||
            { fail 'The read-only EFI mount does not match the selection.'; return 1; }
    fi
    [[ ! -e $esp_probe/EFI/APPLE ]] &&
        { "$existing" || fresh_esp "$esp_probe"; } ||
        { fail 'EFI is not empty. A new installation requires an empty Linux EFI partition.'; return 1; }
    if ! "$existing"; then
        free_at_least "$root_probe" "$root_min" && free_at_least "$esp_probe" "$esp_min" ||
            { fail 'Insufficient free space. Root needs 15 GiB and EFI needs 256 MiB.'; return 1; }
    fi
}

storage_open() {
    local root_options=defaults
    storage_check && storage_same_selection && storage_mount_layout || return 1
    if ! findmnt -rn -M /mnt >/dev/null; then
        if [[ -e /mnt ]] && ! fresh_esp /mnt; then
            fail 'The unmounted /mnt directory already contains files.'
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
    storage_mount_layout || return 1
    storage_mount_identity /mnt "$root_id" "$fs_type" &&
    storage_mount_identity /mnt/boot "$esp_id" vfat && [[ ! -e /mnt/boot/EFI/APPLE ]] ||
        { fail 'Cannot verify the selected root and Linux EFI mounts.'; return 1; }
    for mountpoint in /mnt /mnt/boot; do
        options=$(findmnt -nro VFS-OPTIONS --mountpoint "$mountpoint") || return 1
        [[ ,$options, == *,rw,* ]] || { fail "$mountpoint is mounted read-only."; return 1; }
    done
}
