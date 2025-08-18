#!/usr/bin/env bash
set -eo pipefail
source "$HOME/Projects/tools/functions.sh"

# --- Validate input ----------------------------------------------------------
if [[ $# -ne 1 ]]; then
  error "Usage: $0 <domain>"
fi

# --- Require not root privileges --------------------------------------------------
if [[ $EUID -eq 0 ]]; then
  error "This script must NOT be run as root. Try: $0"
fi

# --- Check Docker and Compose availability -----------------------------------
for cmd in docker "docker compose" ufw; do
  if ! $cmd version &>/dev/null; then error "Missing dependency: $cmd"; fi
done

# --- Variables ---------------------------------------------------------------
DOMAIN="$1"
NETWORK_NAME="internal_net"

COMPOSE_DIR="$HOME/Projects/projects/nexus"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
DOCKER_FILE="$COMPOSE_DIR/Dockerfile"
NEXUS_PROP="$COMPOSE_DIR/nexus.properties"

SUBDOMAIN_CONF="$HOME/Projects/projects/nginx/subdomains/nexus.$DOMAIN.conf"

# --- Copy root-ca.crt to the context of docker build ------------------------
mkdir -p "$COMPOSE_DIR/certs"
cp "$COMPOSE_DIR/../certs/root-ca.crt" "$COMPOSE_DIR/certs/$DOMAIN.root-ca.crt"

# --- Create Dockerfile ------------------------------------------------------
log "Creating $DOCKER_FILE..."
write "$DOCKER_FILE" "
  FROM sonatype/nexus3:latest

  USER root

  COPY certs/estimular.com.br.root-ca.crt /tmp/estimular-root.crt
  RUN keytool -importcert -trustcacerts \
      -alias estimular-root \
      -file /tmp/estimular-root.crt \
      -cacerts -storepass changeit -noprompt || true

  USER nexus"

# --- Create docker-compose.yml ----------------------------------------------
log "Creating $COMPOSE_FILE..."
write "$COMPOSE_FILE" "
  services:
    nexus:
      build: .
      container_name: nexus
      restart: unless-stopped
      ports:
        - '5001:5001'
      volumes:
        - nexus-data:/nexus-data
        - ./nexus.properties:/nexus-data/etc/nexus.properties:ro
      networks:
        - ${NETWORK_NAME}

  volumes:
    nexus-data:

  networks:
    ${NETWORK_NAME}:
      external: true"

# --- Generate nexus.properties -----------------------------------------------
log "Creating $NEXUS_PROP..."
write "$NEXUS_PROP" "
  nexus.prometheus.enabled=true"

# --- Generate settings.xml ---------------------------------------------------
log "Creating Maven settings.xml"
write "$COMPOSE_DIR/settings.xml" "
  <settings xmlns=\"http://maven.apache.org/SETTINGS/1.0.0\"
            xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"
            xsi:schemaLocation=\"
              http://maven.apache.org/SETTINGS/1.0.0
              https://maven.apache.org/xsd/settings-1.0.0.xsd\">

    <mirrors>
      <mirror>
        <id>nexus-maven-central</id>
        <name>Nexus Maven Central Proxy</name>
        <url>https://nexus.$DOMAIN/repository/maven-public/</url>
        <mirrorOf>*</mirrorOf>
      </mirror>
    </mirrors>

    <servers>
      <server>
        <id>maven-releases</id>
        <username>henrique</username>
        <password>ampa</password>
      </server>
      <server>
        <id>maven-snapshots</id>
        <username>henrique</username>
        <password>ampa</password>
      </server>
      <server>
        <id>nexus-maven-central</id>
        <username>henrique</username>
        <password>ampa</password>
      </server>
    </servers>

    <profiles>
      <profile>
        <id>nexus</id>
        <activation>
          <activeByDefault>true</activeByDefault>
        </activation>
        <repositories>
          <repository>
            <id>maven-releases</id>
            <url>https://nexus.$DOMAIN/repository/maven-releases/</url>
            <releases>
              <enabled>true</enabled>
            </releases>
            <snapshots>
              <enabled>false</enabled>
            </snapshots>
          </repository>
          <repository>
            <id>maven-snapshots</id>
            <url>https://nexus.$DOMAIN/repository/maven-snapshots/</url>
            <releases>
              <enabled>false</enabled>
            </releases>
            <snapshots>
              <enabled>true</enabled>
            </snapshots>
          </repository>
        </repositories>
      </profile>
    </profiles>

    <activeProfiles>
      <activeProfile>nexus</activeProfile>
    </activeProfiles>
  </settings>"

# --- Generate pom.xml -----------------------------------------------------
log "Creating Maven pom.xml sample"
write "$COMPOSE_DIR/pom.xml" "
  <project xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"
           xmlns=\"http://maven.apache.org/POM/4.0.0\"
           xsi:schemaLocation=\"http://maven.apache.org/POM/4.0.0 
                               http://maven.apache.org/xsd/maven-4.0.0.xsd\">
    <modelVersion>4.0.0</modelVersion>

    <distributionManagement>
      <repository>
        <id>nexus-releases</id>
        <name>Nexus Release Repository</name>
        <url>https://nexus.$DOMAIN/repository/maven-releases/</url>
      </repository>
      <snapshotRepository>
        <id>nexus-snapshots</id>
        <name>Nexus Snapshot Repository</name>
        <url>https://nexus.$DOMAIN/repository/maven-snapshots/</url>
      </snapshotRepository>
    </distributionManagement>

  </project>"

# --- Generate init.gradle --------------------------------------------------
log "Creating Gradle init.gradle"
write "$COMPOSE_DIR/init.gradle" "
  // Apply Nexus as a mirror of Maven Central for all projects
  allprojects {
    repositories {
      maven {
        name = \"nexus-maven-central\"
        url = uri(\"https://nexus.$DOMAIN/repository/maven-public/\")
        credentials {
          username = \"henrique\"
          password = \"ampa\"
        }
      }
    }
  }

  // Add publishing logic after all projects are configured
  projectsEvaluated {
    allprojects { project ->
      if (project.plugins.hasPlugin('maven-publish')) {
        project.publishing {
          publications {
            // publications are declared in each build.gradle
          }
          repositories {
            if (project.version.toString().endsWith(\"-SNAPSHOT\")) {
              maven {
                name = \"maven-snapshots\"
                url = uri(\"https://nexus.$DOMAIN/repository/maven-snapshots/\")
                credentials {
                  username = \"henrique\"
                  password = \"ampa\"
                }
              }
            } else {
              maven {
                name = \"maven-releases\"
                url = uri(\"https://nexus.$DOMAIN/repository/maven-releases/\")
                credentials {
                  username = \"henrique\"
                  password = \"ampa\"
                }
              }
            }
          }
        }
      }
    }
  }"

# --- Generate build.gradle --------------------------------------------------
log "Creating Gradle build.gradle sample"
write "$COMPOSE_DIR/buid.gradle" "
  plugins {
    id 'maven-publish'
  }

  publishing {
    publications {
      mavenJava(MavenPublication) {
        from components.java
      }
    }
  }"

# --- Create nginx configuration ----------------------------------------------
log "Creating $SUBDOMAIN_CONF"
write "$SUBDOMAIN_CONF" "
  # HTTP -> HTTPS
  server {
    listen 80;
    listen [::]:80;
    server_name nexus.$DOMAIN;
    location /.well-known/acme-challenge/ { root /usr/share/nginx/html; }
    return 301 https://\$host\$request_uri;
  }

  # HTTPS vhost for Nexus
  server {
    listen 443 ssl http2;
    server_name nexus.$DOMAIN;

    # Using your existing self-signed bundle for $DOMAIN (SAN includes nexus.$DOMAIN)
    include /etc/nginx/conf.d/ssl.inc;

    # Large artifacts/uploads
    client_max_body_size 2G;
    proxy_request_buffering off;
    proxy_read_timeout 900;
    proxy_connect_timeout 60;
    proxy_send_timeout 900;

    location / {
      proxy_http_version 1.1;
      proxy_set_header Host              \$host;
      proxy_set_header X-Real-IP         \$remote_addr;
      proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_set_header X-Forwarded-Host  \$host;
      proxy_set_header X-Forwarded-Port  \$server_port;

      # Authorization header (safe pass-through)
      proxy_set_header Authorization     \$http_authorization;
      proxy_pass http://nexus:8081;
    }
  }"

# --- Ensure Docker network exists --------------------------------------------
if ! docker network ls --format '{{.Name}}' | grep -qx "$NETWORK_NAME"; then
  log "Creating Docker network '${NETWORK_NAME}'"
  docker network create "$NETWORK_NAME"
fi

# --- Launch Jenkins ----------------------------------------------------------
log "Starting Jenkins container"
cd "$COMPOSE_DIR"
docker compose build --no-cache
docker compose up -d

# --- UFW rules (safe) ---------------------------------------------------------
log "Configuring UFW (allow 5001)"
sudo ufw allow 5001/tcp  || true
sudo ufw reload || true
sudo ufw --force enable

# --- Reload Nginx if running --------------------------------------------------
if docker ps --format '{{.Names}}' | grep -qx nginx; then
  log "Reloading Nginx"
  docker exec nginx nginx -s reload &> /dev/null
fi

# --- Summary -----------------------------------------------------------------
info
info "Nexus setup complete"
info "  • Web UI        : https://nexus.$DOMAIN"
info "  • Docker Repo   : nexus.$DOMAIN:5001"
