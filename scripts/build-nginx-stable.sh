#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# build-nginx-stable.sh
#
# Purpose  : Build latest STABLE NGINX from source, hide brand/version,
#            and add a PHP-FPM (FastCGI) example vhost.
# OS       : Ubuntu 22.04 (Jammy) - 64-bit
# User     : Must be run as root.
# Features :
#   - Parse nginx.org download page to get the latest *stable* tarball
#   - Build with headers-more module to remove the Server header
#   - server_tokens off; more_clear_headers Server;
#   - Hide FastCGI / upstream headers (X-Powered-By, Server)
#   - Provide php-fpm sample vhost (socket or TCP) + /www with phpinfo()
#   - Install systemd unit, test config, enable & start
# Usage    :
#   sudo -i
#   bash build-nginx-stable.sh
# -----------------------------------------------------------------------------

set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo "Please run as root."; exit 1; }
export DEBIAN_FRONTEND=noninteractive

SRCDIR="/usr/local/src"
INSTALL_SBIN="/usr/sbin/nginx"
CONF_DIR="/etc/nginx"
CONF_MAIN="${CONF_DIR}/nginx.conf"
CONF_D="${CONF_DIR}/conf.d"
LOG_DIR="/var/log/nginx"
CACHE_DIR="/var/cache/nginx"
MOD_DIR="/usr/lib/nginx/modules"
WWW_ROOT="/www"

echo ">>> Installing build dependencies..."
apt-get update -y
apt-get install -y \
  build-essential git curl ca-certificates wget perl \
  libpcre2-dev zlib1g-dev libssl-dev tar xz-utils unzip

