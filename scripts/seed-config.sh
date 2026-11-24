#!/usr/bin/env bash
set -euo pipefail

source_file=$1
target_file=$2

if [[ -e "$target_file" || -L "$target_file" ]]; then
    exit 0
fi

target_dir=$(dirname -- "$target_file")
mkdir -p -- "$target_dir"
temp_file=$(mktemp "$target_dir/.seed.XXXXXX")
trap 'rm -f -- "$temp_file"' EXIT
install -m 0600 -- "$source_file" "$temp_file"

# Publish the completed file atomically. Keep any file created concurrently.
if ! ln -T -- "$temp_file" "$target_file"; then
    [[ -e "$target_file" || -L "$target_file" ]] || exit 1
fi
