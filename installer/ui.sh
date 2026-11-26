#!/usr/bin/env bash
# shellcheck shell=bash

prompt() {
    printf '%s ' "$1"
    IFS= read -r reply
}

select_item() {
    local label=$1 default=$2 index
    shift 2
    local -a choices=("$@")
    for index in "${!choices[@]}"; do
        printf '  %d. %s\n' "$((index + 1))" "${choices[index]}"
    done
    while prompt "$label [${default:-0}, 0 Back]"; do
        local choice=${reply:-${default:-0}}
        [[ $choice != 0 ]] || return 1
        if [[ $choice =~ ^[1-9][0-9]{0,3}$ ]] && (( choice <= ${#choices[@]} )); then
            selection=${choices[choice - 1]}
            return 0
        fi
        printf 'Choose a number from the list.\n'
    done
    return 1
}

profile_load() {
    local chosen=$1
    if [[ -z ${profile_settings[$chosen]+saved} ]]; then
        local defaults
        defaults=$(nix_cmd eval --json --no-update-lock-file "path:$work/repo#nixosConfigurations.$chosen" \
            --apply "$(<"$source_dir/installer/profile.nix")" 2>>"$log_file") ||
            { fail 'Could not load profile defaults. Check the network and log.'; return 1; }
        profile_settings[$chosen]=$defaults
    fi
    if [[ -n $profile ]]; then
        profile_settings[$profile]=$settings
    fi
    profile=$chosen
    settings=${profile_settings[$chosen]}
}

ui_profile() {
    local recommended=$1 index=0
    case "$recommended" in
        thinkpad) index=1 ;;
        macbook) index=2 ;;
        vmware) index=3 ;;
        vm) index=4 ;;
    esac
    printf 'Suggested profile: %s\n' "${recommended:-none}"
    select_item 'Hardware profile' "$index" thinkpad macbook vmware vm || return 1
    retry 'Load profile defaults' profile_load "$selection"
}