echo ">>> Detecting latest STABLE tarball from nginx.org ..."
DL_HTML="$(curl -fsSL https://nginx.org/en/download.html)"
TARBALL_URL="$(printf '%s' "${DL_HTML}" | perl -0777 -ne 'if(/Stable version.*?href="([^"]*nginx-[0-9.]+\.tar\.gz)"/s){print $1}' || true)"
[[ -n "${TARBALL_URL}" ]] || { echo "Cannot find stable tarball URL."; exit 1; }
TARBALL_NAME="$(basename "${TARBALL_URL}")"
NGINX_VER="$(sed -E 's/^nginx-([0-9.]+)\.tar\.gz$/\1/' <<<"${TARBALL_NAME}")"
echo ">>> Stable: nginx-${NGINX_VER}  (${TARBALL_URL})"

mkdir -p "${SRCDIR}"; cd "${SRCDIR}"
rm -rf "nginx-${NGINX_VER}" "${TARBALL_NAME}"
curl -fL "${TARBALL_URL}" -o "${TARBALL_NAME}"
tar -xzf "${TARBALL_NAME}"
cd "nginx-${NGINX_VER}"

echo ">>> Fetching headers-more module (to clear Server header)..."
cd "${SRCDIR}"
rm -rf headers-more-nginx-module
git clone --depth=1 https://github.com/openresty/headers-more-nginx-module.git
HMORE_PATH="${SRCDIR}/headers-more-nginx-module"
cd "nginx-${NGINX_VER}"

echo ">>> Ensuring runtime users/dirs..."
id -u nginx >/dev/null 2>&1 || adduser --system --no-create-home --group --shell /usr/sbin/nologin nginx
install -d -m0755 "${CONF_DIR}" "${CONF_D}" "${LOG_DIR}" "${CACHE_DIR}" "${MOD_DIR}" "${WWW_ROOT}"

echo ">>> Configuring..."
./configure \
  --prefix=/usr/local/nginx \
  --sbin-path="${INSTALL_SBIN}" \
  --modules-path="${MOD_DIR}" \
  --conf-path="${CONF_MAIN}" \
  --error-log-path="${LOG_DIR}/error.log" \
  --http-log-path="${LOG_DIR}/access.log" \
  --pid-path=/run/nginx.pid \
  --lock-path=/var/lock/nginx.lock \
  --with-threads \
  --with-file-aio \
  --with-pcre2 \
  --with-http_ssl_module \
  --with-http_v2_module \
  --with-http_gzip_static_module \
  --with-http_stub_status_module \
  --with-stream \
  --with-stream_ssl_module \
  --add-module="${HMORE_PATH}" \
  --with-cc-opt='-O2 -fstack-protector-strong -fPIC' \
  --with-ld-opt='-Wl,-z,relro -Wl,-z,now'

echo ">>> Building & installing ..."
make -j"$(nproc)"
make install

# ----- base configs (mime/fastcgi params) -----
[[ -f "${CONF_DIR}/mime.types" ]]     || install -m0644 "${SRCDIR}/nginx-${NGINX_VER}/conf/mime.types" "${CONF_DIR}/mime.types"
[[ -f "${CONF_DIR}/fastcgi_params" ]] || install -m0644 "${SRCDIR}/nginx-${NGINX_VER}/conf/fastcgi_params" "${CONF_DIR}/fastcgi_params"

# ----- main nginx.conf (stealth + hardening) -----
cat > "${CONF_MAIN}" <<'NGX'
user  nginx;
worker_processes auto;

error_log  /var/log/nginx/error.log notice;
pid        /run/nginx.pid;

events { worker_connections 1024; }

http {
    include       mime.types;
    default_type  application/octet-stream;

    # ---- Stealth ----
    server_tokens off;             # hide version; not removing header by itself
    more_clear_headers Server;     # requires headers-more; drop Server header entirely

    # Hide upstream/FastCGI headers that may disclose stack details
    proxy_hide_header Server;      # (proxy upstreams)
    fastcgi_hide_header X-Powered-By;
    fastcgi_hide_header Server;

    # Basic security headers
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options DENY always;
    add_header Referrer-Policy no-referrer-when-downgrade always;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" "$http_user_agent"';
    access_log  /var/log/nginx/access.log main;

    sendfile on; tcp_nopush on; keepalive_timeout 65;

    # Default site with custom error pages (no nginx branding)
    server {
        listen 80 default_server;
        server_name _;
        root /www;
        index index.html;

        error_page 404 /errors/404.html;
        error_page 500 502 503 504 /errors/50x.html;
        location = /errors/404.html { internal; }
        location = /errors/50x.html { internal; }

        location / { try_files $uri $uri/ =404; }
    }

    include /etc/nginx/conf.d/*.conf;
}
NGX

# ----- PHP-FPM example vhost -----
install -d -m0755 "${WWW_ROOT}"
[[ -f "${WWW_ROOT}/index.html" ]] || printf '<!doctype html><title>OK</title><h1>OK</h1>\n' > "${WWW_ROOT}/index.html"
[[ -f "${WWW_ROOT}/index.php" ]]  || cat > "${WWW_ROOT}/index.php" <<'PHP'
<?php phpinfo();
PHP
cat > "${CONF_D}/php-fpm-example.conf" <<'EOF'
server {
    listen       80;
    server_name  _;
    root         /www;
    index        index.php index.html;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        try_files $uri =404;
        include /etc/nginx/fastcgi_params;
        # SCRIPT_FILENAME from doc: combine $document_root + $fastcgi_script_name
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;

        # --- Option A: UNIX socket (adjust to your php-fpm version socket) ---
        fastcgi_pass unix:/run/php/php-fpm.sock;

        # --- Option B: TCP listener ---
        # fastcgi_pass 127.0.0.1:9000;
    }

    location ~ /\.ht { deny all; }
}
EOF

# ----- systemd unit -----
cat > /etc/systemd/system/nginx.service <<"UNIT"
[Unit]
Description=NGINX web server (stealth build)
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
UNIT

systemctl daemon-reload
"${INSTALL_SBIN}" -t
systemctl enable --now nginx

echo ">>> Installed $(nginx -v 2>&1)"
echo ">>> Verify: curl -I http://127.0.0.1 | sed -n '1,/^$/p'"
echo ">>> Expect: no 'Server:' header; PHP: /www/index.php shows phpinfo() via FastCGI."
