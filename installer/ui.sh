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
    while prompt "$label [${default:-0}; 0 — назад]"; do
        local choice=${reply:-${default:-0}}
        [[ $choice != 0 ]] || return 1
        if [[ $choice =~ ^[1-9][0-9]{0,3}$ ]] && (( choice <= ${#choices[@]} )); then
            selection=${choices[choice - 1]}
            return 0
        fi
        printf 'Номер вне списка.\n'
    done
    return 1
}

profile_load() {
    local chosen=$1
    if [[ -z ${profile_settings[$chosen]+saved} ]]; then
        local defaults
        defaults=$(nix_cmd eval --json --no-update-lock-file "path:$work/repo#nixosConfigurations.$chosen" \
            --apply "$(<"$source_dir/installer/profile.nix")" 2>>"$log_file") ||
            { fail 'Не удалось прочитать параметры Flake. Проверьте сеть и журнал.'; return 1; }
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
    select_item 'Аппаратный профиль' "$index" thinkpad macbook vmware vm || return 1
    retry 'Чтение параметров профиля' profile_load "$selection"
}

ui_partition() {
    local role=$1 current=$2 item index choice=0
    storage_scan || return 1
    storage_list
    local -a candidates=() visible=()
    mapfile -t candidates < <(storage_candidates "$role")
    for item in "${candidates[@]}"; do
        if [[ $role == efi && $profile == macbook ]]; then
            local disk
            disk=$(part_info "$item" | jq -er .pkname) || continue
            mac_esp_identity "$disk" "$item" >/dev/null || continue
        fi
        visible+=("$item")
    done
    (( ${#visible[@]} )) || { fail 'Подходящих разделов нет.'; return 1; }
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
    select_item "Раздел $role" "$choice" "${visible[@]}"
}

ui_desktop() {
    select_item 'Графическое окружение' 0 'Niri + DMS' 'KDE Plasma' 'Niri + KDE Plasma' 'TTY' || return 0
    local niri=false plasma=false
    case "$selection" in
        'Niri + DMS') niri=true ;;
        'KDE Plasma') plasma=true ;;
        'Niri + KDE Plasma') niri=true; plasma=true ;;
    esac
    settings=$(jq --argjson n "$niri" --argjson p "$plasma" \
        '.desktop += {niri:{enable:$n},plasma:{enable:$p},defaultSession:null}' <<< "$settings")
}

ui_components() {
    local entry
    local -a entries
    while true; do
        mapfile -t entries < <(jq -r '
          (.components | to_entries[] | .key as $group | .value | to_entries[]
            | "\($group).\(.key) [\(if .value then "+" else "-" end)]"),
          (.desktop | to_entries[] | select(.key == "dms" or .key == "vicinae") |
            "desktop.\(.key) [\(if .value.enable then "+" else "-" end)]")' <<< "$settings")
        select_item 'Номер переключает компонент' 0 "${entries[@]}" || return 0
        entry=${selection%% *}
        settings=$(jq --arg group "${entry%.*}" --arg name "${entry#*.}" '
            if $group == "desktop" then .desktop[$name].enable |= not
            else .components[$group][$name] |= not end' <<< "$settings") || return 1
    done
}

valid_identity() {
    local host user locale
    host=$(jq -r .hostname <<< "$settings")
    user=$(jq -r .user <<< "$settings")
    locale=$(jq -r .locale <<< "$settings")
    [[ $host =~ ^[[:alnum:]]([[:alnum:]-]{0,61}[[:alnum:]])?$ &&
       $user =~ ^[a-z_][a-z0-9_-]{0,30}$ && $user != root && $user != nobody &&
       $locale =~ ^([a-z]{2,3}_[A-Z]{2}|C)\.UTF-8$ ]] ||
        { fail 'Некорректный hostname, логин или локаль (например ru_RU.UTF-8).'; return 1; }
    if getent passwd "$user" >/dev/null; then
        fail 'Это имя уже используется в Live. Выберите отдельное имя пользователя.'
        return 1
    fi
}

ui_identity() {
    local key label current value
    for key in hostname user timezone locale; do
        current=$(jq -r --arg key "$key" '.[$key] // "UTC"' <<< "$settings") || return 1
        case "$key" in
            hostname) label='Имя компьютера' ;;
            user) label='Имя пользователя' ;;
            timezone) label='Часовой пояс, например Europe/Moscow' ;;
            locale) label='Локаль, например ru_RU.UTF-8' ;;
        esac
        prompt "$label [$current]" || return 1
        value=${reply:-$current}
        if [[ $key == timezone ]] && ! { [[ $value == UTC ]] ||
            { [[ $value =~ ^[A-Za-z0-9_+/-]+$ && $value != /* ]] &&
                timedatectl list-timezones | grep -Fx "$value" >/dev/null; }; }; then
            fail 'Неизвестный часовой пояс.'
            continue
        fi
        settings=$(jq --arg key "$key" --arg value "$value" '.[$key] = $value' <<< "$settings") || return 1
    done
    valid_identity
}

ui_dns() {
    select_item 'DNS' 0 system yandex cloudflare google custom || return 0
    if [[ $selection == custom ]]; then
        local address
        local -a entered
        prompt "До трёх IP-адресов через пробел [${custom_dns[*]}]" || return 1
        if [[ -n $reply ]]; then
            read -r -a entered <<< "$reply"
            (( ${#entered[@]} && ${#entered[@]} <= 3 )) || { fail 'Ожидалось от одного до трёх IP-адресов.'; return 1; }
            for address in "${entered[@]}"; do
                valid_dns "$address" || { fail "Некорректный DNS: $address"; return 1; }
            done
            custom_dns=("${entered[@]}")
        fi
        (( ${#custom_dns[@]} )) || return 0
    fi
    dns_mode=$selection
}

ui_plan() {
    printf '\nПлан установки\n'
    printf 'Модель   %s %s\nПрофиль  %s\nКорень   %s (%s)\nESP      %s (FAT32)\n' \
        "$vendor" "$model" "$profile" "$root_dev" "$fs_type" "$esp_dev"
    printf 'UUID     %s\nESP ID   %s\n' "$root_uuid" "$efi_partuuid"
    if [[ $fs_type == btrfs ]]; then
        printf 'Btrfs    compress=zstd:3,noatime\n'
    else
        printf 'Ext4     Будет сохранён. Рекомендуемый вариант для новой установки — Btrfs.\n'
    fi
    if [[ $profile == macbook ]]; then
        printf 'Apple ESP  %s\nFirmware   %s\n' "$apple_partuuid" "$firmware_mode"
    fi
    printf 'DNS       %s\n' "$dns_mode"
    jq -r '"Хост      \(.hostname)\nЛогин     \(.user)\nПояс      \(.timezone // "UTC")\nЛокаль    \(.locale)\nТема GRUB \(.theme)",
      "Сеансы    \([.desktop | select(.niri.enable or .plasma.enable) |
        (. | select(.niri.enable) | "Niri"), (. | select(.plasma.enable) | "Plasma")] |
        if length == 0 then "TTY" else join(", ") end)",
      "Компоненты",
      (.desktop | select(.niri.enable) | ["DMS", .dms.enable, "Vicinae", .vicinae.enable] | @tsv),
      (.components | to_entries[] | .key as $group | .value |
        "\($group)  \([to_entries[]|select(.value)|.key] | join(", "))")' <<< "$settings"
}

ui_password() {
    local confirm
    while true; do
        printf 'Пароль пользователя: '
        IFS= read -rs password || return 1
        printf '\nПовтор пароля: '
        IFS= read -rs confirm || return 1
        printf '\n'
        if [[ -n $password && $password == "$confirm" ]]; then
            return 0
        fi
        unset password confirm
        fail 'Пароль пустой или значения различаются.'
    done
}

ui_menu() {
    while true; do
        printf '\n%s · корень %s · ESP %s\n' "$profile" "${root_dev:-—}" "${esp_dev:-—}"
        printf '%s\n' '1 Профиль' '2 Корневой раздел' '3 EFI-раздел' '4 Хост, пользователь, локаль' \
            '5 Графическое окружение' '6 Компоненты' '7 Тема GRUB' '8 DNS и проверка сети'
        [[ $profile != macbook ]] || printf '9 Firmware Broadcom\n'
        printf '%s\n' 'Enter Просмотр плана' 'q Выход'
        prompt 'Выбор' || return 1
        case "$reply" in
            1) ui_profile "$profile" || : ;;
            2) if ui_partition root "$root_dev"; then root_dev=$selection; fi ;;
            3) if ui_partition efi "$esp_dev"; then esp_dev=$selection; fi ;;
            4) ui_identity || : ;;
            5) ui_desktop || : ;;
            6) ui_components || : ;;
            7) if select_item 'Тема GRUB' 0 minegrub world-selection none; then
                   settings=$(jq --arg theme "$selection" '.theme = $theme' <<< "$settings") || return 1
               fi ;;
            8) ui_dns || :
               network_preflight || : ;;
            9) if [[ $profile == macbook ]] &&
                  select_item 'Firmware Broadcom (Live или образ Recovery)' 0 live sonoma ventura monterey none; then
                   firmware_mode=$selection
               fi ;;
            q) return 1 ;;
            '')
                [[ -n $root_dev && -n $esp_dev ]] || { fail 'Выберите оба раздела.'; continue; }
                hardware_check && valid_identity && storage_check && storage_mount_layout || continue
                ui_plan || return 1
                if "$dry_run"; then
                    printf 'Dry-run завершён. Разделы и DNS не изменены.\n'
                    return 0
                fi
                prompt 'Для начала установки введите УСТАНОВИТЬ. Enter — вернуться в меню.' || return 1
                [[ $reply == УСТАНОВИТЬ ]] || continue
                mount_key=$(storage_selection)
                ui_password
                return $? ;;
            *) fail 'Неизвестный пункт.' ;;
        esac
    done
}
