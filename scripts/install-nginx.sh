#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# install-nginx.sh
#
# Build & install NGINX 1.28.0, overwrite nginx.conf & unit,
# install headers-more dynamic module, hide/replace Server header, use www-data,
# ship disabled example vhosts (*.conf.example), custom error pages.
#
# OS       : Ubuntu 22.04 (Jammy) / 24.04 (Noble) - 64-bit
# User     : Run as root.
# -----------------------------------------------------------------------------

set -euo pipefail
trap 'echo "[ERROR] line $LINENO: command exited with status $?" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/os.sh"
require_supported_ubuntu
ensure_apt_ready

[[ "$(id -u)" -eq 0 ]] || { echo "Please run as root."; exit 1; }

export DEBIAN_FRONTEND=noninteractive

NGINX_VERSION="1.28.0"
TARBALL_URL="https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"

echo ">>> Install build deps..."
apt-get update -y
filter_available() {
  local out=()
  for pkg in "$@"; do
    if apt-cache policy "$pkg" 2>/dev/null | awk -F': ' '/Candidate:/ {print $2}' | grep -qv '(none)'; then
      out+=("$pkg")
    fi
  done
  printf '%s\n' "${out[@]}"
}
deps=(
  build-essential git curl ca-certificates wget perl tar xz-utils unzip
  libssl-dev zlib1g-dev libpcre3-dev libpcre2-dev
)
mapfile -t avail_deps < <(filter_available "${deps[@]}")
apt-get install -y "${avail_deps[@]}"

echo ">>> Prepare dirs & user..."
id -u www-data >/dev/null 2>&1 || adduser --system --no-create-home --group --shell /usr/sbin/nologin www-data
install -d -m0755 /etc/nginx /etc/nginx/conf.d /etc/nginx/snippets /var/log/nginx /var/cache/nginx /usr/lib/nginx/modules

echo ">>> Download & unpack NGINX ${NGINX_VERSION}..."
TMPDIR="$(mktemp -d)"
cd "${TMPDIR}"
curl -fL "${TARBALL_URL}" -o nginx.tar.gz
tar -xzf nginx.tar.gz
cd "nginx-${NGINX_VERSION}"

echo ">>> Configure core..."
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

echo ">>> Build & install core..."
make -j"$(nproc)"
make install

# Base includes (always install fresh)
install -m0644 ./conf/mime.types     /etc/nginx/mime.types
install -m0644 ./conf/fastcgi_params /etc/nginx/fastcgi_params

# Remove branded default html (avoid fallback Welcome to nginx!)
rm -f /usr/local/nginx/html/index.html /usr/local/nginx/html/50x.html 2>/dev/null || true
rm -f /usr/share/nginx/html/index.html /usr/share/nginx/html/50x.html 2>/dev/null || true

echo ">>> Build headers-more dynamic module..."
cd "${TMPDIR}"
git clone --depth=1 https://github.com/openresty/headers-more-nginx-module.git
cd "nginx-${NGINX_VERSION}"
./configure --with-compat --add-dynamic-module=../headers-more-nginx-module
make modules

echo ">>> Locate & install module .so ..."
MOD_SO="objs/ngx_http_headers_more_filter_module.so"
[[ -f "$MOD_SO" ]] || MOD_SO="$(find objs -maxdepth 1 -type f -name 'ngx_http_headers_more*_module*.so' -print -quit)"
[[ -n "${MOD_SO:-}" && -f "$MOD_SO" ]] || { echo "headers-more .so not found"; exit 1; }
install -d -m0755 /usr/lib/nginx/modules
install -m0644 "$MOD_SO" /usr/lib/nginx/modules/

echo ">>> Prepare site root & custom error pages..."
install -d -m0755 /www /www/errors
[[ -f /www/index.html ]] || printf "<!doctype html><meta charset=utf-8><title>OK</title><h1>OK</h1>\n" > /www/index.html
printf "<!doctype html><meta charset=utf-8><title>Not Found</title><h1>404 Not Found</h1>\n" > /www/errors/404.html
printf "<!doctype html><meta charset=utf-8><title>Error</title><h1>Service Error</h1>\n"       > /www/errors/50x.html
chown -R www-data:www-data /www

echo ">>> Write /etc/nginx/nginx.conf ..."
tmp_ng="$(mktemp)"
cat > "${tmp_ng}" <<"EOF"
user  www-data;
worker_processes  auto;

