#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# setup-php84-fpm.sh
#
# Purpose  : Install PHP 8.4 FPM on Ubuntu and start the service.
# OS       : Ubuntu 22.04 (Jammy) - 64-bit
# User     : Must be run as root.
# Features :
#   - Adds ppa:ondrej/php
#   - Installs php8.4-fpm + php8.4-cli + php8.4-opcache
#   - Enables & starts php8.4-fpm
#   - Prints the FPM socket and creates /run/php/php-fpm.sock symlink
# Usage    :
#   sudo -i
#   bash setup-php84-fpm.sh
# -----------------------------------------------------------------------------

set -euo pipefail

[[ "$(id -u)" -eq 0 ]] || { echo "Please run as root."; exit 1; }

export DEBIAN_FRONTEND=noninteractive

echo ">>> Installing prerequisites ..."
apt-get update -y
apt-get install -y --no-install-recommends software-properties-common ca-certificates curl

echo ">>> Adding PPA: ondrej/php ..."
add-apt-repository -y ppa:ondrej/php
apt-get update -y

echo ">>> Installing PHP 8.4 FPM ..."
apt-get install -y php8.4-fpm php8.4-cli php8.4-common php8.4-opcache

echo ">>> Enabling and starting php8.4-fpm ..."
systemctl enable --now php8.4-fpm

POOL_CONF="/etc/php/8.4/fpm/pool.d/www.conf"
if [[ ! -r "${POOL_CONF}" ]]; then
  echo "Pool config not found: ${POOL_CONF}" >&2
  exit 1
fi

SOCKET="$(awk -F= '/^[[:space:]]*listen[[:space:]]*=/{gsub(/[[:space:]]/,"",$2); print $2; exit}' "${POOL_CONF}")"
mkdir -p /run/php
if [[ -n "${SOCKET}" ]]; then
  ln -sfn "${SOCKET}" /run/php/php-fpm.sock
fi

echo
echo "PHP-FPM version:"
php-fpm8.4 -v || php-fpm -v || true
echo
echo "Pool config : ${POOL_CONF}"
echo "FPM socket  : ${SOCKET:-<unknown>}"
echo
echo "✅ Done. NGINX can use: fastcgi_pass unix:/run/php/php-fpm.sock;"
