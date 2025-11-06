#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# build-nginx-stable-stealth.sh
#
# Build & install NGINX 1.28.0 from fixed URL, create conf.d, add php-fpm/proxy
# samples, and apply "stealth" hardening (randomized Server header via
# headers-more + split_clients). Fixed so that all location{} live in server{}.
# OS  : Ubuntu 22.04
# User: root
# -----------------------------------------------------------------------------

set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo "Please run as root."; exit 1; }
export DEBIAN_FRONTEND=noninteractive

# ====== version & URL =========================================================
NGINX_VERSION="1.28.0"
BASE_URL="https://nginx.org/download"
TARBALL="nginx-${NGINX_VERSION}.tar.gz"
TARBALL_URL="${BASE_URL}/${TARBALL}"

# ====== deps ==================================================================
echo ">>> Installing build dependencies..."
apt-get update -y
apt-get install -y \
  build-essential git curl ca-certificates wget perl \
  libpcre2-dev zlib1g-dev libssl-dev tar xz-utils unzip

# ====== download & unpack =====================================================
TMPDIR="$(mktemp -d)"
echo ">>> Working in ${TMPDIR}"
cd "${TMPDIR}"
echo ">>> Downloading ${TARBALL_URL}"
curl -fL "${TARBALL_URL}" -o "${TARBALL}"
tar -xzf "${TARBALL}"
cd "nginx-${NGINX_VERSION}"

# ====== runtime users/dirs ====================================================
id -u nginx >/dev/null 2>&1 || adduser --system --no-create-home --group --shell /usr/sbin/nologin nginx
install -d -m0755 /etc/nginx /etc/nginx/conf.d /var/log/nginx /var/cache/nginx /usr/lib/nginx/modules

# ====== configure & build nginx ==============================================
# Official flags; keep --with-compat for dynamic modules later. :contentReference[oaicite:1]{index=1}
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

# ====== base config (ensure conf.d and includes) ==============================
[[ -f /etc/nginx/mime.types ]]     || install -m0644 ./conf/mime.types /etc/nginx/mime.types
[[ -f /etc/nginx/fastcgi_params ]] || install -m0644 ./conf/fastcgi_params /etc/nginx/fastcgi_params

# Main config (includes conf.d)
install -d -m0755 /www
[[ -f /www/index.html ]] || printf "<!doctype html><title>OK</title><h1>OK</h1>\n" > /www/index.html
install -d -m0755 /www/errors
printf "<!doctype html><title>Not Found</title><h1>404 Not Found</h1>\n" > /www/errors/404.html
printf "<!doctype html><title>Error</title><h1>Service Error</h1>\n"       > /www/errors/50x.html

if [[ ! -f /etc/nginx/nginx.conf ]]; then
  echo ">>> Writing /etc/nginx/nginx.conf ..."
  cat > /etc/nginx/nginx.conf <<"EOF"
user  nginx;
worker_processes  auto;

