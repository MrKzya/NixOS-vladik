#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# This program handles the password through standard input only.
set +x
set -uo pipefail
umask 077
ulimit -c 0
export LC_ALL=C
export NIX_REMOTE=local

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) || exit 1

# shellcheck source=installer/hardware.sh
source "$source_dir/installer/hardware.sh"
# shellcheck source=installer/storage.sh
source "$source_dir/installer/storage.sh"
# shellcheck source=installer/network.sh
source "$source_dir/installer/network.sh"
# shellcheck source=installer/cache.sh
source "$source_dir/installer/cache.sh"
# shellcheck source=installer/configuration.sh
source "$source_dir/installer/configuration.sh"
# shellcheck source=installer/ui.sh
source "$source_dir/installer/ui.sh"

fail() {
    printf '%s\n' "$*" >&2
    return 1
}

nix_cmd() {
    nix --extra-experimental-features 'nix-command flakes' "$@"
}

run() {
    printf '\n[%s] %s\n' "$(date -Is)" "$*" >>"$log_file"
    "$@" >>"$log_file" 2>&1
}

retry() {
    local label=$1
    shift
    while true; do
        printf '%s\n' "$label"
        "$@" && return 0
        printf 'Этап завершился с ошибкой. Журнал: %s\n' "$log_file" >&2
        if [[ $1 == network_preflight ]]; then
            prompt 'Enter — повторить, d — параметры DNS, q — выйти из этапа.' || return 1
            if [[ $reply == d ]]; then
                network_restore_dns || return 1
                ui_dns || :
                continue
            fi
        elif [[ $1 == config_generate && $profile == macbook ]]; then
            prompt 'Enter — повторить, f — источник firmware, q — выйти из этапа.' || return 1
            if [[ $reply == f ]]; then
                ui_firmware || :
                continue
            fi
        else
            prompt 'Enter — повторить, q — выйти из этапа.' || return 1
        fi
        [[ -z $reply ]] || return 1
    done
}

