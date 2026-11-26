#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR/../..
# Function mocks are called by the sourced installer.
# shellcheck disable=SC2329
set -eu -o pipefail

tests=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=install.sh
source "$tests/../../install.sh"

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
log_file=$work/log
touch "$log_file"
saved_plan=$work/saved.local.json
export_plan=$work/exported.local.json
declare -a custom_dns=() probe_mounts=()
if [[ $(uname -s) == Darwin ]]; then
    mv() {
        if [[ $1 == -fT ]]; then shift; command mv -f "$@";
        else command mv "$@"; fi
    }
fi

fail_test() {
    printf 'FAIL %s\n' "$*" >&2
    exit 1
}

reject() {
    if "$@" >/dev/null 2>&1; then fail_test "unexpected success: $*"; fi
}

# These helpers fail immediately if fixture tests try to touch the host.
mount() { fail_test 'mount called by fixture'; }
umount() { fail_test 'umount called by fixture'; }
nixos-install() { fail_test 'nixos-install called by fixture'; }
systemctl() { fail_test 'systemctl called by fixture'; }

printf 'Hardware detection\n'
[[ $(detect_profile 'Apple Inc.' 'MacBookAir9,1' none) == macbook ]]
[[ $(detect_profile LENOVO 'ThinkPad X1' none) == thinkpad ]]
[[ $(detect_profile '' '' vmware) == vmware ]]
[[ $(detect_profile '' '' kvm) == vm ]]
[[ -z $(detect_profile 'Apple Inc.' 'MacBookAir7,2' none) ]]
vendor='Apple Inc.' model='MacBookAir9,1' profile=vmware
reject hardware_check

printf 'Storage validation, Apple ESP, wrong mount, default Btrfs\n'
fixture=$(cat "$tests/disks.json")
lsblk() {
    if [[ $1 == -dnro ]]; then
        jq -r --arg name "${*: -1}" '.blockdevices[] | select(.name == $name) | ."maj:min"' <<< "$fixture"
    else printf '%s\n' "$fixture"; fi
}
dry_run=true
firmware_mode=none
profile=macbook
root_dev=/dev/nvme9n1p6
esp_dev=/dev/nvme9n1p7
storage_check
[[ $fs_type == btrfs && $apple_partuuid == 10000000-0000-0000-0000-000000000001 ]]
storage_scan
[[ $(storage_candidates root) == "$root_dev" ]]
revision="test"
mount_key=$(storage_selection)
root_ref=$(storage_partition_ref "$root_dev")
esp_ref=$(storage_partition_ref "$esp_dev")
esp_dev=/dev/nvme9n1p9
reject storage_check
esp_dev=/dev/nvme9n1p7
profile=thinkpad
reject storage_check
profile=macbook
fixture=$(jq '.blockdevices[4].mountpoints=["/tmp/elsewhere"]' "$tests/disks.json")
reject storage_check
fixture=$(jq '.blockdevices[4].fstype="ext4"' "$tests/disks.json")
storage_check
[[ $fs_type == ext4 ]]
fixture=$(jq '.blockdevices[4].size=1024' "$tests/disks.json")
reject storage_check
fixture=$(jq '.blockdevices[3].fsver="FAT16"' "$tests/disks.json")
reject storage_check
fixture=$(jq '.blockdevices += [(.blockdevices[3] + {name:"/dev/sdz1"})]' "$tests/disks.json")
reject storage_check
fixture=$(jq '.blockdevices[4].partuuid="20000000-0000-0000-0000-000000000004"' "$tests/disks.json")
storage_check
reject storage_same_selection
fixture=$(cat "$tests/disks.json")
storage_check
storage_same_selection
findmnt() { printf '%s\n' / /mnt/unrelated; }
reject storage_mount_layout
mount_source=$root_dev'[/]'
mount_root=/
mount_options=rw,subvolid=5,subvol=/
btrfs_devices=1
findmnt() {
    if [[ $1 == -lno ]]; then printf '%s\n' / /mnt /mnt/boot
    elif [[ $3 == /mnt ]]; then
        jq -n --arg source "$mount_source" --arg root "$mount_root" --arg options "$mount_options" \
            '{filesystems:[{source:$source,fstype:"btrfs",fsroot:$root,"fs-options":$options,"maj:min":"0:54"}]}'
    else
        jq -n --arg efi "$esp_dev" '{filesystems:[{source:$efi,fstype:"vfat",fsroot:"/","fs-options":"rw"}]}'
    fi
}
readlink() { printf '%s\n' "${*: -1}"; }
test() { if [[ $1 == -b ]]; then [[ $2 == /dev/nvme9n1p[679] ]]; else builtin test "$@"; fi; }
btrfs() { printf '\tTotal devices %d FS bytes used 1000\n' "$btrfs_devices"; }
storage_mount_layout
mount_source=/dev/nvme9n1p9
reject storage_mount_layout
mount_source=$root_dev
mount_root=/@home
reject storage_mount_layout
mount_root=/
mount_options=rw,subvolid=256,subvol=/
reject storage_mount_layout
mount_options=rw,subvolid=5,subvol=/
btrfs_devices=2
reject storage_mount_layout
(
    findmnt() { if [[ $1 == -lno ]]; then printf '/\n'; else return 1; fi; }
    mount() { printf '%s\n' "$*" > "$work/mount-args"; return 1; }
    reject storage_probe
    grep -F -- '-t btrfs -o ro,rescue=nologreplay,subvolid=5' "$work/mount-args" >/dev/null
)
(
    test() { return 1; }
    reject require_uefi
    test() { [[ $* == '-d /sys/firmware/efi' ]]; }
    require_uefi
)

