#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# install-php.sh
#
# Purpose : Install PHP (version via $PHP_VER) + FPM + common extensions on Ubuntu,
#           then enable & start php-fpm, and expose a stable /run/php/php-fpm.sock symlink.
# OS      : Ubuntu 22.04 (Jammy)
# User    : root
# Usage   : sudo -i ; bash install-php.sh
# Notes   : Packages come from ppa:ondrej/php (versioned as php<ver>-<ext>).
# -----------------------------------------------------------------------------

set -euo pipefail

[[ "$(id -u)" -eq 0 ]] || { echo "Please run as root."; exit 1; }
export DEBIAN_FRONTEND=noninteractive

# ------ Version knob ----------------------------------------------------------
PHP_VER="${PHP_VER:-8.4}"   # change here if you want (e.g., 8.3/8.2)

echo ">>> Installing prerequisites ..."
apt-get update -y
apt-get install -y --no-install-recommends software-properties-common ca-certificates curl

echo ">>> Adding PPA: ondrej/php ..."
# Co-installable PHP versions & extensions for Ubuntu LTS are provided here.
add-apt-repository -y ppa:ondrej/php    # :contentReference[oaicite:3]{index=3}
apt-get update -y

echo ">>> Building package list for PHP ${PHP_VER} ..."
core_pkgs=(
  "php${PHP_VER}-fpm"
  "php${PHP_VER}-cli"
  "php${PHP_VER}-common"
  "php${PHP_VER}-opcache"
)

# Commonly used extensions (safe defaults)
exts=(
  "php${PHP_VER}-curl"
  "php${PHP_VER}-gd"
  "php${PHP_VER}-zip"
  "php${PHP_VER}-mbstring"
  "php${PHP_VER}-intl"
  "php${PHP_VER}-xml"
  "php${PHP_VER}-bcmath"
  "php${PHP_VER}-mysql"
  "php${PHP_VER}-sqlite3"
  "php${PHP_VER}-readline"
)

# Optional PECL-packaged exts that *may* be present in PPA (install only if available)
optional_exts=(
  "php${PHP_VER}-imagick"
  "php${PHP_VER}-redis"
)

# Keep only packages that actually exist (Candidate != (none))
filter_available() {
  local out=()
  for pkg in "$@"; do
    if apt-cache policy "$pkg" 2>/dev/null | awk -F': ' '/Candidate:/ {print $2}' | grep -qv '(none)'; then
      out+=("$pkg")
    else
      echo ">>> Skipping unavailable package: $pkg"
    fi
  done
  printf '%s\n' "${out[@]}"
}

install_list=()
mapfile -t avail_core < <(filter_available "${core_pkgs[@]}")
mapfile -t avail_exts < <(filter_available "${exts[@]}")
mapfile -t avail_opt  < <(filter_available "${optional_exts[@]}")
install_list=("${avail_core[@]}" "${avail_exts[@]}" "${avail_opt[@]}")

echo ">>> Installing PHP ${PHP_VER} & extensions ..."
apt-get install -y "${install_list[@]}"

# Enable extensions (idempotent). Not strictly required if package auto-enables,
# but safe to ensure they're active for this PHP version.
enable_mods=()
for pkg in "${avail_exts[@]}" "${avail_opt[@]}"; do
  mod="${pkg##*-}"              # php<ver>-<mod> -> <mod>
  [[ "$mod" == "common" || "$mod" == "fpm" || "$mod" == "cli" || "$mod" == "opcache" ]] && continue
  enable_mods+=("$mod")
done
if ((${#enable_mods[@]})); then
  echo ">>> Enabling modules with phpenmod for PHP ${PHP_VER} ..."
  phpenmod -v "${PHP_VER}" "${enable_mods[@]}" || true   # :contentReference[oaicite:4]{index=4}
fi

echo ">>> Enabling and starting php${PHP_VER}-fpm ..."
systemctl enable --now "php${PHP_VER}-fpm"

# Derive FPM socket (from default pool www.conf), then publish a stable symlink:
POOL_CONF="/etc/php/${PHP_VER}/fpm/pool.d/www.conf"   # standard path on Ubuntu/Debian :contentReference[oaicite:5]{index=5}
if [[ ! -r "${POOL_CONF}" ]]; then
  echo "ERROR: Pool config not found: ${POOL_CONF}" >&2
  exit 1
fi

SOCKET="$(awk -F= '/^[[:space:]]*listen[[:space:]]*=/{gsub(/[[:space:]]/,"",$2); print $2; exit}' "${POOL_CONF}")"
mkdir -p /run/php
if [[ -n "${SOCKET}" && "${SOCKET}" == /* ]]; then
  ln -sfn "${SOCKET}" /run/php/php-fpm.sock
  link_target="${SOCKET}"
else
  link_target="(tcp:${SOCKET:-unknown})"
fi

echo
echo "PHP-FPM version:"
"php-fpm${PHP_VER}" -v || php-fpm -v || true
echo
echo "Pool config : ${POOL_CONF}"
echo "FPM listen  : ${SOCKET:-<unknown>}"
echo "Symlink     : /run/php/php-fpm.sock -> ${link_target}"
echo
echo "✅ Done. NGINX can use: fastcgi_pass unix:/run/php/php-fpm.sock;"
