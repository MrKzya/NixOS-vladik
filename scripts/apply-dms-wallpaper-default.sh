#!/usr/bin/env bash
set -euo pipefail

state_dir=$1
wallpaper=$2
session=$state_dir/dms/session.json
legacy_session=$state_dir/DankMaterialShell/session.json

if [[ ! -e "$session" && ! -L "$session" && -e "$legacy_session" ]]; then
    session=$legacy_session
fi

is_default() {
    local managed='^/nix/store/[0-9a-z]{32}-nixos-vladik-wallpaper\.jpg$'
    [[ -z "$1" || "$1" =~ $managed ]]
}

# Keep per-mode, per-monitor and cycling setups under DMS's control.
current=''
if [[ -e "$session" || -L "$session" ]]; then
    [[ -f "$session" && -w "$session" && ! -L "$session" ]] || exit 0
    if ! current=$(jq -sr '
        if length != 1 or (.[0] | type) != "object" then error("expected session object")
        else .[0] | if .perMonitorWallpaper == true or .perModeWallpaper == true
            or ((.wallpaperCyclingFolderPath // "") != "")
            then "custom" else (.wallpaperPath // "") end
        end' "$session" 2>/dev/null); then
        printf '%s\n' 'DMS: invalid session.json; wallpaper default skipped.' >&2
        exit 0
    fi
    is_default "$current" || exit 0
fi

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
active_state=$(systemctl --user show dms.service --property=ActiveState --value 2>/dev/null) || active_state=''
case "$active_state" in
    active|reloading)
        if ! current=$(dms ipc call wallpaper get 2>/dev/null); then
            printf '%s\n' 'DMS: could not read wallpaper over IPC; wallpaper default skipped.' >&2
            exit 0
        fi
        is_default "$current" && [[ "$current" != "$wallpaper" ]] || exit 0
        if ! reply=$(dms ipc call wallpaper set "$wallpaper") || [[ "$reply" != SUCCESS:* ]]; then
            printf '%s\n' 'DMS: wallpaper update over IPC failed.' >&2
        fi
        exit 0
        ;;
    activating|deactivating)
        exit 0
        ;;
esac

[[ "$current" != "$wallpaper" ]] || exit 0
target_dir=$(dirname -- "$session")
mkdir -p -- "$target_dir"
temp_file=$(mktemp "$target_dir/.session.XXXXXX")
trap 'rm -f -- "$temp_file"' EXIT

if [[ -f "$session" ]]; then
    jq --arg wallpaper "$wallpaper" '.wallpaperPath = $wallpaper' "$session" > "$temp_file"
    mv -T -- "$temp_file" "$session"
else
    jq -n --arg wallpaper "$wallpaper" '{wallpaperPath: $wallpaper}' > "$temp_file"
    if ! ln -T -- "$temp_file" "$session"; then
        [[ -e "$session" || -L "$session" ]] || exit 1
    fi
fi