# dynamic modules will be loaded below by sed if headers-more is built
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

    sendfile on;
    tcp_nopush on;
    keepalive_timeout 65;
    gzip on;

    # Load extra vhosts
    include /etc/nginx/conf.d/*.conf;

    # Default site (server context可放location与error_page) :contentReference[oaicite:2]{index=2}
    server {
        listen 80 default_server;
        server_name _;
        root /www;

        # error pages + their location{} 必须放在 server{} (location 不能在 http{}) :contentReference[oaicite:3]{index=3}
        error_page 404 /errors/404.html;
        error_page 500 502 503 504 /errors/50x.html;
        location = /errors/404.html { internal; }
        location = /errors/50x.html { internal; }

        location / { try_files $uri $uri/ =404; }
    }
}
EOF
else
  if ! grep -q 'include /etc/nginx/conf\.d/\*\.conf;' /etc/nginx/nginx.conf; then
    awk '
      BEGIN{added=0}
      /^http[[:space:]]*\{/ && !added { print; print "    include /etc/nginx/conf.d/*.conf;"; added=1; next }
      { print }
    ' /etc/nginx/nginx.conf > /etc/nginx/nginx.conf.tmp && mv /etc/nginx/nginx.conf.tmp /etc/nginx/nginx.conf
  fi
fi

# ====== conf.d: PHP-FPM example ========
[[ -f /www/index.php ]] || printf "<?php phpinfo();\n" > /www/index.php
cat > /etc/nginx/conf.d/php-fpm-example.conf <<"EOF"
# /etc/nginx/conf.d/php-fpm-example.conf
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

    # FastCGI to php-fpm；SCRIPT_FILENAME 来自官方写法。:contentReference[oaicite:4]{index=4}
    location ~ \.php$ {
        try_files $uri =404;
        include /etc/nginx/fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_pass unix:/run/php/php-fpm.sock;   # 或 127.0.0.1:9000
    }

    location ~ /\.ht { deny all; }
}
EOF

# ====== conf.d: proxy_pass example ===============================
cat > /etc/nginx/conf.d/proxy-pass-example.conf <<"EOF"
# /etc/nginx/conf.d/proxy-pass-example.conf
server {
    listen       80;
    server_name  _;
    root         /www;

    error_page 404 /errors/404.html;
    error_page 500 502 503 504 /errors/50x.html;
    location = /errors/404.html { internal; }
    location = /errors/50x.html { internal; }

    location /app/ {
        proxy_pass http://127.0.0.1:3000/;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection        "";
    }

    location /ws {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host       $host;
    }
}
EOF

# ====== build headers-more dynamic module & stealth config ====================
echo ">>> Building headers-more dynamic module..."
cd "${TMPDIR}"
git clone --depth=1 https://github.com/openresty/headers-more-nginx-module.git
cd "nginx-${NGINX_VERSION}"
./configure --with-compat --add-dynamic-module=../headers-more-nginx-module
make modules
install -m644 objs/ngx_http_headers_more_filter_module.so /usr/lib/nginx/modules/

if ! grep -q 'ngx_http_headers_more_filter_module\.so' /etc/nginx/nginx.conf; then
  sed -i '1iload_module /usr/lib/nginx/modules/ngx_http_headers_more_filter_module.so;' /etc/nginx/nginx.conf
fi

cat > /etc/nginx/conf.d/00-stealth-security.conf <<"EOF"
# Hide version; brand will be overridden below.
server_tokens off;

# Pseudo-random fake brands per request (http scope) :contentReference[oaicite:7]{index=7}
split_clients "${msec}${remote_addr}${request_length}${uri}" $fake_server {
    20% "Apache";
    20% "cloudflare";
    20% "LiteSpeed";
    20% "Varnish";
    *   "ATS";
}

# Remove & overwrite Server header (headers-more; allowed in http) :contentReference[oaicite:8]{index=8}
more_clear_headers Server;
more_set_headers   "Server: $fake_server";

# Remove common leaks & upstream banners
more_clear_headers X-Powered-By;
proxy_hide_header  Server;
fastcgi_hide_header X-Powered-By;
fastcgi_hide_header Server;

# Conservative security headers (extend with HSTS/CSP when HTTPS is enabled)
add_header X-Content-Type-Options nosniff always;
add_header X-Frame-Options DENY always;
add_header Referrer-Policy no-referrer-when-downgrade always;
add_header Permissions-Policy "geolocation=(), camera=(), microphone=()" always;
EOF

# Disable PHP "X-Powered-By" for ALL installed php-fpm versions (generic)
# Works for Debian/Ubuntu PHP packages that use /etc/php/<ver>/fpm/conf.d
shopt -s nullglob
for fpm_dir in /etc/php/*/fpm; do
  ver="${fpm_dir#/etc/php/}"; ver="${ver%/fpm}"        # e.g. "8.4"
  ini_d="${fpm_dir}/conf.d"
  install -d -m0755 "${ini_d}"
  cat > "${ini_d}/zz-hardening.ini" <<'INI'
; hardening: hide PHP signature in HTTP responses
expose_php = Off
INI
  # Reload that specific FPM service if present
  systemctl reload "php${ver}-fpm" 2>/dev/null || \
  systemctl try-reload-or-restart "php${ver}-fpm" 2>/dev/null || true
done
shopt -u nullglob

# ====== systemd unit ==========================================================
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
nginx -v
echo ">>> Build args:"
nginx -V 2>&1 | tr ';' '\n' | sed 's/^ \+//'

# cleanup
rm -rf "${TMPDIR}"
