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
lsblk() { printf '%s\n' "$fixture"; }
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
findmnt() {
    if [[ ${1:-} == -lno ]]; then printf '%s\n' / /mnt /mnt/boot
    elif [[ ${*: -1} == /mnt ]]; then printf '%s\n' '259:6 btrfs /'
    else printf '%s\n' '259:7 vfat /'; fi
}
storage_mount_layout

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
    if [[ $2 == route ]]; then printf '%s\n' '[{"dev":"wlan-test","prefsrc":"10.0.0.1"}]'
    else printf '%s\n' '[{"flags":["UP"],"addr_info":[{"scope":"global"}]}]'; fi
}
timeout() { return 1; }
dns_mode=system
network_route
[[ $link == wlan-test ]]
if network_preflight 2> "$work/dns-dry-run"; then fail_test 'DNS failure accepted'; fi
grep -F 'В dry-run DNS не меняется' "$work/dns-dry-run" >/dev/null
resolvectl() {
    if (( $# == 2 )); then printf 'Link 12 (%s): 10.0.0.1\n' "$link"
    else printf '%s\n' "$*" >> "$log_file"; fi
}
network_resolves() { return 0; }
network_try_dns 1.1.1.1
network_restore_dns
grep -Fx 'dns wlan-test 1.1.1.1' "$log_file" >/dev/null
grep -Fx 'dns wlan-test 10.0.0.1' "$log_file" >/dev/null

printf 'Interactive selection persists through menus and dry-run\n'
settings='{"hostname":"nixos-test","user":"emptyfixture","timezone":"UTC","locale":"en_US.UTF-8",
  "theme":"minegrub","desktop":{"niri":{"enable":true},"plasma":{"enable":false},
    "dms":{"enable":true},"vicinae":{"enable":true},"defaultSession":null},
  "components":{"apps":{"firefox":true},"gaming":{},"system":{},"hardware":{}}}'
declare -A profile_settings
nix_cmd() { fail_test 'profile should be loaded from saved options'; }
profile_settings[vmware]=${settings/minegrub/none}
ui_components <<< $'1\n0' >/dev/null
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
grep -F 'Dry-run завершён' "$work/dry-run" >/dev/null
grep -F 'compress=zstd:3,noatime' "$work/dry-run" >/dev/null

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
password_stage
reject grep -F 'private test password' "$log_file" "$work/password-ui"
[[ $(bash "$source_dir/install.sh" --help) == *--dry-run* ]]

printf 'Installer fixtures passed.\n'
