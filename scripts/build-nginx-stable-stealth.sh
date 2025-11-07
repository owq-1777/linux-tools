#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# build-nginx-stable-stealth.sh  (EN)
#
# Build & install NGINX 1.28.0 from fixed URL, create conf.d, ship DISABLED
# examples (*.conf.example) for php-fpm and proxy-pass, and apply stealth
# hardening (headers-more + split_clients). Uses www-data everywhere.
# OS  : Ubuntu 22.04
# User: root
# -----------------------------------------------------------------------------

set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo "Please run as root."; exit 1; }
export DEBIAN_FRONTEND=noninteractive
FORCE="${FORCE:-0}"

NGINX_VERSION="1.28.0"
BASE_URL="https://nginx.org/download"
TARBALL="nginx-${NGINX_VERSION}.tar.gz"
TARBALL_URL="${BASE_URL}/${TARBALL}"

echo ">>> Preflight checks (use FORCE=1 to continue despite warnings)..."

# 1) Existing systemd unit?
if systemctl list-units --type=service --all | grep -qE '^\s*nginx\.service'; then
  state="$(systemctl is-active nginx || true)"
  unit_path="$(systemctl cat nginx | head -n1 | sed 's/^# //')"
  echo " - systemd unit: nginx.service (state: ${state}) -> ${unit_path}"
  [[ "${state}" == "active" ]] && echo "   WARN: nginx is running. Consider: systemctl stop nginx"
else
  echo " - systemd unit: nginx.service not present (will be created)"
fi

# 2) Which nginx binary resolves now?
if command -v nginx >/dev/null 2>&1; then
  BIN="$(command -v nginx)"; VER="$($BIN -v 2>&1 || true)"
  echo " - current nginx binary: ${BIN}  (${VER})"
else
  echo " - current nginx binary: (not found)"
fi

# 3) Any apt nginx packages?
dpkg -l 'nginx*' 2>/dev/null | awk '/^ii/{print " - apt package: "$2" "$3}' || true
dpkg -l 'nginx*' 2>/dev/null | grep -q '^ii' && \
  echo "   NOTE: /etc/systemd/system overrides packaged units (your custom unit will take precedence)." # :contentReference[oaicite:1]{index=1}

# 4) Ports (non-fatal)
ss -ltn 'sport = :80'  | tail -n +2 | grep -q . && echo " - port 80 in use (non-fatal)"
ss -ltn 'sport = :443' | tail -n +2 | grep -q . && echo " - port 443 in use (non-fatal)"

# 5) Default server / modules hints
if [[ -d /etc/nginx ]]; then
  ds_count="$(grep -R --include='*.conf' -nE '^\s*listen\s+.*\bdefault_server\b' /etc/nginx 2>/dev/null | wc -l || true)"
  [[ "${ds_count}" -gt 1 ]] && echo " - WARN: multiple 'default_server' listeners found (${ds_count})."
  grep -R --include='*.conf' -n '^load_module' /etc/nginx 2>/dev/null | grep -q . && \
    echo " - NOTE: dynamic modules must be binary-compatible with core (use --with-compat)." # :contentReference[oaicite:2]{index=2}
fi

if [[ "${FORCE}" != "1" ]]; then
  echo ">>> Preflight done. To proceed anyway: FORCE=1 bash $(basename "$0")"
  exit 2
fi

echo ">>> Installing build dependencies..."
apt-get update -y
apt-get install -y \
  build-essential git curl ca-certificates wget perl \
  libpcre2-dev zlib1g-dev libssl-dev tar xz-utils unzip

# --- Download & unpack --------------------------------------------------------
TMPDIR="$(mktemp -d)"
echo ">>> Working in ${TMPDIR}"
cd "${TMPDIR}"
echo ">>> Downloading ${TARBALL_URL}"
curl -fL "${TARBALL_URL}" -o "${TARBALL}"
tar -xzf "${TARBALL}"
cd "nginx-${NGINX_VERSION}"

# --- Runtime users/dirs (use www-data) ---------------------------------------
# www-data exists on Ubuntu by default; create only if missing.
id -u www-data >/dev/null 2>&1 || adduser --system --no-create-home --group --shell /usr/sbin/nologin www-data
install -d -m0755 /etc/nginx /etc/nginx/conf.d /var/log/nginx /var/cache/nginx /usr/lib/nginx/modules

