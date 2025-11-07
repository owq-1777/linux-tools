#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# build-nginx-stable-stealth.sh (force overwrite)
#
# Build & install NGINX 1.28.0 from fixed URL, always overwrite nginx.conf,
# ship DISABLED examples (*.conf.example), apply stealth hardening (headers-more
# + split_clients), use www-data everywhere, and remove branded default pages.
# OS  : Ubuntu 22.04
# User: root
# -----------------------------------------------------------------------------

set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo "Please run as root."; exit 1; }
export DEBIAN_FRONTEND=noninteractive
FORCE="${FORCE:-1}"   # default to 1 now (force)

NGINX_VERSION="1.28.0"
TARBALL_URL="https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"

ts() { date +%Y%m%d-%H%M%S; }
backup() { local p="$1"; [[ -e "$p" || -L "$p" ]] && cp -a "$p" "${p}.bak-$(ts)"; }

echo ">>> Preflight..."
# show current binary & apt packages (informational)
command -v nginx >/dev/null 2>&1 && echo " - current nginx: $(command -v nginx) ($(\nginx -v 2>&1 || true))"
dpkg -l 'nginx*' 2>/dev/null | awk '/^ii/{print " - apt package: "$2" "$3}' || true
ss -ltn 'sport = :80'  | tail -n +2 | grep -q . && echo " - port 80 in use (non-fatal)"
ss -ltn 'sport = :443' | tail -n +2 | grep -q . && echo " - port 443 in use (non-fatal)"
[[ "$FORCE" == "1" ]] || { echo "Set FORCE=1 to proceed."; exit 2; }

echo ">>> Installing build deps..."
apt-get update -y
apt-get install -y build-essential git curl ca-certificates wget perl \
  libpcre2-dev zlib1g-dev libssl-dev tar xz-utils unzip

TMPDIR="$(mktemp -d)"; cd "$TMPDIR"
echo ">>> Downloading $TARBALL_URL"
curl -fL "$TARBALL_URL" -o nginx.tar.gz
tar -xzf nginx.tar.gz
cd "nginx-${NGINX_VERSION}"

# runtime user/dirs
id -u www-data >/dev/null 2>&1 || adduser --system --no-create-home --group --shell /usr/sbin/nologin www-data
install -d -m0755 /etc/nginx /etc/nginx/conf.d /etc/nginx/snippets /var/log/nginx /var/cache/nginx /usr/lib/nginx/modules

echo ">>> Configuring core..."
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
# (configure flags per official docs; --with-compat aids dyn-module ABI) :contentReference[oaicite:1]{index=1}

echo ">>> Building & installing core..."
make -j"$(nproc)"
make install

# Always install fresh copies of base includes (force overwrite)
install -m0644 ./conf/mime.types     /etc/nginx/mime.types
install -m0644 ./conf/fastcgi_params /etc/nginx/fastcgi_params

# Remove bundled branded pages to avoid fallback
rm -f /usr/local/nginx/html/index.html /usr/local/nginx/html/50x.html 2>/dev/null || true
rm -f /usr/share/nginx/html/index.html /usr/share/nginx/html/50x.html 2>/dev/null || true

# Build headers-more dynamic module (lets us clear/set built-in Server header) :contentReference[oaicite:2]{index=2}
echo ">>> Building headers-more module..."
cd "$TMPDIR"
git clone --depth=1 https://github.com/openresty/headers-more-nginx-module.git
cd "nginx-${NGINX_VERSION}"
./configure --with-compat --add-dynamic-module=../headers-more-nginx-module
make modules
install -m644 objs/ngx_http_headers_more_filter_module.so /usr/lib/nginx/modules/

# Site root & custom pages (no nginx branding)
install -d -m0755 /www /www/errors
[[ -f /www/index.html ]] || printf "<!doctype html><meta charset=utf-8><title>OK</title><h1>OK</h1>\n" > /www/index.html
printf "<!doctype html><meta charset=utf-8><title>Not Found</title><h1>404 Not Found</h1>\n" > /www/errors/404.html
printf "<!doctype html><meta charset=utf-8><title>Error</title><h1>Service Error</h1>\n"       > /www/errors/50x.html
chown -R www-data:www-data /www

# -----------------------------------------------------------------------------
# FORCE-OVERWRITE nginx.conf (backup then replace)
# -----------------------------------------------------------------------------
backup /etc/nginx/nginx.conf
cat > /etc/nginx/nginx.conf <<"EOF"
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

    # Load additional configs
    include /etc/nginx/conf.d/*.conf;

    # Default site using /www with custom error pages
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

# Snippet: server-scope locations for error pages (must live in server{}, not http{}) :contentReference[oaicite:3]{index=3}
backup /etc/nginx/snippets/error-pages-locations.conf
cat > /etc/nginx/snippets/error-pages-locations.conf <<"EOF"
location = /errors/404.html { internal; }
location = /errors/50x.html { internal; }
EOF

# DISABLED examples (do not load by default)
backup /etc/nginx/conf.d/php-fpm.conf.example || true
cat > /etc/nginx/conf.d/php-fpm.conf.example <<"EOF"
server {
    listen 80;
    server_name _;
    root /www;
    index index.php index.html;

    error_page 404 /errors/404.html;
    error_page 500 502 503 504 /errors/50x.html;
    include /etc/nginx/snippets/error-pages-locations.conf;

    location / { try_files $uri $uri/ /index.php?$args; }

    # FastCGI per official docs: SCRIPT_FILENAME + pass to php-fpm. :contentReference[oaicite:4]{index=4}
    location ~ \.php$ {
        try_files $uri =404;
        include /etc/nginx/fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_pass unix:/run/php/php-fpm.sock;   # or 127.0.0.1:9000
    }

    location ~ /\.ht { deny all; }
}
EOF

backup /etc/nginx/conf.d/proxy-pass.conf.example || true
cat > /etc/nginx/conf.d/proxy-pass.conf.example <<"EOF"
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

# HTTP-scope stealth (split_clients; add_header with 'always'; clear/set Server via headers-more)
backup /etc/nginx/conf.d/00-stealth-security.conf
cat > /etc/nginx/conf.d/00-stealth-security.conf <<"EOF"
server_tokens off;

# http-scope variable for random brand (split_clients is http-only) :contentReference[oaicite:5]{index=5}
split_clients "${msec}${remote_addr}${request_length}${uri}" $fake_server {
    20% "Apache";
    20% "cloudflare";
    20% "LiteSpeed";
    20% "Varnish";
    *   "ATS";
}

# Clear & overwrite Server header (headers-more supports built-in headers) :contentReference[oaicite:6]{index=6}
more_clear_headers Server;
more_set_headers   "Server: $fake_server";

# Strip common leaks and upstream banners
more_clear_headers X-Powered-By;
proxy_hide_header  Server;
fastcgi_hide_header X-Powered-By;
fastcgi_hide_header Server;

# Security headers; 'always' to cover 4xx/5xx too :contentReference[oaicite:7]{index=7}
add_header X-Content-Type-Options nosniff always;
add_header X-Frame-Options DENY always;
add_header Referrer-Policy no-referrer-when-downgrade always;
add_header Permissions-Policy "geolocation=(), camera=(), microphone=()" always;
EOF

# systemd unit (force overwrite)
backup /etc/systemd/system/nginx.service
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

echo ">>> Done."
echo "Examples are disabled by default:"
echo "  - /etc/nginx/conf.d/php-fpm.conf.example"
echo "  - /etc/nginx/conf.d/proxy-pass.conf.example"
echo "Enable by: cp *.conf.example *.conf && nginx -t && systemctl reload nginx"
