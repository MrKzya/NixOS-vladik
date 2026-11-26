#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR/../..
set -euo pipefail

# shellcheck source=scripts/verify-linux-esp.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/verify-linux-esp.sh"

test_linux=/dev/test-linux
test_apple=/dev/test-apple
mount_source=$test_linux
mount_type=vfat
mount_root=/
readlink() {
    case "${*: -1}" in
        /fixture/linux|"$test_linux") printf '%s\n' "$test_linux" ;;
        /fixture/apple|"$test_apple") printf '%s\n' "$test_apple" ;;
        *) return 1 ;;
    esac
}
findmnt() {
    case "${*: -1}" in
        SOURCE) printf '%s\n' "$mount_source" ;;
        FSTYPE) printf '%s\n' "$mount_type" ;;
        FSROOT) printf '%s\n' "$mount_root" ;;
        *) return 1 ;;
    esac
}
test() {
    if [[ $1 == -b ]]; then
        [[ $2 == "$test_linux" || $2 == "$test_apple" ]]
    else
        builtin test "$@"
    fi
}
lsblk() {
    # The udev-only/default probe prints no PARTTYPE in this chroot fixture.
    [[ " $* " == *' --properties-by blkid '* ]] || return 0
    case "${*: -1}" in
        "$test_linux") printf '%s\n' c12a7328-f81f-11d2-ba4b-00a0c93ec93b ;;
        "$test_apple") printf '%s\n' "${apple_type:-c12a7328-f81f-11d2-ba4b-00a0c93ec93b}" ;;
        *) return 1 ;;
    esac
}
reject() {
    if verify_linux_esp "$@"; then
        printf 'Unexpected ESP acceptance\n' >&2
        exit 1
    fi
}
[[ -z $(lsblk -dn -o PARTTYPE "$test_linux") ]]
verify_linux_esp /fixture/linux /fixture/apple
reject /fixture/linux /fixture/linux
mount_source=$test_apple
reject /fixture/linux /fixture/apple
mount_source=$test_linux
mount_type=ext4
reject /fixture/linux /fixture/apple
mount_type=vfat
mount_root=/subtree
reject /fixture/linux /fixture/apple
mount_root=/
apple_type=7c3457ef-0000-11aa-aa11-00306543ecac
reject /fixture/linux /fixture/apple
printf 'EFI guard: blkid without udev, swapped ESP, mount, filesystem and GPT type passed.\n'
