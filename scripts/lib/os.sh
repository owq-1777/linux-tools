#!/usr/bin/env bash
set -euo pipefail
detect_ubuntu() {
  . /etc/os-release
  UBUNTU_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
  VERSION_ID="${VERSION_ID:-}"
  ID="${ID:-}"
  export UBUNTU_CODENAME VERSION_ID ID
  IS_NOBLE=0
  IS_JAMMY=0
  [[ "${UBUNTU_CODENAME}" == "noble" ]] && IS_NOBLE=1
  [[ "${UBUNTU_CODENAME}" == "jammy" ]] && IS_JAMMY=1
  export IS_NOBLE IS_JAMMY
}
require_supported_ubuntu() {
  detect_ubuntu
  [[ "${ID}" == "ubuntu" ]] || { echo "Unsupported OS: ${ID:-unknown}"; exit 1; }
  case "${VERSION_ID}" in
    "22.04"|"24.04") ;;
    *) echo "Unsupported Ubuntu ${VERSION_ID:-unknown} (${UBUNTU_CODENAME:-unknown}); require 22.04 or 24.04"; exit 1;;
  esac
}
ensure_apt_ready() {
  export DEBIAN_FRONTEND=noninteractive
  command -v apt-get >/dev/null 2>&1 || { echo "apt-get not found"; exit 1; }
}
