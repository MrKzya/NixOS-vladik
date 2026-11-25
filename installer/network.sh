#!/usr/bin/env bash
# shellcheck shell=bash

valid_dns() {
    local addr=$1 original=$1 compressed=false base chunk
    if [[ $addr =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        local -a octets
        IFS=. read -r -a octets <<< "$addr"
        for chunk in "${octets[@]}"; do
            [[ ($chunk == 0 || $chunk != 0*) && 10#$chunk -le 255 ]] || return 1
        done
        return 0
    fi
    [[ $addr == *:* && $addr != *:::* && $addr =~ ^[[:xdigit:]:]+$ ]] || return 1
    if [[ $addr == *::* ]]; then
        compressed=true
        base=${addr#*::}
        [[ $base != *::* ]] || return 1
        addr=${addr%%::*}:${base}
    elif [[ $addr == :* || $addr == *: ]]; then
        return 1
    fi
    addr=${addr#:}
    addr=${addr%:}
    local -a groups
    IFS=: read -r -a groups <<< "$addr"
    for chunk in "${groups[@]}"; do
        [[ $chunk =~ ^[[:xdigit:]]{1,4}$ ]] || return 1
    done
    if "$compressed"; then
        [[ ${#groups[@]} -lt 8 && $original == *::* ]]
    else
        [[ ${#groups[@]} == 8 ]]
    fi
}

dns_servers() {
    case "$1" in
        system) ;;
        yandex) printf '%s\n' 77.88.8.8 77.88.8.1 ;;
        cloudflare) printf '%s\n' 1.1.1.1 1.0.0.1 ;;
        google) printf '%s\n' 8.8.8.8 8.8.4.4 ;;
        custom) printf '%s\n' "${custom_dns[@]}" ;;
    esac
}

network_route() {
    local route destination addresses
    for destination in 1.1.1.1 2606:4700:4700::1111; do
        route=$(ip -j route get "$destination" 2>/dev/null) || continue
        link=$(jq -er '.[0] | select(.dev != "lo" and (.prefsrc // .src)) | .dev' <<< "$route") || continue
        addresses=$(ip -j address show dev "$link" 2>/dev/null) || continue
        if jq -e 'any(.[]; (any(.flags[]; . == "UP")) and
            (any(.addr_info[]; .scope == "global")))' <<< "$addresses" >/dev/null; then
            return 0
        fi
    done
    fail 'Не найден интерфейс с IP-адресом и маршрутом в интернет. Проверьте подключение Live ISO.'
}

network_resolves() {
    local host
    for host in github.com raw.githubusercontent.com cache.nixos.org; do
        timeout 5 getent ahosts "$host" >/dev/null || return 1
    done
}

network_restore_dns() {
    if [[ -n ${dns_link:-} ]]; then
        if ! resolvectl dns "$dns_link" "${previous_dns[@]}" >>"$log_file" 2>&1; then
            fail "Не удалось восстановить DNS для интерфейса $dns_link."
            return 1
        fi
        dns_link=''
    fi
    if [[ -n ${dns_mount:-} ]]; then
        umount -- "$dns_mount" || return 1
        dns_mount=''
    fi
}

network_try_dns() {
    local active
    local -a servers=("$@")
    network_restore_dns || return 1
    if command -v resolvectl >/dev/null && active=$(resolvectl dns "$link" 2>/dev/null); then
        read -r -a previous_dns <<< "${active#*:}"
        # An empty argument resets only the DNS list for this link, not other settings.
        (( ${#previous_dns[@]} )) || previous_dns=("")
        dns_link=$link
        resolvectl dns "$link" "${servers[@]}" >>"$log_file" 2>&1 || return 1
    else
        active=$(readlink -e /etc/resolv.conf) || return 1
        [[ -f $active ]] || return 1
        printf 'nameserver %s\n' "${servers[@]}" > "$work/resolv.conf" || return 1
        mount --bind "$work/resolv.conf" "$active" || return 1
        dns_mount=$active
    fi
    network_resolves
}

network_preflight() {
    local endpoint rev
    local -a servers=()
    network_route || return 1
    if ! network_resolves; then
        if "$dry_run"; then
            fail 'Системный DNS не отвечает. В dry-run DNS не меняется.'
            return 1
        fi
        mapfile -t servers < <(dns_servers "$dns_mode")
        (( ${#servers[@]} )) || servers=(1.1.1.1 8.8.8.8)
        printf 'Проверка временного DNS на %s.\n' "$link"
        if ! network_try_dns "${servers[@]}"; then
            network_restore_dns || return 1
            fail 'DNS недоступен. Проверьте подключение либо выберите DNS в меню.'
            return 1
        fi
    fi

    rev=$(jq -er '.nodes.nixpkgs.locked.rev' "$source_dir/flake.lock") || return 1
    local -a endpoints=(
        "https://github.com/"
        "https://raw.githubusercontent.com/NixOS/nixpkgs/$rev/README.md"
        "https://codeload.github.com/"
        "https://cache.nixos.org/nix-cache-info"
    )
    for endpoint in "${endpoints[@]}"; do
        # codeload's root redirects or responds without a tarball; metadata below checks the actual inputs.
        if ! curl --proto '=https' --proto-redir '=https' --location --max-time 15 --retry 1 \
            --fail --silent --show-error --output /dev/null "$endpoint" >>"$log_file" 2>&1; then
            fail "HTTPS недоступен: $endpoint"
            return 1
        fi
    done
    if [[ $profile == macbook ]]; then
        curl --proto '=https' --fail --silent --show-error --max-time 8 \
            --output /dev/null "$cache_url/nix-cache-info" >>"$log_file" 2>&1 ||
            printf 'Публичный кеш T2 недоступен. Будет проверен локальный Nix Store.\n'
    fi
}
