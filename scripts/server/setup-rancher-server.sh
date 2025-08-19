#!/usr/bin/env bash
set -eo pipefail
source "$(pwd)/../functions.sh"
source "$(pwd)/../dns.sh"

# --- Validate input ----------------------------------------------------------
if [[ $# -ne 1 ]]; then
  error "Usage: $0 <domain>"
fi

# --- Require not root privileges ---------------------------------------------
if [[ $EUID -eq 0 ]]; then
  error "This script must NOT be run as root. Try: $0"
fi

# --- Check Docker and Compose availability -----------------------------------
for cmd in docker "docker compose" ufw openssl; do
  if ! $cmd version &>/dev/null; then error "Missing dependency: $cmd"; fi
done

# --- Variables ---------------------------------------------------------------
DOMAIN="$1"
NETWORK_NAME="internal_net"

COMPOSE_DIR="$HOME/Projects/projects/rancher"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"

SUBDOMAIN_CONF="$HOME/Projects/projects/nginx/subdomains/rancher.$DOMAIN.conf"

# --- Copy root-ca.crt to the context of docker build ------------------------
mkdir -p "$COMPOSE_DIR/certs"
cp "$COMPOSE_DIR/../certs/root-ca.crt" "$COMPOSE_DIR/certs/root-ca.crt"

# --- Create docker-compose.yml ----------------------------------------------
log "Creating $COMPOSE_FILE"
write "$COMPOSE_FILE" "
  services:
    rancher:
      container_name: rancher
      image: rancher/rancher:latest
      restart: unless-stopped
      privileged: true
      environment:
        - CATTLE_SERVER_URL=https://rancher.$DOMAIN
        - SSL_CERT_DIR=/etc/ssl/certs-custom
      volumes:
        - rancher-data:/var/lib/rancher
        - ./certs:/etc/ssl/certs-custom:ro
      dns:
        - $DNS_IP
      networks:
        - $NETWORK_NAME

  volumes:
    rancher-data:

  networks:
    $NETWORK_NAME:
      external: true"

# --- Create nginx configuration ----------------------------------------------
log "Creating $SUBDOMAIN_CONF"
write "$SUBDOMAIN_CONF" "
  # HTTP -> HTTPS
  server {
    listen 80;
    listen [::]:80;
    server_name rancher.$DOMAIN;
    location /.well-known/acme-challenge/ { root /usr/share/nginx/html; }
    return 301 https://\$host\$request_uri;
  }

  # HTTPS vhost for Rancher
  server {
    listen 443 ssl http2;
    server_name rancher.$DOMAIN;

    # Certs & common TLS settings
    include /etc/nginx/conf.d/ssl.inc;

    # Rancher requires websockets + forwarded headers when TLS is terminated here
    location / {
      proxy_http_version 1.1;

      proxy_set_header Host              \$host;
      proxy_set_header X-Real-IP         \$remote_addr;
      proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;      # avoid redirect loops
      proxy_set_header X-Forwarded-Host  \$host;
      proxy_set_header X-Forwarded-Port  \$server_port;

      # WebSocket upgrade for shell/log streaming, etc.
      proxy_set_header Upgrade           \$http_upgrade;
      proxy_set_header Connection        \"upgrade\";

      # Keep long-lived sessions alive
      proxy_read_timeout 900s;
      proxy_send_timeout 900s;
      proxy_connect_timeout 60s;
      proxy_buffering off;
      proxy_request_buffering off;

      proxy_pass http://rancher:80;
    }
  }"

# --- Ensure Docker network exists --------------------------------------------
if ! docker network ls --format '{{.Name}}' | grep -qx "$NETWORK_NAME"; then
  log "Creating Docker network '$NETWORK_NAME'"
  docker network create "$NETWORK_NAME"
fi

# --- Launch Rancher ----------------------------------------------------------
log "Starting Rancher container"
cd "$COMPOSE_DIR"
docker compose build --no-cache
docker compose up -d

# --- Reload Nginx if running --------------------------------------------------
if docker ps --format '{{.Names}}' | grep -qx nginx; then
  log "Reloading Nginx"
  docker exec nginx nginx -s reload &> /dev/null
fi

# --- Looks for bootstrap password (wait briefly if needed) --------------------
log "Fetching bootstrap password"
PASSWORD=""
for i in {1..20}; do
  PASSWORD="$(docker logs rancher 2>&1 | awk -F': ' '/Bootstrap Password:/ {print $2; exit}' || true)"
  [[ -n "$PASSWORD" ]] && break
  sleep 3
done

# --- Summary -----------------------------------------------------------------
info
info "Rancher setup completed."
info "  • Web UI        : https://rancher.$DOMAIN"
info "  • Admin user    : admin"
info "  • Admin password: $PASSWORD"
