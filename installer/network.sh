#!/usr/bin/env bash
# shellcheck shell=bash

valid_dns() {
    local addr=$1 original=$1 compressed=false base chunk
    if [[ $addr =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        local -a octets
        IFS=. read -r -a octets <<< "$addr"
        for chunk in "${octets[@]}"; do
            [[ $chunk == 0 || $chunk != 0* ]] && (( 10#$chunk <= 255 )) || return 1
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

route_interface() {
    local family=$1 destination=$2 route addresses device
    route=$(ip -j "-$family" route get "$destination" 2>/dev/null) || return 1
    device=$(jq -er '.[0] | select(.dev != "lo" and (.prefsrc // .src)) | .dev' <<< "$route") || return 1
    addresses=$(ip -j "-$family" address show dev "$device" 2>/dev/null) || return 1
    jq -e 'any(.[]; any(.flags[]; . == "UP") and any(.addr_info[]; .scope == "global"))' \
        <<< "$addresses" >/dev/null && printf '%s\n' "$device"
}

network_route() {
    local addresses
    ipv4_link=$(route_interface 4 1.1.1.1) || ipv4_link=''
    ipv6_link=$(route_interface 6 2606:4700:4700::1111) || ipv6_link=''
    link=${ipv4_link:-$ipv6_link}
    if [[ -n $link ]]; then
        printf 'Network routes: IPv4 %s, IPv6 %s.\n' "${ipv4_link:-unavailable}" "${ipv6_link:-unavailable}"
        return 0
    fi
    addresses=$(ip -j address show 2>/dev/null) || return 1
    if ! jq -e 'any(.[]; .ifname != "lo" and any(.flags[]; . == "LOWER_UP"))' <<< "$addresses" >/dev/null; then
        fail 'No active network link.'
    elif ! jq -e 'any(.[]; .ifname != "lo" and any(.addr_info[]; .scope == "global"))' <<< "$addresses" >/dev/null; then
        fail 'The network link has no routable IP address.'
    else
        fail 'No IPv4 or IPv6 route to the Internet.'
    fi
}

network_resolves() {
    local host
    for host in github.com raw.githubusercontent.com codeload.github.com cache.nixos.org; do
        printf 'Resolving %s\n' "$host"
        timeout "${dns_timeout:-15}" getent ahosts "$host" >/dev/null ||
            { fail "DNS resolution failed or timed out for $host."; return 1; }
    done
}

network_restore_dns() {
    if [[ -n ${dns_link:-} ]]; then
        if ! resolvectl dns "$dns_link" "${previous_dns[@]}" >>"$log_file" 2>&1; then
            fail "Could not restore DNS on $dns_link."
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

https_probe() {
    local url=$1 status=0 response trial family
    local -a families=()
    [[ -z ${ipv6_link:-} ]] || families+=(-6)
    [[ -z ${ipv4_link:-} ]] || families+=(-4)
    (( ${#families[@]} )) || families+=('')
    for ((trial=1; trial<=${https_attempts:-3}; trial++)); do
        for family in "${families[@]}"; do
            printf 'Checking %s %s (attempt %d/%d)\n' "${family:--auto}" "$url" "$trial" "${https_attempts:-3}"
            status=0
            response=$(curl ${family:+"$family"} --proto '=https' --proto-redir '=https' --head --location \
                --connect-timeout "${connect_timeout:-25}" --max-time "${https_timeout:-50}" \
                --silent --show-error --output /dev/null --write-out '%{http_code}' "$url" 2>>"$log_file") || status=$?
            printf '%s %s: HTTP %s, curl exit %s\n' "$family" "$url" "${response:-unknown}" "$status" >>"$log_file"
            if (( status == 0 )); then
                case "$response" in
                    2??) return 0 ;;
                    429|5??) status=22; break ;;
                    *) fail "HTTP $response from $url."; return 1 ;;
                esac
            fi
            (( status != 60 )) || break
        done
        (( status != 60 )) || break
        (( trial == ${https_attempts:-3} )) || sleep "$((2 * trial))"
    done
    case $status in
        5|6) fail "DNS resolution failed for $url" ;;
        35|51|58|59|60|77|82|83|90|91) fail "TLS verification or handshake failed for $url. Check the clock and certificates." ;;
        22) fail "HTTP error from $url. See the log for the response code." ;;
        7) fail "No connection to $url over the available IP routes." ;;
        28) fail "Connection to $url was too slow or timed out. Check the log to distinguish DNS from connection delays." ;;
        *) fail "Cannot reach $url (curl exit $status)." ;;
    esac
}

network_preflight() {
    local endpoint rev endpoints
    local -a servers=()
    network_route || return 1
    printf 'Checking DNS...\n'
    if ! network_resolves; then
        if "$dry_run"; then
            fail 'System DNS failed. DNS was not changed during the dry run.'
            return 1
        fi
        mapfile -t servers < <(dns_servers "$dns_mode")
        (( ${#servers[@]} )) || servers=(1.1.1.1 8.8.8.8)
        printf 'Trying temporary DNS on %s.\n' "$link"
        if ! network_try_dns "${servers[@]}"; then
            network_restore_dns || return 1
            fail 'DNS remains unavailable. Check the connection or choose a DNS provider.'
            return 1
        fi
    fi

    # Check the exact locked archive URLs with HEAD, without fetching the closures.
    endpoints=$(jq -er --arg profile "$profile" '
      .nodes | to_entries[] |
      select($profile == "macbook" or (.key | test("^(t2-kernel-|t2fanrd)") | not)) |
      .value.locked | select(.type == "github" and .rev != null) |
      "https://codeload.github.com/\(.owner)/\(.repo)/tar.gz/\(.rev)"
    ' "$source_dir/flake.lock") || return 1
    rev=$(jq -er '.nodes.nixpkgs.locked.rev' "$source_dir/flake.lock") || return 1
    https_probe "https://raw.githubusercontent.com/NixOS/nixpkgs/$rev/README.md" || return 1
    https_probe "https://cache.nixos.org/nix-cache-info" || return 1
    while IFS= read -r endpoint; do https_probe "$endpoint" || return 1; done <<< "$endpoints"
    if [[ $profile == macbook ]]; then
        https_probe "$cache_url/nix-cache-info" ||
            printf 'The public T2 cache is unavailable. Checking the local Nix store is still possible.\n'
    fi
}