ui_partition() {
    local role=$1 current=$2 item index choice=0
    storage_scan || return 1
    storage_list
    local -a candidates=() visible=()
    mapfile -t candidates < <(storage_candidates "$role")
    for item in "${candidates[@]}"; do
        if [[ $role == EFI && $profile == macbook ]]; then
            local disk
            disk=$(part_info "$item" | jq -er .pkname) || continue
            mac_esp_identity "$disk" "$item" >/dev/null || continue
        fi
        visible+=("$item")
    done
    (( ${#visible[@]} )) || { fail 'No eligible partitions found.'; return 1; }
    for index in "${!visible[@]}"; do
        [[ ${visible[index]} != "$current" ]] || choice=$((index + 1))
    done
    if (( choice == 0 && ${#visible[@]} == 1 )); then
        choice=1
    elif [[ $choice == 0 && $role == root ]]; then
        local -a preferred
        mapfile -t preferred < <(jq -r '[.blockdevices[] | select(.type == "part" and .fstype == "btrfs" and (.ro | not))] | .[].name' <<< "$devices")
        if (( ${#preferred[@]} == 1 )); then
            for index in "${!visible[@]}"; do
                [[ ${visible[index]} != "${preferred[0]}" ]] || choice=$((index + 1))
            done
        fi
    fi
    if (( choice > 0 )); then
        printf 'Suggested %s partition: %s\n' "$role" "${visible[choice - 1]}"
    fi
    select_item "$role partition" "$choice" "${visible[@]}"
}

ui_desktop() {
    select_item 'Desktop environment' 0 'Niri + DMS' 'KDE Plasma' 'Niri + KDE Plasma' 'TTY' || return 0
    local niri=false plasma=false
    case "$selection" in
        'Niri + DMS') niri=true ;;
        'KDE Plasma') plasma=true ;;
        'Niri + KDE Plasma') niri=true; plasma=true ;;
    esac
    settings=$(jq --argjson n "$niri" --argjson p "$plasma" \
        '.desktop += {niri:{enable:$n},plasma:{enable:$p},defaultSession:null}' <<< "$settings")
}

component_value() {
    jq -r --arg group "${1%.*}" --arg name "${1#*.}" '
      if $group == "desktop" then .desktop[$name].enable
      else .components[$group][$name] end' <<< "$settings"
}

ui_components() {
    local mode=${1:-toggle} category group key label value index
    local -a groups=(Desktop Applications Terminal Development Gaming Hardware System Bootloader)
    local -a options keys
    while select_item 'Component category' 0 "${groups[@]}"; do
        category=$selection
        if [[ $category == Bootloader ]]; then
            [[ $mode != defer ]] || continue
            if select_item 'GRUB theme' 0 minegrub world-selection none; then
                settings=$(jq --arg theme "$selection" '.theme = $theme' <<< "$settings") || return 1
                plan_save || return 1
            fi
            continue
        fi
        while true; do
            options=() keys=()
            if [[ $category == Desktop && $mode == toggle ]]; then
                options+=('Choose Niri, KDE Plasma or TTY') keys+=(environment)
            fi
            while IFS='|' read -r group key label; do
                [[ $group == "$category" ]] || continue
                value=$(component_value "$key") || return 1
                [[ $value != null ]] || continue
                [[ $mode != defer || $value == true ]] || continue
                options+=("$label [$([[ $value == true ]] && printf on || printf off)]")
                keys+=("$key")
            done < "$source_dir/installer/components.tsv"
            if (( ${#options[@]} == 0 )); then
                printf 'No available components in this category.\n'
                break
            fi
            select_item "$category" 0 "${options[@]}" || break
            for index in "${!options[@]}"; do
                [[ ${options[index]} != "$selection" ]] || { key=${keys[index]}; break; }
            done
            if [[ $key == environment ]]; then
                ui_desktop || return 1
            else
                settings=$(jq --arg group "${key%.*}" --arg name "${key#*.}" '
                  if $group == "desktop" then .desktop[$name].enable |= not
                  else .components[$group][$name] |= not end' <<< "$settings") || return 1
                if [[ $mode == defer ]]; then
                    plan_save || return 1
                    printf 'Deferred %s. Re-enable it in hosts/%s/settings.local.json after boot.\n' "$key" "$profile"
                    return 0
                fi
            fi
            plan_save || return 1
        done
    done
    [[ $mode != defer ]]
}

valid_timezone() {
    [[ $1 == UTC ]] || { [[ $1 =~ ^[A-Za-z0-9_+/-]+$ && $1 != /* ]] &&
        timedatectl list-timezones | grep -Fx "$1" >/dev/null; }
}

valid_identity() {
    local host user locale
    host=$(jq -r .hostname <<< "$settings")
    user=$(jq -r .user <<< "$settings")
    locale=$(jq -r .locale <<< "$settings")
    [[ $host =~ ^[[:alnum:]]([[:alnum:]-]{0,61}[[:alnum:]])?$ &&
       $user =~ ^[a-z_][a-z0-9_-]{0,30}$ && $user != root && $user != nobody &&
       $locale =~ ^([a-z]{2,3}_[A-Z]{2}|C)\.UTF-8$ ]] ||
        { fail 'Invalid hostname, username or locale (example: en_US.UTF-8).'; return 1; }
    if getent passwd "$user" >/dev/null; then
        fail 'That username already exists in the Live ISO. Choose a different one.'
        return 1
    fi
}

ui_identity() {
    local key label current value
    for key in hostname user timezone locale; do
        current=$(jq -r --arg key "$key" '.[$key] // "UTC"' <<< "$settings") || return 1
        case "$key" in
            hostname) label='Hostname' ;;
            user) label='Username' ;;
            timezone) label='Time zone (example: Europe/Moscow)' ;;
            locale) label='Locale (example: en_US.UTF-8)' ;;
        esac
        prompt "$label [$current]" || return 1
        value=${reply:-$current}
        if [[ $key == timezone ]] && ! valid_timezone "$value"; then
            fail 'Unknown time zone.'
            continue
        fi
        settings=$(jq --arg key "$key" --arg value "$value" '.[$key] = $value' <<< "$settings") || return 1
    done
    valid_identity
}

ui_dns() {
    select_item 'DNS' 0 System Yandex Cloudflare Google Custom || return 0
    if [[ $selection == Custom ]]; then
        local address
        local -a entered
        prompt "Up to three IP addresses [${custom_dns[*]}]" || return 1
        if [[ -n $reply ]]; then
            read -r -a entered <<< "$reply"
            (( ${#entered[@]} && ${#entered[@]} <= 3 )) || { fail 'Enter one to three IP addresses.'; return 1; }
            for address in "${entered[@]}"; do
                valid_dns "$address" || { fail 'Invalid DNS address.'; return 1; }
            done
            custom_dns=("${entered[@]}")
        fi
        (( ${#custom_dns[@]} )) || return 0
    fi
    dns_mode=${selection,,}
}

ui_firmware() {
    select_item 'Firmware Broadcom' 0 live archive sonoma ventura monterey none || return 0
    if [[ $selection == archive ]]; then
        local archive
        prompt "Path to the t2linux archive or firmware directory [${firmware_archive:--}]" || return 1
        archive=${reply:-${firmware_archive:-}}
        [[ $archive == /* && -r $archive && ( -f $archive || -d $archive ) ]] ||
            { fail 'Enter an accessible absolute path.'; return 1; }
        firmware_archive=$archive
    fi
    firmware_mode=$selection
}

ui_plan() {
    local group key label value
    printf '\nInstallation plan\n'
    printf 'Hardware  %s %s\nProfile   %s\nRoot      %s (%s)\nEFI       %s (FAT32)\n' \
        "$vendor" "$model" "$profile" "$root_dev" "$fs_type" "$esp_dev" | ascii_text
    printf 'Root UUID %s\nEFI ID    %s\n' "$root_uuid" "$efi_partuuid"
    if [[ $fs_type == btrfs ]]; then
        printf 'Btrfs     compress=zstd:3,noatime\n'
    else
        printf 'ext4      Keep existing ext4. Btrfs is recommended for new disks.\n'
    fi
    if [[ $profile == macbook ]]; then
        printf 'Apple EFI %s\nFirmware  %s\n' "$apple_partuuid" "$firmware_mode"
    fi
    printf 'DNS       %s\n' "$dns_mode"
    jq -r '"Hostname  \(.hostname)\nUser      \(.user)\nTime zone \(.timezone)\nLocale    \(.locale)\nGRUB      \(.theme)",
      "Desktop   \([.desktop | select(.niri.enable or .plasma.enable) |
        (. | select(.niri.enable) | "Niri"), (. | select(.plasma.enable) | "Plasma")] |
        if length == 0 then "TTY" else join(", ") end)", "Enabled components"' <<< "$settings" || return 1
    while IFS='|' read -r group key label; do
        value=$(component_value "$key") || return 1
        if [[ $value == true ]]; then
            printf '  %-12s %s\n' "$group" "$label"
        fi
    done < "$source_dir/installer/components.tsv"
}

ui_password() {
    local confirm
    while true; do
        printf 'User password: '
        IFS= read -rs password || { unset password; return 1; }
        printf '\nRepeat password: '
        IFS= read -rs confirm || { unset password; return 1; }
        printf '\n'
        if [[ -n $password && $password == "$confirm" ]]; then return 0; fi
        unset password confirm
        fail 'Passwords are empty or do not match.'
    done
}

ui_confirm() {
    [[ -n $root_dev && -n $esp_dev ]] || { fail 'Select the root and EFI partitions.'; return 1; }
    hardware_check && valid_identity && storage_check && storage_check_refs && storage_mount_layout || return 1
    if ! "$dry_run" && [[ $profile == macbook && $firmware_mode == archive && -z ${firmware_archive:-} ]]; then
        fail 'Select the firmware archive path in Hardware before starting.'
        return 1
    fi
    ui_plan || return 1
    if "$dry_run"; then
        printf 'Dry run complete. Target disks and DNS were unchanged.\n'
        return 0
    fi
    prompt 'Type INSTALL to continue:' && [[ $reply == INSTALL ]] || return 1
    mount_key=$(storage_selection)
}

ui_menu() {
    while true; do
        plan_save || { fail 'Could not save the installation plan.'; return 1; }
        printf '\n%s | Root: %s | EFI: %s\n' "$profile" "${root_dev:--}" "${esp_dev:--}"
        printf '%s\n' '1 Hardware profile' '2 Root partition' '3 EFI partition' '4 Hostname, user, locale' \
            '5 Desktop environment' '6 Components and bootloader' '7 DNS and network check'
        [[ $profile != macbook ]] || printf '8 Broadcom firmware\n'
        printf '%s\n' 'Enter Review installation plan' 'q Quit'
        prompt 'Selection:' || return 1
        case "$reply" in
            1) ui_profile "$profile" || : ;;
            2) if ui_partition root "$root_dev"; then
                   root_ref=$(storage_partition_ref "$selection") && root_dev=$selection ||
                       { root_ref=null root_dev=''; fail 'The root disk has no unique GPT identity.'; }
               fi ;;
            3) if ui_partition EFI "$esp_dev"; then
                   esp_ref=$(storage_partition_ref "$selection") && esp_dev=$selection ||
                       { esp_ref=null esp_dev=''; fail 'The EFI disk has no unique GPT identity.'; }
               fi ;;
            4) ui_identity || : ;;
            5) ui_desktop || : ;;
            6) ui_components || : ;;
            7) ui_dns || :
               network_preflight || : ;;
            8) [[ $profile != macbook ]] || ui_firmware || : ;;
            q) return 1 ;;
            '') ui_confirm || continue
                "$dry_run" && return 0
                ui_password
                return $? ;;
            *) fail 'Invalid menu option.' ;;
        esac
    done
}
