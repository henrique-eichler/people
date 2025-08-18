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
for cmd in docker "docker compose" ufw openssl; do
  if ! $cmd version &>/dev/null; then error "Missing dependency: $cmd"; fi
done

# --- Variables ---------------------------------------------------------------
DOMAIN="$1"
NETWORK_NAME="internal_net"

COMPOSE_DIR="$HOME/Projects/projects/nginx"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
NGINX_CONF="$COMPOSE_DIR/nginx.conf"

CONF_DIR="$COMPOSE_DIR/conf.d"
DEFAULT_CONF="$CONF_DIR/default.conf"
HOME_CONF="$CONF_DIR/home.conf"
SSL_INC="$CONF_DIR/ssl.inc"

SUBDOMAINS_DIR="$COMPOSE_DIR/subdomains"

HTML_DIR="$COMPOSE_DIR/html"
HTML_FILE="$HTML_DIR/index.html"

CERTS_DIR="$HOME/Projects/projects/certs"
ROOT_CNF="$CERTS_DIR/root-ca.cnf"
ROOT_KEY="$CERTS_DIR/root-ca.key"
ROOT_CRT="$CERTS_DIR/root-ca.crt"
DOMAIN_CNF="$CERTS_DIR/$DOMAIN.cnf"
DOMAIN_CSR="$CERTS_DIR/$DOMAIN.csr"
DOMAIN_KEY="$CERTS_DIR/$DOMAIN.key"
DOMAIN_CRT="$CERTS_DIR/$DOMAIN.crt"

# --- Ensure directories exist ------------------------------------------------
mkdir -p "$COMPOSE_DIR" "$CONF_DIR" "$SUBDOMAINS_DIR" "$HTML_DIR" "$CERTS_DIR"

# --- Create Root CA (once) ---------------------------------------------------
if [[ ! -f "$ROOT_KEY" || ! -f "$ROOT_CRT" ]]; then
  log "Creating $ROOT_CNF..."
  write "$ROOT_CNF" "
    [ req ]
    default_bits       = 4096
    prompt             = no
    default_md         = sha256
    x509_extensions    = v3_ca
    distinguished_name = dn

    [ dn ]
    C  = BR
    ST = GO
    L  = Goias
    O  = Espaco Estimular
    OU = Clinica
    CN = Estimular Internal Root

    [ v3_ca ]
    basicConstraints = critical, CA:true, pathlen:0
    keyUsage         = critical, keyCertSign, cRLSign
    subjectKeyIdentifier = hash
    authorityKeyIdentifier = keyid:always"

  openssl req -x509 -new -nodes -sha256 -days 3650 \
    -newkey rsa:4096 -keyout "$ROOT_KEY" -out "$ROOT_CRT" \
    -config "$ROOT_CNF"
fi

# --- Create wildcard + apex leaf cert (if missing) ---------------------------
if [[ ! -f "$DOMAIN_CRT" || ! -f "$DOMAIN_KEY" ]]; then
  log "Creating $DOMAIN_CNF..."
  write "$DOMAIN_CNF" "
    [req]
    default_bits = 3072
    prompt = no
    default_md = sha256
    distinguished_name = dn
    req_extensions = v3_req

    [dn]
    C=BR
    ST=GO
    L=Goias
    O=Espaco Estimular
    OU=Clinica
    CN=*.$DOMAIN

    [v3_req]
    subjectAltName = @alt
    keyUsage = critical, digitalSignature, keyEncipherment
    extendedKeyUsage = serverAuth

    [alt]
    DNS.1 = *.$DOMAIN
    DNS.2 = $DOMAIN"

  openssl req -new -newkey rsa:3072 -nodes \
    -keyout "$DOMAIN_KEY" -out "$DOMAIN_CSR" -config "$DOMAIN_CNF"

  openssl x509 -req -in "$DOMAIN_CSR" \
    -CA "$ROOT_CRT" -CAkey "$ROOT_KEY" -CAcreateserial \
    -out "$DOMAIN_CRT" -days 825 -sha256 \
    -extensions v3_req -extfile "$DOMAIN_CNF"

  chmod 600 "$ROOT_KEY" "$DOMAIN_KEY" || true
fi