# --- Configure & build nginx (keep --with-compat for dyn-modules) ------------
# Official docs: configure flags; enable http_ssl/v2, stream, etc. :contentReference[oaicite:3]{index=3}
echo ">>> Configuring..."
./configure \
  --prefix=/usr/local/nginx \
  --sbin-path=/usr/sbin/nginx \
  --modules-path=/usr/lib/nginx/modules \
  --conf-path=/etc/nginx/nginx.conf \
  --error-log-path=/var/log/nginx/error.log \
  --http-log-path=/var/log/nginx/access.log \
  --pid-path=/run/nginx.pid \
  --lock-path=/var/lock/nginx.lock \
  --with-threads \
  --with-file-aio \
  --with-compat \
  --with-http_ssl_module \
  --with-http_v2_module \
  --with-http_gzip_static_module \
  --with-http_stub_status_module \
  --with-stream \
  --with-stream_ssl_module \
  --with-cc-opt='-O2 -fstack-protector-strong -fPIC' \
  --with-ld-opt='-Wl,-z,relro -Wl,-z,now'

echo ">>> Building & installing..."
make -j"$(nproc)"
make install

# --- Base config & example sites (www-data) ----------------------------------
[[ -f /etc/nginx/mime.types     ]] || install -m0644 ./conf/mime.types /etc/nginx/mime.types
[[ -f /etc/nginx/fastcgi_params ]] || install -m0644 ./conf/fastcgi_params /etc/nginx/fastcgi_params

install -d -m0755 /www
chown -R www-data:www-data /www
[[ -f /www/index.html ]] || printf "<!doctype html><title>OK</title><h1>OK</h1>\n" > /www/index.html
install -d -m0755 /www/errors
printf "<!doctype html><title>Not Found</title><h1>404 Not Found</h1>\n" > /www/errors/404.html
printf "<!doctype html><title>Error</title><h1>Service Error</h1>\n"       > /www/errors/50x.html
chown -R www-data:www-data /www/errors

# Main nginx.conf (http{} includes conf.d; default server uses www-data)
if [[ ! -f /etc/nginx/nginx.conf ]]; then
  echo ">>> Writing /etc/nginx/nginx.conf ..."
  cat > /etc/nginx/nginx.conf <<"EOF"
user  www-data;
worker_processes  auto;

# load_module /usr/lib/nginx/modules/ngx_http_headers_more_filter_module.so;

error_log  /var/log/nginx/error.log notice;
pid        /run/nginx.pid;

events { worker_connections 1024; }

