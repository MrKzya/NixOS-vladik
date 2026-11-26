#!/usr/bin/env bash
# shellcheck shell=bash

plan_encode() {
    local addresses
    addresses=$(printf '%s\n' "${custom_dns[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))') || return 1
    jq -n --arg profile "$profile" --argjson settings "$settings" \
        --arg mode "$dns_mode" --argjson addresses "$addresses" --arg firmware "$firmware_mode" \
        --argjson root "${root_ref:-null}" --argjson efi "${esp_ref:-null}" \
        '{version:1,profile:$profile,settings:$settings,dns:{mode:$mode,addresses:$addresses},
          firmware:$firmware,root:$root,efi:$efi}'
}

plan_write() {
    local destination=$1 temp data
    data=$(plan_encode) || return 1
    [[ ! -L $destination && ( ! -e $destination || -f $destination ) ]] || return 1
    temp=$(mktemp -- "${destination}.XXXXXXXX") || return 1
    if ! printf '%s\n' "$data" > "$temp" || ! mv -fT -- "$temp" "$destination"; then
        rm -f -- "$temp"
        return 1
    fi
}

plan_save() {
    plan_write "$saved_plan" || return 1
    [[ -z $export_plan ]] || plan_write "$export_plan"
}

plan_load() {
    local file=$1 data chosen candidate old_profile=$profile old_settings=$settings address
    local -a addresses
    [[ -f $file && ! -L $file ]] && data=$(jq -ce -s '
        select(length == 1) | .[0] |
        def disk: . == null or (type == "object" and keys == ["disk","fs","part","uuid"]
            and all(.[]; type == "string" and length > 0));
        select(keys == ["dns","efi","firmware","profile","root","settings","version"]
          and .version == 1
          and (.profile | IN("thinkpad","macbook","vmware","vm"))
          and (.firmware | IN("none","live","archive","sonoma","ventura","monterey"))
          and (.dns | keys == ["addresses","mode"])
          and (.dns.mode | IN("system","yandex","cloudflare","google","custom"))
          and (.dns.addresses | type == "array" and length <= 3 and all(.[]; type == "string"))
          and (.dns.mode != "custom" or (.dns.addresses | length > 0))
          and (.root | disk) and (.efi | disk) and (.settings | type == "object"))
    ' "$file" 2>>"$log_file") || { fail 'Invalid or unreadable installation plan.'; return 1; }
    chosen=$(jq -r .profile <<< "$data")
    candidate=$(jq -c .settings <<< "$data")
    mapfile -t addresses < <(jq -r '.dns.addresses[]' <<< "$data")
    for address in "${addresses[@]}"; do
        valid_dns "$address" || { fail 'Invalid DNS address in saved plan.'; return 1; }
    done
    profile_load "$chosen" || return 1
    if ! settings=$(jq -ce --argjson candidate "$candidate" '
        def sameShape($source):
          type == ($source | type)
          and (if type == "object" then keys == ($source | keys)
            and all(to_entries[]; .key as $k | .value | sameShape($source[$k]))
            else true end);
        . as $defaults | $candidate |
        select(sameShape($defaults)
          and (.theme | IN("minegrub","world-selection","none"))
          and (.desktop.defaultSession == $defaults.desktop.defaultSession))
        ' <<< "$settings") || ! valid_identity || ! valid_timezone "$(jq -r .timezone <<< "$settings")"; then
        profile=$old_profile settings=$old_settings
        fail 'Saved settings do not match this installer version or contain invalid values.'
        return 1
    fi

    dns_mode=$(jq -r .dns.mode <<< "$data")
    custom_dns=("${addresses[@]}")
    firmware_mode=$(jq -r .firmware <<< "$data")
    firmware_archive=''
    root_ref=$(jq -c .root <<< "$data")
    esp_ref=$(jq -c .efi <<< "$data")
    storage_scan || return 1
    root_dev=$(storage_restore_partition "$root_ref") || root_dev=''
    esp_dev=$(storage_restore_partition "$esp_ref") || esp_dev=''
    if [[ ( $root_ref != null && -z $root_dev ) || ( $esp_ref != null && -z $esp_dev ) ]]; then
        printf 'Saved partition identity no longer matches. Select the missing partitions again.\n'
    elif [[ -n $root_dev && -n $esp_dev ]] && ! (hardware_check && storage_check && storage_mount_layout); then
        printf 'Saved partitions did not pass safety checks. Select both partitions again.\n'
        root_dev='' esp_dev=''
    fi
    [[ -n $root_dev ]] || root_ref=null
    [[ -n $esp_dev ]] || esp_ref=null
    printf 'Loaded plan from %s. Review the target before installation.\n' "$file"
}
