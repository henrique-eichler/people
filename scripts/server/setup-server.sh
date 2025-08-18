#!/usr/bin/env bash
set -eo pipefail
source "$HOME/Projects/tools/functions.sh"

# --- Validate input ----------------------------------------------------------
if [[ $# -ne 1 ]]; then
  error "Usage: $0 <domain>"
fi

# --- Require not root privileges --------------------------------------------------
if [[ $EUID -eq 0 ]]; then
  error "This script must NOT be ran as root. Try: $0 <domain>"
fi

# --- Variables ---------------------------------------------------------------
DOMAIN="$1"

listContainers() { docker ps -a | grep -v CONTAINER | awk '{print $1}'; }
listVolumes()    { docker volume ls | grep -v DRIVER | awk '{print $2}'; }
listImages()     { docker image ls | grep -v REPOSITORY | awk '{print $3}'; }

# --- Stop and remove all running/stopped containers -------------------------
log "killing docker containers..."
listContainers && listContainers | xargs -r docker kill
listContainers && listContainers | xargs -r docker rm

# --- Remove all Docker volumes ----------------------------------------------
# log "killing docker volumes..."
# listVolumes && listVolumes | xargs -r docker volume rm

# --- Remove all Docker images ----------------------------------------------
# log "killing docker images..."
# listImages && listImages | xargs docker image rm 

# --- Remove previous project directory --------------------------------------
log "deleting projects dir..."
rm -rf "$HOME/Projects/projects"

clear

# --- Recreate environment ---------------------------------------------------
log "Installation of services..."

./setup-node-exporter.sh $DOMAIN

./setup-dns-server.sh $DOMAIN 100.64.64.200
./setup-nginx-server.sh $DOMAIN

./setup-prometheus-server.sh $DOMAIN
./setup-grafana-server.sh $DOMAIN

./setup-postgresql-server.sh $DOMAIN giteadb gitea giteapwd
./setup-redis-server.sh $DOMAIN

./setup-nexus-server.sh $DOMAIN
./setup-gitea-server.sh $DOMAIN
./setup-jenkins-server.sh $DOMAIN
./setup-rancher-server.sh $DOMAIN

./setup-ollama-server.sh $DOMAIN deepseek-R1:1.5b

./setup-postgresql-server.sh $DOMAIN peopledb people peoplepwd


# --- Summary ----------------------------------------------------------------
info
info "All services have been reinstalled and are running:"
info
docker ps --format "  - {{.Names}} ({{.Status}})"

