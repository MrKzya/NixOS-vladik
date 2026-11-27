#!/usr/bin/env bash

umask 077
runtime=${XDG_RUNTIME_DIR:?}/macbook-backlight
state=${XDG_STATE_HOME:-$HOME/.local/state}/macbook-backlight
mkdir -p "$runtime" "$state"
exec 9>"$runtime/lock"
flock 9
auto_off=$state/auto-off
if [[ -e $runtime/idle ]]; then
    touch "$auto_off"
    rm -f -- "$runtime/idle"
fi

adjust() {
    local kind=$1 action=$2 class device current maximum stored saved target step percent
    local -a scales
    case "$kind" in
        keyboard)
            class=leds device=:white:kbd_backlight
            scales=(0 1 2 3 4 5 6 7 8 9 10 15 20 25 30 40 50 60 70 80 90 100)
            ;;
        display)
            class=backlight device=intel_backlight
            scales=(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 25 30 40 50 60 70 80 90 100)
            ;;
    esac
    [[ -d /sys/class/$class/$device ]] || return 0
    local -a ctl=(brightnessctl --class="$class" --device="$device")
    maximum=$("${ctl[@]}" max) && current=$("${ctl[@]}" get) || return 1
    [[ $maximum =~ ^[1-9][0-9]{0,9}$ && $current =~ ^(0|[1-9][0-9]{0,9})$ && $current -le $maximum ]] || return 1
    stored=$state/level
    [[ $kind != display ]] || stored=$state/display-level
    saved=''
    if [[ -r $stored ]]; then
        saved=$(<"$stored")
        [[ $saved =~ ^(0|[1-9][0-9]{0,9})$ && $saved -le $maximum ]] || saved=''
    fi
    target=$current

    case "$action" in
        init)
            # systemd-backlight already loaded any manual value, including zero.
            [[ $kind == keyboard && -e $auto_off ]] || return 0
            (( current )) || target=${saved:-0}
            ;;
        idle)
            [[ $kind == keyboard ]] || return 0
            if [[ ! -e $auto_off ]]; then
                printf '%s\n' "$current" > "$stored"
                (( current )) || return 0
                touch "$auto_off"
            fi
            target=0
            ;;
        resume)
            [[ $kind == keyboard && -e $auto_off ]] || return 0
            # A nonzero sysfs brightness set directly during idle takes precedence.
            (( current )) || target=${saved:-0}
            ;;
        snapshot)
            [[ $kind != keyboard || ! -e $auto_off || $current != 0 ]] || return 0
            printf '%s\n' "$current" > "$stored"
            return
            ;;
        wake)
            [[ -n $saved ]] || return 0
            target=$saved
            ;;
        up|down)
            # Compare raw units to rounded raw steps. Repeated presses cannot get
            # stuck on steps that round to the same value on a smaller device.
            if [[ $kind == keyboard && -e $auto_off && $current == 0 ]]; then
                current=${saved:-0}
                target=$current
            fi
            for percent in "${scales[@]}"; do
                step=$(( (maximum * percent + 50) / 100 ))
                if [[ $action == up && $step -gt $current ]]; then
                    target=$step
                    break
                fi
                if [[ $action == down && $step -lt $current ]]; then
                    target=$step
                fi
            done
            ;;
    esac

    "${ctl[@]}" --quiet set "$target" || return 1
    if [[ $action != idle ]]; then
        [[ $kind != keyboard ]] || rm -f -- "$auto_off"
        printf '%s\n' "$target" > "$stored"
    fi
}

case "${1:-}" in
    init|idle|resume|up|down) adjust keyboard "$1" ;;
    display-up|display-down) adjust display "${1#display-}" ;;
    snapshot|wake)
        status=0
        adjust keyboard "$1" || status=$?
        adjust display "$1" || status=$?
        exit "$status"
        ;;
    *) exit 2 ;;
esac
