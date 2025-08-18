#!/usr/bin/env bash
set -euo pipefail

# Backup all Docker volumes whose names end with "-data" into a single archive.
# Usage:
#   sudo ./backup_docker_data_volumes.sh [OUTPUT_ARCHIVE.tar.gz]
#
# Default output: ./docker-volumes-backup-YYYYmmdd-HHMMSS.tar.gz

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo) so we can read /var/lib/docker/volumes/*/_data." >&2
  exit 1
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
out="${1:-docker-volumes-backup-${timestamp}.tar.gz}"

# Gather candidate volumes
mapfile -t vols < <(docker volume ls -q | grep -E -- '-data$' || true)

if [[ ${#vols[@]} -eq 0 ]]; then
  echo "No volumes ending with '-data' were found." >&2
  exit 0
fi

# Create temp workspace
workdir="$(mktemp -d -t docker-vols-backup-XXXXXXXX)"
trap 'rm -rf "$workdir"' EXIT

volroot="$workdir/volumes"
mkdir -p "$volroot"

manifest="$workdir/manifest.jsonl"
touch "$manifest"

echo "Discovered volumes:"
for v in "${vols[@]}"; do
  mp="$(docker volume inspect -f '{{.Mountpoint}}' "$v")"
  echo "  - $v -> $mp"
  # Copy into workspace (preserves perms/ownership/timestamps)
  mkdir -p "$volroot/$v"
  rsync -a --delete "$mp/." "$volroot/$v/"

  # Write one JSON line per volume to manifest (name + mountpoint)
  printf '{"name":"%s","mountpoint":"%s"}\n' "$v" "$mp" >> "$manifest"
done

# Pack into one archive (volumes + manifest)
tar -C "$workdir" -czf "$out" manifest.jsonl volumes

echo "Backup complete: $out"
