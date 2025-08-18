# Backup: Docker volumes backup and restore

Last updated: 2025-08-18 16:08

Purpose
- Explain how to create a backup of Docker volumes using docker-backup-volumes.sh.
- Explain how to restore Docker volumes using docker-restore-volumes.sh.
- Clarify what gets backed up (volume naming convention) and provide safe‑usage tips.

Important note about names
- You may see references to docker-backup-volume.sh and docker-restore-volume.sh (singular). In this repository the actual scripts are pluralized:
  - scripts/backup/docker-backup-volumes.sh
  - scripts/backup/docker-restore-volumes.sh
- Use the pluralized names shown above.

Prerequisites
- Docker installed and running on the machine where you will back up or restore.
- Run these scripts with sudo (they must read/write under /var/lib/docker/volumes/*/_data).
- rsync and tar available (present by default on Ubuntu Server).
- Enough free disk space for the backup archive and temporary workspace.

What is backed up
- The backup script selects Docker volumes whose names end with "-data".
- This convention matches the volumes created by the provided service setup scripts (e.g., gitea-data, grafana-data, postgres-data, etc.).

Safety recommendations
- For a consistent backup, stop containers using the volumes you will back up.
- For a safe restore, stop containers that use the target volumes before restoring.

1) Create a backup
Usage
- sudo scripts/backup/docker-backup-volumes.sh [OUTPUT_ARCHIVE.tar.gz]
  - If OUTPUT_ARCHIVE is omitted, a file named docker-volumes-backup-YYYYmmdd-HHMMSS.tar.gz is created in the current directory.

What the script does
- Enumerates Docker volumes whose names end with -data.
- Stages their contents into a temporary workspace using rsync -a --delete to preserve permissions/ownership/timestamps and mirror the state.
- Writes a manifest.jsonl file (one JSON line per volume) with name and mountpoint.
- Packs the staging directory (volumes/ + manifest.jsonl) into the output tar.gz archive.

Examples
- Default location/name (current directory):
  - sudo scripts/backup/docker-backup-volumes.sh
- Save to a specific path:
  - sudo scripts/backup/docker-backup-volumes.sh /backups/docker-vols-$(date +%F).tar.gz
- See which volumes will be included:
  - docker volume ls --format '{{.Name}}' | grep -E -- '-data$'

2) Restore from a backup
Usage
- sudo scripts/backup/docker-restore-volumes.sh PATH/TO/ARCHIVE.tar.gz

What the script does
- Extracts the archive into a temporary directory.
- Reads the list of volumes from manifest.jsonl; if missing, infers from directory names under volumes/.
- Creates any missing volumes automatically.
- Copies data into each volume mountpoint using rsync -a (preserves metadata). Note: it does not use --delete; extra files already present in the volume will be kept.

Examples
- Restore all volumes contained in an archive on the same machine:
  - sudo scripts/backup/docker-restore-volumes.sh /backups/docker-vols-2025-08-18.tar.gz
- Restore on another host:
  - Copy the archive to the target host, ensure Docker is installed and running, then run the same restore command with sudo.

Restoring only a single volume (advanced)
- The provided restore script restores all volumes present in the archive. To restore one volume:
  - Option A (manual rsync):
    - tar -xzf ARCHIVE.tar.gz volumes/VOLNAME
    - docker volume create VOLNAME  # if it does not exist
    - MP=$(docker volume inspect -f '{{.Mountpoint}}' VOLNAME)
    - sudo rsync -a volumes/VOLNAME/. "$MP"/
  - Option B (create a reduced archive with only that volume directory, plus optionally a minimal manifest.jsonl).

Verification
- List volumes and inspect sizes:
  - docker volume ls
  - du -sh /var/lib/docker/volumes/VOLNAME/_data
- Start the relevant containers and verify the applications see the expected data.

Retention and storage
- Store archives on external storage or a backup server.
- Consider a rotation strategy (e.g., daily with 7–14 days retention).
- Periodically test restoring to ensure backups are valid.

Troubleshooting
- Error: "Please run as root" → Use sudo to run the scripts.
- "No volumes ending with '-data' were found" → Ensure your volumes follow the -data naming convention or rename/create accordingly.
- "Invalid archive: 'volumes/' directory not found" → Make sure the archive was created by the provided backup script and is not corrupted.
- Permissions look wrong after restore → The scripts preserve UID/GID; ensure the target host uses compatible user/group IDs for the services.

Quick reference
- Backup now (default name):
  - sudo scripts/backup/docker-backup-volumes.sh
- Backup to custom path:
  - sudo scripts/backup/docker-backup-volumes.sh /backups/docker-vols-$(date +%Y%m%d-%H%M%S).tar.gz
- Restore from archive:
  - sudo scripts/backup/docker-restore-volumes.sh /backups/docker-vols.tar.gz
