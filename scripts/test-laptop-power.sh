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

# The MacBook policy migrates stale V3.1 timeouts and preserves other settings.
printf '%s\n' '{"batterySuspendTimeout":0,"acSuspendTimeout":200,"currentTheme":"custom"}' > "$scratch/mac-settings"
touch "$scratch/mac-settings.nixos-vladik-power-v1"
bash "$source_dir/scripts/dms-defaults.sh" power-managed "$scratch/mac-settings" "$scratch/defaults"
jq -e '.batterySuspendTimeout == 900 and .currentTheme == "custom"' "$scratch/mac-settings" >/dev/null

export XDG_RUNTIME_DIR=$scratch/run XDG_STATE_HOME=$scratch/state
export KBD_LEVEL=$scratch/keyboard DISPLAY_LEVEL=$scratch/display
export KBD_MAX=14660 DISPLAY_MAX=17777
mkdir -p "$scratch/sys/leds/:white:kbd_backlight" "$scratch/sys/backlight/intel_backlight"
printf '5864\n' > "$KBD_LEVEL"
printf '8889\n' > "$DISPLAY_LEVEL"
sed "s@/sys/class@$scratch/sys@" "$source_dir/scripts/macbook-backlight.sh" > "$scratch/backend"
flock() { :; }
brightnessctl() {
    local value maximum
    case "$2" in
        --device=:white:kbd_backlight) value=$KBD_LEVEL maximum=$KBD_MAX ;;
        --device=intel_backlight) value=$DISPLAY_LEVEL maximum=$DISPLAY_MAX ;;
        *) return 1 ;;
    esac
    shift 2
    [[ $1 != --quiet ]] || shift
    case "$1" in
        get) cat "$value" ;;
        max) printf '%s\n' "$maximum" ;;
        set) printf '%d\n' "$2" > "$value" ;;
    esac
}
# shellcheck disable=SC2034
export -f brightnessctl flock

bash "$scratch/backend" idle
[[ $(<"$KBD_LEVEL") == 0 && $(<"$DISPLAY_LEVEL") == 8889 ]]
bash "$scratch/backend" resume
[[ $(<"$KBD_LEVEL") == 5864 ]]

# Suspend while keyboard idle. The kernel can reset both brightness levels.
bash "$scratch/backend" idle
bash "$scratch/backend" snapshot
printf '0\n' > "$DISPLAY_LEVEL"
bash "$scratch/backend" wake
[[ $(<"$KBD_LEVEL") == 5864 && $(<"$DISPLAY_LEVEL") == 8889 ]]
bash "$scratch/backend" idle
XDG_RUNTIME_DIR=$scratch/reboot bash "$scratch/backend" init
[[ $(<"$KBD_LEVEL") == 5864 ]]
printf '0\n' > "$KBD_LEVEL"
XDG_RUNTIME_DIR=$scratch/next-reboot bash "$scratch/backend" init
[[ $(<"$KBD_LEVEL") == 0 ]]

# Keyboard manual zero vs automatic blanking, and the display 0 -> 1% step.
printf '147\n' > "$KBD_LEVEL"
bash "$scratch/backend" down
bash "$scratch/backend" idle
bash "$scratch/backend" resume
[[ $(<"$KBD_LEVEL") == 0 ]]
printf '178\n' > "$DISPLAY_LEVEL"
bash "$scratch/backend" display-down
[[ $(<"$DISPLAY_LEVEL") == 0 ]]
bash "$scratch/backend" snapshot
printf '500\n' > "$KBD_LEVEL"
printf '500\n' > "$DISPLAY_LEVEL"
bash "$scratch/backend" wake
[[ $(<"$KBD_LEVEL") == 0 && $(<"$DISPLAY_LEVEL") == 0 ]]
bash "$scratch/backend" display-up
[[ $(<"$DISPLAY_LEVEL") == 178 ]]

# Direct writes between adjacent percentages are compared in raw units.
printf '1540\n' > "$KBD_LEVEL"
bash "$scratch/backend" up
[[ $(<"$KBD_LEVEL") == 2199 ]]
printf '1540\n' > "$KBD_LEVEL"
bash "$scratch/backend" down
[[ $(<"$KBD_LEVEL") == 1466 ]]
export KBD_MAX=3
printf '0\n' > "$KBD_LEVEL"
bash "$scratch/backend" up
[[ $(<"$KBD_LEVEL") == 1 ]]
bash "$scratch/backend" up
[[ $(<"$KBD_LEVEL") == 2 ]]

printf '%s\n' 'DMS power migration, display and keyboard brightness fixtures passed.'