release_mounts() {
    local index
    local -n mounts=$1
    for ((index=${#mounts[@]} - 1; index >= 0; index--)); do
        umount -- "${mounts[index]}" || return 1
        unset 'mounts[index]'
    done
}

cleanup() {
    local status=$?
    trap - EXIT
    unset password
    network_restore_dns || status=1
    release_mounts probe_mounts || status=1
    release_mounts owned_mounts || status=1
    if [[ -n ${work:-} && -d $work ]]; then
        printf 'Журнал: %s\n' "$log_file"
    fi
    return "$status"
}

probe_stage() {
    # A failed probe must release its own mounts before retrying the same stage.
    local rc=0
    storage_probe || rc=$?
    release_mounts probe_mounts || return 1
    return "$rc"
}

target_stage() {
    storage_open && config_save && cache_copy_kernel
}

system_stage() {
    storage_verify &&
    run nixos-install --root /mnt --flake "$target_flake" --no-update-lock-file \
        --no-channel-copy --no-root-passwd --no-bootloader "${install_opts[@]}"
}

boot_stage() {
    local system
    storage_check && storage_same_selection && storage_verify || return 1
    system=$(readlink /mnt/nix/var/nix/profiles/system) || return 1
    [[ $system =~ ^system-[0-9]+-link$ ]] || return 1
    system=$(readlink "/mnt/nix/var/nix/profiles/$system") || return 1
    [[ $system == /nix/store/* && -d /mnt$system ]] || return 1
    run nixos-install --root /mnt --system "$system" --no-channel-copy --no-root-passwd "${install_opts[@]}" &&
    storage_verify && [[ -s /mnt/boot/EFI/BOOT/BOOTX64.EFI && -s /mnt/boot/grub/grub.cfg ]] ||
        { fail 'Не подтверждены EFI fallback и меню GRUB на выбранном Linux ESP.'; return 1; }
}

password_stage() {
    local username
    username=$(jq -er .user <<< "$settings") || return 1
    storage_verify || return 1
    # Do not pass the password to run(), a child environment, a process argument or a file.
    if ! printf '%s:%s\n' "$username" "$password" |
        nixos-enter --root /mnt -- /run/current-system/sw/bin/chpasswd >>"$log_file" 2>&1; then
        fail 'Не удалось установить пароль пользователя.'
        return 1
    fi
    awk -F: -v name="$username" '$1 == name && $2 ~ /^\$/ { found = 1 } END { exit !found }' /mnt/etc/shadow ||
        { fail 'У установленной учётной записи не обнаружен хеш пароля.'; return 1; }
}

finish_stage() {
    storage_verify || return 1
    [[ ! -L /mnt/var && ! -L /mnt/var/log && ! -L /mnt/var/log/nixos-vladik-install.log ]] || return 1
    mkdir -p /mnt/var/log &&
    install -m 0600 "$log_file" /mnt/var/log/nixos-vladik-install.log &&
    sync -f /mnt &&
    sync -f /mnt/boot &&
    rm -- /mnt/.nixos-vladik-install &&
    sync -f /mnt
}

main() {
    dry_run=false
    case "${1:-}" in
        --dry-run) dry_run=true; shift ;;
        -h|--help)
            printf '%s\n' 'NixOS-vladik Installer' 'sudo bash install.sh [--dry-run]' \
                'Разметка GPT и форматирование выполняются до запуска. Установщик использует /mnt.'
            return 0 ;;
    esac
    (( $# == 0 )) || { fail 'Неизвестный аргумент. Доступен --help.'; return 2; }
    [[ $(uname -s) == Linux && $(uname -m) == x86_64 && -t 0 ]] ||
        { fail 'Требуется x86_64 Linux Live ISO и терминал. Для SSH используется ssh -t.'; return 1; }
    (( EUID == 0 )) || { fail 'Запуск из Live выполняется через sudo.'; return 1; }
    if ! "$dry_run" && [[ ! -d /sys/firmware/efi ]]; then
        fail 'Live ISO загружен в Legacy BIOS. Для установки EFI необходим UEFI.'
        return 1
    fi
    local command
    for command in git jq nix nix-store nixos-generate-config nixos-install nixos-enter lsblk findmnt \
        ip getent curl flock unshare tar; do
        command -v "$command" >/dev/null ||
            { fail "В Live ISO отсутствует $command. См. docs/INSTALLATION.md."; return 1; }
    done

    if ! "$dry_run" && [[ ${NIXOS_VLADIK_PRIVATE_MOUNTS:-} != 1 ]]; then
        export NIXOS_VLADIK_PRIVATE_MOUNTS=1
        exec unshare --mount --propagation private -- bash "$source_dir/install.sh"
    fi
    if ! "$dry_run"; then
        exec 9>/run/lock/nixos-vladik-install.lock
        flock -n 9 || { fail 'Установщик уже запущен.'; return 1; }
    fi

    unset password
    work=$(mktemp -d /run/nixos-vladik.XXXXXXXX) || return 1
    log_file=$work/install.log
    touch "$log_file" || return 1
    declare -ga probe_mounts=() owned_mounts=() custom_dns=() install_opts=() kernel_paths=() t2_options=()
    declare -gA profile_settings=()
    profile='' settings='' root_dev='' esp_dev='' dns_mode=system firmware_mode=none
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP

    if ! revision=$(git -c "safe.directory=$source_dir" -C "$source_dir" rev-parse HEAD 2>>"$log_file") ||
       ! [[ $(git -c "safe.directory=$source_dir" -C "$source_dir" branch --show-current) == installer ]] ||
       ! git -c "safe.directory=$source_dir" -C "$source_dir" diff --quiet HEAD; then
        fail 'Требуется чистая локальная копия ветки installer.'
        return 1
    fi
    cache_options && retry 'Подготовка локальной копии проекта' project_clone || return 1
    read_hardware
    printf 'Оборудование: %s %s\nCPU: %s\n' "$vendor" "$model" "$cpu"
    if ! "$dry_run" && ! network_resolves; then
        until network_preflight; do
            prompt 'Enter — параметры DNS, q — выход.' || return 1
            [[ -z $reply ]] || return 1
            ui_dns || :
        done
    fi
    ui_profile "$(detect_profile "$vendor" "$model" "$virtualization")" || return 1
    ui_menu || return 1
    "$dry_run" && return 0

    [[ $profile != macbook ]] || install_opts=("${t2_options[@]}")
    retry 'Проверка разделов и свободного места' probe_stage &&
    retry 'Проверка доступа к источникам Nix' network_preflight &&
    retry 'Генерация и вычисление конфигурации' config_generate &&
    retry 'Проверка готового ядра' cache_kernel &&
    retry 'Монтирование и сохранение конфигурации' target_stage &&
    retry 'Установка NixOS' system_stage &&
    retry 'Установка и проверка GRUB' boot_stage &&
    retry 'Настройка учётной записи' password_stage &&
    retry 'Проверка и завершение' finish_stage || return 1
    unset password
    network_restore_dns && release_mounts owned_mounts || return 1
    printf 'Установка завершена. Конфигурация: /etc/nixos/NixOS-vladik.\n'
    prompt 'Перезагрузить систему? [y/N]' || return 0
    if [[ $reply == y || $reply == Y ]]; then
        systemctl reboot
    fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
