#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# setup-stable-php-fpm.sh
#
# Purpose  : Install the latest *stable* php-fpm from Ondřej Surý PPA on Ubuntu 22.04.
# OS       : Ubuntu 22.04 (Jammy) - 64-bit
# User     : Must be run as root.
# Features :
#   - Adds ppa:ondrej/php
#   - Finds highest phpX.Y-fpm whose Candidate version is NOT rc/beta/alpha/dev
#   - Installs phpX.Y-fpm + phpX.Y-cli (+ phpX.Y-opcache if available)
#   - Enables & starts phpX.Y-fpm
#   - Prints pool socket path and creates a convenience symlink
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

echo ">>> Detecting latest *stable* php-fpm package ..."
# List candidates like php8.3-fpm php8.4-fpm php8.5-fpm ...
mapfile -t CANDIDATES < <(apt-cache search php-fpm | awk '{print $1}' | grep -E '^php[0-9]\.[0-9]-fpm$' | sort -V)

STABLE_PKGS=()
for pkg in "${CANDIDATES[@]}"; do
  cand_ver="$(apt-cache policy "$pkg" | awk '/Candidate:/ {print $2; exit}')"
  # Skip if no candidate or marked as rc/beta/alpha/dev
  if [[ -z "$cand_ver" || "$cand_ver" == "(none)" ]]; then
    continue
  fi
  if [[ "$cand_ver" =~ (~|-)rc|(~|-)beta|(~|-)alpha|(~|-)dev ]]; then
    continue
  fi
  STABLE_PKGS+=("$pkg")
done

if (( ${#STABLE_PKGS[@]} == 0 )); then
  echo "No stable phpX.Y-fpm found in APT (only pre-release present). Aborting." >&2
  echo "Tip: You can pin a known stable series, e.g.: apt-get install -y php8.4-fpm php8.4-cli" >&2
  exit 1
fi

# Pick the highest X.Y among stable list
PKG="${STABLE_PKGS[-1]}"
PHPV="${PKG#php}"; PHPV="${PHPV%-fpm}"
echo ">>> Selected stable: ${PKG}  (PHP ${PHPV})"

echo ">>> Installing ${PKG} + php${PHPV}-cli ..."
apt-get install -y "${PKG}" "php${PHPV}-cli" "php${PHPV}-common"

# Try OPcache if available (optional)
OPCACHE_PKG="php${PHPV}-opcache"
if apt-cache policy "${OPCACHE_PKG}" | awk '/Candidate:/ {print $2}' | grep -vq '^(none)$' && \
   apt-cache policy "${OPCACHE_PKG}" | awk '/Candidate:/ {print $2}' | grep -Eqv '(~|-)rc|(~|-)beta|(~|-)alpha|(~|-)dev'
then
  echo ">>> Installing ${OPCACHE_PKG} ..."
  apt-get install -y "${OPCACHE_PKG}"
  OPCACHE_STATUS="installed"
else
  echo ">>> ${OPCACHE_PKG} not present (or pre-release); skipping."
  OPCACHE_STATUS="missing"
fi

echo ">>> Enabling and starting service: php${PHPV}-fpm ..."
systemctl enable --now "php${PHPV}-fpm"

POOL_CONF="/etc/php/${PHPV}/fpm/pool.d/www.conf"
[[ -r "${POOL_CONF}" ]] || { echo "Pool config not found: ${POOL_CONF}"; exit 1; }
SOCKET="$(awk -F= '/^[[:space:]]*listen[[:space:]]*=/{gsub(/[[:space:]]/,"",$2); print $2; exit}' "${POOL_CONF}" || true)"

# Convenience symlink for NGINX configs
if [[ -n "${SOCKET}" && -S "${SOCKET}" ]]; then
  mkdir -p /run/php
  ln -sfn "${SOCKET}" /run/php/php-fpm.sock
fi

echo
echo "PHP-FPM version:"
if command -v "php-fpm${PHPV}" >/dev/null 2>&1; then "php-fpm${PHPV}" -v || true; else php-fpm -v || true; fi
echo
echo "Pool config : ${POOL_CONF}"
echo "FPM socket  : ${SOCKET:-<unknown>}"
echo "OPcache     : ${OPCACHE_STATUS}  (check: php -m | grep -i opcache)"
echo
echo "✅ Done. NGINX can use: unix:/run/php/php-fpm.sock  (or: unix:${SOCKET:-/run/php/php${PHPV}-fpm.sock})"
