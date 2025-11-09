#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# install-php.sh
#
# Purpose : Install PHP (version via $PHP_VER) + FPM + common extensions on Ubuntu,
#           then enable & start php-fpm, expose a stable /run/php/php-fpm.sock symlink,
#           and install Composer globally bound to the selected PHP version.
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
add-apt-repository -y ppa:ondrej/php
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

# Optional PECL-packaged extensions that may be present in the PPA (install only if available)
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

# Enable extensions (idempotent)
enable_mods=()
for pkg in "${avail_exts[@]}" "${avail_opt[@]}"; do
  mod="${pkg##*-}"              # php<ver>-<mod> -> <mod>
  [[ "$mod" == "common" || "$mod" == "fpm" || "$mod" == "cli" || "$mod" == "opcache" ]] && continue
  enable_mods+=("$mod")
done
if ((${#enable_mods[@]})); then
  echo ">>> Enabling modules with phpenmod for PHP ${PHP_VER} ..."
  phpenmod -v "${PHP_VER}" "${enable_mods[@]}" || true
fi

echo ">>> Enabling and starting php${PHP_VER}-fpm ..."
systemctl enable --now "php${PHP_VER}-fpm"

# Derive FPM socket (from default pool www.conf), then publish a stable symlink:
POOL_CONF="/etc/php/${PHP_VER}/fpm/pool.d/www.conf"   # standard path on Ubuntu/Debian
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

# ---------- Composer (global) -------------------------------------------------
echo ">>> Ensuring 'php' resolves to PHP ${PHP_VER} for Composer ..."
# Prefer update-alternatives if available; otherwise create a safe shim.
if command -v update-alternatives >/dev/null 2>&1 && [[ -x "/usr/bin/php${PHP_VER}" ]]; then
  # Register current PHP if not registered yet.
  if ! update-alternatives --query php >/dev/null 2>&1; then
    update-alternatives --install /usr/bin/php php "/usr/bin/php${PHP_VER}" 1
  fi
  # Point 'php' to the requested version.
  update-alternatives --set php "/usr/bin/php${PHP_VER}" || true
fi
# Fallback shim if /usr/bin/php is still missing or not pointing to the target version:
if ! command -v php >/dev/null 2>&1; then
  ln -s "/usr/bin/php${PHP_VER}" /usr/local/bin/php
fi

echo ">>> Installing Composer ..."
# Composer needs unzip and git for extracting archives and fetching repositories
apt-get install -y --no-install-recommends unzip git

# Download and verify installer (official recommendation: verify sha384)
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
curl -fsSL https://composer.github.io/installer.sig -o "${TMP_DIR}/installer.sig"
curl -fsSL https://getcomposer.org/installer -o "${TMP_DIR}/composer-setup.php"

EXPECTED_SIG="$(cat "${TMP_DIR}/installer.sig")"
ACTUAL_SIG="$(php -r "echo hash_file('sha384', '${TMP_DIR}/composer-setup.php');")"

if [[ "${EXPECTED_SIG}" != "${ACTUAL_SIG}" ]]; then
  echo "ERROR: Invalid Composer installer signature." >&2
  exit 1
fi

php "${TMP_DIR}/composer-setup.php" --install-dir=/usr/local/bin --filename=composer --quiet
rm -f "${TMP_DIR}/composer-setup.php" || true

# Set a sane memory limit for Composer-heavy installs (optional)
if [[ -d "/etc/php/${PHP_VER}/cli/conf.d" ]]; then
  echo "memory_limit = -1" > "/etc/php/${PHP_VER}/cli/conf.d/99-composer-memory.ini"
fi

# ---------- Final output ------------------------------------------------------
echo
echo "PHP-FPM version:"
"php-fpm${PHP_VER}" -v || php-fpm -v || true
echo
echo "Pool config : ${POOL_CONF}"
echo "FPM listen  : ${SOCKET:-<unknown>}"
echo "Symlink     : /run/php/php-fpm.sock -> ${link_target}"
echo
echo "Composer    : $(/usr/local/bin/composer --version 2>/dev/null || echo 'not found')"
echo
echo "✅ Done. NGINX can use: fastcgi_pass unix:/run/php/php-fpm.sock;"
echo "✅ Composer installed at: /usr/local/bin/composer"
