#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# build-nginx-stable-stealth.sh  (rev2: purge NGINX-branded pages)
# Build NGINX 1.28.0, ship disabled examples, stealth headers, and custom pages.
# Default vhost uses /www and includes error-page snippet; builtin html removed.
# -----------------------------------------------------------------------------

set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo "Please run as root."; exit 1; }
export DEBIAN_FRONTEND=noninteractive
FORCE="${FORCE:-0}"

NGINX_VERSION="1.28.0"
TARBALL_URL="https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"

echo ">>> Preflight (use FORCE=1 to proceed anyway)..."
if systemctl list-units --type=service --all | grep -qE '^\s*nginx\.service'; then
  state="$(systemctl is-active nginx || true)"
  unit_path="$(systemctl cat nginx | head -n1 | sed 's/^# //')"
  echo " - nginx.service: ${state} -> ${unit_path}"
  [[ "$state" == "active" ]] && echo "   WARN: nginx is running; consider: systemctl stop nginx"
fi
command -v nginx >/dev/null 2>&1 && { echo " - current nginx: $(command -v nginx) ($(\nginx -v 2>&1 || true))"; }
dpkg -l 'nginx*' 2>/dev/null | awk '/^ii/{print " - apt package: "$2" "$3}' || true
ss -ltn 'sport = :80'  | tail -n +2 | grep -q . && echo " - port 80 in use (non-fatal)"
ss -ltn 'sport = :443' | tail -n +2 | grep -q . && echo " - port 443 in use (non-fatal)"
if [[ -d /etc/nginx ]]; then
  ds_count="$(grep -R --include='*.conf' -nE '^\s*listen\s+.*\bdefault_server\b' /etc/nginx 2>/dev/null | wc -l || true)"
  [[ "$ds_count" -gt 1 ]] && echo " - WARN: multiple default_server listeners ($ds_count)"
fi
[[ "$FORCE" == "1" ]] || { echo ">>> Preflight done. Proceed with: FORCE=1 bash $(basename "$0")"; exit 2; }

echo ">>> Installing build deps..."
apt-get update -y
apt-get install -y build-essential git curl ca-certificates wget perl \
  libpcre2-dev zlib1g-dev libssl-dev tar xz-utils unzip

TMPDIR="$(mktemp -d)"; cd "$TMPDIR"
echo ">>> Downloading $TARBALL_URL"
curl -fL "$TARBALL_URL" -o "nginx.tar.gz"
tar -xzf nginx.tar.gz
cd "nginx-${NGINX_VERSION}"

# runtime dirs / user (www-data)
id -u www-data >/dev/null 2>&1 || adduser --system --no-create-home --group --shell /usr/sbin/nologin www-data
install -d -m0755 /etc/nginx /etc/nginx/conf.d /etc/nginx/snippets /var/log/nginx /var/cache/nginx /usr/lib/nginx/modules

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
  --with-ld-opt='-Wl,-z,relro -Wl,-z,now'   # --with-compat helps dyn-mod compatibility. :contentReference[oaicite:1]{index=1}

echo ">>> Building & installing..."
make -j"$(nproc)"
make install

# base files
[[ -f /etc/nginx/mime.types     ]] || install -m0644 ./conf/mime.types /etc/nginx/mime.types
[[ -f /etc/nginx/fastcgi_params ]] || install -m0644 ./conf/fastcgi_params /etc/nginx/fastcgi_params

# site root & custom pages (no nginx branding)
install -d -m0755 /www /www/errors
[[ -f /www/index.html ]] || printf "<!doctype html><meta charset=utf-8><title>OK</title><h1>OK</h1>\n" > /www/index.html
printf "<!doctype html><meta charset=utf-8><title>Not Found</title><h1>404 Not Found</h1>\n" > /www/errors/404.html
printf "<!doctype html><meta charset=utf-8><title>Error</title><h1>Service Error</h1>\n"       > /www/errors/50x.html
chown -R www-data:www-data /www

