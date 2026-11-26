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
# shellcheck source=installer/plan.sh
source "$source_dir/installer/plan.sh"
# shellcheck source=installer/ui.sh
source "$source_dir/installer/ui.sh"

fail() {
    printf '%s\n' "$*" >&2
    if [[ -n ${log_file:-} ]]; then printf '%s\n' "$*" >>"$log_file"; fi
    return 1
}

ascii_text() { tr -cd '\11\12\40-\176'; }

nix_cmd() {
    nix --extra-experimental-features 'nix-command flakes' "$@"
}

run() {
    printf '\n[%s] %s\n' "$(date -Is)" "$*" >>"$log_file"
    "$@" >>"$log_file" 2>&1
}

stage_error() {
    local label=$1 rc=$2 start=$3 details
    printf '[FAIL] %s (exit %s). Full log: %s\n' "$label" "$rc" "$log_file" >&2
    details=$(tail -n "+$((start+1))" "$log_file" | grep -Ev '^(@nix |$)' | tail -n 10) || :
    if [[ -s $work/build-errors && $label == 'Install NixOS' ]]; then
        tail -n 8 "$work/build-errors" | ascii_text >&2
    elif [[ -n $details ]]; then
        printf '%s\n' "$details" | ascii_text >&2
    fi
}

retry() {
    local label=$1 rc start
    shift
    while true; do
        printf '[RUN] %s\n' "$label"
        start=$(wc -l < "$log_file")
        rc=0
        "$@" || rc=$?
        if (( rc == 0 )); then
            printf '[OK] %s\n' "$label"
            return 0
        fi
        (( rc != 130 )) || exit 130
        stage_error "$label" "$rc" "$start"
        case "$1" in
            network_preflight)
                prompt 'Enter Retry | d DNS settings | q Quit' || return 1
                if [[ $reply == d ]]; then
                    network_restore_dns && ui_dns && plan_save || return 1
                    continue
                fi ;;
            config_generate)
                prompt 'Enter Retry | f MacBook firmware source | q Quit' || return 1
                if [[ $reply == f && $profile == macbook ]]; then
                    ui_firmware && plan_save || return 1
                    continue
                fi ;;
            system_stage)
                prompt 'Enter Retry | c Change components | d Defer component | q Quit' || return 1
                if [[ $reply == c || $reply == d ]]; then
                    if [[ $reply == d ]]; then ui_components defer || continue
                    else ui_components || return 1; fi
                    while ! ui_confirm; do
                        prompt 'Enter Review again | q Quit' && [[ -z $reply ]] || return 1
                    done
                    plan_save && retry 'Regenerate configuration' config_generate &&
                        retry 'Verify prebuilt kernel' cache_kernel &&
                        retry 'Update target configuration' target_stage || return 1
                    continue
                fi ;;
            *) prompt 'Enter Retry | q Quit' || return 1 ;;
        esac
        [[ -z $reply ]] || return "$rc"
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
        printf 'Full log: %s\n' "$log_file"
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

