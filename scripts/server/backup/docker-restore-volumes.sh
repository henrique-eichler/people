#!/usr/bin/env bash
set -euo pipefail

# Restore Docker volumes from a single archive created by backup_docker_data_volumes.sh
# Usage:
#   sudo ./restore_docker_data_volumes.sh PATH/TO/ARCHIVE.tar.gz
#
# Notes:
# - Will create missing volumes automatically.
# - Copies files into each volume mountpoint with rsync -a (preserves metadata).

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo) so we can write to /var/lib/docker/volumes/*/_data." >&2
  exit 1
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 PATH/TO/ARCHIVE.tar.gz" >&2
  exit 1
fi

archive="$1"
if [[ ! -f "$archive" ]]; then
  echo "Archive not found: $archive" >&2
  exit 1
fi

workdir="$(mktemp -d -t docker-vols-restore-XXXXXXXX)"
trap 'rm -rf "$workdir"' EXIT

echo "Extracting archive..."
tar -C "$workdir" -xzf "$archive"

# Backward-compatible: if manifest is missing, infer from folder names
manifest="$workdir/manifest.jsonl"
volroot="$workdir/volumes"

if [[ ! -d "$volroot" ]]; then
  echo "Invalid archive: 'volumes/' directory not found." >&2
  exit 1
fi

# Build list of volume names
declare -a vols=()
if [[ -f "$manifest" ]]; then
  # Extract names from JSON lines (no jq needed)
  while IFS= read -r line; do
    name="$(sed -n 's/.*"name":"\([^"]*\)".*/\1/p' <<<"$line")"
    [[ -n "$name" ]] && vols+=("$name")
  done < "$manifest"
else
  # Fallback: directory names under volumes/
  while IFS= read -r -d '' dir; do
    vols+=("$(basename "$dir")")
  done < <(find "$volroot" -mindepth 1 -maxdepth 1 -type d -print0)
fi

if [[ ${#vols[@]} -eq 0 ]]; then
  echo "No volumes found in archive." >&2
  exit 1
fi

echo "Restoring volumes:"
for v in "${vols[@]}"; do
  src="$volroot/$v"
  if [[ ! -d "$src" ]]; then
    echo "  - Skipping $v (no data dir found in archive)" >&2
    continue
  fi

  # Ensure volume exists
  if ! docker volume inspect "$v" >/dev/null 2>&1; then
    echo "  - Creating missing volume: $v"
    docker volume create "$v" >/dev/null
  else
    echo "  - Using existing volume: $v"
  fi

  mp="$(docker volume inspect -f '{{.Mountpoint}}' "$v")"
  if [[ -z "$mp" || ! -d "$mp" ]]; then
    echo "    ! Could not resolve mountpoint for $v" >&2
    continue
  fi

  echo "    -> $mp"
  # Copy data into volume (preserve metadata)
  rsync -a "$src/." "$mp/"
done

echo "Restore complete."