# --- docker-compose.yml -------------------------------------------------------
log "Creating $COMPOSE_FILE..."
write "$COMPOSE_FILE" "
  services:
    nginx:
      image: nginx:stable-alpine
      container_name: nginx
      restart: unless-stopped
      networks:
        - $NETWORK_NAME
      ports:
        - '80:80'
        - '443:443'
      volumes:
        - ./nginx.conf:/etc/nginx/nginx.conf:ro
        - ./conf.d:/etc/nginx/conf.d:ro
        - ./subdomains:/etc/nginx/subdomains:ro
        - $CERTS_DIR:/etc/nginx/certs:ro
        - ./html:/usr/share/nginx/html:ro
      healthcheck:
        test: ['CMD-SHELL', 'nginx -t']
        interval: 30s
        timeout: 5s
        retries: 3

  networks:
    $NETWORK_NAME:
      external: true"

# --- nginx.conf (top-level) ---------------------------------------------------
log "Creating $NGINX_CONF..."
write "$NGINX_CONF" "
  user  nginx;
  worker_processes auto;

  events { worker_connections 1024; }

  http {
    sendfile on;
    tcp_nopush on;
    types_hash_max_size 4096;

    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    access_log /var/log/nginx/access.log;
    error_log  /var/log/nginx/error.log;

    keepalive_timeout 65;

    # Allow proxy_pass to Docker service names
    resolver 127.0.0.11 valid=30s ipv6=off;
    resolver_timeout 5s;

    # Load site configs
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/subdomains/*.conf;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript application/xml text/xml;
  }"

log "Creating $SSL_INC..."
write "$SSL_INC" "
  ssl_certificate     /etc/nginx/certs/$DOMAIN.crt;
  ssl_certificate_key /etc/nginx/certs/$DOMAIN.key;

  ssl_session_timeout 1d;
  ssl_session_cache shared:SSL:10m;
  ssl_session_tickets off;

  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_prefer_server_ciphers off;

  # Enable when clients trust your CA/cert
  # add_header Strict-Transport-Security \"max-age=31536000\" always;"

# --- Default site (serves local HTML on root host) ----------------------------
write "$HOME_CONF" "
  # HTTP -> HTTPS redirect for default host
  server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name $DOMAIN *.$DOMAIN;
    location /.well-known/acme-challenge/ { root /usr/share/nginx/html; }
    return 301 https://\$host\$request_uri;
  }

  # HTTPS default site
  server {
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    server_name $DOMAIN;

    include /etc/nginx/conf.d/ssl.inc;
    client_max_body_size 200M;

    root   /usr/share/nginx/html;
    index  index.html;

    location / {
      try_files \$uri \$uri/ =404;
    }

    location /certs/ {
      alias /etc/nginx/certs/;
      autoindex off;
      types { application/x-x509-ca-cert crt; }
    }
  }"

write "$HTML_FILE" "
  <!DOCTYPE html>
  <html lang='en'>
  <head>
    <meta charset='UTF-8' />
    <title>ServerX Services · estimular.com.br</title>
    <meta name='viewport' content='width=device-width, initial-scale=1' />
    <style>
      :root{
        --bg:#0b1020; --card:#11172a; --muted:#9aa4b2; --text:#f5f7fb; --brand:#6aa6ff; --accent:#22c55e; --border:#263048;
      }
      *{box-sizing:border-box}
      body{
        margin:0; padding:2rem; font:16px/1.55 system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,Noto Sans,Arial,sans-serif;
        color:var(--text); background:radial-gradient(1200px 800px at 20% -10%, #152043, transparent), var(--bg);
      }
      header{max-width:1100px; margin:0 auto 1.5rem auto}
      h1{margin:0 0 .25rem 0; font-size:1.75rem}
      .muted{color:var(--muted)}
      .wrap{max-width:1100px; margin:0 auto; display:grid; gap:1.25rem}
      /* cards */
      ul.cards{list-style:none; padding:0; margin:0; display:grid; grid-template-columns:repeat(auto-fit,minmax(240px,1fr)); gap:.85rem}
      .card{
        display:block; border:1px solid var(--border); background:linear-gradient(180deg,#121a31,#0f1527);
        border-radius:.75rem; padding:1rem .95rem; color:var(--text); text-decoration:none; transition:.2s ease transform, .2s ease box-shadow, .2s ease border-color;
      }
      .card:hover{transform:translateY(-2px); box-shadow:0 8px 30px rgba(0,0,0,.25); border-color:#345;}
      .card small{display:block; color:var(--muted); margin-top:.25rem}
      /* CA section */
      section.ca{border:1px solid var(--border); border-radius:.9rem; background:linear-gradient(180deg,#121a31,#0f1527); padding:1rem}
      section.ca h2{margin:.25rem 0 .5rem 0; font-size:1.25rem}
      .actions{display:flex; gap:.5rem; flex-wrap:wrap; margin:.5rem 0 1rem}
      .btn{
        appearance:none; border:1px solid var(--border); background:#0e1730; color:var(--text);
        padding:.55rem .8rem; border-radius:.6rem; cursor:pointer; text-decoration:none; font-weight:600;
      }
      .btn.primary{border-color:#3b82f6; background:linear-gradient(180deg,#2563eb,#1d4ed8); box-shadow:inset 0 1px 0 rgba(255,255,255,.15)}
      .btn.success{border-color:#16a34a; background:linear-gradient(180deg,#22c55e,#16a34a)}
      code, pre{font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,'Liberation Mono',Consolas,monospace}
      pre{margin:.5rem 0 0; padding:.75rem; background:#0c1328; border:1px solid var(--border); border-radius:.6rem; overflow:auto}
      details{border:1px solid var(--border); border-radius:.6rem; padding:.75rem; background:#0c1328}
      details+details{margin-top:.5rem}
      summary{cursor:pointer; user-select:none; color:var(--brand); font-weight:600}
      .kbd{display:inline-block; padding:.15rem .4rem; border:1px solid var(--border); border-radius:.35rem; background:#0c1328; font-size:.85em}
      footer{margin-top:1.25rem; color:var(--muted); font-size:.9rem}
      .row{display:grid; gap:.75rem; grid-template-columns:1fr; }
      @media (min-width:860px){ .row{grid-template-columns:1.2fr .8fr} }
      .hint{font-size:.92rem; color:var(--muted)}
      .copy{margin-left:.25rem}
    </style>
  </head>
  <body>
    <header>
      <h1>Available Services</h1>
      <p class='muted'>This page is served by Nginx on <strong>estimular.com.br</strong> inside the tailnet.</p>
    </header>

    <main class='wrap'>
      <ul class='cards'>
        <li><a class='card' href='https://gitea.estimular.com.br/'><strong>Gitea</strong><small>gitea.estimular.com.br</small></a></li>
        <li><a class='card' href='https://grafana.estimular.com.br/'><strong>Grafana</strong><small>grafana.estimular.com.br</small></a></li>
        <li><a class='card' href='https://jenkins.estimular.com.br/'><strong>Jenkins</strong><small>jenkins.estimular.com.br</small></a></li>
        <li><a class='card' href='https://keycloak.estimular.com.br/'><strong>Keycloak</strong><small>keycloak.estimular.com.br</small></a></li>
        <li><a class='card' href='https://nexus.estimular.com.br/'><strong>Nexus Repository</strong><small>nexus.estimular.com.br</small></a></li>
        <li><a class='card' href='https://prometheus.estimular.com.br/'><strong>Prometheus</strong><small>prometheus.estimular.com.br</small></a></li>
        <li><a class='card' href='https://rancher.estimular.com.br/'><strong>Rancher</strong><small>rancher.estimular.com.br</small></a></li>
      </ul>

      <section class='ca' id='root-ca'>
        <div class='row'>
          <div>
            <h2>Trust the Estimular Root CA</h2>
            <p class='hint'>
              Our internal services use a private certificate authority. Install the Root CA below so browsers, Gradle, Docker, and CLIs trust
              <span class='kbd'>*.estimular.com.br</span>.
            </p>
            <div class='actions'>
              <a class='btn primary' href='/certs/root-ca.crt' download>⬇ Download root-ca.crt</a>
              <button class='btn copy' data-copy='curl -fsSLk https://estimular.com.br/certs/root-ca.crt -o root-ca.crt'>Copy curl command</button>
              <button class='btn copy' data-copy='wget --no-check-certificate https://estimular.com.br/certs/root-ca.crt -O root-ca.crt'>Copy wget command</button>
            </div>

            <details>
              <summary>Linux (Ubuntu/Debian) – System trust store</summary>
              <pre><code>sudo install -m 0644 root-ca.crt /usr/local/share/ca-certificates/estimular-root-ca.crt
  sudo update-ca-certificates</code></pre>
              <p class='hint'>This makes browsers and most tools trust the CA. Java/Gradle may still need the JVM truststore (see below).</p>
            </details>

            <details>
              <summary>macOS – System trust (Keychain)</summary>
              <pre><code>sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain root-ca.crt</code></pre>
            </details>

            <details>
              <summary>Windows – Local Machine (PowerShell as Admin)</summary>
              <pre><code>Import-Certificate -FilePath .\root-ca.crt -CertStoreLocation Cert:\LocalMachine\Root</code></pre>
            </details>

            <details>
              <summary>Java/Gradle – JVM truststore (no root access required)</summary>
              <pre><code># Create a personal truststore and point Gradle to it
  keytool -importcert -alias estimular-root -keystore ~/.gradle/estimular-truststore.jks -storepass changeit -file root-ca.crt -noprompt
  printf '%s\n' 'org.gradle.jvmargs=-Djavax.net.ssl.trustStore=/home/$USER/.gradle/estimular-truststore.jks -Djavax.net.ssl.trustStorePassword=changeit' >> ~/.gradle/gradle.properties
  ./gradlew --stop && ./gradlew build</code></pre>
            </details>

            <details>
              <summary>Optional: verify checksum after download</summary>
              <pre><code># Linux/macOS
  sha256sum root-ca.crt
  # or
  shasum -a 256 root-ca.crt

  # Windows (PowerShell)
  Get-FileHash .\root-ca.crt -Algorithm SHA256</code></pre>
              <p class='hint'>Compare the hash with the value published by your admin.</p>
            </details>
          </div>

          <div>
            <details open>
              <summary>Why do I need this?</summary>
              <p class='hint'>Our services are available only inside the tailnet and use certificates issued by a private CA. Public CAs don’t issue certs for internal IPs or private networks without DNS‑01. Installing the Root CA lets your system verify our TLS certificates.</p>
            </details>
            <details>
              <summary>Troubleshooting</summary>
              <ul class='hint'>
                <li><strong>SSL handshake / PKIX path building failed</strong> → JVM doesn’t trust the CA. Import into the JVM truststore as above.</li>
                <li><strong>Browser shows “Not secure”</strong> → Import the CA into the OS trust store; restart the browser.</li>
                <li><strong>Gradle still fails</strong> → Ensure <code>org.gradle.jvmargs</code> points to your truststore and restart the daemon: <code>./gradlew --stop</code>.</li>
              </ul>
            </details>
          </div>
        </div>
        <footer>Need help? Ping <span class='kbd'>server.taila5359d.ts.net</span> on Tailscale.</footer>
      </section>
    </main>

    <script>
      // Copy-to-clipboard for buttons
      document.querySelectorAll('.btn.copy').forEach(btn => {
        btn.addEventListener('click', async () => {
          const text = btn.getAttribute('data-copy');
          try {
            await navigator.clipboard.writeText(text);
            const old = btn.textContent;
            btn.textContent = 'Copied!';
            btn.classList.add('success');
            setTimeout(()=>{ btn.textContent = old; btn.classList.remove('success'); }, 1400);
          } catch (e) {
            alert('Copy failed. Select and copy manually:\n\n' + text);
          }
        });
      });
    </script>
  </body>
  </html>"

# --- Ensure Docker network exists --------------------------------------------
if ! docker network ls --format '{{.Name}}' | grep -qx "$NETWORK_NAME"; then
  log "Creating Docker network '$NETWORK_NAME'"
  docker network create "$NETWORK_NAME"
fi

# --- Bring up Nginx -----------------------------------------------------------
log "Validating docker-compose.yml"
docker compose -f "$COMPOSE_FILE" config >/dev/null

log "Starting Nginx container"
( cd "$COMPOSE_DIR" && docker compose up -d )

# --- UFW rules (safe) ---------------------------------------------------------
log "Configuring UFW (allow 80, 443)"
sudo ufw allow 80/tcp  || true
sudo ufw allow 443/tcp || true
sudo ufw reload || true
sudo ufw --force enable

# --- Summary -----------------------------------------------------------------
info "Nginx reverse proxy is up."
info "Default site: https://$DOMAIN (serves /usr/share/nginx/html/index.html)"
info "Put your vhost files under: $SUBDOMAINS_DIR (each as its own .conf)"
info "Join your app containers to the '$NETWORK_NAME' network so 'proxy_pass http://service:port;' works."