# remove bundled welcome/error pages to avoid fallback showing "Welcome to nginx!"
rm -f /usr/local/nginx/html/index.html /usr/local/nginx/html/50x.html 2>/dev/null || true
rm -f /usr/share/nginx/html/index.html /usr/share/nginx/html/50x.html 2>/dev/null || true  # some distros use this path. :contentReference[oaicite:2]{index=2}

# main config (includes conf.d, uses www-data, default_server -> /www, includes snippet)
if [[ ! -f /etc/nginx/nginx.conf ]]; then
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
    autoindex off;

    include /etc/nginx/conf.d/*.conf;

    server {
        listen 80 default_server;
        server_name _;
        root /www;

        # global error pages for default vhost
        error_page 404 /errors/404.html;
        error_page 500 502 503 504 /errors/50x.html;
        include /etc/nginx/snippets/error-pages-locations.conf;

        location / { try_files $uri $uri/ =404; }
    }
}
EOF
else
  # ensure conf.d include and user www-data
  grep -q 'include /etc/nginx/conf\.d/\*\.conf;' /etc/nginx/nginx.conf || \
    awk 'BEGIN{a=0} /^http[[:space:]]*\{/ && !a {print;print "    include /etc/nginx/conf.d/*.conf;";a=1;next} {print}' \
      /etc/nginx/nginx.conf > /etc/nginx/nginx.conf.tmp && mv /etc/nginx/nginx.conf.tmp /etc/nginx/nginx.conf
  sed -ri '0,/^\s*user\s+/s//user  www-data;/' /etc/nginx/nginx.conf || true
fi

# snippet: server-scope locations for error pages (cannot live in http {}) :contentReference[oaicite:3]{index=3}
cat > /etc/nginx/snippets/error-pages-locations.conf <<"EOF"
location = /errors/404.html { internal; }
location = /errors/50x.html { internal; }
EOF

# disabled examples
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

# build headers-more dyn module; load at top; http-scope stealth (split_clients + always)
echo ">>> Building headers-more module..."
cd "$TMPDIR"
git clone --depth=1 https://github.com/openresty/headers-more-nginx-module.git
cd "nginx-${NGINX_VERSION}"
./configure --with-compat --add-dynamic-module=../headers-more-nginx-module
make modules
install -m644 objs/ngx_http_headers_more_filter_module.so /usr/lib/nginx/modules/

grep -q 'ngx_http_headers_more_filter_module\.so' /etc/nginx/nginx.conf || \
  sed -i '1iload_module /usr/lib/nginx/modules/ngx_http_headers_more_filter_module.so;' /etc/nginx/nginx.conf

cat > /etc/nginx/conf.d/00-stealth-security.conf <<"EOF"
server_tokens off;

# http-scope: split_clients (generate $fake_server) :contentReference[oaicite:5]{index=5}
split_clients "${msec}${remote_addr}${request_length}${uri}" $fake_server {
    20% "Apache";
    20% "cloudflare";
    20% "LiteSpeed";
    20% "Varnish";
    *   "ATS";
}

# overwrite Server header (needs headers-more) :contentReference[oaicite:6]{index=6}
more_clear_headers Server;
more_set_headers   "Server: $fake_server";

# strip common leaks
more_clear_headers X-Powered-By;
proxy_hide_header  Server;
fastcgi_hide_header X-Powered-By;
fastcgi_hide_header Server;

# security headers; 'always' to cover 4xx/5xx, per docs. :contentReference[oaicite:7]{index=7}
add_header X-Content-Type-Options nosniff always;
add_header X-Frame-Options DENY always;
add_header Referrer-Policy no-referrer-when-downgrade always;
add_header Permissions-Policy "geolocation=(), camera=(), microphone=()" always;
EOF

# systemd unit
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
echo "Default vhost: /www (no NGINX branding)."
echo "Examples (disabled): /etc/nginx/conf.d/php-fpm.conf.example, proxy-pass.conf.example"
echo "Enable by: cp *.conf.example *.conf && nginx -t && systemctl reload nginx"