progress_runtime() {
    local path
    if command -v python3 >/dev/null; then
        progress_python=$(command -v python3)
    else
        path=$(nix_cmd build --print-out-paths --out-link "$work/progress-python" \
            --inputs-from "path:$work/repo" --no-update-lock-file nixpkgs#python3 2>>"$log_file") || return 1
        progress_python=$path/bin/python3
    fi
    [[ -x $progress_python ]]
}

system_stage() {
    local attempt rc marker=$work/download-failure
    storage_verify || return 1
    for attempt in 1 2 3; do
        rm -f -- "$marker" "$work/build-errors" || return 1
        rc=0
        # Nix applies the first three options to substituters. fetchurl receives the
        # curl speed guard through its declared NIX_CURL_FLAGS impure environment.
        NIX_CURL_FLAGS="--connect-timeout $connect_timeout --speed-limit 1 --speed-time $download_idle_timeout --retry 2 --retry-delay 3 --retry-max-time 300" \
            "$progress_python" "$source_dir/installer/progress.py" "$log_file" "$marker" \
            "$work/build-errors" "$((SECONDS - install_started))" \
            nixos-install --root /mnt --flake "$target_flake" --no-update-lock-file \
            --log-format internal-json --option stalled-download-timeout "$download_idle_timeout" \
            --option connect-timeout "$connect_timeout" --option download-attempts 3 \
            --no-channel-copy --no-root-passwd --no-bootloader "${install_opts[@]}" || rc=$?
        (( rc != 0 )) || return 0
        [[ -f $marker ]] && (( attempt < 3 && rc != 130 )) || return "$rc"
        stage_error 'Install NixOS' "$rc" "$(wc -l < "$log_file")"
        printf 'Retrying failed download (%d/3). Completed Nix store objects will be reused.\n' "$((attempt+1))"
        sleep "$((attempt*3))"
    done
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
        { fail 'EFI fallback loader or GRUB menu is missing from the selected Linux EFI partition.'; return 1; }
}

password_stage() {
    local username
    username=$(jq -er .user <<< "$settings") || return 1
    storage_verify || return 1
    # Do not pass the password to run(), a child environment, a process argument or a file.
    if ! printf '%s:%s\n' "$username" "$password" |
        nixos-enter --root /mnt -- /run/current-system/sw/bin/chpasswd >/dev/null 2>&1; then
        fail 'Could not set the user password.'
        return 1
    fi
    awk -F: -v name="$username" '$1 == name && $2 ~ /^\$/ { found = 1 } END { exit !found }' /mnt/etc/shadow ||
        { fail 'The installed account has no password hash.'; return 1; }
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

require_uefi() {
    test -d /sys/firmware/efi || fail 'Legacy BIOS detected. Boot the Live ISO in UEFI mode.'
}

main() {
    local -a original_args=("$@")
    local requested_plan='' fresh_plan=false recommendation='' command path timeout_value
    dry_run=false export_plan=''
    while (( $# )); do
        case "$1" in
            --dry-run) dry_run=true ;;
            --new-plan) fresh_plan=true ;;
            --plan|--export-plan)
                (( $# > 1 )) || { fail "Missing path after $1."; return 2; }
                [[ ! -L $2 ]] || { fail 'Choose a plan path that is not a symbolic link.'; return 2; }
                path=$(readlink -m -- "$2") || return 2
                if [[ $1 == --plan ]]; then requested_plan=$path; else export_plan=$path; fi
                shift ;;
            -h|--help)
                printf '%s\n' 'NixOS-vladik Installer' \
                    'sudo bash install.sh [--dry-run] [--plan FILE | --new-plan] [--export-plan FILE]' \
                    'Prepare GPT partitions and filesystems before starting. The installer uses /mnt.'
                return 0 ;;
            *) fail 'Unknown argument. See --help.'; return 2 ;;
        esac
        shift
    done
    [[ -z $requested_plan || $fresh_plan == false ]] ||
        { fail 'Choose either --plan or --new-plan.'; return 2; }
    case "$export_plan" in
        /mnt|/mnt/*) fail 'Export the plan outside /mnt.'; return 2 ;;
    esac
    [[ $(uname -s) == Linux && $(uname -m) == x86_64 && -t 0 ]] ||
        { fail 'Use an x86_64 Linux Live ISO and a terminal. For SSH, use ssh -t.'; return 1; }
    require_uefi || return 1
    (( EUID == 0 )) || { fail 'Run the installer with sudo.'; return 1; }

    for command in git jq nix nix-store nixos-generate-config nixos-install nixos-enter lsblk findmnt \
        ip getent curl flock unshare tar btrfs; do
        command -v "$command" >/dev/null ||
            { fail "Missing Live ISO command: $command. See docs/INSTALLATION.md."; return 1; }
    done
    dns_timeout=${NIXOS_VLADIK_DNS_TIMEOUT:-15}
    connect_timeout=${NIXOS_VLADIK_CONNECT_TIMEOUT:-25}
    https_timeout=${NIXOS_VLADIK_HTTPS_TIMEOUT:-50}
    https_attempts=${NIXOS_VLADIK_HTTPS_ATTEMPTS:-3}
    download_idle_timeout=${NIXOS_VLADIK_DOWNLOAD_IDLE_TIMEOUT:-90}
    for timeout_value in "$dns_timeout" "$connect_timeout" "$https_timeout" "$https_attempts" "$download_idle_timeout"; do
        [[ $timeout_value =~ ^[1-9][0-9]{0,3}$ ]] ||
            { fail 'Timeouts and retry counts must be positive integers.'; return 2; }
    done

    if ! "$dry_run" && [[ ${NIXOS_VLADIK_PRIVATE_MOUNTS:-} != 1 ]]; then
        export NIXOS_VLADIK_PRIVATE_MOUNTS=1
        exec unshare --mount --propagation private -- bash "$source_dir/install.sh" "${original_args[@]}"
    fi
    exec 9>/run/lock/nixos-vladik-install.lock || return 1
    flock -n 9 || { fail 'The installer is already running.'; return 1; }

    unset password
    work=$(mktemp -d /run/nixos-vladik.XXXXXXXX) || return 1
    log_file=$work/install.log
    saved_plan=/run/nixos-vladik-plan.local.json
    touch "$log_file" || return 1
    declare -ga probe_mounts=() owned_mounts=() custom_dns=() install_opts=() kernel_paths=() t2_options=()
    declare -gA profile_settings=()
    profile='' settings='' root_dev='' esp_dev='' root_ref=null esp_ref=null dns_mode=system firmware_mode=none
    dns_link='' dns_mount='' firmware_archive=''
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP

    if ! revision=$(git -c "safe.directory=$source_dir" -C "$source_dir" rev-parse HEAD 2>>"$log_file") ||
       ! [[ $(git -c "safe.directory=$source_dir" -C "$source_dir" branch --show-current) == installer ]] ||
       ! git -c "safe.directory=$source_dir" -C "$source_dir" diff --quiet HEAD; then
        fail 'Use a clean checkout of the installer branch.'
        return 1
    fi
    printf 'NixOS-vladik - Installation\nFull log: %s (tail -f from another terminal).\n' "$log_file"
    cache_options && retry 'Prepare project checkout' project_clone || return 1
    read_hardware
    printf 'Hardware: %s %s\nCPU: %s\n' "$vendor" "$model" "$cpu" | ascii_text
    recommendation=$(detect_profile "$vendor" "$model" "$virtualization")
    printf '[OK] Hardware detection (suggested profile: %s)\n' "${recommendation:-none}"
    if ! "$dry_run"; then
        printf 'Checking DNS...\n'
        if ! network_resolves; then
            until network_preflight; do
                prompt 'Enter DNS settings | q Quit' && [[ -z $reply ]] || return 1
                ui_dns || :
            done
        fi
    fi
    if [[ -n $requested_plan ]]; then
        plan_load "$requested_plan" || return 1
    elif ! "$fresh_plan" && [[ -f $saved_plan ]]; then
        prompt 'Resume the saved plan? [Y/n]' || return 1
        if [[ $reply != [nN] ]]; then plan_load "$saved_plan" || return 1; fi
    fi
    [[ -n $profile ]] || ui_profile "$recommendation" || return 1
    ui_menu || return 1
    "$dry_run" && return 0

    install_started=$SECONDS
    [[ $profile != macbook ]] || install_opts=("${t2_options[@]}")
    retry 'Verify partitions and free space' probe_stage &&
    retry 'Check Nix sources and network' network_preflight &&
    retry 'Prepare progress monitor' progress_runtime &&
    retry 'Generate and evaluate configuration' config_generate &&
    retry 'Verify prebuilt kernel' cache_kernel &&
    retry 'Mount partitions and save configuration' target_stage &&
    retry 'Install NixOS' system_stage &&
    retry 'Install and verify GRUB' boot_stage &&
    retry 'Set up user account' password_stage &&
    retry 'Final verification' finish_stage || return 1
    unset password
    network_restore_dns && release_mounts owned_mounts || return 1
    printf 'Installation complete. Configuration: /etc/nixos/NixOS-vladik.\n'
    prompt 'Reboot now? [y/N]' || return 0
    if [[ $reply == y || $reply == Y ]]; then systemctl reboot; fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
