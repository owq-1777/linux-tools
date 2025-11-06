#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# setup-latest-php-fpm.sh
#
# Purpose  : Install the latest stable php-fpm available for Ubuntu via the
#            Ondřej Surý PPA, enable and start the service, and show the socket.
# OS       : Ubuntu 22.04 (Jammy) - 64-bit
# User     : Must be run as root.
# Features :
#   - Adds ppa:ondrej/php (widely used for up-to-date PHP on Ubuntu)
#   - Detects the highest phpX.Y-fpm package available and installs it
#   - Enables & starts phpX.Y-fpm service
#   - Prints detected PHP version and the FPM socket path from www.conf
#   - Idempotent: safe to re-run
# Usage    :
#   sudo -i
#   bash setup-latest-php-fpm.sh
# Notes    :
#   - The socket path comes from /etc/php/<ver>/fpm/pool.d/www.conf (listen=).
#   - Optionally creates a convenience symlink /run/php/php-fpm.sock if the
#     socket exists, for easier NGINX config.
# -----------------------------------------------------------------------------

set -euo pipefail

# ---- root requirement --------------------------------------------------------
if [[ "$(id -u)" -ne 0 ]]; then
  echo "Please run as root (e.g., sudo -i && bash setup-latest-php-fpm.sh)." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo ">>> Installing prerequisites ..."
apt-get update -y
apt-get install -y --no-install-recommends software-properties-common ca-certificates curl

# ---- Add Ondřej Surý PHP PPA (de-facto repo for latest PHP on Ubuntu) --------
# ref: https://launchpad.net/~ondrej/+archive/ubuntu/php
echo ">>> Adding PPA: ondrej/php ..."
add-apt-repository -y ppa:ondrej/php
apt-get update -y

# ---- Detect the highest phpX.Y-fpm available in APT --------------------------
echo ">>> Detecting latest php-fpm package ..."
PKG="$(apt-cache search php-fpm | awk '{print $1}' | grep -E '^php[0-9]\.[0-9]-fpm$' | sort -V | tail -1 || true)"
if [[ -z "${PKG}" ]]; then
  echo "Error: Could not find any phpX.Y-fpm package in APT." >&2
  exit 1
fi
PHPV="${PKG#php}"; PHPV="${PHPV%-fpm}"
echo ">>> Selected: ${PKG}  (PHP ${PHPV})"

# ---- Install php-fpm (+ basic companions) ------------------------------------
echo ">>> Installing ${PKG} ..."
apt-get install -y "${PKG}" "php${PHPV}-cli" "php${PHPV}-opcache"

# (Optional common extensions – uncomment if you need them)
# apt-get install -y "php${PHPV}-curl" "php${PHPV}-mbstring" "php${PHPV}-xml" "php${PHPV}-zip" "php${PHPV}-mysql" "php${PHPV}-gd"

# ---- Enable & start php-fpm --------------------------------------------------
echo ">>> Enabling and starting service: php${PHPV}-fpm ..."
systemctl enable --now "php${PHPV}-fpm"

# ---- Read socket path from the default pool ----------------------------------
POOL_CONF="/etc/php/${PHPV}/fpm/pool.d/www.conf"
if [[ ! -r "${POOL_CONF}" ]]; then
  echo "Error: Pool config not found: ${POOL_CONF}" >&2
  exit 1
fi

SOCKET="$(awk -F= '/^[[:space:]]*listen[[:space:]]*=/{gsub(/[[:space:]]/,"",$2); print $2; exit}' "${POOL_CONF}" || true)"

echo ">>> PHP-FPM installed."
echo "PHP-FPM version:"
if command -v "php-fpm${PHPV}" >/dev/null 2>&1; then
  "php-fpm${PHPV}" -v || true
else
  php-fpm -v || true
fi

echo
echo "Detected pool config : ${POOL_CONF}"
echo "Detected FPM socket  : ${SOCKET:-<unknown>}"
echo

# Optional: create a convenience symlink for NGINX configs
if [[ -S "${SOCKET}" ]]; then
  echo ">>> Creating convenience symlink: /run/php/php-fpm.sock -> ${SOCKET}"
  mkdir -p /run/php
  ln -sfn "${SOCKET}" /run/php/php-fpm.sock
else
  echo "Note: Socket not found yet (service may still be starting)."
  echo "      You can point NGINX to: ${SOCKET:-/run/php/php${PHPV}-fpm.sock}"
fi

echo
echo "✅ Done. Service status:"
systemctl --no-pager --full status "php${PHPV}-fpm" || true

cat <<'EOM'

Tips:
- Your NGINX fastcgi_pass can use either the versioned socket:
    fastcgi_pass unix:/run/php/php<ver>-fpm.sock;
  or the convenience symlink we created:
    fastcgi_pass unix:/run/php/php-fpm.sock;

- The socket path and other pool settings live in:
    /etc/php/<ver>/fpm/pool.d/www.conf

EOM