load_module /usr/lib/nginx/modules/ngx_http_headers_more_filter_module.so;

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
    autoindex off;

    include /etc/nginx/conf.d/*.conf;

    server {
        listen 80 default_server;
        server_name _;
        root /www;
        index index.html index.php;

        error_page 404 /errors/404.html;
        error_page 500 502 503 504 /errors/50x.html;
        include /etc/nginx/snippets/error-pages-locations.conf;

        location / { try_files $uri $uri/ /index.html; }
    }
}
EOF
install -m0644 "${tmp_ng}" /etc/nginx/nginx.conf
rm -f "${tmp_ng}"

echo ">>> Write error-pages snippet ..."
install -d -m0755 /etc/nginx/snippets
tmp_sn="$(mktemp)"
cat > "${tmp_sn}" <<"EOF"
location = /errors/404.html { internal; }
location = /errors/50x.html { internal; }
EOF
install -m0644 "${tmp_sn}" /etc/nginx/snippets/error-pages-locations.conf
rm -f "${tmp_sn}"

echo ">>> Write stealth & security to /etc/nginx/conf.d/00-stealth-security.conf ..."
install -d -m0755 /etc/nginx/conf.d
tmp_st="$(mktemp)"
cat > "${tmp_st}" <<"EOF"
server_tokens off;

# http-scope split_clients to generate fake brand
split_clients "${msec}${remote_addr}${request_length}${uri}" $fake_server {
    20% "Apache";
    20% "cloudflare";
    20% "LiteSpeed";
    20% "Varnish";
    *   "ATS";
}

# Overwrite Server header (headers-more)
more_clear_headers Server;
more_set_headers   "Server: $fake_server";

# Strip common leaks & upstream banners
more_clear_headers X-Powered-By;
proxy_hide_header  Server;
fastcgi_hide_header X-Powered-By;
fastcgi_hide_header Server;

# Security headers; 'always' to cover 4xx/5xx as well
add_header X-Content-Type-Options nosniff always;
add_header X-Frame-Options DENY always;
add_header Referrer-Policy no-referrer-when-downgrade always;
add_header Permissions-Policy "geolocation=(), camera=(), microphone=()" always;
EOF
install -m0644 "${tmp_st}" /etc/nginx/conf.d/00-stealth-security.conf
rm -f "${tmp_st}"

echo ">>> Ship disabled example vhosts (*.conf.example) ..."
# php-fpm example
tmp_pf="$(mktemp)"
cat > "${tmp_pf}" <<"EOF"
# /etc/nginx/conf.d/php-fpm.conf.example (disabled by default)
server {
    listen 80;
    server_name _;
    root /www;
    index index.php index.html;

    error_page 404 /errors/404.html;
    error_page 500 502 503 504 /errors/50x.html;
    include /etc/nginx/snippets/error-pages-locations.conf;

    location / { try_files $uri $uri/ /index.php?$args; }

    # FastCGI (SCRIPT_FILENAME + pass to php-fpm)
    location ~ \.php$ {
        try_files $uri =404;
        include /etc/nginx/fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_pass unix:/run/php/php-fpm.sock;   # or 127.0.0.1:9000
    }

    location ~ /\.ht { deny all; }
}
EOF
install -m0644 "${tmp_pf}" /etc/nginx/conf.d/php-fpm.conf.example
rm -f "${tmp_pf}"

# proxy-pass example
tmp_px="$(mktemp)"
cat > "${tmp_px}" <<"EOF"
# /etc/nginx/conf.d/proxy-pass.conf.example (disabled by default)
server {
    listen 80;
    server_name _;
    root /www;

    error_page 404 /errors/404.html;
    error_page 500 502 503 504 /errors/50x.html;
    include /etc/nginx/snippets/error-pages-locations.conf;

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
install -m0644 "${tmp_px}" /etc/nginx/conf.d/proxy-pass.conf.example
rm -f "${tmp_px}"

echo ">>> Write systemd unit ..."
tmp_sd="$(mktemp)"
cat > "${tmp_sd}" <<"EOF"
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
install -m0644 "${tmp_sd}" /etc/systemd/system/nginx.service
rm -f "${tmp_sd}"

echo ">>> Test & enable..."
systemctl daemon-reload
/usr/sbin/nginx -t
systemctl enable --now nginx

echo ">>> Done."
echo "Examples are disabled by default:"
echo "  - /etc/nginx/conf.d/php-fpm.conf.example"
echo "  - /etc/nginx/conf.d/proxy-pass.conf.example"
echo "Enable by: cp *.conf.example *.conf && nginx -t && systemctl reload nginx"
