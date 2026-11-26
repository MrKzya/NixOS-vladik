#!/usr/bin/env bash

# This runs from an active local Niri session. brightnessctl has logind support.
shopt -s nullglob
devices=(/sys/class/leds/*:kbd_backlight)
(( ${#devices[@]} == 1 )) || exit 0

umask 077
runtime=${XDG_RUNTIME_DIR:?}/macbook-backlight
state=${XDG_STATE_HOME:-$HOME/.local/state}/macbook-backlight
mkdir -p "$runtime" "$state"
exec 9>"$runtime/lock"
flock 9

device=${devices[0]##*/}
led() { brightnessctl --class=leds --device="$device" "$@"; }
case "${1:-}" in
    init|idle|resume|wake|up|down) ;;
    *) exit 2 ;;
esac

current=$(led get) || exit 0
[[ $current =~ ^[0-9]+$ ]] || exit 0
saved=0
if [[ -r $state/level ]]; then
    saved=$(<"$state/level")
    [[ $saved =~ ^[0-9]+$ ]] || saved=0
fi

save() { printf '%s\n' "$1" > "$state/level"; }

restore() {
    if [[ -e $runtime/idle ]]; then
        if [[ $current == 0 && $saved != 0 ]]; then
            led --quiet set "$saved" || return 1
        fi
        rm -f -- "$runtime/idle"
    fi
}

case "$1" in
    init)
        if [[ -e $state/level && ! -e $runtime/idle ]]; then
            led --quiet set "$saved"
        fi
        ;;
    idle)
        if [[ -e $runtime/idle ]]; then
            [[ $current == 0 ]] || led --quiet set 0
        else
            save "$current"
            if [[ $current != 0 ]]; then
                led --quiet set 0 && touch "$runtime/idle"
            fi
        fi
        ;;
    resume) restore ;;
    wake)
        if [[ -e $state/level ]]; then
            led --quiet set "$saved" && rm -f -- "$runtime/idle"
        fi
        ;;
    up|down)
        restore || exit 1
        change=+10%
        [[ $1 == up ]] || change=10%-
        led --quiet set "$change" && level=$(led get) && save "$level"
        ;;
esac
