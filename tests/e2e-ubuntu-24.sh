#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/os.sh"
require_supported_ubuntu
ensure_apt_ready
[[ "$(id -u)" -eq 0 ]] || { echo "Please run as root."; exit 1; }
bash "${ROOT_DIR}/scripts/setup-system-base.sh"
bash "${ROOT_DIR}/scripts/setup-system-build-toolchain.sh"
bash "${ROOT_DIR}/scripts/install-docker.sh"
bash "${ROOT_DIR}/scripts/install-nginx.sh"
bash "${ROOT_DIR}/scripts/install-php.sh"
docker --version >/dev/null 2>&1 || { echo "docker not ready"; exit 1; }
/usr/sbin/nginx -v >/dev/null 2>&1 || { echo "nginx not ready"; exit 1; }
php -v >/dev/null 2>&1 || { echo "php not ready"; exit 1; }
echo "OK"
