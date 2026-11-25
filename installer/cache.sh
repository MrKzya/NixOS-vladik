#!/usr/bin/env bash
# shellcheck shell=bash

cache_options() {
    cache_url=$(nix_cmd eval --raw --file "$source_dir/modules/hardware/t2-cache.nix" url) &&
    cache_key=$(nix_cmd eval --raw --file "$source_dir/modules/hardware/t2-cache.nix" key) || return 1
    t2_options=(--option require-sigs true --option extra-substituters "$cache_url"
        --option extra-trusted-public-keys "$cache_key")
}

cache_kernel() {
    local report path
    [[ $profile == macbook ]] || return 0
    report=$(nix_cmd eval --json --no-update-lock-file "path:$work/repo#nixosConfigurations.$profile" \
        --apply "$(<"$source_dir/installer/cache.nix")" 2>>"$log_file") || return 1
    jq -e '.initrdModules | index("apple-bce") != null' <<< "$report" >/dev/null ||
        { fail 'Выбранное ядро T2 не соответствует initrd с apple-bce.'; return 1; }
    mapfile -t kernel_paths < <(jq -r '[.image, .modules] + .externalModules | unique[]' <<< "$report")
    for path in "${kernel_paths[@]}"; do
        [[ $path =~ ^/nix/store/[a-z0-9]{32}-[^/]+$ ]] || return 1
        if ! run nix-store --realise "$path" --indirect --add-root "$work/${path##*/}" \
                --option max-jobs 0 --option builders '' --option fallback false "${t2_options[@]}"; then
            fail "Готовый объект T2 недоступен: $path. Сборка ядра отключена."
            return 1
        fi
    done
    path=$(jq -er .modules <<< "$report") || return 1
    kernel_has_bce "$path" || { fail 'В полученном дереве модулей отсутствует apple-bce.'; return 1; }
    printf 'Ядро T2 %s и модули доступны в Live Store.\n' "$(jq -r .version <<< "$report")"
}

kernel_has_bce() {
    local module
    module=$(find "$1/lib/modules" -name 'apple-bce.ko*' -print -quit) || return 1
    [[ -n $module ]] || grep -Eq '/apple[-_]bce\.ko$' "$1"/lib/modules/*/modules.builtin
}

cache_copy_kernel() {
    local path
    [[ $profile == macbook ]] || return 0
    run nix_cmd copy --to /mnt "${t2_options[@]}" "${kernel_paths[@]}" || return 1
    # Kernel builds in nixos-install are unnecessary once these paths are valid in its store.
    for path in "${kernel_paths[@]}"; do
        run nix-store --store /mnt --check-validity "$path" || return 1
    done
}
