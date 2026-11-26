#!/usr/bin/env bash
set -euo pipefail

source_dir=$(cd "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT

printf '%s\n' '{"acMonitorTimeout":600,"acLockTimeout":900,"batteryMonitorTimeout":120,"batteryLockTimeout":420,"batterySuspendTimeout":900}' > "$scratch/defaults"
printf '%s\n' '{"currentTheme":"custom","batteryMonitorTimeout":0}' > "$scratch/settings"
bash "$source_dir/scripts/dms-defaults.sh" power "$scratch/settings" "$scratch/defaults"
jq -e '.currentTheme == "custom" and .batteryLockTimeout == 420 and .acLockTimeout == 900' "$scratch/settings" >/dev/null
printf '%s\n' '{"currentTheme":"custom","batteryMonitorTimeout":205}' > "$scratch/custom"
bash "$source_dir/scripts/dms-defaults.sh" power "$scratch/custom" "$scratch/defaults"
jq -e '.batteryMonitorTimeout == 205 and (has("batteryLockTimeout") | not)' "$scratch/custom" >/dev/null
printf '%s\n' '{"batteryMonitorTimeout":0}' > "$scratch/settings"
bash "$source_dir/scripts/dms-defaults.sh" power "$scratch/settings" "$scratch/defaults"
jq -e '.batteryMonitorTimeout == 0 and (has("batteryLockTimeout") | not)' "$scratch/settings" >/dev/null
printf '%s\n' '{"dankKbdLayout":{"enabled":true}}' > "$scratch/plugin"
bash "$source_dir/scripts/dms-defaults.sh" plugin "$scratch/plugin"
jq -e '.dankKbdLayout.enabled and .macbookBacklight.enabled' "$scratch/plugin" >/dev/null

export XDG_RUNTIME_DIR=$scratch/run XDG_STATE_HOME=$scratch/state
export LEVEL_FILE=$scratch/brightness
mkdir -p "$scratch/leds"
touch "$scratch/leds/apple::kbd_backlight"
printf '40\n' > "$LEVEL_FILE"
sed "s@/sys/class/leds@$scratch/leds@" "$source_dir/scripts/macbook-backlight.sh" > "$scratch/backend"
flock() { :; }
brightnessctl() {
    shift 2
    [[ $1 != --quiet ]] || shift
    local value
    case "$1" in
        get) cat "$LEVEL_FILE" ;;
        set)
            case "$2" in
                10%-) value=$(<"$LEVEL_FILE"); value=$((value > 10 ? value - 10 : 0)) ;;
                +10%) value=$(<"$LEVEL_FILE"); value=$((value + 10)) ;;
                *) value=$2 ;;
            esac
            printf '%d\n' "$value" > "$LEVEL_FILE"
            ;;
    esac
}
# shellcheck disable=SC2034
export -f brightnessctl flock
bash "$scratch/backend" idle
[[ $(<"$LEVEL_FILE") == 0 ]]
bash "$scratch/backend" resume
[[ $(<"$LEVEL_FILE") == 40 ]]
printf '10\n' > "$LEVEL_FILE"
bash "$scratch/backend" down
[[ $(<"$LEVEL_FILE") == 0 ]]
bash "$scratch/backend" idle
bash "$scratch/backend" resume
[[ $(<"$LEVEL_FILE") == 0 ]]
printf '40\n' > "$LEVEL_FILE"
bash "$scratch/backend" wake
[[ $(<"$LEVEL_FILE") == 0 ]]
rm -- "$scratch/leds/apple::kbd_backlight"
bash "$scratch/backend" init
printf '%s\n' 'DMS timer migration and keyboard backlight state passed.'