printf 'DNS validation and failure paths\n'
valid_dns 1.1.1.1
valid_dns 2001:4860:4860::8888
valid_dns ::
reject valid_dns 256.1.1.1
reject valid_dns 2001:::1
reject valid_dns '1::2::3'
ip() { return 2; }
reject network_preflight
ip() {
    if [[ $3 == route ]]; then printf '%s\n' '[{"dev":"wlan-test","prefsrc":"10.0.0.1"}]'
    else printf '%s\n' '[{"flags":["UP"],"addr_info":[{"scope":"global"}]}]'; fi
}
timeout() { return 1; }
dns_mode=system
network_route
[[ $link == wlan-test ]]
if network_preflight 2> "$work/dns-dry-run"; then fail_test 'DNS failure accepted'; fi
grep -F 'DNS was not changed' "$work/dns-dry-run" >/dev/null
resolvectl() {
    if (( $# == 2 )); then printf 'Link 12 (%s): 10.0.0.1\n' "$link"
    else printf '%s\n' "$*" >> "$log_file"; fi
}
network_resolves() { return 0; }
network_try_dns 1.1.1.1
network_restore_dns
grep -Fx 'dns wlan-test 1.1.1.1' "$log_file" >/dev/null
grep -Fx 'dns wlan-test 10.0.0.1' "$log_file" >/dev/null

printf 'HTTPS diagnostics and board-specific firmware import\n'
curl() { return 60; }
if https_probe https://test.invalid 2> "$work/tls"; then fail_test 'TLS failure accepted'; fi
grep -F 'TLS verification' "$work/tls" >/dev/null
curl() { printf '404'; }
if https_probe https://test.invalid 2> "$work/http"; then fail_test 'HTTP error accepted'; fi
grep -F 'HTTP 404' "$work/http" >/dev/null
sleep() { printf 'sleep %s\n' "$*" >> "$work/curl-args"; }
curl() {
    printf '%s\n' "$*" >> "$work/curl-args"
    if [[ $1 == -6 ]]; then return 28; fi
    if [[ $(grep -c -- '^-4 ' "$work/curl-args") == 1 ]]; then printf '503'; else printf '200'; fi
}
https_probe https://test.invalid >/dev/null
[[ $(grep -c -- '^-6 ' "$work/curl-args") == 2 && $(grep -c -- '^-4 ' "$work/curl-args") == 2 ]]
grep -F -- '--connect-timeout 25 --max-time 50' "$work/curl-args" >/dev/null
grep -Fx 'sleep 2' "$work/curl-args" >/dev/null
mkdir "$work/broadcom"
printf 'test\n' > "$work/broadcom/brcmfmac4377b3-pcie.apple,formosa.bin"
printf 'test\n' > "$work/broadcom/brcmfmac4377b3-pcie.apple,formosa-xyz.txt"
printf 'test\n' > "$work/broadcom/brcmfmac4377b3-pcie.apple,wrong-board.txt"
printf 'test\n' > "$work/broadcom/brcmbt4377b3-apple,formosa.bin"
(cd "$work/broadcom" && tar -cf "$work/firmware.tar" .)
firmware_import "$work/firmware.tar" "$work/imported"
[[ -s $work/imported/brcmbt4377b3-apple,formosa.bin ]]
[[ ! -e $work/imported/brcmfmac4377b3-pcie.apple,wrong-board.txt ]]
rm -- "$work/broadcom/brcmfmac4377b3-pcie.apple,formosa-xyz.txt"
(cd "$work/broadcom" && tar -cf "$work/missing.tar" .)
reject firmware_import "$work/missing.tar" "$work/incomplete"

printf 'Interactive selection persists through menus and dry-run\n'
settings='{"hostname":"nixos-test","user":"emptyfixture","timezone":"UTC","locale":"en_US.UTF-8",
  "theme":"minegrub","desktop":{"niri":{"enable":true},"plasma":{"enable":false},
    "dms":{"enable":true},"vicinae":{"enable":true},"defaultSession":null},
  "components":{"apps":{"firefox":true},"gaming":{},"system":{},"hardware":{}}}'
declare -A profile_settings
nix_cmd() { fail_test 'profile should be loaded from saved options'; }
profile_settings[vmware]=${settings/minegrub/none}
ui_components <<< $'2\n1\n0\n0' >/dev/null
ui_desktop <<< '3' >/dev/null
jq -e '.components.apps.firefox == false and .desktop.niri.enable and .desktop.plasma.enable' \
    <<< "$settings" >/dev/null
profile_load vmware
[[ $(jq -r .theme <<< "$settings") == none ]]
profile_load macbook
[[ $(jq -r .components.apps.firefox <<< "$settings") == false ]]
findmnt() { printf '%s\n' /; }
getent() { return 2; }
ui_menu <<< '' > "$work/dry-run"
grep -F 'Dry run complete' "$work/dry-run" >/dev/null
grep -F 'compress=zstd:3,noatime' "$work/dry-run" >/dev/null
cmp "$saved_plan" "$export_plan"
settings=$(jq '.components.apps.firefox = true' <<< "$settings")
fixture=$(jq '.blockdevices[4].name = "/dev/nvme9n1p66"' "$tests/disks.json")
plan_load "$export_plan" >/dev/null
[[ $root_dev == /dev/nvme9n1p66 && $(jq -r .components.apps.firefox <<< "$settings") == false ]]
fixture=$(jq '.blockdevices[0].ptuuid = "20000000-0000-0000-0000-000000000000"' "$tests/disks.json")
plan_load "$export_plan" > "$work/changed-disk"
[[ -z $root_dev && -z $esp_dev ]]
grep -F 'Saved partition identity no longer matches' "$work/changed-disk" >/dev/null
jq '.settings.password="fixture"' "$export_plan" > "$work/invalid.json"
reject plan_load "$work/invalid.json"
fixture=$(cat "$tests/disks.json")
plan_load "$export_plan" >/dev/null
dry_run=false
(
    storage_check() { return 0; }
    storage_mount_layout() { return 0; }
    storage_check_refs() { return 0; }
    reject ui_confirm <<< 'install'
    ui_confirm <<< 'INSTALL' > "$work/confirmed"
    grep -F 'Type INSTALL to continue:' "$work/confirmed" >/dev/null
)

printf 'T2 cache gate and missing object\n'
: > "$log_file"
nix_cmd() {
    printf '%s\n' '{"version":"fixture","image":"/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-test-image","modules":"/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-test-modules","externalModules":[],"initrdModules":["apple-bce"]}'
}
cache_url=https://test.invalid
t2_options=(--option require-sigs true)
run() { printf '%s\n' "$*" >> "$log_file"; return 1; }
reject cache_kernel
grep -F -- '--option max-jobs 0 --option builders  --option fallback false' "$log_file" >/dev/null
run() { printf '%s\n' "$*" >> "$log_file"; }
kernel_has_bce() { [[ $1 == /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-test-modules ]]; }
cache_kernel >/dev/null
[[ ${#kernel_paths[@]} == 2 ]]

printf 'Retry and password handling\n'
attempts=0
transient() { attempts=$((attempts + 1)); (( attempts == 2 )); }
retry 'test' transient <<< '' >/dev/null 2>&1
[[ $attempts == 2 ]]
storage_verify() { return 0; }
nixos-enter() {
    local input
    [[ $* == '--root /mnt -- /run/current-system/sw/bin/chpasswd' ]]
    IFS= read -r input
    [[ $input == 'emptyfixture:private test password' ]]
}
awk() { [[ ${*: -1} == /mnt/etc/shadow ]]; }
: > "$log_file"
ui_password <<< $'private test password\nprivate test password' > "$work/password-ui"
plan_save
password_stage
reject grep -F 'private test password' "$log_file" "$work/password-ui" "$saved_plan" "$export_plan"
[[ $(bash "$source_dir/install.sh" --help) == *--dry-run* ]]

printf 'Retry download in the same target store\n'
progress_python=progress_fixture
target_flake=path:/mnt/etc/nixos/NixOS-vladik#vmware
connect_timeout=25
download_idle_timeout=90
install_started=$SECONDS
install_opts=()
attempts=0
progress_fixture() {
    [[ $NIX_CURL_FLAGS == *'--speed-time 90'* && ${*:6} == *'--root /mnt'* ]] || return 90
    printf '%s\n' "${*:6}" >> "$work/nix-attempts"
    attempts=$((attempts + 1))
    if (( attempts == 1 )); then
        touch "$3"
        printf '%s\n' 'curl: (28) Operation too slow' > "$4"
        return 17
    fi
}
system_stage > "$work/retry-ui" 2>&1
[[ $(sort -u "$work/nix-attempts" | wc -l) -eq 1 && $attempts == 2 ]]
grep -F 'Completed Nix store objects will be reused' "$work/retry-ui" >/dev/null

printf 'Installer fixtures passed.\n'
