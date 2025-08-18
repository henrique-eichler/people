#!/usr/bin/env bash
set -euo pipefail
source "$(getent passwd ${SUDO_USER:-$USER} | cut -d: -f6)/Projects/tools/functions.sh"

# --- Pre-checks ----------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root. Try: sudo $0"
fi

sudo apt update
sudo apt install spice-vdagent

sudo systemctl enable --now spice-vdagentd.service

sudo shutdown now -r
