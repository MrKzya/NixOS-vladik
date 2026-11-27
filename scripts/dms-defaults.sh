#!/usr/bin/env bash
set -euo pipefail
umask 077
mode=$1
file=$2
[[ -f $file && ! -L $file ]] || exit 0
case "$mode" in
    power)
        marker="$file.nixos-vladik-power-v1"
        [[ ! -e $marker ]] || exit 0
        before=$(jq -c . "$file") || exit 0
        after=$(jq -c --slurpfile defaults "$3" '
          if type == "object" and
             ([.acMonitorTimeout,.acLockTimeout,.acSuspendTimeout,
               .batteryMonitorTimeout,.batteryLockTimeout,.batterySuspendTimeout] |
               all(. == null or . == 0))
          then . + $defaults[0] else . end' <<< "$before") || exit 0
        ;;
    power-managed)
        before=$(jq -c . "$file") || exit 0
        after=$(jq -c --slurpfile defaults "$3" '
          if type == "object" then . + $defaults[0] else . end' <<< "$before") || exit 0
        ;;
    plugin)
        before=$(jq -c . "$file") || exit 0
        after=$(jq -c 'if type == "object" and (has("macbookBacklight") | not)
          then . + {macbookBacklight: {enabled: true}} else . end' <<< "$before") || exit 0
        ;;
    *) exit 2 ;;
esac

if [[ $before != "$after" ]]; then
    temp=$(mktemp "$(dirname -- "$file")/.dms-defaults.XXXXXXXX")
    trap 'rm -f -- "$temp"' EXIT
    jq . <<< "$after" > "$temp"
    mv -f -- "$temp" "$file"
fi
if [[ $mode == power ]]; then
    touch -- "$marker"
fi
