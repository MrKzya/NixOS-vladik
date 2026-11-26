#!/usr/bin/env bash
# shellcheck shell=bash

read_hardware() {
    local dmi=/sys/class/dmi/id
    vendor=$(cat "$dmi/sys_vendor" 2>/dev/null || :)
    model=$(cat "$dmi/product_name" 2>/dev/null || :)
    virtualization=$(systemd-detect-virt --vm 2>/dev/null || :)
    cpu=$(awk -F ': *' '/^model name/ { print $2; exit }' /proc/cpuinfo)
}

is_t2_macbook() {
    [[ $1 =~ ^MacBookAir(8,[12]|9,1)$ ||
       $1 =~ ^MacBookPro(15,[1-4]|16,[1-4])$ ]]
}

detect_profile() {
    local vendor=${1,,} model=$2 virtualization=$3
    if [[ $virtualization == vmware || $vendor == *vmware* ]]; then
        printf '%s\n' vmware
    elif [[ $virtualization == kvm || $virtualization == qemu || $vendor == *qemu* ]]; then
        printf '%s\n' vm
    elif [[ $vendor == *apple* ]] && is_t2_macbook "$model"; then
        printf '%s\n' macbook
    elif [[ $vendor == *lenovo* && ${model,,} == *thinkpad* ]]; then
        printf '%s\n' thinkpad
    fi
}

hardware_check() {
    if [[ $profile == macbook ]]; then
        [[ ${vendor,,} == *apple* ]] && is_t2_macbook "$model" ||
            { fail 'The macbook profile requires a supported Intel MacBook T2 model.'; return 1; }
    elif [[ ${vendor,,} == *apple* ]]; then
        fail 'Use the macbook profile on Apple hardware to enable EFI safety checks.'
        return 1
    fi
}