http {
    include       mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" "$http_user_agent"';
    access_log  /var/log/nginx/access.log main;

    sendfile on; tcp_nopush on; keepalive_timeout 65; gzip on;

    include /etc/nginx/conf.d/*.conf;

    server {
        listen 80 default_server;
        server_name _;
        root /www;

        error_page 404 /errors/404.html;
        error_page 500 502 503 504 /errors/50x.html;
        location = /errors/404.html { internal; }
        location = /errors/50x.html { internal; }

        location / { try_files $uri $uri/ =404; }
    }
}
EOF
else
  # Ensure conf.d include exists
  if ! grep -q 'include /etc/nginx/conf\.d/\*\.conf;' /etc/nginx/nginx.conf; then
    awk 'BEGIN{a=0} /^http[[:space:]]*\{/ && !a {print;print "    include /etc/nginx/conf.d/*.conf;";a=1;next} {print}' \
      /etc/nginx/nginx.conf > /etc/nginx/nginx.conf.tmp && mv /etc/nginx/nginx.conf.tmp /etc/nginx/nginx.conf
  fi
  # Ensure 'user www-data;' at top
  sed -ri '0,/^\s*user\s+/s//user  www-data;/' /etc/nginx/nginx.conf || true
fi

# --- DISABLED examples (won't load because *.conf.example) --------------------
# FastCGI example according to official docs (SCRIPT_FILENAME etc.). :contentReference[oaicite:4]{index=4}
cat > /etc/nginx/conf.d/php-fpm.conf.example <<"EOF"
# /etc/nginx/conf.d/php-fpm.conf.example (disabled by default)
server {
    listen       80;
    server_name  _;
    root         /www;
    index        index.php index.html;

    error_page 404 /errors/404.html;
    error_page 500 502 503 504 /errors/50x.html;
    location = /errors/404.html { internal; }
    location = /errors/50x.html { internal; }

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        try_files $uri =404;
        include /etc/nginx/fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_pass unix:/run/php/php-fpm.sock;   # or 127.0.0.1:9000
    }

    location ~ /\.ht { deny all; }
}
EOF

# Proxy + WebSocket example per official guidance. :contentReference[oaicite:5]{index=5}
cat > /etc/nginx/conf.d/proxy-pass.conf.example <<"EOF"
# /etc/nginx/conf.d/proxy-pass.conf.example (disabled by default)
server {
    listen       80;
    server_name  _;
    root         /www;

    error_page 404 /errors/404.html;
    error_page 500 502 503 504 /errors/50x.html;
    location = /errors/404.html { internal; }
    location = /errors/50x.html { internal; }

    # Reverse proxy
    location /app/ {
        proxy_pass http://127.0.0.1:3000/;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection        "";
    }

    # WebSocket upgrade
    location /ws {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host       $host;
    }
}
EOF

# --- Build headers-more module & stealth include (http-scope only) -----------
# Headers-More lets us clear/set 'Server' (server_tokens off hides only version). :contentReference[oaicite:6]{index=6}
echo ">>> Building headers-more dynamic module..."
cd "${TMPDIR}"
git clone --depth=1 https://github.com/openresty/headers-more-nginx-module.git
cd "nginx-${NGINX_VERSION}"
./configure --with-compat --add-dynamic-module=../headers-more-nginx-module
make modules
install -m644 objs/ngx_http_headers_more_filter_module.so /usr/lib/nginx/modules/

# Load module at top of nginx.conf once
if ! grep -q 'ngx_http_headers_more_filter_module\.so' /etc/nginx/nginx.conf; then
  sed -i '1iload_module /usr/lib/nginx/modules/ngx_http_headers_more_filter_module.so;' /etc/nginx/nginx.conf
fi

# http-scope stealth & security (split_clients is http-only). :contentReference[oaicite:7]{index=7}
cat > /etc/nginx/conf.d/00-stealth-security.conf <<"EOF"
server_tokens off;

# Pseudo-random fake brands per request (http scope)
split_clients "${msec}${remote_addr}${request_length}${uri}" $fake_server {
    20% "Apache";
    20% "cloudflare";
    20% "LiteSpeed";
    20% "Varnish";
    *   "ATS";
}

# Clear & overwrite Server header (headers-more)
more_clear_headers Server;
more_set_headers   "Server: $fake_server";

# Remove common leaks and upstream banners
more_clear_headers X-Powered-By;
proxy_hide_header  Server;
fastcgi_hide_header X-Powered-By;
fastcgi_hide_header Server;

# Conservative security headers (extend with HSTS/CSP once HTTPS is enabled)
add_header X-Content-Type-Options nosniff always;
add_header X-Frame-Options DENY always;
add_header Referrer-Policy no-referrer-when-downgrade always;
add_header Permissions-Policy "geolocation=(), camera=(), microphone=()" always;
EOF

# --- systemd unit -------------------------------------------------------------
cat > /etc/systemd/system/nginx.service <<"EOF"
[Unit]
Description=NGINX web server (from source, stealth)
After=network.target

[Service]
Type=forking
PIDFile=/run/nginx.pid
ExecStart=/usr/sbin/nginx -c /etc/nginx/nginx.conf
ExecReload=/usr/sbin/nginx -s reload
ExecStop=/usr/sbin/nginx -s quit
PrivateTmp=true
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
/usr/sbin/nginx -t
systemctl enable --now nginx

echo ">>> Installed NGINX:"
which nginx
nginx -v
echo ">>> Build args:"
nginx -V 2>&1 | tr ';' '\n' | sed 's/^ \+//'

rm -rf "${TMPDIR}"

echo
echo "Examples are disabled by default:"
echo "  - /etc/nginx/conf.d/php-fpm.conf.example"
echo "  - /etc/nginx/conf.d/proxy-pass.conf.example"
echo "Enable one by copying/renaming to *.conf, then: nginx -t && systemctl reload nginx"
